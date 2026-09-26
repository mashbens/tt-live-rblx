"""
Kelola daftar pembeli (buyers.json) yang dibaca main.py.

    python pembeli.py repo andi 12345678     # repo sendiri: ../tt-rblx-andi
    python pembeli.py tambah andi 12345678   # buat token baru, cetak tokennya
    python pembeli.py daftar
    python pembeli.py hapus andi

Tiap pembeli = satu token (diisi di .env pembeli sebagai API_TOKEN) + Roblox
userId pemilik Private Server-nya. Lihat bagian KANAL di main.py.

`tambah` juga menulis paket_pembeli/<nama>/.env yang sudah terisi -- taruh
di sebelah TikTokRoblox.exe di paket yang dikirim ke pembeli itu.

File ini cuma mengubah buyers.json di laptop. `make pembeli` yang juga
mengirimnya ke VM -- main.py di sana membacanya ulang sendiri, tanpa restart.

buyers.json berisi token semua pembeli: ada di .gitignore, jangan di-commit.
"""

import json
import os
import re
import secrets
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).parent
FILE = ROOT / "buyers.json"
PAKET = ROOT / "paket_pembeli"
PUBLIC_URL = os.environ.get("PUBLIC_URL", "https://rblx.buanaglobalcipta.com")

# Setelan listener yang ikut disalin dari .env pemilik ke .env pembeli.
# Yang menentukan tier ada di LISTENER (tier_dari_gift), jadi ambang koin dan
# nama gift pembeli harus sama dengan milik pemilik -- kalau tidak, gift yang
# sama jadi tier berbeda tergantung siapa yang live. Rahasia (EulerStream,
# TUNNEL_SSH, API_TOKEN pemilik) sengaja tidak ada di sini.
KUNCI_SALIN = re.compile(
    r"^(TIER[0-9]_KOIN|GIFT_TIER|GIFT_NAIK|LIKE_[A-Z_]+|USER_COOLDOWN_S|"
    r"NAME_DEDUPE_S|VERIFY_ROBLOX|REQUIRE_SINGLE_WORD)=")


def tulis_env(nama: str, token: str) -> Path:
    salin = []
    env = ROOT / ".env"
    if env.exists():
        salin = [b for b in env.read_text().splitlines() if KUNCI_SALIN.match(b)]
    folder = PAKET / nama
    folder.mkdir(parents=True, exist_ok=True)
    isi = f"""# Setelan TikTokRoblox untuk {nama}. JANGAN dibagikan: token di bawah
# yang menghubungkan live kamu ke Private Server kamu.
API_TOKEN={token}
PUSH_URL={PUBLIC_URL}/api/push

# Setelan gift -- sama dengan milik pemilik game, jangan diubah.
""" + "\n".join(salin) + "\n"
    (folder / ".env").write_text(isi)
    return folder / ".env"


# Kunci .env pemilik yang TIDAK disalin ke repo pembeli: diganti nilai milik
# pembeli itu di buat_repo.
KUNCI_GANTI = re.compile(r"^(INSTANCE|API_TOKEN|PUSH_URL)=")


def buat_repo(nama: str, roblox_id: str) -> int:
    """Repo sendiri untuk satu pembeli: worktree git di sebelah repo ini.

    Worktree, bukan salinan: perbaikan di main tinggal di-merge ke
    pembeli/<nama>, dan yang dikustom per pembeli (Lua, lagu, .env) tetap
    miliknya sendiri.
    """
    tujuan = ROOT.parent / f"{ROOT.name}-{nama}"
    if tujuan.exists():
        print(f"{tujuan} sudah ada.")
        return 1
    # Worktree dibuat dari commit terakhir -- perubahan yang belum di-commit
    # tidak ikut, dan repo pembeli diam-diam jadi versi lama.
    kotor = subprocess.run(["git", "status", "--porcelain", "--untracked-files=no"],
                           cwd=ROOT, capture_output=True, text=True).stdout
    if kotor.strip():
        print("Ada perubahan yang belum di-commit -- commit dulu, supaya ikut "
              "ke repo pembeli:\n" + kotor)
        return 1

    subprocess.run(["git", "worktree", "add", str(tujuan), "-b", f"pembeli/{nama}"],
                   cwd=ROOT, check=True)

    # .venv dipakai bersama (isinya sama), asset/ disalin (lagu per pembeli
    # boleh beda). Dua-duanya tidak ada di git, jadi worktree tidak membawanya.
    (tujuan / ".venv").symlink_to(ROOT / ".venv")
    if (ROOT / "asset").is_dir():
        shutil.copytree(ROOT / "asset", tujuan / "asset", dirs_exist_ok=True)

    url = f"{PUBLIC_URL.rstrip('/')}/{nama}"
    env_lama = (ROOT / ".env").read_text().splitlines() if (ROOT / ".env").exists() else []
    env = [b for b in env_lama if not KUNCI_GANTI.match(b)]
    env += [
        "",
        f"# Repo pembeli {nama} -- container tt-rblx-{nama}, {url}",
        f"INSTANCE={nama}",
        # Kunci pemilik untuk container ini (make mock/peek/clear dari repo
        # ini). Pembeli memakai tokennya sendiri dari buyers.json.
        f"API_TOKEN={secrets.token_urlsafe(24)}",
        f"PUSH_URL={url}/api/push",
    ]
    (tujuan / ".env").write_text("\n".join(env) + "\n")
    (tujuan / ".env").chmod(0o600)

    lua = tujuan / "src/ServerScriptService/AvatarQueueV2.server.luau"
    teks, n = re.subn(r'^(local URL\s*=\s*)"[^"]*"', rf'\g<1>"{url}"',
                      lua.read_text(), count=1, flags=re.M)
    if n != 1:
        print(f"PERINGATAN: baris `local URL = ...` tidak ketemu di {lua.name} -- isi sendiri: {url}")
    lua.write_text(teks)
    subprocess.run(["git", "commit", "-q", "-am", f"URL server pembeli {nama}: {url}"],
                   cwd=tujuan, check=True)

    subprocess.run([sys.executable, "pembeli.py", "tambah", nama, roblox_id],
                   cwd=tujuan, check=True, env={**os.environ, "PUBLIC_URL": url})

    print(f"""
Repo pembeli siap: {tujuan}  (branch pembeli/{nama})
Lanjut:
  cd {tujuan}
  # kustom Lua di src/, lagu di asset/, setelan tier di .env
  make deploy           # container tt-rblx-{nama} + route {url}/
  make rojo             # sinkron ke Studio, lalu publish sebagai GAME BARU
  make exe              # -> C:\\tt-rblx-build\\TikTokRoblox-{nama}.zip""")
    return 0


def muat() -> dict:
    return json.loads(FILE.read_text()) if FILE.exists() else {}


def simpan(data: dict) -> None:
    FILE.write_text(json.dumps(data, indent=2) + "\n")
    FILE.chmod(0o600)


def main(argv: list[str]) -> int:
    data = muat()
    perintah = argv[0] if argv else "daftar"

    if perintah == "tambah" and len(argv) == 3:
        nama, roblox_id = argv[1], argv[2]
        # Jadi nama folder di paket_pembeli/.
        if not re.fullmatch(r"[A-Za-z0-9_-]+", nama):
            print(f"Nama cuma boleh huruf, angka, - dan _, bukan '{nama}'.")
            return 1
        if not roblox_id.isdigit():
            print(f"Roblox userId harus angka, bukan '{roblox_id}'.")
            print("Lihat di profil Roblox-nya: roblox.com/users/<ANGKA>/profile")
            return 1
        lama = data.get(nama, {})
        # Tambah ulang nama yang sudah ada = ganti userId, token tetap. Token
        # baru cuma kalau memang belum punya -- pembeli tidak perlu mengubah
        # .env-nya tiap kali salah ketik userId dibetulkan.
        token = lama.get("token") or secrets.token_urlsafe(24)
        for lain, v in data.items():
            if lain != nama and v.get("robloxId") == int(roblox_id):
                print(f"userId {roblox_id} sudah dipakai '{lain}'.")
                return 1
        data[nama] = {"token": token, "robloxId": int(roblox_id)}
        simpan(data)
        env = tulis_env(nama, token)
        print(f"Pembeli '{nama}' (Roblox {roblox_id}).")
        print(f"  API_TOKEN={token}")
        print(f"  .env siap kirim: {env.relative_to(ROOT)}")
        return 0

    if perintah == "repo" and len(argv) == 3:
        if not re.fullmatch(r"[A-Za-z0-9_-]+", argv[1]) or not argv[2].isdigit():
            print("python pembeli.py repo <nama: huruf/angka/-/_> <Roblox userId>")
            return 1
        return buat_repo(argv[1], argv[2])

    if perintah == "hapus" and len(argv) == 2:
        if data.pop(argv[1], None) is None:
            print(f"Tidak ada pembeli '{argv[1]}'.")
            return 1
        simpan(data)
        print(f"'{argv[1]}' dihapus -- tokennya langsung tidak berlaku.")
        return 0

    if perintah == "daftar":
        if not data:
            print("Belum ada pembeli.")
        for nama, v in data.items():
            print(f"  {nama:<20} Roblox {v.get('robloxId')}   "
                  f"token {v.get('token', '')[:6]}…")
        return 0

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
