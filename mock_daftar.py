"""
Mock cepat dari daftar username sungguhan (default tt-username-list.txt).

Diambil acak dari daftar: 1 nama jadi raksasa (Doughnut, tier 5), 5 nama jadi Rose
(tier 3), sisanya (default 30) komentar biasa tier 1 -- seperti live asli,
kebanyakan penonton cuma ngetik username. Raksasa (default Darling4300)
muncul paling awal, lalu satu komentar tiap 5 detik dengan satu Rose tiap
20 detik di antaranya; Rose habis, sisanya komentar biasa. Yang kelewat
jeda sorotan server atau kebuang karena QUEUE_MAX penuh boleh ke-skip.

Jalankan:
    .venv/bin/python mock_daftar.py
    .venv/bin/python mock_daftar.py --raksasa 2 --rose 3 --komen 50 --file nama.txt
"""

import argparse
import asyncio
import json
import os
import random

import tiktok_listener
from mock_comments import koin_gift
from tiktok_listener import PUSH_URL, Pipeline, log


def token_pembeli(nama: str) -> str:
    """Token pembeli dari buyers.json -- yang sama dengan .exe/dashboard-nya.

    API_TOKEN di .env masuk kanal `utama`, dan Private Server pembeli cuma
    mengambil dari kanalnya sendiri: mock-nya "masuk", tapi tidak pernah
    muncul di game.
    """
    with open("buyers.json", encoding="utf-8") as f:
        return json.load(f)[nama]["token"]


def susun_rencana(nama: list[str], nama_raksasa: list[str], raksasa: int,
                 rose: int, komen: int, tiap_rose: int) -> list[tuple[str | None, str]]:
    """Raksasa dulu di awal, lalu komentar biasa dengan satu Rose tiap
    `tiap_rose` giliran; Rose habis, sisanya komentar biasa saja."""
    raksasa_nama = nama_raksasa[:raksasa]
    kurang = raksasa - len(raksasa_nama)
    sisa = [n for n in nama if n not in raksasa_nama]
    pilih = random.sample(sisa, min(kurang + rose + komen, len(sisa)))
    raksasa_nama += pilih[:kurang]
    rose_nama, komen_nama = pilih[kurang:kurang + rose], pilih[kurang + rose:]

    rencana: list[tuple[str | None, str]] = [("Doughnut", n) for n in raksasa_nama]
    giliran = 0
    while rose_nama or komen_nama:
        giliran += 1
        if rose_nama and (giliran % tiap_rose == 0 or not komen_nama):
            rencana.append(("Rose", rose_nama.pop(0)))
        else:
            rencana.append((None, komen_nama.pop(0)))
    return rencana


async def main(file: str, nama_raksasa: list[str], raksasa: int, rose: int,
               komen: int, jeda: float, seling_rose: float,
               dry_run: bool, pembeli: str | None) -> None:
    if pembeli:
        tiktok_listener.API_TOKEN = token_pembeli(pembeli)
    with open(file, encoding="utf-8") as f:
        nama = list(dict.fromkeys(b.strip() for b in f if b.strip()))
    tiap_rose = max(1, round(seling_rose / jeda)) if jeda > 0 else 1
    rencana = susun_rencana(nama, nama_raksasa, raksasa, rose, komen, tiap_rose)

    pipeline = Pipeline(dry_run=dry_run)
    await pipeline.open()
    log.info("Mock daftar -> %s, kanal %s%s", PUSH_URL, pembeli or "utama",
             "  (DRY RUN)" if dry_run else "")
    log.info("Komentar tiap %.0f detik, Rose tiap %.0f detik, total %s penonton (~%.0f detik)",
             jeda, jeda * tiap_rose, len(rencana), jeda * len(rencana))
    try:
        for i, (gift, user) in enumerate(rencana):
            # Penonton TikTok-nya dibedakan, supaya tidak kena USER_COOLDOWN_S.
            penonton = f"mock_daftar_{i}"
            if gift:
                await pipeline.handle_gift(penonton, user, gift, 1, koin_gift(gift))
            await pipeline.handle(penonton, user, user)
            if jeda > 0 and i < len(rencana) - 1:
                await asyncio.sleep(jeda)
    finally:
        await pipeline.aclose()
    log.info("Selesai: masuk %s, ditolak %s, per tier %s",
             pipeline.pushed, pipeline.rejected, pipeline.per_tier)


def cli() -> None:
    parser = argparse.ArgumentParser(description="Mock dari daftar username")
    parser.add_argument("--file", default="tt-username-list.txt")
    parser.add_argument("--raksasa", type=int, default=1, help="Jumlah Doughnut (tier 5)")
    parser.add_argument("--nama-raksasa", default="Darling4300",
                        help="Username raksasa, pisahkan koma (kurang = diisi acak)")
    parser.add_argument("--rose", type=int, default=5, help="Jumlah Rose (tier 3)")
    parser.add_argument("--komen", type=int, default=30,
                        help="Jumlah komentar username biasa (tier 1)")
    parser.add_argument("--jeda", type=float, default=5.0,
                        help="Detik antar komentar (0 = sekaligus)")
    parser.add_argument("--seling-rose", type=float, default=20.0,
                        help="Detik antar Rose; di antaranya komentar biasa")
    parser.add_argument("--dry-run", action="store_true", help="Jangan kirim ke /api/push")
    parser.add_argument("--pembeli", default=os.environ.get("INSTANCE") or None,
                        help="Kanal pembeli di buyers.json (default: INSTANCE di .env)")
    parser.add_argument("--utama", action="store_true",
                        help="Kirim ke kanal utama (API_TOKEN), bukan kanal pembeli")
    a = parser.parse_args()
    nama_raksasa = [n.strip() for n in a.nama_raksasa.split(",") if n.strip()]
    asyncio.run(main(a.file, nama_raksasa, a.raksasa, a.rose, a.komen, a.jeda,
                     a.seling_rose, a.dry_run,
                     None if a.utama else a.pembeli))


if __name__ == "__main__":
    cli()
