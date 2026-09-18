"""
Mock server untuk Roblox Avatar Queue.

Jalankan:
    pip install fastapi uvicorn httpx
    uvicorn test:app --reload --port 8000

Lalu di terminal lain:
    make tunnel   (SSH ke VM, https://rblx.buanaglobalcipta.com)

Perubahan dari versi sebelumnya:
- /api/next sekarang ikut mengembalikan displayName.
  Roblox memblokir HttpService dari domain roblox.com, jadi display name
  tidak bisa diambil dari dalam Studio. Python yang mengambilkannya.
"""

import os
import secrets
import time
from collections import deque

import httpx
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from roblox_ssl import ROBLOX_HEADERS, USERS_API, _make_ssl_context

# HARUS di atas semua _env_float() di bawah.
#
# Tanpa baris ini SETIAP setelan .env yang dibaca file ini diam-diam
# diabaikan: TIER*_SCALE, SPOTLIGHT_MS_TIER*, QUEUE_MAX, ambang
# koin. Tidak ada error, tidak ada peringatan -- yang dipakai nilai default,
# dan satu-satunya cara menyadarinya adalah mengubah angka di .env lalu
# heran kenapa panggung tidak berubah.
#
# tiktok_listener.py sudah memanggilnya sejak awal; file ini kelewat.
load_dotenv()

# Dibuat sekali, dipakai ulang: membangun konteks SSL berarti memuat ulang
# seluruh sertifikat CA sistem, dan lookup displayName jalan per avatar.
_SSL_CONTEXT = _make_ssl_context()

app = FastAPI(title="Roblox Avatar Queue Server")

# Kunci untuk endpoint yang MENGUBAH antrian (/api/push, /api/clear,
# /api/cache). Server ini dibuka ke internet lewat subdomain publik, dan
# tanpa kunci siapa pun yang tahu alamatnya bisa menjejalkan nama ke
# panggung atau mengosongkan antrian di tengah live.
#
# Kosong = tanpa kunci, untuk `make server` di laptop. Di VM wajib diisi,
# dan listener di laptop mengirim nilai yang sama lewat header X-Token.
# /api/next dan /api/settings sengaja tidak dikunci: Roblox cuma membaca,
# dan HttpService Studio tidak perlu tahu rahasia apa pun.
API_TOKEN = os.environ.get("API_TOKEN", "")


def cek_token(x_token: str = Header(default="")) -> None:
    if API_TOKEN and not secrets.compare_digest(x_token, API_TOKEN):
        raise HTTPException(status_code=401, detail="token salah")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Antrian. Isinya dict, bukan string polos, karena tiap entri sekarang membawa
# tier dan siapa yang memanggilnya.
queue: deque[dict] = deque()

# Batas panjang antrian. Ini BUKAN soal memori (ribuan string itu remeh) --
# ini soal jarak waktu antara orang mengetik dan avatarnya muncul.
#
# Studio mengambil satu nama per polling, jadi panjang antrian = lama tunggu.
# Dengan polling 1 detik, 30 nama berarti paling lama ~30 detik. Lewat dari itu
# penontonnya sudah pergi sebelum avatarnya nongol, dan panggung menampilkan
# orang-orang dari beberapa menit lalu -- buat live, itu sama saja rusak.
#
# Saat penuh, yang DIBUANG adalah komentar yang baru datang, bukan yang sudah
# antri. Konsekuensinya sengaja dipilih: siapa pun yang sudah masuk antrian
# dijamin kebagian tampil, tidak tergusur di detik terakhir.
QUEUE_MAX = int(os.environ.get("QUEUE_MAX", "30"))


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.environ[name])
    except (KeyError, ValueError):
        return default


# ---------------------------------------------------------------------- TIER --

# Arti VISUAL tiap tier. Tabel ini sengaja ada di sini, bukan di listener:
# main.py yang melayani Roblox Studio, jadi sisi Lua cukup membaca field yang
# dikirim tanpa menyimpan tabel apa pun sendiri. Mau menyetel ukuran atau efek?
# Cukup ubah di sini (atau lewat .env), tidak perlu menyentuh Studio.
#
# LIMA tier, ditentukan NAMA GIFT (tier_dari_gift di tiktok_listener.py):
#
#   tier 1  komentar biasa     -- ikut antre, tidak ada apa-apa
#   tier 2  Rose               -- skip lane + cakram biru di kakinya,
#                                 sorotan 3 detik, TANPA efek VFX acak
#   tier 3  Rosa / 1.000 tap   -- AURA: border + efek VFX acak 1 dari 3 di
#                                 badannya, kamera pelan 4 detik
#   tier 4  Bouquet Flower     -- NOVA: melayang naik, waktu berhenti, lalu
#                                 membanting diri ke tanah dan menyapu
#                                 barisan. Lalu menari 3 detik dengan aura
#                                 VFX acak (undian kedua, terpisah)
#   tier 5  Doughnut           -- UKURAN: raksasa 4x di belakang barisan,
#                                 tidak menari, cuma melambai, polos
#
# Dulu EMPAT: tier "border saja" 1 koin pernah dibuang karena bedanya
# terlalu tipis. Dia kembali (tier 2) dengan alasan yang dulu belum ada:
# sorotan 4 detik untuk tiap gift 1 koin menguasai kamera saat live ramai,
# dan gift yang jauh lebih mahal antre di belakangnya.
#
# Kenapa bukan sekadar "tier 2 tapi lebih": penonton tidak menghitung
# efek. Yang mereka ingat cuma satu kalimat per tier -- "yang itu
# raksasa", "yang itu jatuh dari langit" -- dan kalimat itu harus ada
# sebelum efeknya dipilih.
TIER_EFFECTS = {
    1: {
        "scale": _env_float("TIER1_SCALE", 1.0),
        "effects": [],
        "nameStyle": "plain",
        "spotlight": False,
    },
    2: {
        # Cakram biru di kaki, tanpa garis tepi dan tanpa aura VFX. TIDAK
        # dipakai gift apa pun lagi sejak susunan digeser (Rose sekarang
        # tier 3) -- dibiarkan supaya push tier 2 manual tetap jalan.
        # Daftar ini keterangan, bukan perintah -- Lua bercabang dari
        # `tier` -- tapi dua sisi yang bercerita beda adalah cara paling
        # gampang menyesatkan orang yang membacanya.
        "scale": _env_float("TIER2_SCALE", 1.0),
        "effects": ["cakram"],
        "nameStyle": "gold",
        "spotlight": True,
        # ORBIT DIMATIKAN untuk semua tier, dan ini kolomnya.
        #
        # Orbit membawa kamera ke SAMPING lalu ke BELAKANG avatarnya, dan
        # dari belakang yang terlihat cuma punggung -- wajah, papan aura,
        # dan cakram semuanya menghadap ke arah lain. Panggung ini ditonton
        # dari depan. Penggantinya busur depan (KAMERA_TIER di Lua).
        #
        # Kolomnya dibiarkan ada, bukan dihapus: Lua masih membacanya,
        # jadi orbit bisa dinyalakan lagi dari sini tanpa menyentuh
        # Studio.
        "orbit": False,
    },
    3: {
        # Rose, gift lain di bawah TIER5_KOIN, atau 1.000 tap (dulu Rosa).
        # Aura VFX acak di badan (satu dari tiga
        # asset, dipilih di Lua) plus border.
        "scale": _env_float("TIER3_SCALE", 1.0),
        "effects": ["border", "aura-vfx"],
        "nameStyle": "gold",
        "spotlight": True,
        "orbit": False,
    },
    4: {
        # Rosa, atau Rose x10 dalam satu combo (dulu Bouquet Flower).
        # Badan normal; yang membuatnya terbaca UPACARANYA
        # (TierNova, dijalankan client). Aura VFX acaknya menyala saat avatar
        # aslinya muncul kembali.
        #
        # Dia dapat DUA undian yang terpisah: palet warna novanya (1 dari
        # 3, NOVA.PALET di Lua) dan aura VFX-nya (1 dari 3) -- jadi ada
        # sembilan kombinasi tampilan.
        #
        # TANPA border: Highlight di badan yang disembunyikan client
        # selama adegannya tetap digambar -- yang terlihat jadi garis tepi
        # kosong berdiri di slot selagi orangnya melayang di atasnya.
        "scale": _env_float("TIER4_SCALE", 1.0),
        "effects": ["nova", "aura-vfx"],
        "nameStyle": "gold",
        "spotlight": True,
        "orbit": False,
    },
    5: {
        # Doughnut, atau gift apa pun >= TIER5_KOIN (termasuk Bouquet
        # Flower). Dibaca Lua sebagai skala raksasa. Di sini, bukan di Lua,
        # supaya bisa digeser lewat .env tanpa menyentuh Studio.
        #
        # AWAS kalau .env-nya dari zaman empat tier: TIER4_SCALE=4 yang
        # tertinggal di sana sekarang memperbesar NOVA, bukan raksasa.
        # _cek_kunci_lama di bawah yang memperingatkannya.
        "scale": _env_float("TIER5_SCALE", 4.0),
        # Cuma "giant" -- TANPA border, cakram, maupun aura VFX (aura
        # sempat dicoba, lalu dicopot). Yang membuat dia terbaca ukuran
        # badannya, dan apa pun yang ditempel di badan atau kakinya cuma
        # menyaingi satu-satunya hal yang jadi intinya.
        "effects": ["giant"],
        "nameStyle": "gold",
        "spotlight": True,
        # Untuk raksasa alasan orbit bahkan lebih kuat: dia yang paling
        # besar, jadi dia yang paling lama memperlihatkan punggung kalau
        # kameranya memutar ke belakang.
        "orbit": False,
    },
}

# Ambang koin untuk gift yang NAMANYA tidak dikenal. HARUS sama dengan
# TIER*_KOIN di tiktok_listener.py -- listener yang memutuskan tier, di sini
# angkanya cuma ditampilkan di /api/settings supaya alat lain tidak perlu
# menebak. Tier 4 (nova) sengaja tidak punya: dia cuma lewat nama.
TIER2_KOIN = int(_env_float("TIER2_KOIN", 1))
TIER3_KOIN = int(_env_float("TIER3_KOIN", 1))
TIER5_KOIN = int(_env_float("TIER5_KOIN", 30))

# Lama sorotan tier 2 (Rose). DATAR, dan paling pendek.
#
# Tiga detik: cukup untuk wajahnya terbaca dan angka auranya mendarat, dan
# tidak lebih. Rose yang paling sering datang di antara yang berbayar, jadi
# tiap detik di sini dikalikan dengan seberapa sering dia muncul.
SPOTLIGHT_MS_T2 = int(_env_float("SPOTLIGHT_MS_TIER2", 3000))

# Lama sorotan tier 3 (Rosa, aura). SEPULUH detik: adegan sinematik --
# kamera menyapu kanan-kiri-kanan, naik-turun dua kali, lalu mendorong masuk
# tepat saat angka auranya mendarat. Layarnya letterbox + warna + kilatan,
# dan garis tepi avatarnya berdenyut. Rinciannya di KAMERA_TIER[3] dan
# LAYAR di AvatarQueueV2.
#
# Naik dari 4 detik atas permintaan. Harganya: Rosa jauh lebih jarang
# disorot saat live ramai (jedanya 12 detik), dan Rose atau Rosa yang
# datang sesudahnya menunggu lebih lama di antrian berbayar.
SPOTLIGHT_MS_T3 = int(_env_float("SPOTLIGHT_MS_TIER3", 10000))

# Lama sorotan tier 4 (nova). DATAR, dan isinya berurutan:
#
#   0,0 - ~0,6   client menunggu aset avatarnya
#   0,0 - 4,0    charge: melayang naik 14 stud, kamera rendah mengorbit
#   4,0 - 5,5    ascend: naik ke 45 stud sambil melintas ke atas slot 1
#   5,5 - 6,5    freeze: orb tersedot, layar abu-abu, kamera ke depan
#   6,5 - 7,1    slam: banting dari 45 stud, kamera meluncur ke atas
#   7,1 - 10,3   impact: shockwave, pilar, petir, kristal -- DAN barisan
#                tersapu, dia jadi orang pertama barisan yang baru
#   10,3 - 13,3  menari sendirian di panggung kosong
#
# 15 detik: tunggu aset 0,6 + nova 10,3 + tarian 3,0 = 13,9, sisanya margin.
# Rinciannya di NOVA di AvatarQueueV2. Uji di test_tier.py menjaga seluruh
# adegan + tarian 3 detik tetap di dalam angka ini, DAN menjaga papan auranya
# tidak dikirim sebelum avatar aslinya dimunculkan kembali.
SPOTLIGHT_MS_T4 = int(_env_float("SPOTLIGHT_MS_TIER4", 15000))

# Lama sorotan tier 5 (raksasa). Juga DATAR: raksasa itu pose diam -- dia
# melambai sekali lalu berdiri saja. Tujuh detik karena badan 4x butuh
# waktu paling lama untuk dibaca mata.
SPOTLIGHT_MS_T5 = int(_env_float("SPOTLIGHT_MS_TIER5", 7000))

# Sanity guard untuk angka yang masuk lewat /api/push. Sama dengan
# KOIN_WARAS di tiktok_listener.py.
KOIN_WARAS        = 1_000_000


def _cek_sorotan_vs_jeda() -> None:
    """Peringatkan kalau sorotan sebuah tier lebih lama dari jedanya sendiri.

    Ini BUKAN lagi penjaga tumpang tindih -- yang menjaga itu sekarang
    SPOTLIGHT_NAPAS_S di _ambil_entri, dan dia menahan sorotan berikutnya
    sampai yang sekarang benar-benar habis, apa pun isi jedanya.

    Yang tersisa di sini peringatan setelan: jeda yang lebih pendek dari
    sorotannya sendiri tidak berarti apa-apa lagi (dia selalu kalah oleh
    napas di atas), jadi angka yang tertulis di .env berhenti bercerita
    jujur tentang seberapa sering tier itu muncul.

    SAMA PANJANG tidak diperingatkan. Jeda 3 detik untuk sorotan 3 detik
    artinya "susul begitu yang sebelumnya selesai", dan napas yang
    menambahkan 1,5 detik di atasnya memang yang diharapkan.
    """
    for tier, lama, jeda, nama in (
        (2, SPOTLIGHT_MS_T2, SPOTLIGHT_GAP_T2_S, "SPOTLIGHT_GAP_TIER2_S"),
        (3, SPOTLIGHT_MS_T3, SPOTLIGHT_GAP_T3_S, "SPOTLIGHT_GAP_TIER3_S"),
        (4, SPOTLIGHT_MS_T4, SPOTLIGHT_GAP_T4_S, "SPOTLIGHT_GAP_TIER4_S"),
        (5, SPOTLIGHT_MS_T5, SPOTLIGHT_GAP_T5_S, "SPOTLIGHT_GAP_TIER5_S"),
    ):
        if lama > jeda * 1000:
            print(
                f"[peringatan] sorotan tier {tier} {lama/1000:.1f}s > "
                f"{nama} {jeda:.0f}s -- jedanya tidak terpakai; yang "
                f"berlaku napas {lama/1000 + SPOTLIGHT_NAPAS_S:.1f}s. "
                f"Naikkan jedanya kalau angka itu yang kamu maksud."
            )


# Kunci .env dari zaman EMPAT tier, yang artinya sudah bergeser.
#
# Yang berbahaya bukan kunci yang tidak dibaca lagi, tapi kunci yang MASIH
# dibaca dengan arti yang sudah pindah. Contoh yang paling mahal:
# TIER4_SCALE=4 yang tertinggal membuat NOVA jadi raksasa 4x, dan
# SPOTLIGHT_MS_TIER3=15000 memberi aura sorotan lima belas detik.
#
# Yang bisa dideteksi dengan pasti cuma TIER4_KOIN: dia tidak dibaca siapa
# pun lagi (nova tidak punya ambang koin), jadi kalau dia masih ada, .env-nya
# belum pernah disesuaikan -- dan kunci tier 2-4 di sebelahnya hampir pasti
# masih berarti yang lama.
_KUNCI_LAMA = ("TIER4_KOIN",)


def _cek_kunci_lama() -> None:
    lama = [k for k in _KUNCI_LAMA if k in os.environ]
    if lama:
        print(
            f"[peringatan] .env masih berisi {', '.join(lama)} -- itu setelan "
            f"zaman empat tier dan tidak dibaca lagi. Tier sekarang lima "
            f"(2 Rose, 3 Rosa/aura, 4 Bouquet/nova, 5 Doughnut/raksasa), "
            f"jadi TIER*_SCALE, SPOTLIGHT_MS_TIER* dan SPOTLIGHT_GAP_TIER*_S "
            f"ikut bergeser satu nomor -- cek semuanya."
        )


def durasi_sorotan(tier: int = 4) -> int:
    """Lama sorotan (ms) untuk sebuah tier. Tidak bergantung koin.

      tier 2  Rose: 3 detik, cukup untuk wajah dan angka auranya
      tier 3  aura + adegan kamera sinematik, 10 detik
      tier 4  adegan nova 10,3 detik, lalu menari 3 detik
      tier 5  raksasa itu pose diam -- panjangnya ditentukan berapa lama
              badan 4x perlu untuk dibaca mata, bukan oleh gerakannya
    """
    if tier <= 2:
        return SPOTLIGHT_MS_T2
    if tier == 3:
        return SPOTLIGHT_MS_T3
    if tier == 4:
        return SPOTLIGHT_MS_T4
    return SPOTLIGHT_MS_T5

# Jeda sorotan tier 2 (Rose). Paling pendek, dan sama dengan sorotannya:
# begitu Rose sebelumnya selesai, yang berikutnya boleh menyusul (ditambah
# SPOTLIGHT_NAPAS_S, jadi praktisnya 4,5 detik).
SPOTLIGHT_GAP_T2_S = _env_float("SPOTLIGHT_GAP_TIER2_S", 3.0)

# Jeda sorotan tier 3 (aura).
#
# Batas bawahnya bukan selera: sorotan + fade keluar (~0,6 detik di Lua)
# harus SELESAI sebelum yang berikutnya mulai. SPOTLIGHT_NAPAS_S di bawah
# yang menjaganya sekarang, tapi jeda yang lebih pendek dari sorotannya
# sendiri berhenti bercerita jujur (lihat _cek_sorotan_vs_jeda).
# 12 = sorotan 10 + napas. Lebih pendek dari itu tidak berarti apa-apa:
# napas sesudah sorotan selalu menang.
SPOTLIGHT_GAP_T3_S = _env_float("SPOTLIGHT_GAP_TIER3_S", 12.0)

# Jeda tier 4 (nova). Nova menyita kamera, panggung, DAN seluruh layar
# sekaligus (letterbox, warna abu-abu, ledakan setinggi 300 stud), dan dua
# nova yang menempel terbaca sebagai satu kekacauan, bukan dua kedatangan.
# 17 = sorotan 15 + napas 2.
SPOTLIGHT_GAP_T4_S = _env_float("SPOTLIGHT_GAP_TIER4_S", 17.0)

# Jeda tier 5 (raksasa). Dua raksasa beruntun saling mengganti di slot yang
# sama, jadi yang pertama butuh waktu untuk sempat dilihat.
SPOTLIGHT_GAP_T5_S = _env_float("SPOTLIGHT_GAP_TIER5_S", 11.0)

# Napas SESUDAH sorotan sebelumnya benar-benar habis, detik.
#
# Ini yang menutup lubang yang dulu bikin sorotan saling tindih: jeda di
# atas dipilih dari tier yang MAU disorot, bukan dari yang SEDANG
# disorot. Raksasa (sorotan 7 detik) diikuti tier 2 cuma menunggu jeda
# tier 2 (6 detik) -- jadi tier 2 mulai persis waktu raksasa belum habis,
# kameranya direbut di tengah adegan, dan salah satu dari keduanya
# kehilangan sorotannya. Yang terlihat di siaran: "tier 2 datang tapi
# tidak disorot".
#
# Sekarang syaratnya dua-duanya (lihat _ambil_entri): jeda milik tier
# yang masuk, DAN sorotan yang sedang jalan harus sudah selesai plus
# angka ini.
#
# Kenapa 1,5 dan bukan sekadar 0,5 napas: cap waktunya dipasang saat
# entri DIAMBIL Studio, sementara adegannya baru mulai setelah avatarnya
# selesai dimuat (2-3 detik). Angka ini yang menanggung selisih itu --
# turunkan kalau sorotan terasa terlalu jarang, naikkan kalau masih ada
# yang tertindih.
SPOTLIGHT_NAPAS_S = _env_float("SPOTLIGHT_NAPAS_S", 1.5)


def _jeda_sorotan(tier: int) -> float:
    """Jeda minimal yang harus dilewati sebelum tier ini boleh disorot."""
    if tier <= 2:
        return SPOTLIGHT_GAP_T2_S
    if tier == 3:
        return SPOTLIGHT_GAP_T3_S
    if tier == 4:
        return SPOTLIGHT_GAP_T4_S
    return SPOTLIGHT_GAP_T5_S

# Kapan sorotan terakhir disajikan. None = belum pernah.
last_spotlight_at: float | None = None

# Berapa lama sorotan yang terakhir disajikan itu, detik. Dipakai
# _ambil_entri untuk tahu kapan dia habis -- tanpa ini yang berikutnya
# cuma bisa menebak lewat jedanya sendiri, dan tebakan itu yang dulu
# salah untuk pasangan raksasa -> tier 2.
last_spotlight_lama_s: float = 0.0

# Cache displayName supaya tidak bolak-balik memanggil API Roblox
# untuk username yang sama. Roblox punya rate limit.
#
# Isinya (displayName, userId). userId ikut disimpan karena satu panggilan
# users.roblox.com sudah membawa dua-duanya -- dan yang KEDUA itu yang
# menyelamatkan Studio dari HTTP 429: tanpa dia, tiap avatar memaksa Studio
# memanggil GetUserIdFromNameAsync sendiri, dan rate limit Roblox untuk
# panggilan itu jauh lebih ketat daripada polling antrian ini.
display_cache: dict[str, tuple[str, int | None]] = {}


_cek_sorotan_vs_jeda()
_cek_kunci_lama()


class PushRequest(BaseModel):
    username: str
    tier: int = 1
    tiktokUser: str | None = None
    # Total koin yang dikeluarkan untuk nama ini. 0 = komentar biasa.
    koin: int = 0


def lookup_user(username: str) -> tuple[str, int | None]:
    """Ambil (displayName, userId) dari username lewat API publik Roblox.

    Kalau gagal karena apa pun (timeout, user tidak ada, API berubah),
    kembalikan username itu sendiri sebagai displayName dan userId None.
    Antrian tidak boleh berhenti hanya karena lookup nama gagal.

    userId-nya bukan bonus, itu inti fungsi ini sekarang. Studio yang
    memanggil GetUserIdFromNameAsync per avatar kena HTTP 429 setelah
    belasan nama; di sini satu nama = satu panggilan SEUMUR HIDUP proses
    (di-cache), dan hasilnya tinggal dibaca Studio dari /api/next.
    """
    if username in display_cache:
        return display_cache[username]

    result: tuple[str, int | None] = (username, None)  # fallback

    try:
        # verify=_SSL_CONTEXT itu WAJIB, bukan pengetatan keamanan.
        #
        # Dulu baris ini memanggil httpx polos, dan itu jenis panggilan yang
        # menggantung sampai timeout di edge server Roblox (alasannya ada di
        # docstring _NoALPNContext). Yang bikin tidak ketahuan: except di
        # bawah menjatuhkannya balik ke username mentah, jadi yang terlihat
        # cuma displayName yang "kebetulan" selalu sama dengan username.
        r = httpx.post(
            USERS_API,
            json={"usernames": [username], "excludeBannedUsers": False},
            headers=ROBLOX_HEADERS,
            timeout=5.0,
            verify=_SSL_CONTEXT,
        )
        r.raise_for_status()
        data = r.json().get("data", [])
        if data:
            result = (data[0].get("displayName") or username, data[0].get("id"))
    except Exception as e:
        print(f"[lookup] gagal untuk '{username}': {e}")

    display_cache[username] = result
    return result


def lookup_display_name(username: str) -> str:
    """displayName saja, buat pemanggil yang tidak butuh userId."""
    return lookup_user(username)[0]


@app.get("/")
def health():
    """Endpoint tes paling dasar untuk memastikan jalur tunnel tembus."""
    return {"test": "ok"}


@app.post("/api/push", dependencies=[Depends(cek_token)])
def push(req: PushRequest):
    """Masukkan username ke antrian. Nanti dipanggil listener TikTok."""
    name = req.username.strip()
    if not name:
        return {"ok": False, "error": "username kosong"}

    tier = req.tier if req.tier in TIER_EFFECTS else 1
    # Dibatasi: gift TikTok ada yang puluhan ribu koin, dan angka liar di sini
    # akan memperpanjang sorotan sampai panggung macet.
    koin = max(0, min(int(req.koin or 0), KOIN_WARAS))
    entry = {
        "username": name,
        "tier": tier,
        "tiktokUser": req.tiktokUser,
        "koin": koin,
    }

    # Yang bayar tidak ikut antre dan tidak kena batas antrian. Dari sisi dia,
    # uangnya sudah keluar -- ditolak karena "antrian penuh" itu tidak bisa
    # diterima. Yang gratisan yang mengalah.
    if tier >= 2:
        # TIDAK digabung dengan kiriman lain dari orang yang sama.
        #
        # Dulu kiriman berikutnya untuk nama yang sama digabung ke entri
        # yang sudah menunggu, dengan tier diambil yang TERTINGGI. Itu
        # separuh dari bug "Doughnut lalu Rose jadi raksasa lagi": Rose-nya
        # dilebur ke entri raksasa dan tidak pernah tampil sendiri.
        #
        # Sekarang tiap gift = satu spawn, dan listener mengirimnya satu
        # per satu. Alasan penggabungan yang dulu (entri yang lebih baru
        # keluar duluan dan angkanya terbaca "turun") sudah tidak berlaku:
        # sisipan di bawah menjaga urutan kirim, jadi yang duluan dikirim
        # yang duluan tampil.

        # Disisipkan SESUDAH gift-gift yang sudah menunggu, bukan di paling
        # depan.
        #
        # Dulu ini appendleft, dan akibatnya urutan yang bayar jadi TERBALIK:
        # tiap gift baru menyalip gift yang sudah antre, jadi orang yang bayar
        # paling awal tampil paling akhir. Terukur: Andi-Budi-Cici mengirim
        # berurutan, yang keluar Cici-Budi-Andi.
        #
        # Yang gratisan tetap tidak pernah didahulukan -- gift selalu berada
        # di depan mereka semua, cuma sekarang sesama gift saling menghormati
        # urutan bayar.
        sisip = 0
        while sisip < len(queue) and queue[sisip]["tier"] >= 2:
            sisip += 1
        queue.insert(sisip, entry)

        return {"ok": True, "queued": name, "tier": tier,
                "koin": koin, "skipped": True, "size": len(queue)}

    if len(queue) >= QUEUE_MAX:
        # Bukan error -- ini kondisi normal saat live sedang ramai. Listener
        # yang memutuskan cara melaporkannya.
        return {"ok": False, "error": "antrian penuh", "full": True, "size": len(queue)}

    queue.append(entry)
    return {"ok": True, "queued": name, "tier": tier, "koin": koin,
            "size": len(queue)}


def _ambil_entri() -> dict | None:
    """Pilih entri yang disajikan berikutnya, dengan menjaga jarak antar sorotan.

    Entri tier 2-5 memicu sorotan yang memakai kamera beberapa detik.
    Selama sorotan sebelumnya BELUM HABIS -- atau jedanya belum lewat --
    entri itu DITAHAN di tempatnya dan entri biasa yang disajikan lebih dulu,
    jadi sorotan tersebar sendiri tanpa ada yang diturunkan tiernya dan tanpa
    dua adegan bertumpuk.

    Kalau isi antrian kebetulan sorotan semua dan jedanya belum lewat,
    kembalikan None: Studio menunggu satu-dua polling lagi, lebih baik daripada
    dua sorotan menempel.
    """
    global last_spotlight_at, last_spotlight_lama_s

    if not queue:
        return None

    now = time.monotonic()

    # Jedanya dihitung dari tier entri yang sedang di depan, bukan satu
    # angka untuk semua: tier 2 (5 detik) boleh menyusul lebih cepat
    # daripada tier 3 yang sorotannya bisa 9 detik lebih.
    depan = queue[0]
    if not TIER_EFFECTS[depan["tier"]]["spotlight"]:
        # Yang di depan bukan sorotan: tidak ada yang perlu dijeda.
        return queue.popleft()

    # DUA syarat, bukan satu.
    #
    # Yang pertama jeda milik tier yang mau masuk -- itu yang mengatur
    # seberapa sering sorotan boleh terjadi. Yang kedua: sorotan yang
    # SEDANG jalan harus sudah habis dulu. Tanpa yang kedua, tier 3
    # (jeda 9 detik) boleh masuk di detik ke-9 sorotan tier 4 yang
    # panjangnya juga 9 detik -- dua adegan bertumpuk, kamera direbut di
    # tengah jalan, dan yang satu kehilangan sorotannya.
    #
    # max(), bukan dijumlah: untuk pasangan yang jedanya memang sudah
    # lebih panjang dari sorotan sebelumnya, tidak ada yang berubah sama
    # sekali dari perilaku lama.
    jeda = max(_jeda_sorotan(depan["tier"]),
               last_spotlight_lama_s + SPOTLIGHT_NAPAS_S)
    boleh_sorot = last_spotlight_at is None or (now - last_spotlight_at) >= jeda

    if boleh_sorot:
        entry = queue.popleft()
        if TIER_EFFECTS[entry["tier"]]["spotlight"]:
            last_spotlight_at = now
            last_spotlight_lama_s = durasi_sorotan(entry["tier"]) / 1000
        return entry

    # Sorotan sedang dijeda: cari entri pertama yang bukan sorotan.
    for i, entry in enumerate(queue):
        if not TIER_EFFECTS[entry["tier"]]["spotlight"]:
            del queue[i]
            return entry

    return None


@app.get("/api/next")
def next_username():
    """Roblox polling ke sini tiap 1-2 detik.

    Mengembalikan satu entri lengkap dengan data tier-nya, lalu menghapus dari
    antrian. Kalau tidak ada yang bisa disajikan, username = null.

    Field `username`, `displayName`, dan `size` bentuknya tidak berubah dari
    versi sebelum ada tier -- skrip Lua lama tetap jalan, cuma belum memakai
    field tier yang baru.
    """
    entry = _ambil_entri()
    if entry is None:
        return {"username": None, "displayName": None, "size": len(queue)}

    name = entry["username"]
    display, user_id = lookup_user(name)
    tier = entry["tier"]
    koin = entry.get("koin", 0)
    efek = TIER_EFFECTS[tier]

    return {
        "username": name,
        "displayName": display,
        # null kalau lookup-nya gagal. Studio jatuh balik ke
        # GetUserIdFromNameAsync kalau field ini kosong.
        "userId": user_id,
        "tier": tier,
        "scale": efek["scale"],
        "effects": efek["effects"],
        "nameStyle": efek["nameStyle"],
        "spotlight": efek["spotlight"],
        # Apakah kameranya MENGORBIT. Dimatikan untuk semua tier -- lihat
        # TIER_EFFECTS.
        "orbit": efek.get("orbit", False),
        "spotlightMs": durasi_sorotan(tier) if efek["spotlight"] else 0,
        "koin": koin,
        "tiktokUser": entry.get("tiktokUser"),
        "size": len(queue),
    }


@app.get("/api/settings")
def settings():
    """Setelan yang sedang berlaku, supaya alat lain tidak perlu menebak.

    Dipakai mock_comments.py: laju sorotan ditentukan SPOTLIGHT_GAP_TIER*_S
    di sini, dan kalau mock mengirim gift lebih cepat dari itu, sisanya
    cuma menumpuk di antrian tanpa pernah terlihat.
    """
    return {
        "queueMax": QUEUE_MAX,
        "spotlightGapTier2S": SPOTLIGHT_GAP_T2_S,
        "spotlightGapTier3S": SPOTLIGHT_GAP_T3_S,
        "spotlightGapTier4S": SPOTLIGHT_GAP_T4_S,
        "spotlightGapTier5S": SPOTLIGHT_GAP_T5_S,
        # Napas wajib sesudah sorotan sebelumnya habis. mock_comments
        # memakai jeda di atas untuk mengatur lajunya, dan sejak ada
        # angka ini jeda itu bukan lagi satu-satunya yang menentukan.
        "spotlightNapasS": SPOTLIGHT_NAPAS_S,
        "spotlightMsTier2": SPOTLIGHT_MS_T2,
        "spotlightMsTier3": SPOTLIGHT_MS_T3,
        "spotlightMsTier4": SPOTLIGHT_MS_T4,
        "spotlightMsTier5": SPOTLIGHT_MS_T5,
        "koinTier2": TIER2_KOIN,
        "koinTier3": TIER3_KOIN,
        "koinTier5": TIER5_KOIN,
        "tiers": {str(k): v for k, v in TIER_EFFECTS.items()},
    }


@app.get("/api/peek")
def peek():
    """Lihat isi antrian tanpa menghapus. Debugging saja."""
    return {
        # Ringkas "nama" untuk tier 1 dan "nama(T2/5koin)" untuk yang ber-gift,
        # supaya `make peek` tetap kebaca sekilas di terminal.
        "queue": [
            e["username"] if e["tier"] == 1
            else f"{e['username']}(T{e['tier']}/{e.get('koin', 0)}koin)"
            for e in queue
        ],
        "detail": list(queue),
        "size": len(queue),
    }


@app.delete("/api/clear", dependencies=[Depends(cek_token)])
def clear():
    """Kosongkan antrian. Debugging saja."""
    n = len(queue)
    queue.clear()
    return {"ok": True, "cleared": n}


@app.delete("/api/cache", dependencies=[Depends(cek_token)])
def clear_cache():
    """Kosongkan cache displayName. Berguna kalau ada yang ganti nama."""
    n = len(display_cache)
    display_cache.clear()
    return {"ok": True, "cleared": n}

# ------------------------------------------------------------------ musik
#
# Lagunya diputar DI LAPTOP (music_player.py), bukan di Roblox: lagu
# berlisensi yang di-upload ke Roblox kena moderasi. Roblox cuma perlu tahu
# lagu nomor berapa yang sedang jalan supaya tariannya ikut ganti.
#
# Yang disimpan KEADAAN, bukan perintah sekali pakai. Server Roblox yang baru
# hidup di tengah lagu langsung tahu lagu yang sedang jalan, tanpa menunggu
# lagu berikutnya.
#
# Waktu mulai dicap dengan jam VM dan dikirim ke Roblox sebagai SISA waktu,
# bukan jam dinding. Jam laptop, VM, dan server Roblox tidak pernah sama
# persis; selisih waktu relatif tidak terpengaruh itu.
class MusicRequest(BaseModel):
    index: int
    nama: str = ""
    # Lagu baru mulai berbunyi sekian ms SESUDAH laporan ini dikirim. Jeda
    # ini yang memberi Roblox waktu untuk polling dan bersiap, jadi harus
    # lebih lama dari POLL_MUSIK di AvatarQueueV2 ditambah waktu tempuh.
    mulai_dalam_ms: int = 0


musik: dict = {"seq": 0, "index": 0, "nama": "", "mulai": 0.0}


@app.post("/api/music", dependencies=[Depends(cek_token)])
def set_music(req: MusicRequest):
    """Dipanggil music_player.py tiap kali akan memulai lagu."""
    musik["seq"] += 1
    musik["index"] = req.index
    musik["nama"] = req.nama
    musik["mulai"] = time.monotonic() + max(0, req.mulai_dalam_ms) / 1000
    return {"ok": True, "seq": musik["seq"]}


@app.get("/api/music")
def get_music():
    """Dibaca Roblox. seq naik tiap lagu baru, termasuk lagu yang sama diulang."""
    if not musik["seq"]:
        return {}
    return {
        "seq": musik["seq"],
        "index": musik["index"],
        "nama": musik["nama"],
        # Positif = belum mulai, tunggu segini. Negatif = sudah jalan sejak
        # segini lalu.
        "sisa_ms": round((musik["mulai"] - time.monotonic()) * 1000),
    }
