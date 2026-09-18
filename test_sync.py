"""Uji penyamaan tarian v2 dengan Lua sungguhan.

Fungsinya diambil APA ADANYA dari KameraClientV2 lewat penanda
baris, jadi yang diuji benar-benar kode yang jalan di Studio.

Yang diuji dua bug yang SAMA-SAMA terlihat sebagai "tariannya
patah-patah", dan dua-duanya tidak pernah memunculkan satu pun baris di
Output:

  1. Avatar yang memainkan animasi LAIN -- raksasa dengan R15Wave
     (~2 detik), atau apa pun yang nanti ditambahkan -- ikut masuk
     kolam penyamaan. Begitu salah satunya terpilih jadi master,
     SELURUH kerumunan dipaksa ke TimePosition milik animasi lambaian
     tiap 0,6 detik -- tarian 10 detik yang terus dilempar balik ke
     detik 0-2.
  2. Selisih waktu dihitung lurus, tidak dilipat. Avatar di detik 9,9
     dari animasi 10 detik dianggap melenceng 9,9 detik dari yang di
     detik 0, padahal dia cuma 0,1 detik di depannya -- jadi dia
     diloncatkan terus-menerus tanpa pernah dianggap benar.
"""
import io, re, sys
from lupa import LuaRuntime

src = io.open("src/StarterPlayer/StarterPlayerScripts/KameraClientV2.client.luau", encoding="utf-8").read().split("\n")


def ambil(nama):
    """Ambil teks satu `local function <nama>` sampai `end` di kolom 0."""
    awal = next(i for i, l in enumerate(src)
                if l.startswith(f"local function {nama}("))
    akhir = next(i for i in range(awal + 1, len(src)) if src[i] == "end")
    teks = "\n".join(src[awal:akhir + 1])
    # Lua biasa tidak punya operator gabungan Luau. Ini SATU-SATUNYA
    # perubahan terhadap kode aslinya, dan cuma sintaks.
    return re.sub(r"(\S+) \+= (\S+)", r"\1 = \1 + \2", teks)


lua = LuaRuntime(unpack_returned_tuples=True)

# AnimationTrack palsu: yang disentuh fungsi-fungsi di bawah cuma
# .Animation.AnimationId dan .TimePosition.
lua.execute("""
function track(id, waktu)
    return { Animation = { AnimationId = id }, TimePosition = waktu or 0 }
end
""")

for f in ("kelompokTerbesar", "selisihLingkar"):
    lua.execute(ambil(f).replace("local function", "function", 1))

g = lua.globals()
gagal = []


def cek(nama, syarat, detail=""):
    print(("  OK   " if syarat else "  GAGAL") + "  " + nama
          + (" -- " + detail if detail and not syarat else ""))
    if not syarat:
        gagal.append(nama)


def daftar(*pasangan):
    """[(animId, waktu), ...] -> tabel Lua berisi track palsu."""
    return lua.table(*[g.track(i, w) for i, w in pasangan])


DANCE = "rbxassetid://106865236633450"
WAVE  = "rbxassetid://507770239"    # raksasa
FALL  = "rbxassetid://507767968"    # yang melayang

print("1. Yang animasinya lain tidak boleh menyeret kerumunan")
grup = g.kelompokTerbesar(daftar(
    (DANCE, 1.0), (DANCE, 1.1), (DANCE, 0.9), (DANCE, 1.2),
    (WAVE, 0.4),      # raksasa
    (FALL, 0.7),      # animasi lain lagi, cuma satu
))
cek("kelompok yang dipilih berisi 4 penari", len(grup) == 4,
    f"berisi {len(grup)}")
cek("semuanya animasi yang sama",
    len({grup[i].Animation.AnimationId for i in range(1, len(grup) + 1)}) == 1)
cek("yang dipilih tariannya, bukan animasi lain",
    grup[1].Animation.AnimationId == DANCE,
    f"terpilih {grup[1].Animation.AnimationId}")

print("\n2. Raksasa sendirian di panggung kosong")
grup = g.kelompokTerbesar(daftar((WAVE, 0.4)))
cek("tetap mengembalikan sesuatu, tidak error", grup is not None)
cek("isinya cuma satu -- gelung utamanya melewati yang begini",
    len(grup) == 1, f"berisi {len(grup)}")

print("\n3. Panggung kosong")
cek("daftar kosong -> tidak ada kelompok",
    g.kelompokTerbesar(lua.table()) is None)

print("\n4. Selisih dilipat lewat titik ulang animasi")
L = 10.0
cek("9,9 vs 0,0 dibaca 0,1 detik, bukan 9,9",
    abs(g.selisihLingkar(0.0, 9.9, L) - 0.1) < 1e-9,
    f"dapat {g.selisihLingkar(0.0, 9.9, L)}")
cek("arah sebaliknya juga",
    abs(g.selisihLingkar(9.9, 0.0, L) + 0.1) < 1e-9,
    f"dapat {g.selisihLingkar(9.9, 0.0, L)}")
cek("selisih biasa tidak berubah",
    abs(g.selisihLingkar(5.0, 4.8, L) - 0.2) < 1e-9,
    f"dapat {g.selisihLingkar(5.0, 4.8, L)}")
cek("tidak pernah lebih jauh dari setengah putaran",
    all(abs(g.selisihLingkar(a / 10, b / 10, L)) <= L / 2 + 1e-9
        for a in range(0, 100, 7) for b in range(0, 100, 11)))
cek("panjang animasi belum diketahui (0) -> dipakai apa adanya",
    abs(g.selisihLingkar(0.0, 9.9, 0) + 9.9) < 1e-9,
    f"dapat {g.selisihLingkar(0.0, 9.9, 0)}")

print("\n5. Yang ketinggalan dipercepat, bukan diperlambat")
# Tanda selisihnya yang menentukan arah koreksi di gelung utama:
#   selisih positif = `kini` di belakang ref  -> kecepatan dinaikkan
cek("yang tertinggal menghasilkan selisih positif",
    g.selisihLingkar(5.0, 4.5, L) > 0)
cek("yang kedahuluan menghasilkan selisih negatif",
    g.selisihLingkar(4.5, 5.0, L) < 0)

print()
if gagal:
    print("GAGAL:", ", ".join(gagal))
    sys.exit(1)
print("Semua lolos.")
