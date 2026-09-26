"""
Pintu masuk .exe Windows untuk pembeli (dibangun lewat tt_rblx.spec).

    TikTokRoblox.exe                  dashboard, browser terbuka sendiri
    TikTokRoblox.exe listener [...]   tiktok_listener.py, argumen sama
    TikTokRoblox.exe mock [...]       mock_comments.py (komentar palsu)
    TikTokRoblox.exe peek             lihat isi antrian
    TikTokRoblox.exe clear            kosongkan antrian

Satu .exe untuk semuanya: dashboard menjalankan listener dengan memanggil
.exe-nya sendiri (lihat perintah() di dashboard.py), karena di dalam .exe
tidak ada python.exe maupun `make`.

Di laptop pemilik repo tetap pakai `make dashboard` / `make listener`.
"""

import sys

# Konsol dan pipa Windows memakai cp1252. Emoji pertama di nama penonton
# TikTok -> UnicodeEncodeError -> listener mati di tengah live. Harus
# sebelum modul lain diimpor: logging listener memegang sys.stderr sejak
# diimpor.
for _aliran in (sys.stdout, sys.stderr):
    if _aliran is not None and hasattr(_aliran, "reconfigure"):
        _aliran.reconfigure(encoding="utf-8", errors="replace")


def main() -> int:
    perintah, argv = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("", [])

    if perintah == "listener":
        import tiktok_listener
        tiktok_listener.main(argv)
        return 0
    if perintah == "mock":
        import mock_comments
        mock_comments.cli(argv)
        return 0

    import dashboard
    if perintah in ("peek", "clear"):
        return dashboard.perintah_antrian(perintah)
    if perintah:
        print(__doc__)
        return 1
    dashboard.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
