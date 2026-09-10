"""
Simulasi komentar TikTok Live tanpa perlu ada yang siaran.

Gunanya: menguji seluruh jalur (saringan -> verifikasi Roblox -> /api/push ->
Roblox Studio) sebelum live beneran, dengan lalu lintas komentar yang mirip
aslinya — campuran username, obrolan biasa, salah ketik, dan orang yang sama
nyepam berkali-kali.

Jalankan:
    .venv/bin/python mock_comments.py                  # ngalir terus, Ctrl+C buat berhenti
    .venv/bin/python mock_comments.py --count 30       # 30 komentar lalu berhenti
    .venv/bin/python mock_comments.py --fast           # tanpa jeda, buat tes cepat
    .venv/bin/python mock_comments.py --dry-run        # jangan kirim ke /api/push
    .venv/bin/python mock_comments.py                  # campuran harian, ketiga tier
    .venv/bin/python mock_comments.py --tier2          # tier 1 + sedikit tier 2, tanpa rosa
    .venv/bin/python mock_comments.py --tier3          # banjir rosa, menguji raksasa

Pipeline-nya diimpor dari tiktok_listener, BUKAN disalin — jadi apa pun yang
lolos di sini persis sama dengan yang bakal lolos pas live.
"""

import argparse
import asyncio
import random

import httpx

from tiktok_listener import PUSH_URL, Pipeline, log

# Semua nama ini sudah dicek dan memang ada di Roblox, jadi mock-nya menguji
# jalur "ketemu" sampai ujung (push beneran), bukan cuma jalur penolakan.
ROBLOX_ADA = [
    "Roblox", "builderman", "armydad405", "benssky2", "burungkakatua_13",
    "Shedletsky", "Stickmasterluke", "Loleris", "TheGamer101", "linkmon99",
    "Sonicthehedgehog", "MrBeast6000", "KreekCraft", "Flamingo", "DenisDaily",
    "Telamon", "ReeseMcBlox", "Merely", "Asimo3089", "badcc",
]

# Bentuknya valid sebagai username, tapi akunnya tidak ada — ini yang harus
# tersaring di langkah verifikasi, bukan lolos ke antrian.
# Semua sudah dicek: benar-benar TIDAK ada di Roblox. Perlu dicek, bukan
# dikarang: "ngasal123" dan "asdasdasdasd11" yang dulu ada di sini ternyata
# akun sungguhan, dan bikin mock-nya seolah verifikasinya bocor.
ROBLOX_NGAWUR = [
    "zxqwertyasdf12", "akun_palsu_9981", "tidakada_woy", "Kyra_Void_9999",
    "qwzxjklmnop7788", "bukanakun_99812",
]

# Obrolan biasa. Yang lebih dari satu kata harus ditolak di langkah format;
# yang satu kata harus ditolak di langkah verifikasi.
OBROLAN = [
    "halo bang", "mantap kali", "first", "wkwkwk", "hadir bang",
    "bagus banget ini", "gas terus", "kok lag ya", "wih keren",
    "bang follow back dong", "up", "🔥🔥🔥", "salam dari medan",
    "avatar gw dong bang", "ke", "yg tadi siapa namanya",
]

# Penonton palsu. Sengaja sedikit, supaya orang yang sama muncul berkali-kali
# dan aturan cooldown ikut kepakai (di live asli, penonton aktif juga sedikit).
#
# SEMUA NAMA DI BAWAH INI KARANGAN — bukan akun TikTok yang beneran ada.
# Jangan dipakai sebagai argumen tiktok_listener.py; itu butuh username akun
# yang sungguhan dan sedang siaran.
PENONTON = [
    ("rizky_ganteng", "Rizky 🔥"),
    ("mamah.muda88", "Mamah Muda"),
    ("bocil_gaming", "Bocil Gaming"),
    ("sultan_andara", "Sultan Andara"),
    ("kyra.void5", "kyra"),
    ("anak_kosan", "Anak Kosan"),
    ("nia_cantik", "Nia ✨"),
    ("gamer_sejati77", "Gamer Sejati"),
]


# Gift yang disimulasikan, beserta harganya dalam koin -- persis seperti
# `gift.diamond_count` yang dikirim TikTok. "kucing" harganya 0: gift gratis
# harus dilewati tanpa menghasilkan apa-apa, dan itu perlu ikut teruji.
# "galaxy" ada di daftar harga tapi TIDAK ikut komposisi harian: gift mahal
# memang jarang, dan kalau ikut di sini sorotan jalan terus sampai mock-nya
# tidak lagi mirip live. Ujinya lewat `--gift galaxy` -- itu jalur yang dulu
# jatuh ke tier 1 gara-gara namanya tidak ada di tabel.
GIFT_KOIN = {
    "rose": 1,
    "rosa": 10,
    "galaxy": 1000,
    "kucing": 0,
}

# Komposisi harian. Sengaja menyentuh KETIGA tier, karena "mock-nya
# jalan" dan "mock-nya menguji yang kamu kira" itu dua hal berbeda --
# dan yang paling gampang rusak tanpa ketahuan justru jalur yang tidak
# pernah dilewati.
#
#   rose    1 koin  -> tier 2      kucing  0 koin -> tier 1 (gift gratis)
#   rosa   10 koin  -> tier 3
#
# Porsinya miring TAJAM ke yang murah, meniru live. Ingat combo ikut
# dikali: rosa x1 sudah tier 3, dan rose x10 juga -- jadi tier 3 muncul
# lebih sering daripada porsi rosa-nya sendiri.
GIFT = (["rose"] * 12) + (["rosa"] * 4) + (["kucing"] * 3)

# Komposisi untuk --tier3: rosa saja. Dulu masih dicampur rose, tapi untuk
# menilai panggung tier 3 campuran itu cuma bikin sorotannya jarang.
GIFT_TIER3 = ["rosa"]

# Komposisi untuk --tier2: rose saja, jadi rosa tidak pernah muncul dan
# sorotan tidak pernah jalan. Dipakai untuk melihat panggung sehari-hari:
# mayoritas tier 1, sesekali ada yang menonjol.
GIFT_TIER2 = ["rose"]


def buat_komentar(rng: random.Random) -> str:
    """Satu komentar acak, dengan komposisi yang mirip live beneran.

    Sengaja tidak rata: di live asli, obrolan biasa jauh lebih banyak daripada
    yang benar-benar ngetik username. Kalau mock-nya isinya username semua,
    saringannya tidak pernah teruji.
    """
    roll = rng.random()
    if roll < 0.35:
        return rng.choice(ROBLOX_ADA)                       # username polos
    if roll < 0.45:
        return "@" + rng.choice(ROBLOX_ADA)                 # pakai '@'
    if roll < 0.55:
        return rng.choice(ROBLOX_NGAWUR)                    # tidak ada di Roblox
    if roll < 0.62:
        # Username tapi ada embel-embelnya -> harus ditolak (lebih dari satu kata).
        return f"{rng.choice(ROBLOX_ADA)} dong bang"
    return rng.choice(OBROLAN)


async def baca_setelan() -> dict:
    """Ambil setelan server. Gagal = kembalikan dict kosong, bukan error --
    mock harus tetap bisa jalan walau server-nya versi lama."""
    url = PUSH_URL.replace("/api/push", "/api/settings")
    try:
        async with httpx.AsyncClient(timeout=5) as c:
            return (await c.get(url)).json()
    except Exception:
        return {}


async def lihat_antrian() -> None:
    """Intip isi antrian lewat /api/peek, kalau server-nya memang hidup."""
    peek_url = PUSH_URL.replace("/api/push", "/api/peek")
    try:
        async with httpx.AsyncClient(timeout=5) as c:
            data = (await c.get(peek_url)).json()
    except Exception as e:
        log.warning("[peek] tidak bisa membaca antrian: %s", e.__class__.__name__)
        return
    log.info("[antrian] %s item: %s", data.get("size"), data.get("queue"))


async def main(count: int | None, min_delay: float | None, max_delay: float | None,
               seed: int | None, dry_run: bool,
               gift_rate: float, gift_pool: list[str], jeda_kunci: str | None,
               gift_follow: float) -> None:
    rng = random.Random(seed)
    pipeline = Pipeline(dry_run=dry_run)
    await pipeline.open()

    log.info("Mock komentar -> %s%s", PUSH_URL, "  (DRY RUN)" if dry_run else "")

    # Sorotan berbayar dijeda di server (SPOTLIGHT_GAP_*). Kirim lebih cepat
    # dari itu dan sisanya cuma menumpuk di antrian tanpa pernah terlihat --
    # persis yang bikin mock ini terasa "macet". Jadi lajunya disamakan dengan
    # jeda server, kecuali kamu menentukan sendiri.
    if jeda_kunci and min_delay is None and max_delay is None and not dry_run:
        setelan = await baca_setelan()
        gap = setelan.get(jeda_kunci)
        if gap:
            min_delay, max_delay = gap * 0.8, gap * 1.3
            log.info("Jeda sorotan server: %.0f detik -> rosa dikirim tiap ~%.0f detik, "
                     "jadi tiap satu benar-benar kebagian tampil.", gap, gap)
            log.info("Mau lebih rapat? Jalankan server dengan SPOTLIGHT_GAP_S=4.")
        else:
            log.warning("Server tidak menjawab /api/settings -- laju sorotan tidak "
                        "bisa disamakan. Server-nya versi lama?")

    if min_delay is None:
        min_delay = 0.8
    if max_delay is None:
        max_delay = 3.0

    log.info("Gift: %.0f%% dari kejadian, dari %s",
             gift_rate * 100, sorted(set(gift_pool)))
    log.info("Ctrl+C untuk berhenti." if count is None else f"{count} komentar.")

    dikirim = 0
    try:
        while count is None or dikirim < count:
            user, nick = rng.choice(PENONTON)

            # Polanya ditiru dari live asli: orang kirim gift DULU, baru
            # ngetik username sedetik-dua kemudian. Seperempatnya sengaja
            # TIDAK ngetik apa-apa -- itu kasus "boost hangus" yang justru
            # paling perlu diuji.
            if rng.random() < gift_rate:
                gift = rng.choice(gift_pool)

                # Sebagian besar orang kirim satu, sebagian menekan
                # tombolnya berkali-kali. Sebarannya sengaja miring ke
                # angka kecil -- kalau combo besar sesering combo kecil,
                # kamu tidak pernah menguji kasus yang paling sering
                # benar-benar terjadi saat live.
                jumlah = rng.choices(
                    [1, 2, 3, 5, 10, 20],
                    weights=[60, 15, 10, 8, 5, 2],
                )[0]
                await pipeline.handle_gift(user, nick, gift, jumlah,
                                           GIFT_KOIN.get(gift, 0))
                if rng.random() < gift_follow:
                    await asyncio.sleep(rng.uniform(0.3, 1.2))
                    nama = rng.choice(ROBLOX_ADA)
                    log.info("💬 %s: %s", nick, nama)
                    await pipeline.handle(user, nick, nama)
                dikirim += 1
                if max_delay > 0:
                    await asyncio.sleep(rng.uniform(min_delay, max_delay))
                continue

            text = buat_komentar(rng)
            log.info("💬 %s: %s", nick, text)

            # Di-await, bukan spawn: mock-nya jadi terbaca urut, satu komentar
            # satu hasil. Di listener asli yang dipakai spawn() supaya komentar
            # berikutnya tidak menunggu verifikasi selesai.
            await pipeline.handle(user, nick, text)

            dikirim += 1
            if max_delay > 0:
                await asyncio.sleep(rng.uniform(min_delay, max_delay))
    except KeyboardInterrupt:
        pass
    finally:
        await pipeline.aclose()
        pipeline.sapu_boost_hangus()
        log.info("Selesai. %s kejadian | %s masuk antrian | %s ditolak | %s gift | %s boost hangus.",
                 dikirim, pipeline.pushed, pipeline.rejected,
                 pipeline.gifts, pipeline.boost_hangus)

        # Rincian per tier, dan yang KOSONG disebut namanya.
        #
        # Ini yang membedakan "mock-nya selesai tanpa error" dari
        # "mock-nya benar-benar menguji panggungmu". Jalan lima menit
        # tanpa satu pun tier 3 berarti raksasanya tidak pernah dicoba
        # sama sekali -- dan itu tidak akan terlihat di mana pun kecuali
        # di baris ini.
        per = pipeline.per_tier
        log.info("Per tier: %s",
                 "  ".join(f"tier {t}={per.get(t, 0)}" for t in (1, 2, 3)))
        kosong = [t for t in (1, 2, 3) if per.get(t, 0) == 0]
        if kosong:
            # Cuma tier 2-4 yang punya mode sendiri; tier 1 datang dari
            # komentar biasa, jadi menyarankan "--tier1" berarti menyuruh
            # orang mengetik flag yang tidak ada.
            punya_mode = [t for t in kosong if t in (2, 3)]
            saran = (f", atau pakai --tier{punya_mode[0]}"
                     if punya_mode else "")
            log.warning("Tier %s TIDAK pernah muncul -- jalurnya belum "
                        "teruji. Perpanjang --count%s.",
                        ", ".join(str(t) for t in kosong), saran)
        if not dry_run:
            await lihat_antrian()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Simulasi komentar TikTok Live")
    parser.add_argument("--count", type=int, default=None,
                        help="Berhenti setelah sekian komentar (default: jalan terus)")
    parser.add_argument("--min-delay", type=float, default=None,
                        help="Jeda minimal antar komentar, detik (default 0.8)")
    parser.add_argument("--max-delay", type=float, default=None,
                        help="Jeda maksimal antar komentar, detik (default 3.0)")
    parser.add_argument("--fast", action="store_true", help="Tanpa jeda sama sekali")
    parser.add_argument("--seed", type=int, default=None, help="Bikin urutannya bisa diulang persis")
    parser.add_argument("--dry-run", action="store_true", help="Jangan kirim ke /api/push")
    parser.add_argument("--tier2", action="store_true",
                        help="Hanya tier 1 dan 2 (rose), tier 2-nya sedikit. Tanpa rosa/sorotan")
    parser.add_argument("--tier3", action="store_true",
                        help="Banjir rosa (10 koin) -- menguji raksasa tier 3")
    parser.add_argument("--gift-rate", type=float, default=None,
                        help="Peluang satu kejadian berupa gift (0..1, default 0.125)")
    parser.add_argument("--gift", action="append", metavar="NAMA",
                        help="Batasi ke gift tertentu, boleh diulang (mis. --gift rosa)")
    args = parser.parse_args()

    min_delay, max_delay = (0.0, 0.0) if args.fast else (args.min_delay, args.max_delay)

    # --tier2/--tier3 cuma menggeser dua angka default; --gift-rate dan
    # --gift tetap boleh menimpanya, jadi bisa dipakai bersamaan.
    dipilih = [n for n, v in (("--tier2", args.tier2),
                              ("--tier3", args.tier3)) if v]
    if len(dipilih) > 1:
        parser.error(" dan ".join(dipilih) + " tidak bisa dipakai bersamaan")

    # Mode tier 3/4 dipakai untuk MENILAI PANGGUNGNYA, bukan meniru live.
    # Jadi tiap kejadian adalah gift (rate 1.0) dan selalu disusul username
    # (follow 1.0) -- kalau tidak, tick yang sudah dilambatkan ke jeda
    # sorotan malah terbuang untuk obrolan biasa.
    if args.tier3:
        bawaan_pool, bawaan_rate = GIFT_TIER3, 1.0
    elif args.tier2:
        # 0.015, bukan angka bulat yang kelihatan masuk akal seperti 0.1.
        # Alasannya: gift menembus cooldown dan dedupe, sementara komentar
        # biasa banyak yang ditolak -- jadi porsi gift di ANTRIAN jauh lebih
        # besar daripada porsinya di kejadian. Diukur: 0.1 -> 26% antrian,
        # 0.02 -> 15%, 0.015 -> ~10%.
        bawaan_pool, bawaan_rate = GIFT_TIER2, 0.015
    else:
        bawaan_pool, bawaan_rate = GIFT, 0.125

    gift_pool = args.gift or bawaan_pool
    gift_rate = args.gift_rate if args.gift_rate is not None else bawaan_rate

    # Berapa sering gift disusul username. Di mock biasa sengaja tidak
    # selalu -- itu kasus "boost hangus" yang perlu ikut teruji.
    gift_follow = 1.0 if args.tier3 else 0.75

    # Tiap tier punya jedanya sendiri di server, dan memakai jeda yang
    # salah membuat mock-nya menumpuk lagi -- persis masalah yang jeda
    # otomatis ini dibuat untuk menyelesaikan.
    jeda_kunci = "spotlightGapTier3S" if args.tier3 else None

    try:
        asyncio.run(main(args.count, min_delay, max_delay, args.seed, args.dry_run,
                         gift_rate, gift_pool, jeda_kunci, gift_follow))
    except KeyboardInterrupt:
        log.info("Berhenti.")
