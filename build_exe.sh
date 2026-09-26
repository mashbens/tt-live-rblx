#!/usr/bin/env bash
# Bangun TikTokRoblox.exe dari WSL, sekali jalan -- lewat `make exe`.
#
#   make exe              -> TikTokRoblox.zip (tanpa .env)
#   make exe NAMA=andi    -> TikTokRoblox-andi.zip, sudah berisi .env andi
#                            (dari `make pembeli NAMA=andi ...`)
#
# PyInstaller tidak bisa membuat .exe dari Linux, jadi yang menjalankannya
# Python WINDOWS -- versi portable dari paket nuget resmi python.org:
# cukup diekstrak, tidak diinstal, tidak menyentuh PATH atau registry.
# WSL bisa menjalankan python.exe itu langsung (interop), jadi tidak ada
# yang perlu diklik di Windows.
#
# Semua kerjaan di $WIN_DIR (drive C:, bukan \\wsl$ -- PyInstaller dan pip
# di Windows tidak akur dengan path UNC). Python dan paketnya diunduh sekali;
# build berikutnya tinggal beberapa puluh detik.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
WIN_DIR="${WIN_DIR:-/mnt/c/tt-rblx-build}"
PY_VER="${PY_VER:-3.12.10}"
NAMA="${NAMA:-}"

PY_DIR="$WIN_DIR/python"
PY_EXE="$PY_DIR/tools/python.exe"
SRC="$WIN_DIR/src"

# File yang masuk ke .exe (modul lokal yang diimpor tt_rblx.py).
SUMBER=(tt_rblx.spec tt_rblx.py dashboard.py tiktok_listener.py roblox_ssl.py mock_comments.py)

if ! command -v cmd.exe >/dev/null; then
    echo "Interop Windows mati -- script ini harus jalan di WSL."
    exit 1
fi
if [ -n "$NAMA" ] && [ ! -f "$ROOT/paket_pembeli/$NAMA/.env" ]; then
    echo "paket_pembeli/$NAMA/.env tidak ada. Jalankan dulu:"
    echo "  make pembeli NAMA=$NAMA ROBLOX_ID=<userId Roblox-nya>"
    exit 1
fi

mkdir -p "$WIN_DIR"

if [ ! -f "$PY_EXE" ]; then
    echo ">> Unduh Python $PY_VER portable (sekali saja, ~15 MB)"
    tmp="$WIN_DIR/python.nupkg"
    curl -fL --progress-bar -o "$tmp" \
        "https://api.nuget.org/v3-flatcontainer/python/$PY_VER/python.$PY_VER.nupkg"
    rm -rf "$PY_DIR"
    python3 -c "import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
        "$tmp" "$PY_DIR"
    rm -f "$tmp"
fi

rm -rf "$SRC"
mkdir -p "$SRC"
for f in "${SUMBER[@]}"; do cp "$ROOT/$f" "$SRC/"; done

# python.exe mewarisi folder kerja WSL sebagai C:\..., jadi semua path di
# bawah relatif ke $SRC -- path Linux tidak berarti apa-apa buat Windows.
cd "$SRC"

echo ">> Pasang paket (yang sudah ada dilewati)"
"$PY_EXE" -m pip install -q --disable-pip-version-check --no-warn-script-location \
    "TikTokLive>=6.4.0" "httpx>=0.27" "python-dotenv>=1.0.0" "websockets>=12.0" \
    pyinstaller

echo ">> PyInstaller"
"$PY_EXE" -m PyInstaller --noconfirm --log-level WARN \
    --distpath dist --workpath build tt_rblx.spec

# Isi zip: .exe + berkas yang dibaca dari sebelahnya (lihat BASE_DIR di
# tiktok_listener.py dan ROOT di dashboard.py).
nama_zip="TikTokRoblox${NAMA:+-$NAMA}.zip"
python3 - "$SRC/dist/TikTokRoblox.exe" "$ROOT" "$NAMA" "$WIN_DIR/$nama_zip" <<'EOF'
import sys, zipfile
from pathlib import Path

exe, root, nama, keluar = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3], sys.argv[4]
isi = {"TikTokRoblox.exe": exe,
       "roblox_blacklist.txt": root / "roblox_blacklist.txt",
       "PANDUAN_PEMBELI.txt": root / "PANDUAN_PEMBELI.txt"}
for lagu in sorted((root / "asset").glob("*.mp3")):
    isi[f"asset/{lagu.name}"] = lagu
if nama:
    isi[".env"] = root / "paket_pembeli" / nama / ".env"

# Satu folder di dalam zip: pembeli yang mengekstrak di Desktop dapat folder
# TikTokRoblox, bukan belasan file berserakan.
with zipfile.ZipFile(keluar, "w", zipfile.ZIP_DEFLATED) as z:
    for nama_arsip, sumber in isi.items():
        z.write(sumber, f"TikTokRoblox/{nama_arsip}")
print(f"   {len(isi)} file")
EOF

win_path="$(wslpath -w "$WIN_DIR/$nama_zip")"
echo ""
echo "Selesai: $win_path"
[ -z "$NAMA" ] && echo "(tanpa .env -- pakai NAMA=... untuk paket pembeli)"
exit 0
