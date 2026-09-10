"""Uji pembukuan slot podium (raksasa) dengan Lua sungguhan.

Fungsi-fungsinya diambil APA ADANYA dari my_sscript_lua lewat penanda
baris, jadi yang diuji benar-benar kode yang jalan di Studio -- bukan
salinan yang bisa basi.
"""
import io, re, sys
from lupa import LuaRuntime

src = io.open("my_sscript_lua", encoding="utf-8").read().split("\n")

def ambil(nama):
    """Ambil teks satu `local function <nama>` sampai `end` di kolom 0."""
    awal = next(i for i, l in enumerate(src)
                if l.startswith(f"local function {nama}("))
    akhir = next(i for i in range(awal + 1, len(src)) if src[i] == "end")
    teks = "\n".join(src[awal:akhir + 1])
    # Lua biasa tidak punya operator gabungan Luau. Ini SATU-SATUNYA
    # perubahan terhadap kode aslinya, dan cuma sintaks.
    return re.sub(r"(\w+) \+= (\S+)", r"\1 = \1 + \2", teks)

lua = LuaRuntime(unpack_returned_tuples=True)

# Stub: cuma yang benar-benar disentuh fungsi-fungsi di bawah.
lua.execute("""
avatars, tracks, tiers, scales, heights = {}, {}, {}, {}, {}
slotOf, giantOrder, giantTaken, giantToken, giantModel = {}, {}, {}, {}, {}
giantOwner, ownerOf, podiums = {}, {}, {}
GIANT_BASE, GIANT_MAX, FX_EXIT = 1000, 5, false
BACK_ROW_SIZE, BACK_SPACING_X, BACK_SPACING_Z, BACK_Z, BASE_Y = 5, 18, 26, 48, 5

-- Workspace palsu: model "hidup" selama Parent-nya belum nil.
hidup = {}
function bikinModel(nama)
    local m = {Name = nama, Parent = "workspace"}
    m.Destroy = function(self) self.Parent = nil; hidup[self] = nil end
    hidup[m] = true
    return m
end
function jumlahHidup()
    local n = 0
    for _ in pairs(hidup) do n = n + 1 end
    return n
end

function hapusPodium(slot, langsung) podiums[slot] = nil end
function playBurstFX() end
function colorFromUsername() return 0 end
""")

for f in ("lepasSlotRaksasa", "buangRaksasa", "pangkasRaksasa",
          "pesanSlot", "ambilSlotRaksasa"):
    try:
        teks = ambil(f)
    except StopIteration:
        continue          # versi lama belum punya fungsi ini
    lua.execute(teks.replace("local function", "function", 1))

lua.execute("""
-- Meniru spawnAvatar: pesan nomor, lalu pasang modelnya.
function tamuDatang(pemilik, nama)
    local slot, token = ambilSlotRaksasa(pemilik)
    local m = bikinModel(nama)
    avatars[slot] = m
    slotOf[string.lower(nama)] = slot
    return slot
end
""")

g = lua.globals()
gagal = []

def cek(nama, syarat, detail=""):
    print(("  OK   " if syarat else "  GAGAL") + "  " + nama + (" -- " + detail if detail and not syarat else ""))
    if not syarat:
        gagal.append(nama)

print("1. Orang yang sama kirim gift tier 3 lima kali")
for i in range(5):
    slot = g.tamuDatang("andi", "builderman")
cek("cuma satu podium terpakai", len(g.giantOrder) == 1, f"ada {len(g.giantOrder)}")
cek("cuma satu avatar berdiri", g.jumlahHidup() == 1,
    f"{g.jumlahHidup()} avatar menumpuk di podium yang sama")
cek("nomor podiumnya tetap sama", slot == 1000, f"slot {slot}")

print("\n2. Lima orang berbeda")
lua.execute("""
avatars, tracks, tiers, scales, heights = {}, {}, {}, {}, {}
slotOf, giantOrder, giantTaken, giantToken, giantModel = {}, {}, {}, {}, {}
giantOwner, ownerOf, podiums, hidup = {}, {}, {}, {}
""")
for n in ("a", "b", "c", "d", "e"):
    g.tamuDatang(n, "user_" + n)
cek("lima podium terisi", len(g.giantOrder) == 5, f"ada {len(g.giantOrder)}")
cek("lima avatar berdiri", g.jumlahHidup() == 5, f"ada {g.jumlahHidup()}")

print("\n3. Orang keenam -- yang terlama harus tenggelam")
g.tamuDatang("f", "user_f")
cek("tetap lima podium", len(g.giantOrder) == 5, f"ada {len(g.giantOrder)}")
cek("tetap lima avatar (yang terlama dihapus)", g.jumlahHidup() == 5,
    f"ada {g.jumlahHidup()}")
cek("'a' sudah tidak punya podium", g.giantOwner["a"] is None)
cek("'f' menempati nomor bekas 'a'", g.giantOwner["f"] == 1000,
    f"dapat {g.giantOwner['f']}")

print("\n4. Campuran: 5 orang, lalu salah satunya kirim lagi 3x")
for i in range(3):
    g.tamuDatang("c", "user_c")
cek("tetap lima podium", len(g.giantOrder) == 5, f"ada {len(g.giantOrder)}")
cek("tetap lima avatar", g.jumlahHidup() == 5, f"ada {g.jumlahHidup()}")

print()
if gagal:
    print("GAGAL:", ", ".join(gagal)); sys.exit(1)
print("Semua lolos.")
