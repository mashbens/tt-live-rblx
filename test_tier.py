"""Uji logika tier v2 dengan Lua sungguhan.

Fungsinya diambil APA ADANYA dari my_scrip_lua_v2 lewat penanda baris,
jadi yang diuji benar-benar kode yang jalan di Studio -- bukan salinan
yang bisa basi.

Dua hal yang diuji, dan dua-duanya adalah bug yang TIDAK menimbulkan
error waktu live -- cuma tampilan yang salah, yang baru ketahuan setelah
siarannya lewat:

  1. lantai aura  -- yang bayar tidak boleh dapat angka kecil, tapi juga
     tidak boleh mengubah langit-langit orang gratisan.
  2. jatah border -- Roblox cuma menggambar sekitar 31 Highlight
     sekaligus. Yang ke-32 diam-diam tidak digambar, tanpa satu pun
     pesan. Kode kita melepas yang paling tua supaya yang HILANG selalu
     border lama, tidak pernah border orang yang barusan bayar.
"""
import io, re, sys
from lupa import LuaRuntime

src = io.open("my_scrip_lua_v2", encoding="utf-8").read().split("\n")


def ambil(nama):
    """Ambil teks satu `local function <nama>` sampai `end` di kolom 0."""
    awal = next(i for i, l in enumerate(src)
                if l.startswith(f"local function {nama}("))
    akhir = next(i for i in range(awal + 1, len(src)) if src[i] == "end")
    teks = "\n".join(src[awal:akhir + 1])
    # Lua biasa tidak punya operator gabungan Luau. Ini SATU-SATUNYA
    # perubahan terhadap kode aslinya, dan cuma sintaks.
    return re.sub(r"(\S+) \+= (\S+)", r"\1 = \1 + \2", teks)


def angka(nama):
    """Nilai sebuah `local <NAMA> = <angka>` dari sumbernya."""
    pola = re.compile(rf"^local {nama}\s*=\s*(-?\d+(?:\.\d+)?)")
    for baris in src:
        m = pola.match(baris)
        if m:
            return float(m.group(1))
    raise SystemExit(f"konstanta {nama} tidak ketemu di my_scrip_lua_v2")


lua = LuaRuntime(unpack_returned_tuples=True)

# Diambil dari sumbernya, tidak ditulis ulang: kalau nanti angkanya
# digeser di my_scrip_lua_v2, tes ini ikut bergeser dan tetap menguji
# yang benar.
AURA_MIN   = int(angka("AURA_MIN"))
AURA_MAX   = int(angka("AURA_MAX"))
LANTAI_T2  = int(angka("AURA_LANTAI_T2"))
LANTAI_T3  = int(angka("AURA_LANTAI_T3"))
MAKS_GARIS = int(angka("BORDER_MAKS_GARIS"))

lua.execute(f"""
TIER_ENABLED   = true
AURA_MIN       = {AURA_MIN}
AURA_MAX       = {AURA_MAX}
AURA_LANTAI_T2 = {LANTAI_T2}
AURA_LANTAI_T3 = {LANTAI_T3}

BORDER_ENABLED    = true
BORDER_GARIS      = true
BORDER_CAKRAM     = false   -- cakram butuh CFrame/workspace sungguhan;
                            -- yang diuji di sini pembukuannya, bukan
                            -- bentuk benda yang digambar.
BORDER_MAKS_GARIS = {MAKS_GARIS}
BORDER_CAKRAM_D     = 5.5   -- tidak dipakai (BORDER_CAKRAM mati), tapi
BORDER_CAKRAM_TIPIS = 0.15  -- pasangBorder tetap menghitung ukurannya
BORDER_CAKRAM_ALPHA = 0.55  -- sebelum memeriksa saklarnya
BORDER_CAKRAM_LAMPU = 14
BORDER_T2_WARNA   = 0
BORDER_T3_WARNA   = 1
BORDER_ISI        = 0.92
BORDER_GARIS_ALPHA = 0
BORDER_T2_UMUR    = 0       -- 0 = tidak pudar sendiri, jadi yang
BORDER_T3_UMUR    = 0       -- menghapus HANYA jatah di atas
BORDER_PUDAR      = 0

borderHidup = {{}}

-- Sepotong Roblox, seperlunya saja.
Enum = {{ HighlightDepthMode = {{ AlwaysOnTop = "AlwaysOnTop" }} }}

digambar = 0
function Instance_new(kelas)
    digambar = digambar + 1
    local o = {{ ClassName = kelas, Parent = nil }}
    o.Destroy = function(self) self.Parent = nil; digambar = digambar - 1 end
    return o
end
Instance = {{ new = Instance_new }}

-- Dijalankan seketika, bukan ditunda: tes ini tidak punya scheduler,
-- dan yang mau dilihat justru akibatnya sesudah pelepasan selesai.
task = {{
    spawn = function(f) f() end,
    delay = function(_, f) f() end,
}}
RunService = {{ Heartbeat = {{ Wait = function() end }} }}
""")

for f in ("hitungAura", "warnaTier", "umurBorder", "lepasBorder",
          "pasangBorder"):
    lua.execute(ambil(f).replace("local function", "function", 1))

lua.execute("""
-- pasangBorder cuma menyentuh model lewat GetPivot, dan itu pun cuma
-- kalau cakramnya nyala.
function bikinModel(nama) return { Name = nama } end
""")

g = lua.globals()
gagal = []


def cek(nama, syarat, detail=""):
    print(("  OK   " if syarat else "  GAGAL") + "  " + nama
          + (" -- " + detail if detail and not syarat else ""))
    if not syarat:
        gagal.append(nama)


print("1. Lantai aura")
t1 = [g.hitungAura(1) for _ in range(4000)]
t2 = [g.hitungAura(2) for _ in range(4000)]
t3 = [g.hitungAura(3) for _ in range(4000)]

cek("tier 1 tidak dikasih lantai", min(t1) < LANTAI_T2,
    f"terendah {min(t1)}, harusnya bisa di bawah {LANTAI_T2}")
cek(f"tier 2 tidak pernah di bawah {LANTAI_T2}%", min(t2) >= LANTAI_T2,
    f"terendah {min(t2)}")
cek(f"tier 3 tidak pernah di bawah {LANTAI_T3}%", min(t3) >= LANTAI_T3,
    f"terendah {min(t3)}")
cek("lantainya naik terus, tidak pernah turun", LANTAI_T2 < LANTAI_T3,
    f"{LANTAI_T2} / {LANTAI_T3} -- tier yang lebih mahal tidak boleh "
    "punya lantai lebih rendah")
cek("langit-langitnya tidak ikut naik", max(t1 + t2 + t3) <= AURA_MAX,
    f"tertinggi {max(t1 + t2 + t3)}")
cek("yang gratisan masih bisa mengalahkan tier 3", max(t1) > LANTAI_T3,
    f"tertinggi tier 1 cuma {max(t1)}")

print("\n2. Jatah Highlight: yang paling tua yang dilepas")
for i in range(MAKS_GARIS):
    g.pasangBorder(g.bikinModel(f"u{i}"), i + 1, 2, 0)
cek(f"{MAKS_GARIS} border pertama semuanya terpasang",
    len(g.borderHidup) == MAKS_GARIS, f"ada {len(g.borderHidup)}")
cek("tidak ada yang dilepas sebelum penuh", g.digambar == MAKS_GARIS,
    f"{g.digambar} Highlight hidup")

tertua = g.borderHidup[1]
g.pasangBorder(g.bikinModel("yang_barusan_bayar"), 999, 3, 0)

cek("jumlahnya tidak melewati jatah", len(g.borderHidup) == MAKS_GARIS,
    f"ada {len(g.borderHidup)} -- lewat dari {MAKS_GARIS}, "
    "Roblox akan diam-diam tidak menggambar sebagiannya")
cek("Highlight hidup ikut tidak lewat", g.digambar == MAKS_GARIS,
    f"{g.digambar} hidup")
cek("yang dilepas yang PALING TUA", tertua.lepas is True)
cek("yang barusan bayar tetap dapat border",
    g.borderHidup[MAKS_GARIS].slot == 999,
    f"yang terakhir slot {g.borderHidup[MAKS_GARIS].slot}")

print("\n3. Border tidak pernah dilepas dua kali")
sebelum = g.digambar
g.lepasBorder(tertua, True)      # yang tadi sudah dilepas
cek("pelepasan kedua diabaikan", g.digambar == sebelum,
    f"{g.digambar} vs {sebelum} -- penghitungnya jadi minus")

print("\n4. Tier 1 tidak dapat apa-apa")
sebelum = len(g.borderHidup)
cek("pasangBorder(tier 1) tidak mengembalikan apa-apa",
    g.pasangBorder(g.bikinModel("gratisan"), 1, 1, 0) is None)
cek("dan tidak menyita jatah", len(g.borderHidup) == sebelum,
    f"{len(g.borderHidup)} vs {sebelum}")

print("\n5. Warna dan umur border beda tiap tier")
cek("dua warna berbeda", g.warnaTier(2) != g.warnaTier(3),
    "tier 2 dan 3 memakai warna yang sama -- penonton tidak bisa "
    "membedakannya dari jauh")
cek("umur border punya jawaban untuk tiap tier",
    all(g.umurBorder(t) is not None for t in (2, 3)))

print()
if gagal:
    print("GAGAL:", ", ".join(gagal))
    sys.exit(1)
print("Semua lolos.")
