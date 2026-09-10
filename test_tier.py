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


def ambil(nama, berkas=None):
    """Ambil teks satu `local function <nama>` sampai `end` di kolom 0.

    `berkas` untuk mengambil dari file lain (kamera_client_lua_v2):
    sebagian fungsi yang perlu diuji hidup di sisi client, dan
    menyalinnya ke sini berarti yang diuji salinan yang bisa basi.
    """
    baris = src if berkas is None else \
        io.open(berkas, encoding="utf-8").read().split("\n")
    awal = next(i for i, l in enumerate(baris)
                if l.startswith(f"local function {nama}("))
    akhir = next(i for i in range(awal + 1, len(baris)) if baris[i] == "end")
    teks = "\n".join(baris[awal:akhir + 1])
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
LANTAI_T4  = int(angka("AURA_LANTAI_T4"))
MAKS_GARIS = int(angka("BORDER_MAKS_GARIS"))

lua.execute(f"""
TIER_ENABLED   = true
AURA_MIN       = {AURA_MIN}
AURA_MAX       = {AURA_MAX}
AURA_LANTAI_T2 = {LANTAI_T2}
AURA_LANTAI_T3 = {LANTAI_T3}
AURA_LANTAI_T4 = {LANTAI_T4}

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
t4 = [g.hitungAura(4) for _ in range(4000)]

cek("tier 1 tidak dikasih lantai", min(t1) < LANTAI_T2,
    f"terendah {min(t1)}, harusnya bisa di bawah {LANTAI_T2}")
cek(f"tier 2 tidak pernah di bawah {LANTAI_T2}%", min(t2) >= LANTAI_T2,
    f"terendah {min(t2)}")
cek(f"tier 3 tidak pernah di bawah {LANTAI_T3}%", min(t3) >= LANTAI_T3,
    f"terendah {min(t3)}")
cek(f"tier 4 tidak pernah di bawah {LANTAI_T4}%", min(t4) >= LANTAI_T4,
    f"terendah {min(t4)}")
cek("lantainya naik terus, tidak pernah turun",
    LANTAI_T2 < LANTAI_T3 < LANTAI_T4,
    f"{LANTAI_T2} / {LANTAI_T3} / {LANTAI_T4} -- tier yang lebih mahal "
    "tidak boleh punya lantai lebih rendah")
cek("langit-langitnya tidak ikut naik",
    max(t1 + t2 + t3 + t4) <= AURA_MAX,
    f"tertinggi {max(t1 + t2 + t3 + t4)}")
cek("yang gratisan masih bisa mengalahkan tier 4", max(t1) > LANTAI_T4,
    f"tertinggi tier 1 cuma {max(t1)} -- kalau tidak, undian penonton "
    "gratisan berhenti punya arti")

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
    all(g.umurBorder(t) is not None for t in (2, 3, 4)))



print("\n6. Kamera per tier")
#
# Yang diuji di sini BUKAN rasa, tapi dua hal yang bisa salah tanpa
# terlihat sampai ada yang bayar:
#
#   1. Putaran angka aura harus SELESAI di dalam sorotannya. Kalau
#      tunda + AURA_ROLL melebihi panjang sorotan, angkanya mendarat
#      setelah kamera pergi -- momen yang dibayar orangnya jatuh di luar
#      sorotannya sendiri, dan itu tidak memunculkan error apa pun.
#   2. Busur kamera tidak boleh keluar dari KERUCUT DEPAN. Begitu
#      simpangannya mendekati 90 derajat, kamera berada di samping badan
#      dan wajah, papan aura, serta border semuanya menghadap ke arah
#      lain. Ini yang dulu terjadi lewat orbit dan jalur tiga sudut.
#   3. Busur tier 3 harus lebih lebar dari tier 2. Itu pembeda gerakan
#      di antara keduanya sekarang; kalau lebarnya kebetulan disetel
#      sama, dua tier berhenti terbaca sebagai dua tingkat dan yang
#      tersisa cuma auranya.
#
# Durasi sorotannya diambil dari main.py, bukan ditulis ulang: dua sisi
# yang menyimpan angka yang sama secara terpisah adalah cara paling
# gampang membuat keduanya diam-diam berbeda.
import main as srv

AURA_ROLL = angka("AURA_ROLL")

lua.execute(f"""
ZOOM_KELUAR       = {angka("ZOOM_KELUAR")}
ZOOM_KELUAR_GIANT = {angka("ZOOM_KELUAR_GIANT")}
""")

awal_tab = next(i for i, l in enumerate(src) if l.startswith("local KAMERA_TIER = {"))
akhir_tab = next(i for i in range(awal_tab + 1, len(src)) if src[i] == "}")
lua.execute("\n".join(src[awal_tab:akhir_tab + 1]).replace("local ", "", 1))
lua.execute(ambil("kameraTier").replace("local function", "function", 1))

for t in (1, 2, 3, 4):
    k = g.kameraTier(t)
    cek(f"tier {t} punya semua angka kamera",
        None not in (k.tahan, k.keluar, k.maks, k.arcDeg, k.arcPutar,
                     k.naikAmp, k.tunda))
    cek(f"tier {t} mundurnya tidak melebihi jarak penuh",
        0 < k.maks <= 1.0, f"maks {k.maks}")

cek("tier tak dikenal jatuh ke tier 1, bukan nil",
    g.kameraTier(99).tahan == g.kameraTier(1).tahan)

# Putaran angka harus selesai di dalam sorotan (tier berbayar saja --
# tier 1 tidak punya sorotan, papannya hidup selama AURA_TIME).
for t, ms in ((2, srv.SPOTLIGHT_MS_T2), (3, srv.SPOTLIGHT_MS_T3)):
    k = g.kameraTier(t)
    habis = k.tunda + AURA_ROLL
    cek(f"tier {t}: angka mendarat sebelum sorotan habis "
        f"({k.tunda:.1f}+{AURA_ROLL:.1f} <= {ms / 1000:.1f}s)",
        habis <= ms / 1000 + 1e-9,
        f"mendarat di {habis:.1f}s, sorotan cuma {ms / 1000:.1f}s")

# Raksasa: papannya cuma nama, jadi tidak ada yang perlu ditunggu.
cek("tier 4 tidak menunda apa-apa (papannya cuma nama)",
    g.kameraTier(4).tunda == 0)

# --- Busur harus tetap di kerucut DEPAN ---
#
# 45 derajat batas yang dipakai di sini, bukan 90. Di 90 kamera tepat di
# samping badan; jauh sebelum itu wajah dan papan aura sudah mulai
# menyerong. Setengahnya memberi jarak yang cukup, dan tidak ada tier
# yang butuh lebih lebar dari itu untuk terasa hidup.
BATAS_DEPAN = 45.0

# Dijalankan lewat fungsi Lua yang SAMA dengan yang dipakai client, jadi
# yang diuji simpangan yang benar-benar terjadi -- bukan angka arcDeg
# yang kebetulan tertulis di tabel.
#
# math.clamp itu Luau (ada di Roblox), tidak ada di Lua standar. Di-shim
# supaya fungsi aslinya bisa dijalankan apa adanya tanpa disunting.
lua.execute("""
if not math.clamp then
    math.clamp = function(v, lo, hi)
        if v < lo then return lo elseif v > hi then return hi else return v end
    end
end
""")
lua.execute(ambil("busurSudut", "kamera_client_lua_v2")
            .replace("local function", "function", 1))

import math as _m


def puncak(t):
    """Simpangan TERJAUH dari depan yang benar-benar dicapai, derajat."""
    k = g.kameraTier(t)
    amp = _m.radians(k.arcDeg)
    return max(abs(_m.degrees(g.busurSudut(i / 400, amp, k.arcPutar)))
               for i in range(401))


for t in (2, 3, 4):
    p = puncak(t)
    cek(f"tier {t} tidak pernah keluar kerucut depan "
        f"(puncak {p:.0f} <= {BATAS_DEPAN:.0f} derajat)",
        p <= BATAS_DEPAN + 1e-9,
        f"puncaknya {p:.0f} derajat -- di situ kamera sudah menyerong "
        "ke samping badan dan wajahnya menghadap ke arah lain")

# Berangkat DAN pulang dari depan: kalau tidak, adegan berikutnya mulai
# dari sudut sisa milik adegan sebelumnya.
for t in (2, 3, 4):
    k = g.kameraTier(t)
    amp = _m.radians(k.arcDeg)
    cek(f"tier {t} mulai dan selesai di depan",
        abs(g.busurSudut(0, amp, k.arcPutar)) < 1e-9
        and abs(g.busurSudut(1, amp, k.arcPutar)) < 1e-6,
        f"mulai {_m.degrees(g.busurSudut(0, amp, k.arcPutar)):.1f}, "
        f"selesai {_m.degrees(g.busurSudut(1, amp, k.arcPutar)):.1f} derajat")

a2, a3 = g.kameraTier(2).arcDeg, g.kameraTier(3).arcDeg
print(f"  (busur tier 2 +/-{a2:.0f} derajat, tier 3 +/-{a3:.0f} derajat)")
cek("busur tier 3 lebih lebar dari tier 2", a3 >= a2 + 8,
    f"{a2:.0f} vs {a3:.0f} derajat -- bedanya terlalu kecil untuk "
    "terbaca sebagai dua tingkat")

# Naik-turun juga harus pulang ke nol, dengan alasan yang sama.
for t in (2, 3, 4):
    k = g.kameraTier(t)
    cek(f"tier {t} naik-turunnya pulang ke tinggi semula",
        abs(k.naikAmp * _m.sin(_m.pi * 1.0)) < 1e-9)

cek("raksasa naik-turunnya paling jauh",
    g.kameraTier(4).naikAmp > g.kameraTier(3).naikAmp,
    "badan 4x dibaca dari kaki ke kepala -- dia yang paling butuh "
    "gerakan vertikal")

print("\n7. Raksasa: satu jawaban, dipakai dua tempat")
#
# Bug yang pernah TERJADI, bukan hipotesis: syarat "tier ini raksasa
# atau bukan" dulu ditulis dua kali -- di gelung utama yang memilih
# SLOT-nya, dan di spawnAvatar yang MEMPERBESAR badannya. Waktu raksasa
# dipindah dari tier 3 ke tier 4, cuma satu yang ikut berubah, dan
# hasilnya tertukar: tier 3 berdiri di belakang barisan dengan badan
# normal, tier 4 jadi raksasa DI DALAM barisan.
#
# Tidak ada error dan tidak ada nil, jadi lint tidak melihat apa pun.
# Yang mengunci sekarang: kedua tempat memanggil adalahRaksasa(), dan
# tes ini menjaga jawabannya.
lua.execute(f"""
GIANT_ENABLED = true
GIANT_MIN_TIER = {int(angka("GIANT_MIN_TIER"))}
""")
lua.execute(ambil("adalahRaksasa").replace("local function", "function", 1))

for t in (1, 2, 3):
    cek(f"tier {t} BUKAN raksasa", g.adalahRaksasa(t) is False,
        f"tier {t} ikut jadi raksasa -- dia harus berdiri di barisan")
cek("tier 4 raksasa", g.adalahRaksasa(4) is True)
cek("tier di atas 4 tetap raksasa", g.adalahRaksasa(5) is True,
    "tier baru di atasnya harus ikut raksasa, bukan diam-diam kembali "
    "jadi badan normal")

# Yang membekukan panggung harus DIIKAT ke tier raksasa, bukan angka
# yang kebetulan sama sekarang. Yang diperiksa sumbernya, bukan
# nilainya: dua angka yang hari ini sama-sama 4 lolos pemeriksaan nilai,
# lalu berpisah diam-diam di perubahan berikutnya.
baris_beku = next((l for l in src if l.startswith("local BEKU_MIN_TIER")), "")
cek("beku diikat ke GIANT_MIN_TIER, bukan angka sendiri",
    "GIANT_MIN_TIER" in baris_beku,
    f"tertulis: {baris_beku.strip()!r} -- kalau raksasa pindah tier, "
    "angka ini tertinggal dan tier di bawahnya ikut membekukan panggung")

# Aura VFX tidak boleh menyentuh raksasa -- dia harus polos.
cek("aura VFX bukan milik tier raksasa",
    int(angka("AURA_VFX_TIER")) < int(angka("GIANT_MIN_TIER")),
    "raksasa harus polos: aura di badan sebesar itu menyaingi ukurannya")

print()
if gagal:
    print("GAGAL:", ", ".join(gagal))
    sys.exit(1)
print("Semua lolos.")
