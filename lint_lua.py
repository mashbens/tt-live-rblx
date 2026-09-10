"""Cari nama KONSTANTA yang dipakai tapi tidak pernah dideklarasikan.

Ini menutup satu lubang yang tidak tertutup oleh apa pun: Lua tidak
menganggap variabel global yang belum ada sebagai kesalahan -- dia
bernilai nil dan diam. Jadi `TABEL_FIELD` yang seharusnya `TABEL.FIELD`
lolos kompilasi dengan mulus, lalu meledak di Studio sebagai:

    invalid argument #2 to 'format' (number expected, got nil)

Dan karena itu terjadi di chunk utama, SELURUH script berhenti di situ
-- gelung pollingnya tidak pernah jalan. Satu salah ketik, panggung
mati total, dan pesannya tidak menyebut nama variabelnya sama sekali.

Yang diperiksa cuma nama GAYA KONSTANTA (HURUF_BESAR_BERGARIS). Nama
lain terlalu banyak bentuknya untuk ditebak tanpa parser Lua sungguhan,
dan konstanta justru yang paling sering ditulis ulang dengan tangan.
"""
import io, re, sys

# Tipe data Roblox yang memang global dan tidak pernah dideklarasikan.
BAWAAN = {
    "Enum", "Instance", "Color3", "Vector3", "CFrame", "UDim2", "UDim",
    "Font", "ColorSequence", "ColorSequenceKeypoint", "NumberSequence",
    "NumberSequenceKeypoint", "NumberRange", "TweenInfo", "Vector2",
    "BrickColor", "Rect", "PhysicalProperties", "Random", "Ray",
}


def bersihkan(s: str) -> str:
    """Sisakan KODE saja: komentar dan isi string dibuang.

    Dua-duanya perlu, dan alasannya sama: nama konstanta muncul di
    banyak tempat yang bukan pemakaian. Komentar di file ini penuh
    menyebut nama konstanta, dan pesan peringatannya menyebut nama
    setelan .env -- keduanya akan terbaca sebagai variabel yang belum
    dideklarasikan, dan hasilnya daftar panjang yang tidak ada artinya
    sehingga tidak ada yang membacanya.

    URUTANNYA PENTING, dan versi pertama fungsi ini salah di situ.
    Komentar baris dibuang duluan, jadi `--` yang ada DI DALAM string
    ("Samakan -- kalau tidak, ") ikut terpotong; sisanya string yang
    tidak pernah ditutup, dan pembuangan string sesudahnya meleset.
    Yang benar: blok komentar (batasnya jelas) -> string -> komentar
    baris. Tiap langkah menghapus hal yang bisa membingungkan langkah
    berikutnya.
    """
    s = re.sub(r"--\[\[.*?\]\]", "", s, flags=re.S)
    s = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', s)
    s = re.sub(r"'(?:[^'\\\n]|\\.)*'", "''", s)
    return "\n".join(re.sub(r"--.*$", "", b) for b in s.split("\n"))


def periksa(path: str) -> list[str]:
    kode = bersihkan(io.open(path, encoding="utf-8").read())

    ada = set(re.findall(r"\blocal\s+function\s+([A-Za-z_]\w*)", kode))
    ada |= set(re.findall(r"^\s*([A-Za-z_]\w*)\s*=", kode, re.M))
    for daftar in re.findall(r"\blocal\s+([A-Za-z_][\w,\s]*)", kode):
        ada |= {x.strip() for x in daftar.split(",") if x.strip()}

    # Yang DIPAKAI. Nama sesudah titik dilewati: `VISUAL.DOF_FOKUS` itu
    # field pada tabel, bukan variabel -- dan field memang tidak pernah
    # dideklarasikan dengan `local`.
    dipakai = {
        m.group(1)
        for m in re.finditer(r"(?<![.\w])([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)\b", kode)
    }

    return sorted(dipakai - ada - BAWAAN)


gagal = False
for p in ("my_scrip_lua_v2", "kamera_client_lua_v2"):
    hilang = periksa(p)
    if hilang:
        gagal = True
        print(f"  GAGAL  {p}: nil global -> {', '.join(hilang)}")
    else:
        print(f"  OK     {p}")

if gagal:
    print("\nNama di atas dipakai tapi tidak pernah dideklarasikan. "
          "Di Lua nilainya nil, dan script berhenti di pemakaian pertama.")
    sys.exit(1)
print("\nSemua lolos.")
