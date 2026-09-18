"""
Baca komentar TikTok Live, saring yang berupa username Roblox, lalu dorong ke
antrian server (`POST /api/push`). Menggantikan langkah manual "hit /api/push
lewat Postman".

Jalankan:
    .venv/bin/python tiktok_listener.py <username_tiktok>     # tanpa @, akun HARUS lagi live
    .venv/bin/python tiktok_listener.py <username_tiktok> --debug

Uji parser/verifikasi tanpa live (nggak perlu ada yang siaran):
    .venv/bin/python tiktok_listener.py --self-test "Roblox"

Alur lengkapnya:
    komentar TikTok -> parse_username() -> blacklist -> cooldown per-penonton
    -> dedupe username -> verifikasi ke Roblox -> POST /api/push
    -> Roblox Studio polling /api/next seperti biasa.

Yang di antrian tetap main.py; file ini cuma pengisi antrian, jadi sisi Roblox
Studio tidak perlu diubah sama sekali.

Butuh EULERSTREAM_API_KEY di .env. Tanpa itu TikTokLive masih bisa connect,
tapi gampang kena rate-limit diam-diam pas live lagi ramai.
"""

import argparse
import asyncio
import json
import logging
import os
import re
import time
from pathlib import Path

import httpx
from dotenv import load_dotenv
from TikTokLive import TikTokLiveClient
from TikTokLive.client.logger import LogLevel
from TikTokLive.client.errors import UserNotFoundError, UserOfflineError
from TikTokLive.client.web.web_settings import WebDefaults
from TikTokLive.events import (CommentEvent, ConnectEvent, DisconnectEvent,
                               GiftEvent, LikeEvent)

# Konteks SSL tanpa ALPN — bukan gaya-gayaan: tanpa itu request ke
# users.roblox.com menggantung sampai timeout. Alasan lengkap ada di docstring
# _NoALPNContext. Diimpor, bukan disalin, supaya kalau Roblox memperbaikinya
# nanti cukup satu tempat yang diubah.
from roblox_ssl import USERS_API, _make_ssl_context

load_dotenv()

BASE_DIR = Path(__file__).resolve().parent


def _env_float(name: str, default: float) -> float:
    try:
        return float(os.environ[name])
    except (KeyError, ValueError):
        return default


# ------------------------------------------------------------------ SETELAN --

# Ke mana username dikirim. Ini server antrian (main.py), bukan server viewer.
PUSH_URL = os.environ.get("PUSH_URL", "http://127.0.0.1:8000/api/push")

# Harus sama dengan API_TOKEN di .env server (VM). Dikirim cuma ke PUSH_URL,
# tidak dipasang di header bawaan client: client yang sama juga memanggil
# users.roblox.com, dan kunci ini tidak ada urusannya di sana.
API_TOKEN = os.environ.get("API_TOKEN", "")

# Jeda minimal antar-summon untuk SATU penonton yang sama. Tanpa ini, satu orang
# bisa mengisi seluruh antrian sendirian.
USER_COOLDOWN_S = _env_float("USER_COOLDOWN_S", 45.0)

# Username Roblox yang sama tidak didorong ulang selama jendela ini, siapa pun
# yang mengetiknya. Pas live ramai, satu nama viral bisa diketik puluhan orang.
NAME_DEDUPE_S = _env_float("NAME_DEDUPE_S", 60.0)

# Verifikasi dulu ke Roblox sebelum masuk antrian. WAJIB nyala kalau
# REQUIRE_SINGLE_WORD juga nyala: tanpa verifikasi, tiap komentar satu kata
# ("mantap", "halo") ikut jadi username dan antrian penuh sampah.
VERIFY_ROBLOX = os.environ.get("VERIFY_ROBLOX", "1") != "0"

# Komentar lebih dari satu kata diabaikan. Trigger-nya memang username polos;
# menyisir tiap kata dalam kalimat bikin request ke Roblox meledak.
REQUIRE_SINGLE_WORD = os.environ.get("REQUIRE_SINGLE_WORD", "1") != "0"

BLACKLIST_PATH = Path(os.environ.get("BLACKLIST_PATH", BASE_DIR / "roblox_blacklist.txt"))


# ---------------------------------------------------------------------- TIER --

# Tier ditentukan NAMA GIFT dulu, baru harganya kalau namanya tidak dikenal.
#
#   tier 1  komentar biasa
#   tier 2  Rose            skip lane + cakram biru, sorotan 3 detik
#   tier 3  Rosa / tap      AURA (efek partikel acak di badan)
#   tier 4  Bouquet Flower  UPACARA (nova)
#   tier 5  Doughnut        UKURAN (raksasa)
#
# KENAPA NAMA, dan kenapa ini membalik keputusan yang dulu tertulis di sini.
#
# Dulu tier dihitung dari JUMLAH koin, dan jumlah itu DITAMBAHKAN tiap gift
# selama jendela GIFT_BOOST_TTL_S. Tujuannya combo: rose x10 = 10 koin =
# sama dengan sekali rosa. Tapi penjumlahan tidak pernah turun, dan itu yang
# bikin bug yang terlihat di siaran: kirim Doughnut (30) lalu Rose (1) =
# 31 koin = RAKSASA LAGI, padahal yang barusan dikirim cuma Rose. Sekali
# jadi raksasa, gift apa pun sesudahnya tetap raksasa.
#
# Sekarang tiap gift menentukan tiernya SENDIRI dan tidak ada yang
# dijumlah. Rose lagi = spawn Rose lagi. Bouquet lagi = nova lagi, tidak
# naik ke raksasa.
#
# Harganya juga tidak bisa lagi jadi satu-satunya penentu: Bouquet Flower
# dan Doughnut sama-sama 30 koin, dan dari koin saja keduanya tidak bisa
# dibedakan -- salah satunya tidak akan pernah tercapai.
#
# Yang DILEPAS untuk ini, sengaja: nyicil tidak lagi dihitung. Rose dikirim
# sepuluh kali terpisah = sepuluh spawn Rose, bukan satu Rosa.
#
# Nama dicocokkan tanpa peduli huruf besar-kecil dan spasi berlebih. Bisa
# ditimpa lewat .env, misal kalau TikTok ternyata menamainya "Flower
# Bouquet":
#
#     GIFT_TIER=rose:2,rosa:3,bouquet flower:4,doughnut:5
#
# Nama yang sebenarnya dikirim TikTok selalu tercetak di log [gift], jadi
# ejaannya dicocokkan dari situ, bukan ditebak.
#
# SUSUNAN SEKARANG (digeser satu tingkat dari aslinya). Nomor di sini nomor
# EFEK di panggung, bukan urutan harga:
#
#   Rose           -> 3  adegan sinematik (garis tepi, aura VFX, letterbox)
#   Rosa           -> 4  nova
#   Doughnut       -> 5  raksasa
#
# Tier 2 (cakram biru) tidak dipakai gift apa pun lagi. Bouquet Flower
# sengaja tidak tercantum: dia ikut harganya (30 koin), jadi raksasa.
# Yang digeser cuma daftar ini dan ambang koin di bawah, bukan nomor tier
# di Lua -- efek tiap nomor tetap persis sama, cuma pemicunya yang pindah.
GIFT_TIER_BAWAAN = "rose:3,rosa:4,doughnut:5"


def _normal_nama_gift(nama: str) -> str:
    return " ".join((nama or "").lower().split())


def _baca_gift_tier(teks: str) -> dict[str, int]:
    hasil: dict[str, int] = {}
    for bagian in teks.split(","):
        if ":" not in bagian:
            continue
        nama, _, angka = bagian.rpartition(":")
        try:
            hasil[_normal_nama_gift(nama)] = int(angka.strip())
        except ValueError:
            continue
    return hasil


GIFT_TIER = _baca_gift_tier(os.environ.get("GIFT_TIER", GIFT_TIER_BAWAAN))

# Gift yang namanya TIDAK ada di GIFT_TIER jatuh ke harganya.
#
# Ini yang menutup lubang yang dulu membuat tabel nama dibuang: TikTok punya
# ratusan gift, dan kalau yang tak tercantum jatuh ke tier 1, orang yang
# kirim Lion 29.999 koin dapat perlakuan sama dengan yang cuma ngetik.
#
# Tier 4 (nova) sengaja TIDAK punya ambang koin: Bouquet Flower harganya
# sama dengan Doughnut, jadi gift tak dikenal seharga 30 koin ke atas
# jatuhnya ke yang tertinggi -- raksasa.
#
# Harga yang dipakai harga SATU gift, bukan dikali combo. Konsisten dengan
# aturan nama: Rose x10 tetap Rose, jadi Finger Heart x10 juga tetap
# seharga satu Finger Heart.
#
# TIER3_KOIN = 1 menutup tier 2 sepenuhnya: semua gift berbayar di bawah
# TIER5_KOIN jatuh ke adegan sinematik, setara Rose. TIER2_KOIN dibiarkan
# ada supaya .env lama tetap terbaca, tapi cabangnya tidak pernah tercapai
# selama dia tidak di bawah TIER3_KOIN.
TIER2_KOIN = int(_env_float("TIER2_KOIN", 1))    # tidak tercapai (lihat di atas)
TIER3_KOIN = int(_env_float("TIER3_KOIN", 1))    # 1-29 koin   -> tier 3 (sinematik, setara Rose)
TIER5_KOIN = int(_env_float("TIER5_KOIN", 30))   # >=30 koin   -> tier 5 (raksasa)


def tier_dari_koin(koin: int) -> int:
    """Tier untuk gift yang namanya tidak dikenal, dari harga satuannya.

    Dibaca dari ambang TERTINGGI ke terendah. Urutan itu bukan gaya
    penulisan: dibalik, 30 koin akan berhenti di cabang tier 2 yang juga
    cocok, dan tidak ada satu pun tier di atasnya yang pernah tercapai.
    """
    if koin >= TIER5_KOIN:
        return 5
    if koin >= TIER3_KOIN:
        return 3
    if koin >= TIER2_KOIN:
        return 2
    return 1


def tier_dari_gift(nama: str, koin_satuan: int) -> tuple[int, str]:
    """(tier, asal) untuk satu gift. `asal` = "nama" atau "koin", untuk log.

    Satu-satunya tempat aturan gift -> tier hidup.
    """
    tier = GIFT_TIER.get(_normal_nama_gift(nama))
    if tier is not None:
        return tier, "nama"
    return tier_dari_koin(koin_satuan), "koin"


# COMBO: jumlah combo = jumlah spawn.
#
#   Rosa x3          -> 3 spawn Rosa
#   Doughnut x3      -> 3 raksasa
#   Finger Heart x3  -> 3 spawn di tier harganya
#
# Satu pengecualian, dan cuma satu: gift di GIFT_NAIK DITAMPUNG. Tiap
# kelipatannya dinaikkan jadi satu spawn tier yang lebih tinggi, dan
# sisanya tetap spawn satu per satu di tiernya sendiri:
#
#   Rose x3   -> 3 Rose
#   Rose x10  -> 1 Rosa (nova)
#   Rose x25  -> 2 Rosa + 5 Rose
#
# Yang TIDAK berubah dari aturan tier: kiriman TERPISAH tetap tidak pernah
# dijumlah. Penampungan ini cuma di dalam SATU combo -- Rose x5 lalu Rose x5
# (dua combo) tetap 10 Rose, bukan 1 Rosa. Menjumlah kiriman terpisah itu
# jalur yang dulu membuat Doughnut lalu Rose jadi raksasa lagi.
#
# Dan naiknya cuma ke tier yang ditulis di sini (Rosa, sekarang nova). Rose
# x10.000 tetap 1.000 nova -- tidak ada jalan dari Rose ke raksasa.
#
# Tidak ada batas jumlah spawn per combo, sengaja (keputusan produk):
# Rose x500 = 50 Rosa yang antre satu per satu, dan gift berbayar lain yang
# datang sesudahnya menunggu di belakangnya.
#
# Formatnya "nama:berapa:tier", dipisah koma. Bisa ditimpa lewat .env:
#
#     GIFT_NAIK=rose:10:4
GIFT_NAIK_BAWAAN = "rose:10:4"


def _baca_gift_naik(teks: str) -> dict[str, tuple[int, int]]:
    hasil: dict[str, tuple[int, int]] = {}
    for bagian in teks.split(","):
        potong = bagian.rsplit(":", 2)
        if len(potong) != 3:
            continue
        try:
            per, tier = int(potong[1].strip()), int(potong[2].strip())
        except ValueError:
            continue
        if per > 0:
            hasil[_normal_nama_gift(potong[0])] = (per, tier)
    return hasil


GIFT_NAIK = _baca_gift_naik(os.environ.get("GIFT_NAIK", GIFT_NAIK_BAWAAN))


def _ringkas_spawn(spawn: list[tuple[int, int]]) -> str:
    """[(3,10),(3,10),(2,1)] -> "2x tier 3 + 1x tier 2", untuk log."""
    hitung: dict[int, int] = {}
    for t, _ in spawn:
        hitung[t] = hitung.get(t, 0) + 1
    return " + ".join(f"{n}x tier {t}" for t, n in hitung.items())


def rincian_gift(nama: str, jumlah: int, koin_satuan: int) -> list[tuple[int, int]]:
    """Satu kiriman gift -> daftar spawn [(tier, koin), ...], urut tampil.

    `koin` di tiap spawn = harga yang membeli spawn ITU (Rosa hasil tampungan
    10 Rose tertulis 10 koin), bukan total combo -- supaya angka di log dan
    papan tidak berbohong soal satu avatar.

    Yang dinaikkan tampil DULUAN, baru sisanya: yang lebih mahal yang
    membuka, sama seperti urutan orang membayar untuk sesuatu yang besar.
    Daftar kosong = gift ini tidak memberi apa-apa (gratis / tier 1).
    """
    jumlah = max(1, int(jumlah or 1))
    koin_satuan = max(0, int(koin_satuan or 0))
    tier, _ = tier_dari_gift(nama, koin_satuan)
    if tier <= 1:
        return []

    naik = GIFT_NAIK.get(_normal_nama_gift(nama))
    if not naik:
        return [(tier, koin_satuan)] * jumlah

    per, tier_naik = naik
    return ([(tier_naik, koin_satuan * per)] * (jumlah // per)
            + [(tier, koin_satuan)] * (jumlah % per))


# Sanity guard, bukan aturan main. Gift termahal TikTok ada di kisaran
# 45.000 koin; apa pun di atas sejuta artinya datanya rusak, bukan orang
# kaya.
#
# Panjang sorotan TIDAK lagi ikut koin: keempat tier punya durasi datar
# (SPOTLIGHT_MS_TIER* di main.py), jadi tidak ada yang bisa memanjang
# liar karena angka besar. Yang dibatasi angka ini cuma kewarasan
# datanya sendiri.
#
# Klamp-nya tetap tidak dipakai untuk mengubah angka yang ditulis di
# papan: yang tampil harus angka yang benar-benar dia bayar.
KOIN_WARAS = 1_000_000

# Orang hampir selalu kirim gift DULU, baru ngetik username beberapa detik
# kemudian. Boost-nya disimpan selama ini, menunggu komentar berikutnya dari
# orang yang sama. Tanpa jendela ini, mayoritas gift jatuh jadi tier 1 dan
# pengirimnya merasa uangnya hilang.
GIFT_BOOST_TTL_S = _env_float("GIFT_BOOST_TTL_S", 90.0)

# --------------------------------------------------------------------- LIKE --

# Berapa kali tap layar untuk naik ke tier 2 (aura) tanpa mengeluarkan koin
# sama sekali.
#
# Ini jalur GRATIS, dan sengaja mahal dalam usaha. Gunanya bukan menyaingi
# gift, tapi memberi penonton yang tidak mau bayar satu hal yang bisa mereka
# kejar -- dan tap-tap itu yang mendorong live-nya naik di beranda TikTok.
#
# Turun 2.000 -> 1.000, dan alasannya data, bukan selera: tiga live
# sungguhan mencatat 296, 641, dan 897 tap SEPANJANG SIARAN, dijumlah dari
# SEMUA penonton. TikTok tidak mengirim satu event per tap -- tap digabung
# dan sebagian tidak pernah dikirim sama sekali -- jadi angka yang sampai ke
# sini jauh di bawah yang dirasakan jari penontonnya. Dengan 2.000 per orang
# jalur ini mustahil tercapai, dan itu sebabnya tier dari tap tidak pernah
# muncul. Angka yang kebaca per orang sekarang ikut dicetak di [detak]
# ("tap terbanyak"): setel angka ini dari situ, bukan dari tebakan.
#
# Hitungannya AKUMULATIF per penonton dan berulang: tiap kelipatan angka ini
# tercapai, dia dapat satu kali tier 2 lagi, sisanya diteruskan ke hitungan
# berikutnya. Tidak ada kedaluwarsa -- orang yang nyicil tap sepanjang
# siaran tetap sampai.
LIKE_PODIUM = int(_env_float("LIKE_PODIUM", 1000))

# Tier yang didapat lewat tap saja.
#
# Setara Rosa: AURA. Bukan lebih -- nova (Bouquet Flower) dan raksasa
# (Doughnut) itu yang DIJUAL, dan kalau tap juga bisa sampai ke sana,
# keduanya kehilangan alasannya untuk dibeli.
#
# Naik dari tier Rose ke tier Rosa waktu Rose turun jadi "skip lane +
# cakram biru" saja. Tap itu usaha yang besar (1.000 per orang), dan
# hadiahnya tidak boleh lebih kecil daripada gift 1 koin.
#
# Tap sekarang spawn SENDIRI, bukan digabung ke gift yang kebetulan
# menunggu. Sama dengan aturan gift: tiap hal yang didapat = satu spawn.
LIKE_TIER = int(_env_float("LIKE_TIER", 3))

# Tiap kelipatan segini dicatat di log, supaya kamu bisa mengumumkan
# progresnya saat live ("tinggal 500 lagi"). 0 = tidak usah dicatat.
LIKE_LOG_EVERY = int(_env_float("LIKE_LOG_EVERY", 500))

# Berapa lama hak podium hasil tap menunggu username, kalau saat ambangnya
# tercapai orangnya belum pernah mengetik nama Roblox. Sama panjang dengan
# jendela boost gift, dengan alasan yang sama: orang mengetik nama SESUDAH
# melakukan sesuatu, bukan sebelumnya.
LIKE_PODIUM_TTL_S = _env_float("LIKE_PODIUM_TTL_S", GIFT_BOOST_TTL_S)

USERNAME_MIN_LEN = 3
USERNAME_MAX_LEN = 20

# Aturan Roblox: alfanumerik + underscore, underscore tidak di awal/akhir.
# Jumlah underscore sengaja tidak dibatasi satu (aturan asli Roblox) supaya
# akun lama yang punya lebih dari satu tidak ditolak duluan di sini —
# yang tidak ada tetap tersaring di langkah verifikasi.
USERNAME_RE = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9_]*[A-Za-z0-9])?$")

# 1 nama = 1 request ke Roblox, jadi hasilnya di-cache. Yang tidak ketemu
# di-cache lebih pendek: orang sering salah ketik lalu membetulkannya.
CACHE_TTL_S = _env_float("CACHE_TTL_S", 12 * 3600)
NEG_CACHE_TTL_S = _env_float("NEG_CACHE_TTL_S", 300.0)

if os.environ.get("EULERSTREAM_API_KEY"):
    WebDefaults.tiktok_sign_api_key = os.environ["EULERSTREAM_API_KEY"]

logging.basicConfig(level=logging.INFO, format="%(asctime)s  %(message)s", datefmt="%H:%M:%S")
log = logging.getLogger("tiktok_listener")

# httpx mencatat tiap request di level INFO. Satu komentar = 2 baris log yang
# menenggelamkan log kita sendiri, jadi dinaikkan ke WARNING.
logging.getLogger("httpx").setLevel(logging.WARNING)


# ------------------------------------------------------------------ PARSING --

def parse_username(text: str) -> str | None:
    """Ambil kandidat username Roblox dari satu komentar, atau None.

    '@' di depan ditoleransi — penonton yang terbiasa nge-mention tidak perlu
    diajari ulang. Penyaring ini sengaja ketat: tiap yang lolos berujung
    request ke Roblox.
    """
    if not text:
        return None

    parts = text.strip().split()
    if not parts:
        return None
    if REQUIRE_SINGLE_WORD and len(parts) != 1:
        return None

    candidate = parts[0].lstrip("@").strip()

    if not (USERNAME_MIN_LEN <= len(candidate) <= USERNAME_MAX_LEN):
        return None
    if not USERNAME_RE.match(candidate):
        return None

    return candidate


def load_blacklist() -> set[str]:
    """Baca daftar blokir (huruf kecil). File tidak ada = tidak ada yang diblokir."""
    try:
        raw = BLACKLIST_PATH.read_text(encoding="utf-8")
    except OSError:
        return set()

    names = set()
    for line in raw.splitlines():
        line = line.split("#", 1)[0].strip().lower()
        if line:
            names.add(line)
    return names


def extract_username(user) -> str:
    """Username TikTok penonton.

    `.unique_id` cuma ada di ExtendedUser, dan library kadang mengirim User
    polos — `display_id` yang selalu ada, jadi dipakai sebagai cadangan.
    """
    for attr in ("unique_id", "display_id"):
        value = getattr(user, attr, None)
        if value:
            return value
    return getattr(user, "nickname", None) or "unknown"


# ------------------------------------------------------------------ PIPELINE --

class Pipeline:
    """Semua state antar-komentar: cooldown, dedupe, cache, HTTP client."""

    def __init__(self, dry_run: bool = False, show_comments: bool = False):
        self.dry_run = dry_run
        self.show_comments = show_comments
        self.blacklist = load_blacklist()

        self._cooldown: dict[str, float] = {}          # username TikTok -> monotonic terakhir
        self._recent_names: dict[str, float] = {}      # username Roblox (lower) -> monotonic
        self._roblox_cache: dict[str, tuple[bool, float]] = {}  # nama -> (ada, kedaluwarsa)
        # penonton -> gift yang belum terpakai, URUT dari yang dikirim duluan.
        # Tiap isinya (tier, koin, nama gift, kedaluwarsa).
        #
        # Daftar, bukan satu angka: dua gift sebelum dia ngetik username =
        # dua spawn, berurutan, tidak ada yang dilewati. Dulu isinya satu
        # angka koin yang DIJUMLAH, dan penjumlahan itu yang membuat
        # Doughnut lalu Rose jadi raksasa lagi.
        self._boost: dict[str, list[tuple[int, int, str, float]]] = {}
        # Username Roblox terakhir yang berhasil dipanggil tiap penonton,
        # dan sampai kapan dia diingat. Ini yang membuat urutan "username
        # dulu, baru gift" ikut jalan. Koinnya tidak disimpan lagi -- tidak
        # ada lagi yang dijumlah.
        self._nama_terakhir: dict[str, tuple[str, float]] = {}
        # penonton -> tap yang belum ditukar jadi tier LIKE_TIER. Yang disimpan
        # SISANYA, bukan totalnya: begitu LIKE_PODIUM tercapai angkanya
        # dikurangi sebanyak itu, jadi tap berikutnya sudah mulai menabung
        # untuk giliran berikutnya.
        self._likes: dict[str, int] = {}
        # penonton -> total tap yang PERNAH tercatat sepanjang siaran, tidak
        # pernah dikurangi. Cuma untuk laporan [detak]: angka inilah yang
        # memberi tahu seberapa realistis LIKE_PODIUM untuk live kamu.
        self._likes_total: dict[str, int] = {}
        # penonton -> kedaluwarsa hak podium yang sudah dia menangkan lewat
        # tap tapi belum sempat dipakai karena username-nya belum disebut.
        self._podium_pending: dict[str, float] = {}
        self._tasks: set[asyncio.Task] = set()

        self._client: httpx.AsyncClient | None = None
        self.seen = 0          # semua komentar yang masuk, termasuk obrolan biasa
        self.pushed = 0
        self.rejected = 0

        # Berapa yang masuk antrian per tier. Dipakai mock_comments untuk
        # membuktikan simulasinya benar-benar menyentuh keempat tier --
        # "mock-nya jalan" dan "mock-nya menguji yang kamu kira" itu dua
        # hal berbeda, dan tanpa angka ini keduanya terlihat sama.
        #
        # Saat live sungguhan angkanya ikut dicetak waktu Ctrl+C, dan di
        # situ dia menjawab pertanyaan yang berbeda: berapa banyak yang
        # benar-benar bayar malam ini, dipecah per tingkat.
        # Kelima kunci ada supaya tier yang tidak dicapai siapa pun ikut
        # tercetak di ringkasan sebagai nol. Penambahannya sendiri lewat
        # .get(tier, 0), jadi tier tak terdaftar tidak akan error --
        # cuma tidak akan pernah muncul di laporan.
        self.per_tier = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
        self.gifts = 0         # gift yang harganya kebaca
        self.boost_hangus = 0  # gift yang tidak pernah disusul komentar
        self.likes = 0         # tap yang tercatat sepanjang siaran
        self.podium_like = 0   # berapa kali ambang tap tercapai

    async def open(self) -> None:
        self._client = httpx.AsyncClient(
            timeout=httpx.Timeout(8.0, connect=5.0),
            headers={"User-Agent": "tt-rblx-listener/0.1", "Accept": "application/json"},
            verify=_make_ssl_context(),
        )

    async def aclose(self) -> None:
        # Task komentar yang masih jalan diselesaikan dulu, baru client ditutup —
        # kalau terbalik, task yang tersisa memakai client yang sudah mati.
        if self._tasks:
            await asyncio.gather(*self._tasks, return_exceptions=True)
        if self._client is not None:
            await self._client.aclose()

    def spawn(self, tiktok_user: str, nickname: str, text: str) -> None:
        """Proses komentar di background.

        Sengaja tidak di-await di handler event: verifikasi ke Roblox bisa
        makan beberapa ratus milidetik, dan komentar berikutnya tidak boleh
        ikut tertahan karenanya.
        """
        task = asyncio.create_task(self.handle(tiktok_user, nickname, text))
        # Tanpa referensi kuat, asyncio boleh membuang task yang belum selesai.
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)

    async def handle_gift(self, tiktok_user: str, nickname: str,
                          gift_name: str, jumlah: int = 1,
                          koin_satuan: int = 0) -> None:
        """Proses gift. Jumlah combo = jumlah spawn (lihat rincian_gift).

        Dua urutan yang sama-sama harus jalan:

        1. GIFT DULU, baru username -> gift-nya disimpan di daftar tunggu,
           menunggu komentar berikutnya dari orang itu (paling lama
           GIFT_BOOST_TTL_S). Semua spawn dari semua gift yang menunggu
           keluar berurutan begitu dia ngetik.
        2. USERNAME DULU, baru gift -> avatarnya sudah/sedang tampil, jadi
           langsung didorong lagi dengan tier gift yang barusan. Tanpa
           jalur ini, orang yang ngetik dulu baru bayar tidak dapat apa-apa
           sampai dia mengetik untuk kedua kalinya -- dan kebanyakan tidak
           melakukannya.

        Tidak ada yang dijumlah ANTAR kiriman di kedua jalur. Di dalam satu
        kiriman, jumlah combo = jumlah spawn -- lihat rincian_gift.

        `koin_satuan` itu harga SATU gift (`gift.diamond_count`).
        """
        koin_satuan = max(0, int(koin_satuan or 0))
        jumlah = max(1, int(jumlah or 1))
        tier, asal = tier_dari_gift(gift_name, koin_satuan)
        spawn = rincian_gift(gift_name, jumlah, koin_satuan)

        if not spawn:
            # Gift gratis, atau harganya tidak terbaca dan namanya tidak
            # dikenal. Bukan error: TikTok memang punya gift 0 koin, dan
            # itu memang tidak layak dibayar dengan tempat di panggung.
            log.info("[gift] '%s' dari %s (%s koin) tidak memberi tier, dilewati",
                     gift_name, nickname, koin_satuan)
            return

        self.gifts += 1
        now = time.monotonic()
        ringkas = _ringkas_spawn(spawn)

        # --- urutan 2: dia baru saja menyebut username ---
        terakhir = self._nama_terakhir.get(tiktok_user)
        if terakhir and now < terakhir[1]:
            nama = terakhir[0]
            log.info("[gift] %s kirim %s x%s (tier %s dari %s) -> '%s' spawn lagi: %s",
                     nickname, gift_name, jumlah, tier, asal, nama, ringkas)

            # Satu per satu, di-await, supaya urutan antriannya = urutan di
            # daftar. Yang gagal di tengah jalan (server antrian mati?)
            # beserta sisanya jatuh ke jalur simpan di bawah, supaya tidak
            # ada yang hilang.
            terkirim = 0
            for t, k in spawn:
                if not await self.push(nama, nickname, t, k):
                    break
                terkirim += 1
            if terkirim:
                self._nama_terakhir[tiktok_user] = (nama, now + GIFT_BOOST_TTL_S)
            if terkirim == len(spawn):
                return
            spawn = spawn[terkirim:]

        # --- urutan 1: simpan, tunggu username ---
        daftar = self._boost.setdefault(tiktok_user, [])
        for t, k in spawn:
            daftar.append((t, k, gift_name, now + GIFT_BOOST_TTL_S))
        log.info("[gift] %s kirim %s x%s (tier %s dari %s) -> %s, "
                 "menunggu username (%.0fs) -- %s spawn antri",
                 nickname, gift_name, jumlah, tier, asal, ringkas,
                 GIFT_BOOST_TTL_S, len(daftar))

    async def handle_like(self, tiktok_user: str, nickname: str,
                          jumlah: int = 1) -> None:
        """Tap layar. Tiap LIKE_PODIUM tap = satu podium, gratis.

        Jalannya persis seperti gift, dan memang harus begitu supaya dua
        urutan yang sama-sama sering terjadi ikut terlayani:

        1. TAP DULU, baru username -> haknya disimpan, menunggu komentar
           berikutnya dari orang itu (paling lama LIKE_PODIUM_TTL_S).
        2. USERNAME DULU, baru tap -> avatarnya sudah berdiri di kerumunan,
           jadi langsung didorong lagi sebagai tier LIKE_TIER tanpa perlu
           mengetik namanya lagi.

        Yang TIDAK ikut: koin. Orang ini tidak membayar apa pun, jadi angka
        koinnya 0 -- kalau tap diterjemahkan jadi "10 koin", papan berbohong
        ke penonton lain tentang siapa yang sebenarnya mengeluarkan uang.
        """
        jumlah = max(1, int(jumlah or 1))
        self.likes += jumlah
        self._likes_total[tiktok_user] = self._likes_total.get(tiktok_user, 0) + jumlah

        total = self._likes.get(tiktok_user, 0) + jumlah

        if total < LIKE_PODIUM:
            self._likes[tiktok_user] = total
            if LIKE_LOG_EVERY > 0 and (
                    total // LIKE_LOG_EVERY) > ((total - jumlah) // LIKE_LOG_EVERY):
                log.info("[like] %s sudah %s tap, kurang %s lagi buat podium",
                         nickname, total, LIKE_PODIUM - total)
            return

        # Kelebihan tap TIDAK dibuang: 2.100 tap = dua podium, sisa 100 tap
        # jalan terus ke hitungan berikutnya. Yang dipakai cuma satu podium
        # sekarang -- mendorong dua avatar sekaligus untuk orang yang sama
        # cuma menghasilkan podium kembar bernama sama.
        self._likes[tiktok_user] = total % LIKE_PODIUM
        self.podium_like += 1
        now = time.monotonic()

        # --- urutan 2: dia baru saja menyebut username ---
        terakhir = self._nama_terakhir.get(tiktok_user)
        if terakhir and now < terakhir[1]:
            nama = terakhir[0]
            log.info("[like] %s tembus %s tap -> '%s' spawn tier %s (tanpa koin)",
                     nickname, LIKE_PODIUM, nama, LIKE_TIER)
            if await self.push(nama, nickname, LIKE_TIER, 0, podium=True):
                self._nama_terakhir[tiktok_user] = (nama, now + GIFT_BOOST_TTL_S)
                return
            # Push gagal (server antrian mati?) -- haknya disimpan di bawah
            # supaya tap-nya tidak hilang begitu saja.

        # --- urutan 1: simpan, tunggu username ---
        self._podium_pending[tiktok_user] = now + LIKE_PODIUM_TTL_S
        log.info("[like] %s tembus %s tap -> berhak podium, menunggu username (%.0fs)",
                 nickname, LIKE_PODIUM, LIKE_PODIUM_TTL_S)

    def _lihat_podium(self, tiktok_user: str) -> bool:
        """Hak podium hasil tap yang sedang menunggu, TANPA memakainya.

        Sama seperti boost koin: baru dianggap terpakai setelah avatarnya
        benar-benar masuk antrian, supaya salah ketik username tidak
        menghanguskan ribuan tap.
        """
        kedaluwarsa = self._podium_pending.get(tiktok_user)
        if kedaluwarsa is None:
            return False
        if time.monotonic() >= kedaluwarsa:
            self._podium_pending.pop(tiktok_user, None)
            log.info("[like] hak podium milik %s sudah kedaluwarsa", tiktok_user)
            return False
        return True

    def _lihat_boost(self, tiktok_user: str) -> list[tuple[int, int, str, float]]:
        """Gift yang sedang menunggu untuk penonton ini, TANPA memakainya.

        Urut dari yang dikirim duluan. Yang sudah kedaluwarsa dibuang di
        sini dan dihitung hangus.

        Sengaja tidak langsung dihapus: kalau dibuang di sini lalu username-nya
        ternyata salah ketik dan gagal verifikasi, orang yang sudah bayar
        kehilangan gift-nya begitu saja. Gift baru dipakai setelah avatarnya
        benar-benar masuk antrian.
        """
        daftar = self._boost.get(tiktok_user)
        if not daftar:
            return []
        now = time.monotonic()
        hidup = [g for g in daftar if now < g[3]]
        for tier, koin, nama_gift, kedaluwarsa in daftar:
            if now >= kedaluwarsa:
                self.boost_hangus += 1
                log.info("[gift] %s (%s koin, tier %s) milik %s sudah kedaluwarsa",
                         nama_gift, koin, tier, tiktok_user)
        if hidup:
            self._boost[tiktok_user] = hidup
        else:
            self._boost.pop(tiktok_user, None)
        return list(hidup)

    def tap_terbanyak(self) -> str:
        """Penonton dengan tap terbanyak sejauh ini, untuk baris [detak].

        Angka ruangan ("897 tap") tidak bisa menjawab apakah LIKE_PODIUM
        masuk akal -- 897 dari satu orang dan 897 dari seratus orang itu
        dua live yang berbeda. Yang menentukan tercapai-tidaknya angka
        per ORANG, jadi itu yang dicetak.
        """
        if not self._likes_total:
            return ""
        user, jumlah = max(self._likes_total.items(), key=lambda kv: kv[1])
        return f" | tap terbanyak {user} {jumlah}/{LIKE_PODIUM}"

    def sapu_boost_hangus(self) -> None:
        """Buang boost yang tidak pernah disusul komentar, sekalian dicatat.

        Dipanggil berkala. Gunanya bukan menghemat memori (isinya sedikit),
        tapi supaya kamu bisa lihat di log seberapa sering orang bayar lalu
        tidak dapat apa-apa -- itu angka yang menentukan apakah aturan
        "gift harus disusul username" ini layak dipertahankan.
        """
        now = time.monotonic()
        for u in list(self._boost):
            hidup = []
            for tier, koin, nama_gift, exp in self._boost[u]:
                if now >= exp:
                    self.boost_hangus += 1
                    log.info("[gift] %s (%s koin, tier %s) hangus -- %s tidak "
                             "pernah ngetik username", nama_gift, koin, tier, u)
                else:
                    hidup.append((tier, koin, nama_gift, exp))
            if hidup:
                self._boost[u] = hidup
            else:
                self._boost.pop(u)

    async def handle(self, tiktok_user: str, nickname: str, text: str) -> None:
        """Tidak pernah raise — satu komentar rusak tidak boleh mematikan listener."""
        try:
            await self._handle(tiktok_user, nickname, text)
        except asyncio.CancelledError:
            raise
        except Exception:
            log.exception("[error] gagal memproses komentar (diabaikan)")

    async def _handle(self, tiktok_user: str, nickname: str, text: str) -> None:
        self.seen += 1
        if self.show_comments:
            log.info("💬 %s: %s", nickname, text)

        name = parse_username(text)
        if not name:
            # Mayoritas komentar berhenti di sini. Alasannya hanya dicetak kalau
            # diminta — kalau tidak, log tenggelam oleh obrolan biasa.
            if self.show_comments:
                log.info("   ↳ bukan bentuk username, dilewati")
            return

        key = name.lower()
        now = time.monotonic()

        if key in self.blacklist:
            log.info("[tolak] '%s' ada di blacklist", name)
            self.rejected += 1
            return

        # Tier menentukan siapa yang boleh menembus rem. Orang yang sudah bayar
        # tidak boleh kena "[tolak] masih cooldown" -- dari sisi dia, uangnya
        # sudah keluar tapi tidak terjadi apa-apa.
        gifts = self._lihat_boost(tiktok_user)
        podium = self._lihat_podium(tiktok_user)
        istimewa = podium or bool(gifts)

        # DIKLAIM SEKARANG, sebelum await pertama di bawah.
        #
        # Tiap komentar diproses di task-nya sendiri (lihat
        # `asyncio.create_task` di atas). Kalau gift-nya baru dihapus
        # sesudah push, dua komentar username beruntun dari orang yang
        # sama sama-sama membaca daftar yang sama selagi yang pertama
        # masih menunggu verifikasi Roblox -- dan satu Doughnut jadi dua
        # raksasa. Yang tidak jadi terkirim dikembalikan lewat `kembalikan`.
        klaim_podium = self._podium_pending.pop(tiktok_user, None) if podium else None
        if gifts:
            daftar = self._boost.get(tiktok_user, [])
            for g in gifts:
                if g in daftar:
                    daftar.remove(g)
            if not daftar:
                self._boost.pop(tiktok_user, None)

        def kembalikan(sisa_gift, podium_kembali: bool) -> None:
            if sisa_gift:
                # Di DEPAN: lebih tua dari gift yang masuk selagi menunggu.
                self._boost[tiktok_user] = list(sisa_gift) + self._boost.get(tiktok_user, [])
            if podium_kembali and klaim_podium is not None:
                lama = self._podium_pending.get(tiktok_user, 0.0)
                self._podium_pending[tiktok_user] = max(lama, klaim_podium)

        if not istimewa:
            last_name = self._recent_names.get(key)
            if last_name is not None and (now - last_name) < NAME_DEDUPE_S:
                log.info("[tolak] '%s' baru saja masuk antrian (%.0fs lalu)", name, now - last_name)
                self.rejected += 1
                return

            last_user = self._cooldown.get(tiktok_user)
            if last_user is not None and (now - last_user) < USER_COOLDOWN_S:
                sisa = USER_COOLDOWN_S - (now - last_user)
                log.info("[tolak] %s masih cooldown (%.0fs lagi)", nickname, sisa)
                self.rejected += 1
                return

        # Cooldown dicatat SEBELUM verifikasi. Kalau dicatat setelahnya, satu
        # orang bisa membanjiri Roblox dengan puluhan verifikasi sekaligus
        # selagi verifikasi pertamanya belum selesai.
        self._cooldown[tiktok_user] = now

        if VERIFY_ROBLOX and not await self.roblox_exists(name):
            log.info("[tolak] '%s' tidak ada di Roblox", name)
            self.rejected += 1
            kembalikan(gifts, podium)
            return

        # Dedupe dicatat hanya kalau push-nya BERHASIL. Kalau server antrian
        # lagi mati, nama itu tidak pernah masuk antrian — memblokirnya 60 detik
        # cuma bikin percobaan berikutnya ikut hilang percuma.
        # Yang dikirim: SETIAP gift yang menunggu, urut dari yang dikirim
        # duluan, lalu hadiah tap-nya kalau ada. Masing-masing satu spawn,
        # dan tidak ada yang dilewati -- Doughnut lalu Rose sebelum dia
        # ngetik = raksasa DULU, baru Rose.
        #
        # Komentar tanpa apa pun yang menunggu tetap satu spawn tier 1.
        # Komentar yang membawa gift TIDAK ikut menambah spawn tier 1 di
        # depannya: namanya dipakai untuk gift-nya, bukan dua kali.
        kiriman = [(tier, koin, False) for tier, koin, _, _ in gifts]
        if podium:
            kiriman.append((LIKE_TIER, 0, True))
        if not kiriman:
            kiriman = [(1, 0, False)]

        # Di-await satu per satu, bukan dikirim bersamaan: main.py
        # menyisipkan tiap kiriman berbayar SESUDAH yang sudah menunggu,
        # jadi urutan await ini yang menjadi urutan tampilnya.
        terkirim = 0
        for tier, koin, dari_tap in kiriman:
            if not await self.push(name, nickname, tier, koin, podium=dari_tap):
                break
            terkirim += 1

        # Yang BERHASIL dikirim saja yang dianggap terpakai. Kalau server
        # antrian mati di tengah jalan, sisanya dikembalikan dan ikut
        # terkirim di komentar berikutnya.
        kembalikan(gifts[terkirim:], podium and terkirim < len(kiriman))

        if terkirim == 0:
            return

        self._recent_names[key] = time.monotonic()
        # Diingat supaya gift yang datang SESUDAH ini tahu username mana
        # yang harus di-spawn, tanpa menunggu orangnya mengetik lagi.
        self._nama_terakhir[tiktok_user] = (
            name, time.monotonic() + GIFT_BOOST_TTL_S)

    async def roblox_exists(self, username: str) -> bool:
        """True kalau username terdaftar di Roblox.

        Kalau Roblox tidak bisa dihubungi, jawabannya True — antrian lebih baik
        kemasukan satu nama meragukan daripada mati total saat Roblox ngadat.
        """
        key = username.lower()
        cached = self._roblox_cache.get(key)
        if cached is not None and time.monotonic() < cached[1]:
            return cached[0]

        try:
            r = await self._client.post(
                USERS_API,
                json={"usernames": [username], "excludeBannedUsers": False},
            )
            r.raise_for_status()
            found = bool(r.json().get("data"))
        except Exception as e:
            log.warning("[verify] gagal cek '%s' (%s) — dianggap ada", username, e.__class__.__name__)
            return True

        ttl = CACHE_TTL_S if found else NEG_CACHE_TTL_S
        self._roblox_cache[key] = (found, time.monotonic() + ttl)
        return found

    async def push(self, username: str, nickname: str, tier: int = 1,
                   koin: int = 0, podium: bool = False) -> bool:
        """Kirim SATU spawn ke antrian. False kalau gagal — pemanggilnya yang
        menentukan apakah kegagalan itu perlu dicatat sebagai 'sudah pernah
        masuk'.

        Tier-nya dikirim apa adanya. Yang menerjemahkan gift jadi tier cuma
        tier_dari_gift; di sini tidak ada lagi yang dihitung ulang, apalagi
        digabung dengan kiriman lain.

        `podium` cuma label: kiriman ini hadiah tap, bukan gift.
        """
        koin = max(0, int(koin or 0))
        tier = max(1, int(tier or 1))

        if self.dry_run:
            log.info("[dry-run] '%s' (dari %s) %s koin = tier %s — tidak dikirim",
                     username, nickname, koin, tier)
            self.pushed += 1
            self.per_tier[tier] = self.per_tier.get(tier, 0) + 1
            return True

        try:
            r = await self._client.post(PUSH_URL, json={
                "username": username,
                "tier": tier,
                # Harga gift INI saja (dikali combo-nya), bukan total. Cuma
                # untuk log dan papan -- tiernya sudah ditentukan di atas.
                "koin": koin,
                # Dipotong: nickname TikTok bisa panjang sekali dan berisi emoji;
                # ini cuma buat ditampilkan "dipanggil oleh ..." di Roblox.
                "tiktokUser": nickname[:40],
            }, headers={"X-Token": API_TOKEN} if API_TOKEN else None)
            r.raise_for_status()
            data = r.json()
        except Exception as e:
            # Server antrian mati bukan alasan listener ikut mati — begitu
            # server hidup lagi, komentar berikutnya masuk seperti biasa.
            log.error("[push] gagal kirim '%s' ke %s: %s (server antrian hidup?)",
                      username, PUSH_URL, e.__class__.__name__)
            return False

        if data.get("full"):
            # Bukan kegagalan: antrian memang sedang penuh. Dicatat sebagai info
            # supaya tidak terlihat seperti kerusakan di log saat live ramai.
            log.info("[penuh] antrian sudah %s, '%s' dilewati", data.get("size"), username)
            return False

        if not data.get("ok"):
            log.error("[push] server menolak '%s': %s", username, data.get("error"))
            return False

        self.pushed += 1
        self.per_tier[tier] = self.per_tier.get(tier, 0) + 1
        label = f" TIER {tier} ({koin} koin)" if tier > 1 else ""
        if podium:
            label = f" TIER {tier} (dari {LIKE_PODIUM} tap)"
        log.info("[push]%s '%s' (dari %s) masuk antrian, panjang %s",
                 label, username, nickname, data.get("size"))
        return True


# -------------------------------------------------------------------- CLIENT --

def build_client(username: str, pipeline: Pipeline) -> TikTokLiveClient:
    client = TikTokLiveClient(unique_id=f"@{username.lstrip('@')}")

    @client.on(ConnectEvent)
    async def on_connect(event: ConnectEvent):
        log.info("Connected ke live @%s — komentar berupa username Roblox akan diantrikan.", username)

    @client.on(DisconnectEvent)
    async def on_disconnect(event: DisconnectEvent):
        log.info("Disconnect dari live (kemungkinan live-nya sudah berakhir).")

    @client.on(CommentEvent)
    async def on_comment(event: CommentEvent):
        if event.user is None:
            return
        tiktok_user = extract_username(event.user)
        nickname = getattr(event.user, "nickname", None) or tiktok_user
        pipeline.spawn(tiktok_user, nickname, event.comment or "")

    @client.on(GiftEvent)
    async def on_gift(event: GiftEvent):
        # Gift "streakable" (Rose termasuk) mengirim event berulang tiap combo
        # naik satu. Kalau semuanya diproses, satu combo Rose jadi belasan
        # boost. Yang dipakai hanya saat streak-nya sudah selesai.
        if event.gift.streakable and event.streaking:
            return
        if event.user is None:
            return

        tiktok_user = extract_username(event.user)
        nickname = getattr(event.user, "nickname", None) or tiktok_user
        # Harga gift dalam koin, dikirim TikTok sendiri. Inilah yang
        # menggantikan tabel nama gift: tidak ada lagi gift "tak dikenal".
        koin = getattr(event.gift, "diamond_count", 0) or 0
        await pipeline.handle_gift(tiktok_user, nickname, event.gift.name,
                                   getattr(event, "repeat_count", 1), koin)

    @client.on(LikeEvent)
    async def on_like(event: LikeEvent):
        # `count` = berapa tap yang dikirim orang ini dalam satu pesan
        # (TikTok menggabungkan tap yang beruntun), BUKAN total like ruangan
        # -- itu `event.total`, dan memakainya berarti satu orang naik
        # podium karena tap ribuan penonton lain.
        if event.user is None:
            return

        tiktok_user = extract_username(event.user)
        nickname = getattr(event.user, "nickname", None) or tiktok_user
        await pipeline.handle_like(tiktok_user, nickname,
                                   getattr(event, "count", 1) or 1)

    return client


async def detak(pipeline: Pipeline, jeda: float = 30.0) -> None:
    """Laporan berkala.

    Tanpa ini, live yang ramai tapi tidak ada yang ngetik username terlihat
    sama persis dengan listener yang mati — dua-duanya diam.
    """
    while True:
        await asyncio.sleep(jeda)
        # Disapu di sini, bukan lewat task sendiri: boost yang hangus tidak
        # mendesak, dan menumpangkannya ke detak menghindari satu task lagi.
        pipeline.sapu_boost_hangus()
        log.info("[detak] %s komentar | %s diantrikan | %s ditolak | %s gift | "
                 "%s boost hangus | %s tap | %s podium dari tap%s",
                 pipeline.seen, pipeline.pushed, pipeline.rejected,
                 pipeline.gifts, pipeline.boost_hangus,
                 pipeline.likes, pipeline.podium_like,
                 pipeline.tap_terbanyak())


def _log_setelan(pipeline: "Pipeline", dry_run: bool) -> None:
    """Ringkasan setelan saat start. Sama untuk semua sumber event."""
    log.info("Target antrian: %s%s", PUSH_URL, "  (DRY RUN)" if dry_run else "")
    log.info("Setelan: cooldown %.0fs | dedupe nama %.0fs | verifikasi Roblox %s | blacklist %s nama",
             USER_COOLDOWN_S, NAME_DEDUPE_S, "ya" if VERIFY_ROBLOX else "tidak", len(pipeline.blacklist))
    log.info("Tier dari nama gift: %s | combo xN = N spawn, kiriman terpisah "
             "tidak dijumlah",
             ", ".join(f"{n} = tier {t}" for n, t in GIFT_TIER.items()))
    log.info("Combo ditampung: %s",
             ", ".join(f"tiap {per} {n} = 1 spawn tier {t}"
                       for n, (per, t) in GIFT_NAIK.items()) or "-")
    log.info("Gift tak dikenal dari harga satuan: >=%s = tier 2, >=%s = tier 3, "
             ">=%s = tier 5 (raksasa) | gift menunggu username %.0fs",
             TIER2_KOIN, TIER3_KOIN, TIER5_KOIN, GIFT_BOOST_TTL_S)
    log.info("Tap-tap: %s tap = tier %s gratis (berulang), haknya menunggu username %.0fs",
             LIKE_PODIUM, LIKE_TIER, LIKE_PODIUM_TTL_S)


async def run_live(username: str, debug: bool, dry_run: bool,
                   show_comments: bool = False) -> None:
    pipeline = Pipeline(dry_run=dry_run, show_comments=show_comments)
    await pipeline.open()

    client = build_client(username, pipeline)
    if debug:
        client.logger.setLevel(LogLevel.DEBUG.value)

    if WebDefaults.tiktok_sign_api_key:
        key = WebDefaults.tiktok_sign_api_key
        log.info("Pakai EulerStream API key dari EULERSTREAM_API_KEY (…%s).", key[-4:])
    else:
        log.info("Jalan tanpa EulerStream API key — rawan rate-limit saat live ramai.")

    _log_setelan(pipeline, dry_run)

    detak_task = asyncio.create_task(detak(pipeline))

    try:
        await client.connect()
    except UserOfflineError:
        # Kasus paling sering dan bukan bug — jangan dilempar sebagai traceback
        # sepanjang layar, cukup satu baris yang kebaca.
        log.error("@%s sedang tidak live. Jalankan lagi setelah siarannya mulai.", username)
        raise SystemExit(1)
    except UserNotFoundError:
        # Beda dengan offline: akunnya sendiri tidak ketemu. Hampir selalu
        # salah ketik username, jadi jangan disamakan pesannya.
        log.error("Akun @%s tidak ditemukan (atau belum pernah live sama sekali). "
                  "Cek ejaan username-nya — tanpa '@', persis seperti di profil.", username)
        raise SystemExit(1)
    except Exception as exc:
        if getattr(exc, "status_code", None) == 400:
            # Signing-nya sendiri sukses (room_id ketemu); yang 400 adalah
            # upgrade WebSocket ke ws-fallback.eulerstream.com. Ini terjadi
            # dengan ATAU tanpa API key, jadi ganti key tidak menolong —
            # masalahnya di sisi EulerStream (fallback proxy / add-on).
            log.error(
                "Signing sukses tapi WebSocket EulerStream menolak (HTTP 400). "
                "Ini bukan soal API key — koneksi anonim pun kena. Sign server "
                "mengarahkan ke ws-fallback.eulerstream.com yang menolak upgrade. "
                "Cek status di https://www.eulerstream.com (kemungkinan gangguan "
                "atau butuh add-on Webcast Premium), lalu coba lagi nanti."
            )
        else:
            log.exception(
                "Gagal connect / terputus dari TikTok Live. Kemungkinan: "
                "(1) EulerStream API key tidak valid/habis kuota, atau "
                "(2) TikTok memblokir request (coba lagi beberapa menit lagi)."
            )
        raise SystemExit(1)
    finally:
        detak_task.cancel()
        await pipeline.aclose()
        log.info("Selesai. %s komentar | %s diantrikan | %s ditolak | %s gift | "
                 "%s boost hangus | %s tap | %s podium dari tap.",
                 pipeline.seen, pipeline.pushed, pipeline.rejected,
                 pipeline.gifts, pipeline.boost_hangus,
                 pipeline.likes, pipeline.podium_like)


# --- Sumber event alternatif: TikFinity Desktop ------------------------------
#
# Jalur EulerStream bisa mati total di luar kendali kita: pernah kejadian sign
# server mengarahkan semua klien ke fallback proxy yang menolak upgrade
# WebSocket, dan tidak ada key atau versi klien yang menolong
# (isaackogan/TikTokLive#376). TikFinity Desktop connect ke TikTok lewat
# infrastrukturnya sendiri lalu menyiarkan ulang tiap event ke WebSocket
# lokal, jadi dipakai sebagai jalur cadangan yang tidak lewat EulerStream.
#
# Payload TikFinity memakai gaya TikTok-Live-Connector: camelCase dan datar,
# beda dari objek TikTokLive. Pemetaannya ditaruh di sini supaya Pipeline
# tetap tidak tahu-menahu soal dari mana event datang.

TIKFINITY_URL = os.environ.get("TIKFINITY_URL", "ws://127.0.0.1:21213/")
TIKFINITY_RETRY_S = 5.0


def _tf_user(data: dict) -> tuple[str, str]:
    """Username + nickname penonton dari payload TikFinity."""
    user = data.get("uniqueId") or data.get("userId") or "unknown"
    return user, data.get("nickname") or user


async def _tf_dispatch(pipeline: Pipeline, raw: str | bytes) -> None:
    """Petakan satu pesan TikFinity ke Pipeline."""
    try:
        msg = json.loads(raw)
    except (TypeError, ValueError):
        return
    if not isinstance(msg, dict):
        return

    event = msg.get("event")
    data = msg.get("data") or {}

    if event == "chat":
        user, nickname = _tf_user(data)
        pipeline.spawn(user, nickname, data.get("comment") or "")

    elif event == "gift":
        # Gift streakable (giftType 1, Rose termasuk) memancing event berulang
        # tiap combo naik, lalu ditutup satu event dengan repeatEnd true.
        # Hanya yang penutup yang dipakai: satu Rose sekali kirim saja sudah
        # menghasilkan dua event, jadi tanpa saringan ini satu Rose kebaca
        # jadi dua boost.
        if data.get("giftType") == 1 and not data.get("repeatEnd"):
            return
        user, nickname = _tf_user(data)
        await pipeline.handle_gift(user, nickname,
                                   data.get("giftName") or "gift",
                                   data.get("repeatCount") or 1,
                                   # Harga gift dalam koin, dikirim TikTok
                                   # sendiri — padanan diamond_count di
                                   # TikTokLive.
                                   data.get("diamondCount") or 0)

    elif event == "like":
        user, nickname = _tf_user(data)
        # `likeCount` = tap dalam pesan ini saja. Jangan pakai
        # `totalLikeCount` (total ruangan sejak live mulai) — itu bikin
        # podium meledak di tap pertama yang masuk.
        await pipeline.handle_like(user, nickname, data.get("likeCount") or 1)

    elif event == "config":
        # Handshake sekali saat connect. Isinya TIDAK bisa dipakai buat menebak
        # apakah TikFinity sudah terhubung ke live: `events` terpantau selalu
        # [] baik saat live tersambung maupun belum. Jadi cuma dicatat.
        log.debug("Handshake TikFinity: %s", data)


async def run_tikfinity(dry_run: bool, show_comments: bool,
                        url: str = TIKFINITY_URL) -> None:
    """Baca event dari TikFinity Desktop, bukan dari EulerStream."""
    try:
        import websockets
    except ModuleNotFoundError:
        log.error("Butuh paket 'websockets'. Pasang dengan: "
                  "./.venv/bin/pip install websockets")
        raise SystemExit(1)

    pipeline = Pipeline(dry_run=dry_run, show_comments=show_comments)
    await pipeline.open()

    log.info("Sumber event: TikFinity Desktop (%s) — tidak lewat EulerStream.", url)
    _log_setelan(pipeline, dry_run)

    detak_task = asyncio.create_task(detak(pipeline))
    pernah_tersambung = False

    try:
        # Sengaja menyambung ulang terus, bukan keluar: TikFinity bisa
        # direstart atau live-nya pindah di tengah siaran, dan listener yang
        # mati diam-diam lebih merugikan daripada log yang agak berulang.
        while True:
            try:
                async with websockets.connect(url, open_timeout=10) as ws:
                    pernah_tersambung = True
                    log.info("Tersambung ke TikFinity — komentar berupa username "
                             "Roblox akan diantrikan.")
                    async for raw in ws:
                        await _tf_dispatch(pipeline, raw)
                log.info("TikFinity menutup koneksi. Menyambung ulang %.0fs.",
                         TIKFINITY_RETRY_S)
            except (OSError, asyncio.TimeoutError):
                # Paling sering: aplikasinya belum dibuka. Bukan bug, jadi
                # jangan dilempar sebagai traceback.
                log.error("Tidak bisa menghubungi TikFinity di %s. Pastikan "
                          "aplikasi TikFinity Desktop jalan di PC ini dan "
                          "Events API-nya aktif. Coba lagi %.0fs.",
                          url, TIKFINITY_RETRY_S)
            except Exception:
                if not pernah_tersambung:
                    raise
                log.warning("Koneksi TikFinity terputus. Menyambung ulang %.0fs.",
                            TIKFINITY_RETRY_S, exc_info=True)
            await asyncio.sleep(TIKFINITY_RETRY_S)
    finally:
        detak_task.cancel()
        await pipeline.aclose()
        log.info("Selesai. %s komentar | %s diantrikan | %s ditolak | %s gift | "
                 "%s boost hangus | %s tap | %s podium dari tap.",
                 pipeline.seen, pipeline.pushed, pipeline.rejected,
                 pipeline.gifts, pipeline.boost_hangus,
                 pipeline.likes, pipeline.podium_like)


def _tf_endpoint(url: str) -> tuple[str, int]:
    """Host+port dari URL TikFinity, buat cek cepat tanpa buka WebSocket."""
    m = re.match(r"wss?://([^/:]+)(?::(\d+))?", url)
    if not m:
        return "127.0.0.1", 21213
    return m.group(1), int(m.group(2) or 21213)


async def tikfinity_hidup(url: str = TIKFINITY_URL, timeout: float = 1.5) -> bool:
    """Apakah Events API TikFinity menyahut sekarang.

    Sengaja cuma buka TCP lalu tutup, bukan handshake WebSocket: yang perlu
    dijawab hanya "aplikasinya nyala atau tidak", dan itu harus cepat karena
    dipanggil sebelum listener mulai.
    """
    host, port = _tf_endpoint(url)
    try:
        _, writer = await asyncio.wait_for(
            asyncio.open_connection(host, port), timeout=timeout)
    except (OSError, asyncio.TimeoutError):
        return False
    writer.close()
    try:
        await writer.wait_closed()
    except OSError:
        pass
    return True


async def run_auto(username: str | None, debug: bool, dry_run: bool,
                   show_comments: bool) -> None:
    """TikFinity kalau ada, kalau tidak baru EulerStream.

    Urutannya begitu dan bukan sebaliknya: TikFinity jalan di PC sendiri dan
    tidak bergantung pada signing pihak ketiga yang bisa mati kapan saja,
    sementara EulerStream pernah mati total tanpa bisa diakali dari sisi kita.
    """
    if await tikfinity_hidup():
        log.info("Sumber otomatis: TikFinity Desktop terdeteksi.")
        await run_tikfinity(dry_run, show_comments)
        return

    if not username:
        log.error("TikFinity tidak jalan, dan tidak ada username TikTok untuk "
                  "jalur EulerStream. Buka aplikasi TikFinity Desktop, atau "
                  "jalankan dengan <username_tiktok>.")
        raise SystemExit(1)

    log.info("Sumber otomatis: TikFinity tidak terdeteksi, pakai EulerStream (@%s).",
             username.lstrip("@"))
    await run_live(username, debug, dry_run, show_comments)


async def run_self_test(texts: list[str]) -> None:
    """Uji parser + verifikasi + push tanpa perlu ada yang live."""
    pipeline = Pipeline(dry_run=False)
    await pipeline.open()
    log.info("Self-test ke %s", PUSH_URL)
    try:
        for i, text in enumerate(texts):
            # Penonton palsu yang beda-beda, supaya cooldown tidak ikut menolak.
            await pipeline.handle(f"selftest_{i}", f"Tester {i}", text)
    finally:
        await pipeline.aclose()
        log.info("Self-test selesai. %s masuk antrian, %s ditolak.", pipeline.pushed, pipeline.rejected)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Antrikan username Roblox dari komentar TikTok Live"
    )
    parser.add_argument("username", nargs="?", help="Username TikTok yang sedang live (tanpa @)")
    parser.add_argument("--debug", action="store_true", help="Log detail dari TikTokLive")
    parser.add_argument("--dry-run", action="store_true",
                        help="Proses komentar tapi jangan kirim ke /api/push")
    parser.add_argument("--show-comments", action="store_true",
                        help="Tampilkan SEMUA komentar yang masuk, bukan cuma yang lolos saringan")
    parser.add_argument("--self-test", nargs="+", metavar="KOMENTAR",
                        help="Uji pipeline dengan komentar palsu, tanpa connect ke TikTok")
    parser.add_argument("--source", choices=("auto", "euler", "tikfinity"),
                        default="auto",
                        help="Sumber event. 'auto' (default): pakai TikFinity "
                             "Desktop kalau jalan, kalau tidak jatuh ke "
                             "EulerStream. 'tikfinity': paksa TikFinity. "
                             "'euler': paksa EulerStream (butuh username)")
    args = parser.parse_args()

    try:
        if args.self_test:
            asyncio.run(run_self_test(args.self_test))
        elif args.source == "tikfinity":
            # Username tidak dipakai: live mana yang dibaca ditentukan oleh
            # akun yang sudah di-connect di aplikasi TikFinity.
            asyncio.run(run_tikfinity(args.dry_run, args.show_comments))
        elif args.source == "euler":
            if not args.username:
                parser.error("--source euler butuh <username_tiktok>")
            asyncio.run(run_live(args.username, args.debug, args.dry_run,
                                 args.show_comments))
        else:
            asyncio.run(run_auto(args.username, args.debug, args.dry_run,
                                 args.show_comments))
    except KeyboardInterrupt:
        log.info("Berhenti.")
