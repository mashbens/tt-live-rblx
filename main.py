"""
Mock server untuk Roblox Avatar Queue.

Jalankan:
    pip install fastapi uvicorn httpx
    uvicorn test:app --reload --port 8000

Lalu di terminal lain:
    ngrok http 8000

Perubahan dari versi sebelumnya:
- /api/next sekarang ikut mengembalikan displayName.
  Roblox memblokir HttpService dari domain roblox.com, jadi display name
  tidak bisa diambil dari dalam Studio. Python yang mengambilkannya.
"""

import os
import time
from collections import deque

import httpx
from dotenv import load_dotenv
from fastapi import FastAPI
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
# Tangganya dibangun dari TIGA hal yang berbeda, bukan dari "efek yang
# makin banyak". Tiap naik satu tier, yang berubah JENISNYA:
#
#   tier 1  komentar biasa   -- ikut antre, tidak ada apa-apa
#   tier 2  >= 1 koin        -- PERHATIAN: border, dan kamera berhenti
#                               di dia beberapa detik tanpa mengorbit
#   tier 3  >= 10 koin       -- UKURAN: raksasa 10x berdiri di belakang
#                               barisan, tidak menari, cuma melambai
#
# Kenapa bukan sekadar "tier 3 tapi lebih": penonton tidak menghitung
# efek. Yang mereka ingat cuma satu kalimat per tier -- "yang itu
# raksasa", "yang itu bikin panggung kosong" -- dan kalimat itu harus
# ada sebelum efeknya dipilih.
TIER_EFFECTS = {
    1: {
        "scale": _env_float("TIER1_SCALE", 1.0),
        "effects": [],
        "nameStyle": "plain",
        "spotlight": False,
    },
    2: {
        "scale": _env_float("TIER2_SCALE", 1.0),
        "effects": ["border"],
        "nameStyle": "gold",
        # Sekarang IKUT mengorbit, dan itu berubah dari sebelumnya.
        #
        # Dulu tier 2 sengaja tidak mengorbit supaya bedanya dengan tier 3
        # ada di JENIS gerakan, bukan cuma di lamanya. Alasan itu masih
        # benar, cuma pembedanya dipindah: yang membedakan sekarang
        # BERAPA BANYAK putarannya (tier 2 seperempat, tier 3 setengah,
        # diatur SINEMA_ORBIT_S per tier di Lua) plus aura VFX yang cuma
        # dipunyai tier 3. Dua tingkat masih terbaca sebagai dua tingkat;
        # yang hilang cuma "berputar atau tidak" sebagai penandanya.
        "spotlight": True,
        "orbit": True,
    },
    3: {
        # BADAN NORMAL sekarang. Raksasanya pindah ke tier 4.
        "scale": _env_float("TIER3_SCALE", 1.0),
        # Yang membedakan tier 3 dari tier 2 aura VFX acak di badannya
        # (satu dari tiga asset, dipilih di Lua) plus putaran kamera yang
        # penuh. Daftar ini keterangan, bukan perintah -- Lua bercabang
        # dari `tier` -- tapi dua sisi yang bercerita beda adalah cara
        # paling gampang menyesatkan orang yang membacanya nanti.
        "effects": ["border", "aura-vfx"],
        "nameStyle": "gold",
        "spotlight": True,
        "orbit": True,
    },
    4: {
        # Dibaca Lua sebagai skala raksasa. Di sini, bukan di Lua,
        # supaya bisa digeser lewat .env tanpa menyentuh Studio.
        "scale": _env_float("TIER4_SCALE", 3.0),
        # Cuma "giant" -- TANPA border, cakram, maupun aura. Yang membuat
        # tier 4 terbaca ukuran badannya, dan apa pun yang ditempel di
        # kakinya cuma menyaingi satu-satunya hal yang jadi intinya.
        "effects": ["giant"],
        "nameStyle": "gold",
        "spotlight": True,
        "orbit": True,
    },
}

# Ambang koin per tier.}

# Ambang koin per tier. HARUS sama dengan TIER2_KOIN/TIER3_KOIN di
# tiktok_listener.py -- listener yang memutuskan tier, di sini angkanya cuma
# dipakai buat menghitung panjang sorotan dan buat ditampilkan di
# /api/settings supaya alat lain tidak perlu menebak.
TIER2_KOIN = int(_env_float("TIER2_KOIN", 1))
TIER3_KOIN = int(_env_float("TIER3_KOIN", 10))
TIER4_KOIN = int(_env_float("TIER4_KOIN", 30))

# Lama sorotan tier 2 (1 koin). Sengaja DATAR: tidak ikut memanjang oleh
# koin seperti tier 3.
#
# Kenapa datar: tier 2 itu tiket masuk paling murah dan paling sering
# dipakai. Kalau panjangnya ikut naik oleh koin, orang yang menumpuk gift
# murah bisa menyamai lama sorotan tier 3 tanpa pernah naik podium -- dan
# 10 koin jadi kehilangan alasannya. Yang membedakan tier 3 sekarang dua
# hal sekaligus: podium, dan sorotan yang bisa memanjang.
SPOTLIGHT_MS_T2 = int(_env_float("SPOTLIGHT_MS_TIER2", 5000))

# Lama sorotan tier 3 (raksasa). Juga DATAR, dan alasannya berbeda dari
# tier 2: raksasa itu pose diam. Dia melambai sekali lalu berdiri saja,
# jadi sorotan yang memanjang cuma memperlihatkan hal yang sama lebih
# lama.
#
# Enam detik, bukan lima: badan 10x butuh waktu lebih lama untuk dibaca
# mata -- kamera harus sempat menyapu dari kaki ke kepala.
SPOTLIGHT_MS_T3 = int(_env_float("SPOTLIGHT_MS_TIER3", 7000))

# Lama sorotan tier 4 (raksasa). Juga DATAR, dan alasannya sama: raksasa
# itu pose diam -- dia melambai sekali lalu berdiri saja.
#
# Sembilan detik karena jalur kameranya punya TIGA perhentian (serong
# kiri -> serong kanan -> belakang). Dibagi tiga, tiap sudut dapat 3
# detik; di bawah itu perhentiannya berhenti terbaca sebagai perhentian
# dan yang terlihat cuma satu sapuan panjang.
SPOTLIGHT_MS_T4 = int(_env_float("SPOTLIGHT_MS_TIER4", 9000))

# Sanity guard untuk angka yang masuk lewat /api/push. Sama dengan
# KOIN_WARAS di tiktok_listener.py.
KOIN_WARAS        = 1_000_000


def _cek_sorotan_vs_jeda() -> None:
    """Peringatkan kalau sorotan bisa lebih lama dari jedanya.

    Kalau itu terjadi, sorotan berikutnya mulai selagi yang sekarang masih
    jalan -- dan Studio membuang yang kedua. Orang yang membayar tidak dapat
    sorotan sama sekali.

    Ketiga tier sekarang panjangnya DATAR, jadi ini tinggal tiga
    perbandingan. Dulu tier tertinggi memanjang ikut koin dan cek-nya harus
    menghitung dulu berapa panjang yang paling mungkin; itu ikut hilang
    bersama koin-memanjangkan-sorotan.
    """
    for tier, lama, jeda, nama in (
        (2, SPOTLIGHT_MS_T2, SPOTLIGHT_GAP_T2_S, "SPOTLIGHT_GAP_TIER2_S"),
        (3, SPOTLIGHT_MS_T3, SPOTLIGHT_GAP_T3_S, "SPOTLIGHT_GAP_TIER3_S"),
        (4, SPOTLIGHT_MS_T4, SPOTLIGHT_GAP_T4_S, "SPOTLIGHT_GAP_TIER4_S"),
    ):
        if lama >= jeda * 1000:
            print(
                f"[peringatan] sorotan tier {tier} {lama/1000:.1f}s >= "
                f"{nama} {jeda:.0f}s -- yang kedua akan dibuang Studio. "
                f"Naikkan jedanya."
            )


def durasi_sorotan(tier: int = 3) -> int:
    """Lama sorotan (ms) untuk sebuah tier.

    Tidak lagi bergantung koin. Ketiganya angka tetap, dan itu keputusan
    yang datang dari bentuk adegannya sendiri:

      tier 2  sorotan datar dan PENDEK, tiket masuk paling murah --
              yang menentukan berapa banyak yang kebagian, bukan seberapa
              megah satu sorotan
      tier 3  putaran kamera penuh + aura VFX, butuh waktu lebih supaya
              dua-duanya sempat terlihat
      tier 4  raksasa itu pose diam -- panjangnya ditentukan jalur kamera
              tiga perhentian, bukan oleh badannya

    Yang membedakan kiriman besar bukan lamanya, tapi BENTUKNYA: 1 koin
    dapat perhatian, 10 koin dapat aura, 30 koin jadi raksasa.
    """
    if tier < 3:
        return SPOTLIGHT_MS_T2
    if tier == 3:
        return SPOTLIGHT_MS_T3
    return SPOTLIGHT_MS_T4

# Jeda khusus sorotan tier 2. Lebih pendek dari tier 3 karena sorotannya
# sendiri lebih pendek (5 detik vs 7 detik ke atas) -- dan karena tier 2
# datang jauh lebih sering, memakai jeda tier 3 untuknya berarti sebagian
# besar yang bayar 1 koin tidak pernah kebagian.
#
# Batas bawahnya bukan selera: sorotan tier 2 + fade keluar (~0,6 detik di
# Lua) harus SELESAI sebelum yang berikutnya mulai, kalau tidak Studio
# membuang yang kedua lewat penjaga `spotlightBusy`.
SPOTLIGHT_GAP_T2_S = _env_float("SPOTLIGHT_GAP_TIER2_S", 7.0)

# Jeda tier 3. Di antara keduanya, sejalan dengan sorotannya yang juga
# di antara keduanya (6 detik).
SPOTLIGHT_GAP_T3_S = _env_float("SPOTLIGHT_GAP_TIER3_S", 9.0)

# Jeda tier 4 (raksasa). Paling panjang karena sorotannya paling panjang;
# syaratnya sama seperti yang lain -- harus lebih besar dari sorotannya
# sendiri plus fade keluar, kalau tidak Studio membuang sorotan
# berikutnya dan yang bayar 30 koin tidak dapat apa-apa.
SPOTLIGHT_GAP_T4_S = _env_float("SPOTLIGHT_GAP_TIER4_S", 11.0)


def _jeda_sorotan(tier: int) -> float:
    """Jeda minimal yang harus dilewati sebelum tier ini boleh disorot."""
    if tier == 2:
        return SPOTLIGHT_GAP_T2_S
    if tier == 3:
        return SPOTLIGHT_GAP_T3_S
    return SPOTLIGHT_GAP_T4_S

# Kapan sorotan terakhir disajikan. None = belum pernah.
last_spotlight_at: float | None = None

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
    """Endpoint tes paling dasar untuk memastikan jalur ngrok tembus."""
    return {"test": "ok"}


@app.post("/api/push")
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
        # Kiriman berikutnya dari orang yang sama untuk nama yang sama
        # DIGABUNG, bukan ditambahkan sebagai entri kedua.
        #
        # Tanpa ini, "rosa x10" lalu "rosa x20" jadi dua entri. Keduanya
        # masuk lewat appendleft, jadi yang keluar duluan justru yang
        # TERBARU -- penonton melihat x20 dulu, lalu x10 menggantikannya
        # beberapa detik kemudian. Terbaca seperti angkanya turun.
        for lama in queue:
            if (lama["tier"] >= 2
                    and lama["username"] == name
                    and lama.get("tiktokUser") == req.tiktokUser):
                lama["tier"] = max(lama["tier"], tier)
                # Diambil yang TERBESAR, bukan dijumlah: listener sudah
                # mengirim total kumulatifnya. Menjumlah lagi di sini
                # membuat kiriman yang sama dihitung dua kali.
                lama["koin"] = max(lama.get("koin", 0), koin)
                return {
                    "ok": True, "queued": name, "tier": lama["tier"],
                    "koin": lama["koin"], "merged": True, "size": len(queue),
                }

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

    Entri tier 3 memicu sorotan yang menghentikan panggung beberapa detik.
    Kalau sorotan sebelumnya baru saja jalan, entri itu DITAHAN di tempatnya
    dan entri biasa yang disajikan lebih dulu -- jadi sorotan tersebar sendiri
    tanpa ada yang diturunkan tiernya.

    Kalau isi antrian kebetulan sorotan semua dan jedanya belum lewat,
    kembalikan None: Studio menunggu satu-dua polling lagi, lebih baik daripada
    dua sorotan menempel.
    """
    global last_spotlight_at

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

    jeda = _jeda_sorotan(depan["tier"])
    boleh_sorot = last_spotlight_at is None or (now - last_spotlight_at) >= jeda

    if boleh_sorot:
        entry = queue.popleft()
        if TIER_EFFECTS[entry["tier"]]["spotlight"]:
            last_spotlight_at = now
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
        # Apakah kameranya MENGORBIT atau cuma menahan dekat. Ini yang
        # membedakan sorotan tier 2 dari tier 3/4 -- lihat TIER_EFFECTS.
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
        "spotlightMsTier2": SPOTLIGHT_MS_T2,
        "spotlightMsTier3": SPOTLIGHT_MS_T3,
        "koinTier2": TIER2_KOIN,
        "koinTier3": TIER3_KOIN,
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


@app.delete("/api/clear")
def clear():
    """Kosongkan antrian. Debugging saja."""
    n = len(queue)
    queue.clear()
    return {"ok": True, "cleared": n}


@app.delete("/api/cache")
def clear_cache():
    """Kosongkan cache displayName. Berguna kalau ada yang ganti nama."""
    n = len(display_cache)
    display_cache.clear()
    return {"ok": True, "cleared": n}