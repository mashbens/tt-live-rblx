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
    .venv/bin/python mock_comments.py                  # skenario pasti, lalu campuran harian
    .venv/bin/python mock_comments.py --tanpa-pembuka  # langsung campuran harian
    .venv/bin/python mock_comments.py --tier2          # banjir Rose, menguji cakram biru
    .venv/bin/python mock_comments.py --tier3          # banjir Rosa, menguji aura VFX
    .venv/bin/python mock_comments.py --tier4          # banjir Bouquet Flower, menguji nova
    .venv/bin/python mock_comments.py --tier5          # banjir Doughnut, menguji raksasa

Pipeline-nya diimpor dari tiktok_listener, BUKAN disalin — jadi apa pun yang
lolos di sini persis sama dengan yang bakal lolos pas live.
"""

import argparse
import asyncio
import random

import httpx

from tiktok_listener import (LIKE_PODIUM, LIKE_TIER, PUSH_URL, Pipeline, log,
                             tier_dari_gift)

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
# `gift.diamond_count` yang dikirim TikTok. NAMA-nya ditulis persis seperti
# nama gift TikTok, karena sekarang namalah yang menentukan tier
# (GIFT_TIER di tiktok_listener.py).
#
# Tiga yang TIDAK ada di GIFT_TIER, sengaja: mereka menguji jalur cadangan
# lewat harga satuan. "Kucing" harganya 0 (gift gratis harus dilewati),
# "Finger Heart" 5 koin harus jatuh ke tier Rose, dan "Galaxy" 1.000 koin
# harus jatuh ke raksasa -- bukan ke tier 1, yang dulu jadi alasan tabel nama
# dibuang.
GIFT_KOIN = {
    "Rose": 1,
    "Rosa": 10,
    # Bouquet Flower dan Doughnut sama-sama 30 koin. Itu justru yang perlu
    # diuji: dari harga saja keduanya tidak bisa dibedakan.
    "Bouquet Flower": 30,
    "Doughnut": 30,
    "Finger Heart": 5,
    "Galaxy": 1000,
    "Kucing": 0,
}


def koin_gift(nama: str) -> int:
    """Harga gift, tanpa peduli huruf besar-kecil (`--gift rose` juga jalan)."""
    for n, k in GIFT_KOIN.items():
        if n.lower() == nama.lower():
            return k
    return 0


# Komposisi harian. Sengaja menyentuh KELIMA tier, karena "mock-nya
# jalan" dan "mock-nya menguji yang kamu kira" itu dua hal berbeda --
# dan yang paling gampang rusak tanpa ketahuan justru jalur yang tidak
# pernah dilewati.
#
#   Rose            1 koin  -> tier 2 (cakram biru)
#   Finger Heart    5 koin  -> tier 2 (tak dikenal, dari harga)
#   Rosa           10 koin  -> tier 3 (aura)
#   Bouquet Flower 30 koin  -> tier 4 (nova)
#   Doughnut       30 koin  -> tier 5 (raksasa)
#   Kucing          0 koin  -> tier 1 (gift gratis)
#
# Porsinya miring ke yang murah, meniru live. Galaxy tidak ikut: gift
# semahal itu memang jarang, dan jalurnya sudah dijamin skenario pembuka.
#
# Bouquet Flower dan Doughnut DINAIKKAN dari 1 ke 3 dan 2. Dengan porsi 1,
# 300 kejadian (sekitar sepuluh menit mock) cuma menghasilkan 3 Bouquet dan
# 1 Doughnut -- nova dan raksasa hampir tidak pernah terlihat, dan mock yang
# jarang menyentuh dua adegan paling mahal tidak menguji yang paling perlu
# diuji. Sekarang kira-kira satu Bouquet per menit.
GIFT = ((["Rose"] * 12) + (["Finger Heart"] * 2) + (["Rosa"] * 4)
        + (["Bouquet Flower"] * 3) + (["Doughnut"] * 2) + (["Kucing"] * 3))

# Komposisi untuk --tier2..5: satu gift saja, untuk menilai SATU jenis
# adegan tanpa ketiban sorotan tier lain.
GIFT_PER_TIER = {
    2: ["Rose"],
    3: ["Rosa"],
    4: ["Bouquet Flower"],
    5: ["Doughnut"],
}


# --------------------------------------------------------------- PEMBUKA --
#
# Campuran acak di bawah MIRIP live, tapi justru karena acak dia tidak
# pernah menjamin apa pun: lima menit tanpa satu pun raksasa, jalur tap yang
# tidak pernah tembus 1.000, gift 1.000 koin yang tidak pernah dikirim.
# Semua itu jalur yang kalau rusak baru ketahuan waktu live.
#
# Jadi `make mock` membuka dengan skenario berurutan yang PASTI menyentuh
# tiap jalur sekali, dan tiap skenario diperiksa hasilnya (bukan cuma
# "tidak error"). Sesudah itu baru campuran acak.
#
# Penontonnya sengaja terpisah dari PENONTON dan username-nya tidak dipakai
# dua kali: cooldown dan dedupe yang terbawa dari skenario sebelumnya akan
# membuat skenario berikutnya gagal karena rem, bukan karena bug.
#
#   (judul, penonton, nama tampil, langkah, yang diharapkan)
#   langkah: ("komen", teks) | ("gift", nama_gift, jumlah) | ("tap", jumlah)
#   harapan: ("tier", [t, t, ...]) -- tier tiap spawn, URUT sesuai masuknya
#            ("tolak",) | ("hangus",)
T = LIKE_TIER
SKENARIO = [
    ("komentar biasa -> tier 1",
     "cakupan_01", "Cakupan 1", [("komen", "Roblox")], ("tier", [1])),
    ("Rose lalu username -> tier 2 (cakram biru)",
     "cakupan_02", "Cakupan 2", [("gift", "Rose", 1), ("komen", "builderman")], ("tier", [2])),
    ("Rosa lalu username -> tier 3 (aura)",
     "cakupan_03", "Cakupan 3", [("gift", "Rosa", 1), ("komen", "Shedletsky")], ("tier", [3])),
    ("Bouquet Flower lalu username -> tier 4 (nova)",
     "cakupan_04", "Cakupan 4", [("gift", "Bouquet Flower", 1), ("komen", "Loleris")], ("tier", [4])),
    ("Doughnut lalu username -> tier 5 (raksasa)",
     "cakupan_05", "Cakupan 5", [("gift", "Doughnut", 1), ("komen", "TheGamer101")], ("tier", [5])),

    # --- bug yang pernah terlihat di siaran: gift MENUMPUK jadi raksasa ---
    ("BUG LAMA: Doughnut lalu Rose sebelum username -> raksasa DULU, baru Rose",
     "cakupan_06", "Cakupan 6",
     [("gift", "Doughnut", 1), ("gift", "Rose", 1), ("komen", "linkmon99")],
     ("tier", [5, 2])),
    ("BUG LAMA: username dulu, Doughnut, lalu Rose -> Rose, bukan raksasa lagi",
     "cakupan_07", "Cakupan 7",
     [("komen", "Telamon"), ("gift", "Doughnut", 1), ("gift", "Rose", 1)],
     ("tier", [1, 5, 2])),
    ("Bouquet dua kali -> nova dua kali, TIDAK naik ke raksasa",
     "cakupan_08", "Cakupan 8",
     [("komen", "Merely"), ("gift", "Bouquet Flower", 1), ("gift", "Bouquet Flower", 1)],
     ("tier", [1, 4, 4])),
    # --- combo: jumlah combo = jumlah spawn, Rose ditampung 10:1 ---
    ("combo Rose x3 -> 3 spawn Rose",
     "cakupan_09", "Cakupan 9", [("gift", "Rose", 3), ("komen", "badcc")], ("tier", [2, 2, 2])),
    ("combo Rose x25 -> 2 Rosa DULU, lalu 5 Rose",
     "cakupan_17", "Cakupan 17", [("gift", "Rose", 25), ("komen", "Stickmasterluke")],
     ("tier", [3, 3, 2, 2, 2, 2, 2])),
    ("combo Doughnut x3 -> 3 raksasa",
     "cakupan_18", "Cakupan 18", [("gift", "Doughnut", 3), ("komen", "Sonicthehedgehog")],
     ("tier", [5, 5, 5])),
    ("Rose x5 lalu Rose x5 (DUA combo) -> 10 Rose, bukan Rosa",
     "cakupan_19", "Cakupan 19",
     [("gift", "Rose", 5), ("gift", "Rose", 5), ("komen", "MrBeast6000")],
     ("tier", [2] * 10)),

    # --- gift yang namanya tidak dikenal jatuh ke harga satuannya ---
    ("Finger Heart 5 koin (tak dikenal) -> tier 2 dari harganya",
     "cakupan_10", "Cakupan 10", [("gift", "Finger Heart", 1), ("komen", "Asimo3089")], ("tier", [2])),
    ("Galaxy 1.000 koin (tak dikenal) -> tier 5, bukan tier 1",
     "cakupan_11", "Cakupan 11", [("gift", "Galaxy", 1), ("komen", "KreekCraft")], ("tier", [5])),
    ("gift gratis (0 koin) lalu username -> tetap tier 1",
     "cakupan_12", "Cakupan 12", [("gift", "Kucing", 1), ("komen", "Flamingo")], ("tier", [1])),

    # --- tap ---
    (f"tap {LIKE_PODIUM} DULU, baru username -> tier {T} gratis",
     "cakupan_13", "Cakupan 13", [("tap", LIKE_PODIUM), ("komen", "DenisDaily")], ("tier", [T])),
    (f"username DULU, baru tap {LIKE_PODIUM} -> spawn tier {T} gratis",
     "cakupan_14", "Cakupan 14", [("komen", "ReeseMcBlox"), ("tap", LIKE_PODIUM)], ("tier", [1, T])),

    ("Rosa tanpa pernah mengetik username -> boost hangus",
     "cakupan_15", "Cakupan 15", [("gift", "Rosa", 1)], ("hangus",)),
    ("username yang tidak ada di Roblox -> ditolak",
     "cakupan_16", "Cakupan 16", [("komen", "zxqwertyasdf12")], ("tolak",)),
]


async def jalankan_pembuka(pipeline: Pipeline, jeda: float) -> list[str]:
    """Jalankan SKENARIO satu per satu. Mengembalikan judul yang GAGAL."""
    gagal = []
    log.info("===== cakupan: %s skenario pasti =====", len(SKENARIO))

    # Tiap push yang BERHASIL dicatat tiernya, urut.
    #
    # Penghitung per tier saja tidak cukup untuk skenario di atas: "raksasa
    # lalu Rose" dan "Rose lalu raksasa" menghasilkan hitungan yang sama
    # persis, padahal yang diminta urutannya -- yang dikirim duluan tampil
    # duluan, tidak ada yang dilewati.
    urutan: list[int] = []
    push_asli = pipeline.push

    async def push_dicatat(username, nickname, tier=1, koin=0, podium=False):
        ok = await push_asli(username, nickname, tier, koin, podium=podium)
        if ok:
            urutan.append(tier)
        return ok

    pipeline.push = push_dicatat

    try:
        for i, (judul, user, nick, langkah, harapan) in enumerate(SKENARIO, 1):
            log.info("----- [%s/%s] %s", i, len(SKENARIO), judul)
            urutan.clear()
            tolak_sebelum = pipeline.rejected

            for aksi in langkah:
                if aksi[0] == "komen":
                    log.info("💬 %s: %s", nick, aksi[1])
                    await pipeline.handle(user, nick, aksi[1])
                elif aksi[0] == "gift":
                    await pipeline.handle_gift(user, nick, aksi[1], aksi[2],
                                               koin_gift(aksi[1]))
                elif aksi[0] == "tap":
                    await pipeline.handle_like(user, nick, aksi[1])
                if jeda > 0:
                    await asyncio.sleep(min(jeda, 1.0))

            if harapan[0] == "tier":
                ok = urutan == harapan[1]
                detail = f"masuk antrian sebagai {urutan or 'tidak ada'}, harusnya {harapan[1]}"
            elif harapan[0] == "tolak":
                ok = pipeline.rejected > tolak_sebelum
                detail = "tidak ditolak"
            else:
                ok = user in pipeline._boost
                detail = "gift-nya tidak tersimpan menunggu username"

            if ok:
                log.info("[cakupan] OK     %s", judul)
            else:
                log.warning("[cakupan] GAGAL  %s -- %s", judul, detail)
                gagal.append(judul)

            if jeda > 0:
                await asyncio.sleep(jeda)
    finally:
        pipeline.push = push_asli

    if gagal:
        log.warning("===== cakupan: %s dari %s GAGAL =====", len(gagal), len(SKENARIO))
    else:
        log.info("===== cakupan: semua %s skenario OK, lanjut campuran acak =====",
                 len(SKENARIO))
    return gagal


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
               gift_follow: float, pembuka: bool = False,
               tap_rate: float = 0.0, combo: bool = True) -> None:
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
            log.info("Jeda sorotan server: %.0f detik -> gift dikirim tiap ~%.0f detik, "
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
    gagal_cakupan: list[str] = []
    try:
        if pembuka:
            gagal_cakupan = await jalankan_pembuka(pipeline, max_delay)

        while count is None or dikirim < count:
            user, nick = rng.choice(PENONTON)

            # Tap layar. Tiap kejadian cuma segenggam tap -- dari data live,
            # TikTok mengirimnya dalam gumpalan puluhan -- jadi di campuran
            # acak ambang LIKE_PODIUM jarang tembus. Yang menjamin jalur itu
            # teruji skenario pembuka; di sini gunanya menguji penghitungan
            # akumulatif dan log progresnya.
            if tap_rate > 0 and rng.random() < tap_rate:
                jumlah = rng.choice([10, 30, 80, 200])
                await pipeline.handle_like(user, nick, jumlah)
                dikirim += 1
                if max_delay > 0:
                    await asyncio.sleep(rng.uniform(min_delay, max_delay))
                continue

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
                )[0] if combo else 1
                # Combo = jumlah spawn sekarang, tanpa batas. Nova x20 itu
                # 20 adegan 17 detik -- enam menit mock yang cuma berisi
                # satu orang. Di live memang bisa terjadi, tapi mock yang
                # meniru live tidak boleh macet karenanya; jalurnya sudah
                # dijamin skenario pembuka.
                if tier_dari_gift(gift, koin_gift(gift))[0] >= 4:
                    jumlah = min(jumlah, 2)
                await pipeline.handle_gift(user, nick, gift, jumlah,
                                           koin_gift(gift))
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
        # tanpa satu pun tier 4 berarti novanya tidak pernah dicoba
        # sama sekali -- dan itu tidak akan terlihat di mana pun kecuali
        # di baris ini.
        per = pipeline.per_tier
        log.info("Per tier: %s",
                 "  ".join(f"tier {t}={per.get(t, 0)}" for t in (1, 2, 3, 4, 5)))
        log.info("Tap: %s tap | %s kali tembus %s tap",
                 pipeline.likes, pipeline.podium_like, LIKE_PODIUM)
        if gagal_cakupan:
            log.warning("Skenario cakupan yang GAGAL: %s", "; ".join(gagal_cakupan))
        kosong = [t for t in (1, 2, 3, 4, 5) if per.get(t, 0) == 0]
        if kosong:
            # Cuma tier 2-5 yang punya mode sendiri; tier 1 datang dari
            # komentar biasa, jadi menyarankan "--tier1" berarti menyuruh
            # orang mengetik flag yang tidak ada.
            punya_mode = [t for t in kosong if t in GIFT_PER_TIER]
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
                        help="Banjir Rose -- menguji cakram biru tier 2")
    parser.add_argument("--tier3", action="store_true",
                        help="Banjir Rosa -- menguji aura VFX tier 3")
    parser.add_argument("--tier4", action="store_true",
                        help="Banjir Bouquet Flower -- menguji adegan nova tier 4")
    parser.add_argument("--tier5", action="store_true",
                        help="Banjir Doughnut -- menguji raksasa tier 5")
    parser.add_argument("--tanpa-pembuka", action="store_true",
                        help="Lewati skenario pasti di awal, langsung campuran acak")
    parser.add_argument("--tap-rate", type=float, default=None,
                        help="Peluang satu kejadian berupa tap layar (0..1, default 0.08)")
    parser.add_argument("--gift-rate", type=float, default=None,
                        help="Peluang satu kejadian berupa gift (0..1, default 0.125)")
    parser.add_argument("--gift", action="append", metavar="NAMA",
                        help="Batasi ke gift tertentu, boleh diulang (mis. --gift Rosa)")
    args = parser.parse_args()

    min_delay, max_delay = (0.0, 0.0) if args.fast else (args.min_delay, args.max_delay)

    # --tier2..5 cuma menggeser dua angka default; --gift-rate dan
    # --gift tetap boleh menimpanya, jadi bisa dipakai bersamaan.
    dipilih = [t for t in GIFT_PER_TIER if getattr(args, f"tier{t}")]
    if len(dipilih) > 1:
        parser.error(" dan ".join(f"--tier{t}" for t in dipilih)
                     + " tidak bisa dipakai bersamaan")
    tier_mode = dipilih[0] if dipilih else None

    # Mode tier dipakai untuk MENILAI PANGGUNGNYA, bukan meniru live.
    # Jadi tiap kejadian adalah gift (rate 1.0) dan selalu disusul username
    # (follow 1.0) -- kalau tidak, tick yang sudah dilambatkan ke jeda
    # sorotan malah terbuang untuk obrolan biasa.
    mode_tier = tier_mode is not None
    if mode_tier:
        bawaan_pool, bawaan_rate = GIFT_PER_TIER[tier_mode], 1.0
    else:
        bawaan_pool, bawaan_rate = GIFT, 0.125

    gift_pool = args.gift or bawaan_pool
    gift_rate = args.gift_rate if args.gift_rate is not None else bawaan_rate

    # Berapa sering gift disusul username. Di mock biasa sengaja tidak
    # selalu -- itu kasus "boost hangus" yang perlu ikut teruji.
    gift_follow = 1.0 if mode_tier else 0.75

    # Tiap tier punya jedanya sendiri di server, dan memakai jeda yang
    # salah membuat mock-nya menumpuk lagi -- persis masalah yang jeda
    # otomatis ini dibuat untuk menyelesaikan.
    jeda_kunci = f"spotlightGapTier{tier_mode}S" if mode_tier else None

    # Pembuka dan tap cuma untuk campuran harian. Mode --tier* dipakai
    # menilai SATU jenis adegan, dan skenario lain yang menyela di tengahnya
    # justru merusak yang sedang dinilai.
    campuran = not mode_tier and not args.gift
    pembuka = campuran and not args.tanpa_pembuka
    tap_rate = (args.tap_rate if args.tap_rate is not None
                else (0.08 if campuran else 0.0))

    try:
        asyncio.run(main(args.count, min_delay, max_delay, args.seed, args.dry_run,
                         gift_rate, gift_pool, jeda_kunci, gift_follow,
                         # Mode --tier* mengirim x1: combo Rose akan naik
                         # jadi Rosa, dan yang sedang dinilai jadi tercampur.
                         pembuka, tap_rate, combo=not mode_tier))
    except KeyboardInterrupt:
        log.info("Berhenti.")
