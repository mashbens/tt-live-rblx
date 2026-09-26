# PyInstaller: satu .exe untuk pembeli (dashboard + listener).
#
# Jangan dipanggil langsung: `make exe` (build_exe.sh) yang menjalankannya
# dengan Python Windows portable, lalu membungkus hasilnya jadi zip.
#
# .env, asset\, dan roblox_blacklist.txt SENGAJA tidak dimasukkan ke .exe:
# mereka dibaca dari folder di sebelah .exe, supaya pembeli bisa mengganti
# lagu dan setelan tanpa build ulang.

from PyInstaller.utils.hooks import collect_all

datas, binaries, hiddenimports = [], [], []
# TikTokLive memuat proto dan modul klien lewat import dinamis yang tidak
# terlihat analisis PyInstaller.
for paket in ("TikTokLive", "TikTokLiveProto", "betterproto2"):
    d, b, h = collect_all(paket)
    datas += d
    binaries += b
    hiddenimports += h

a = Analysis(
    ["tt_rblx.py"],
    datas=datas,
    binaries=binaries,
    hiddenimports=hiddenimports + ["dashboard", "tiktok_listener", "mock_comments"],
    # Cuma dipakai tes dan server VM.
    excludes=["lupa", "fastapi", "uvicorn", "tkinter"],
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    name="TikTokRoblox",
    # Konsol tetap ada: jendela itu yang menandakan dashboard hidup, dan
    # menutupnya mematikan listener juga.
    console=True,
    upx=False,
)
