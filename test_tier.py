"""Uji logika tier v2 dengan Lua sungguhan.

Fungsinya diambil APA ADANYA dari AvatarQueueV2 lewat penanda baris,
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

src = io.open("src/ServerScriptService/AvatarQueueV2.server.luau", encoding="utf-8").read().split("\n")


def ambil(nama, berkas=None):
    """Ambil teks satu `local function <nama>` sampai `end` di kolom 0.

    `berkas` untuk mengambil dari file lain (KameraClientV2):
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
    raise SystemExit(f"konstanta {nama} tidak ketemu di AvatarQueueV2")


def angka_baris_awal(pola):
    """Angka dari baris pertama sumber yang cocok dengan `pola`."""
    r = re.compile(pola)
    for baris in src:
        m = r.match(baris)
        if m:
            return float(m.group(1))
    raise SystemExit(f"pola {pola} tidak ketemu di AvatarQueueV2")


lua = LuaRuntime(unpack_returned_tuples=True)

# Diambil dari sumbernya, tidak ditulis ulang: kalau nanti angkanya
# digeser di AvatarQueueV2, tes ini ikut bergeser dan tetap menguji
# yang benar.
AURA_MIN   = int(angka("AURA_MIN"))
AURA_MAX   = int(angka("AURA_MAX"))
LANTAI_T2  = int(angka("AURA_LANTAI_T2"))
LANTAI_T3  = int(angka("AURA_LANTAI_T3"))
LANTAI_T4  = int(angka("AURA_LANTAI_T4"))
RAKSASA    = int(angka("AURA_RAKSASA"))
RAKSASA_MIN = int(angka("AURA_RAKSASA_MIN"))
MAKS_GARIS = int(angka("BORDER_MAKS_GARIS"))

lua.execute(f"""
TIER_ENABLED   = true
AURA_MIN       = {AURA_MIN}
AURA_MAX       = {AURA_MAX}
AURA_LANTAI_T2 = {LANTAI_T2}
AURA_LANTAI_T3 = {LANTAI_T3}
AURA_LANTAI_T4 = {LANTAI_T4}
AURA_RAKSASA   = {RAKSASA}
AURA_RAKSASA_MIN = {RAKSASA_MIN}
GIANT_MIN_TIER = {int(angka("GIANT_MIN_TIER"))}
NOVA           = {{ TIER = {int(angka_baris_awal(r"^NOVA\.TIER\s*=\s*(\d+)"))} }}
BORDER_GARIS_MIN_TIER = {int(angka("BORDER_GARIS_MIN_TIER"))}

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
t5 = [g.hitungAura(5) for _ in range(4000)]

cek("tier 1 tidak dikasih lantai", min(t1) < LANTAI_T2,
    f"terendah {min(t1)}, harusnya bisa di bawah {LANTAI_T2}")
cek(f"tier 2 tidak pernah di bawah {LANTAI_T2}%", min(t2) >= LANTAI_T2,
    f"terendah {min(t2)}")
cek(f"tier 3 tidak pernah di bawah {LANTAI_T3}%", min(t3) >= LANTAI_T3,
    f"terendah {min(t3)}")
cek(f"tier 4 (nova) tidak pernah di bawah {LANTAI_T4}%", min(t4) >= LANTAI_T4,
    f"terendah {min(t4)}")
# Raksasa diundi di rentangnya SENDIRI, setipis 9.999-10.000.
#
# Dua-duanya harus benar-benar keluar: rentang yang cuma pernah
# menghasilkan satu angka sama saja dengan tidak diundi -- dan putarannya
# jadi tidak punya apa pun untuk ditunggu.
cek(f"raksasa diundi {RAKSASA_MIN}-{RAKSASA}%, dan kedua ujungnya keluar",
    min(t5) == RAKSASA_MIN and max(t5) == RAKSASA,
    f"{min(t5)}-{max(t5)}")
cek("lantainya naik terus, tidak pernah turun",
    LANTAI_T2 < LANTAI_T3 < LANTAI_T4 < RAKSASA_MIN,
    f"{LANTAI_T2} / {LANTAI_T3} / {LANTAI_T4} / {RAKSASA} -- tier yang "
    "lebih mahal tidak boleh punya angka lebih rendah")
# Langit-langit UNDIAN. Raksasa sengaja di luarnya, dan itu satu-satunya
# pengecualian: dia tidak ikut diundi, jadi tidak ada yang bisa dia
# rusak dengan berada di atas atap.
cek("langit-langit undian tidak ikut naik",
    max(t1 + t2 + t3 + t4) <= AURA_MAX,
    f"tertinggi {max(t1 + t2 + t3 + t4)}")
cek(f"raksasa memang di LUAR skala semua orang ({RAKSASA_MIN} > {AURA_MAX})",
    RAKSASA_MIN > AURA_MAX,
    "angkanya masih bisa dicapai penonton gratisan yang beruntung -- "
    "yang bayar paling mahal membayar untuk angka yang bukan miliknya")
# Sampai di mana penonton gratisan masih punya kesempatan.
#
# Tes ini dulu berbunyi "yang gratisan masih bisa mengalahkan tier 4",
# dan itu memang prinsipnya sampai lantainya 550/600/650. Lantai
# 900/999/1000 MELEPAS prinsip itu untuk tier 3 dan 4 dengan sengaja --
# yang dibeli 10 koin sekarang angka yang pasti, bukan undian yang bagus.
#
# Yang tersisa dijaga di sini, dan itu yang sekarang jadi janjinya:
# tier 2 masih bisa dikalahkan, jadi undian gratisan belum sepenuhnya
# kehilangan arti.
cek("yang gratisan masih bisa mengalahkan tier 2", max(t1) > LANTAI_T2,
    f"tertinggi tier 1 cuma {max(t1)} -- kalau tier 2 pun tidak bisa "
    "dikalahkan, undian penonton gratisan berhenti punya arti sama sekali")
cek(f"nova praktis dijamin ({LANTAI_T4}-{AURA_MAX}%)",
    AURA_MAX - LANTAI_T4 <= 5,
    f"lantai {LANTAI_T4} -- yang diminta angka yang pasti untuk nova")
cek("langit-langitnya tidak pernah dinaikkan untuk menutupi lantainya",
    AURA_MAX == 1000,
    f"AURA_MAX {AURA_MAX} -- yang dinaikkan harus lantainya, bukan ini; "
    "menaikkan atapnya mengubah arti angka untuk SEMUA orang")

print("\n2. Jatah Highlight: yang paling tua yang dilepas")
# Tier 3 (Rosa): tier terendah yang dapat garis tepi. Rose cuma cakram.
for i in range(MAKS_GARIS):
    g.pasangBorder(g.bikinModel(f"u{i}"), i + 1, 3, 0)
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

# Rose (tier 2): cakram biru saja. Yang diuji di sini dia TIDAK menyita
# jatah garis -- Rose yang paling sering datang, dan kalau dia ikut memakai
# jatah Highlight, border orang yang bayar Rosa dilepas duluan untuk dia.
# (Cakramnya sendiri butuh workspace sungguhan, jadi dimatikan di tes ini.)
sebelum = len(g.borderHidup)
g.pasangBorder(g.bikinModel("rose"), 1, 2, 0)
cek("Rose tidak dapat garis tepi, dan tidak menyita jatah Highlight",
    len(g.borderHidup) == sebelum,
    f"{len(g.borderHidup)} vs {sebelum} -- Rose ikut memakai jatah garis")

print("\n5. Warna dan umur border beda tiap tier")
cek("Rose dan Rosa sama-sama BIRU", g.warnaTier(2) == g.warnaTier(3),
    "cakram Rose harus biru -- itu yang diminta")
cek("tier nova ke atas punya warna sendiri", g.warnaTier(3) != g.warnaTier(4),
    "tier 3 dan 4 memakai warna yang sama -- penonton tidak bisa "
    "membedakannya dari jauh")
cek("umur border punya jawaban untuk tiap tier",
    all(g.umurBorder(t) is not None for t in (2, 3, 4, 5)))



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
#   3. Kamera tier 2 harus PELAN: tanpa denyut dan mundurnya panjang. Itu
#      yang diminta untuk aura, dan satu angka denyut yang tersalin dari
#      tier lain membuat partikel auranya terlihat bergetar.
#
# Durasi sorotannya diambil dari main.py, bukan ditulis ulang: dua sisi
# yang menyimpan angka yang sama secara terpisah adalah cara paling
# gampang membuat keduanya diam-diam berbeda.
import main as srv

AURA_ROLL = angka("AURA_ROLL")

lua.execute(f"""
ZOOM_KELUAR       = {angka("ZOOM_KELUAR")}
ZOOM_KELUAR_GIANT = {angka("ZOOM_KELUAR_GIANT")}
-- auraMulai tier 3 menjumlahkannya: nova baru mulai sesudah client
-- selesai menunggu aset avatarnya.
SPAWN_SIAP_MAKS   = {angka("SPAWN_SIAP_MAKS")}
""")

# Tabel NOVA dimuat DULUAN, sebelum KAMERA_TIER, dan itu bukan urutan
# yang bebas dipilih: auraMulai tier 3 ditulis sebagai `novaTotal() + 0.1`
# di sumbernya -- justru supaya lama adegan nova cuma punya satu jawaban.
# Konsekuensinya di sini, tabelnya harus sudah ada waktu KAMERA_TIER
# dijalankan.
#
# Color3 di-stub karena NOVA.PALET isinya triplet biasa, tapi baris lain
# di dalam rentang yang diambil bisa saja memanggilnya nanti.
lua.execute("""
Color3 = { fromRGB = function(r, g, b) return { r, g, b } end }
""")
awal_nova = next(i for i, l in enumerate(src) if l.startswith("local NOVA = {}"))
akhir_nova = next(i for i in range(awal_nova, len(src)) if src[i].startswith("NOVA.TARI"))
lua.execute("\n".join(src[awal_nova:akhir_nova + 1]).replace("local ", "", 1))
lua.execute(ambil("novaTotal").replace("local function", "function", 1))

# LAYAR juga dimuat duluan: KAMERA_TIER[3] membaca LAYAR.PILIHAN.
awal_layar = next(i for i, l in enumerate(src) if l.startswith("local LAYAR = {}"))
akhir_layar = next(i for i in range(awal_layar, len(src))
                   if src[i].startswith("LAYAR.PILIHAN = {"))
akhir_layar = next(i for i in range(akhir_layar, len(src)) if src[i] == "}")
lua.execute("\n".join(src[awal_layar:akhir_layar + 1]).replace("local ", "", 1))

# ROSA juga: KAMERA_TIER[3] membaca ROSA.JALUR.
awal_rosa = next(i for i, l in enumerate(src) if l.startswith("local ROSA = {}"))
akhir_rosa = next(i for i in range(awal_rosa, len(src))
                  if src[i].startswith("ROSA.TEMA = {"))
akhir_rosa = next(i for i in range(akhir_rosa, len(src)) if src[i] == "}")
lua.execute("\n".join(src[awal_rosa:akhir_rosa + 1]).replace("local ", "", 1))

awal_tab = next(i for i, l in enumerate(src) if l.startswith("local KAMERA_TIER = {"))
akhir_tab = next(i for i in range(awal_tab + 1, len(src)) if src[i] == "}")
lua.execute("\n".join(src[awal_tab:akhir_tab + 1]).replace("local ", "", 1))
lua.execute(ambil("kameraTier").replace("local function", "function", 1))

for t in (1, 2, 3, 4, 5):
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
#
# `roll` dibaca per tier, bukan AURA_ROLL untuk semua: tier yang
# sorotannya pendek memakai putaran yang lebih pendek juga. Yang dijaga
# di sini tetap satu hal yang sama -- hentakan mendaratnya tidak boleh
# jatuh SESUDAH kameranya pergi.
SOROTAN_MS = {2: srv.SPOTLIGHT_MS_T2, 3: srv.SPOTLIGHT_MS_T3,
              4: srv.SPOTLIGHT_MS_T4, 5: srv.SPOTLIGHT_MS_T5}

# auraMulai ikut dijumlah: tier yang pesan auranya DITAHAN server (nova)
# baru mulai menghitung tunda sesudah tahanan itu lewat.
for t, ms in sorted(SOROTAN_MS.items()):
    k = g.kameraTier(t)
    roll = k.roll or AURA_ROLL
    mulai = k.auraMulai or 0
    habis = mulai + k.tunda + roll
    cek(f"tier {t}: angka mendarat sebelum sorotan habis "
        f"({mulai:.1f}+{k.tunda:.1f}+{roll:.1f} <= {ms / 1000:.1f}s)",
        habis <= ms / 1000 + 1e-9,
        f"mendarat di {habis:.1f}s, sorotan cuma {ms / 1000:.1f}s")

# --- LAYAR SINEMATIK ROSA ---
#
# Yang dijaga: pilihannya ada, letterbox sempat masuk DAN keluar di dalam
# sorotan 4 detiknya, dan versi bawaan tetap lebih tipis dari nova --
# kalau sama tebal, nova (30 koin) kehilangan satu-satunya yang membedakan
# layarnya dari Rosa (10 koin).
MODE_ROSA = g.LAYAR.MODE_ROSA
cek(f"mode layar Rosa dikenal ('{MODE_ROSA}')",
    MODE_ROSA == "mati" or g.LAYAR.PILIHAN[MODE_ROSA] is not None,
    "salah ketik -- Rosa jalan tanpa efek layar")
for nama in ("tipis", "warna", "penuh"):
    o = g.LAYAR.PILIHAN[nama]
    cek(f"pilihan layar '{nama}' ada", o is not None)
    if o is not None:
        cek(f"layar '{nama}': masuk + keluar muat di sorotan Rosa "
            f"({o.masuk}+{o.keluar} <= {SOROTAN_MS[3] / 1000:.1f}s)",
            o.masuk + o.keluar <= SOROTAN_MS[3] / 1000)
cek("letterbox Rosa bawaan lebih tipis dari nova",
    g.LAYAR.PILIHAN.tipis.letterbox < g.NOVA.CONFIG.letterbox,
    "Rosa dan nova sama tebal -- layar nova tidak lagi istimewa")
cek("tier lain tidak ikut dapat efek layar Rosa",
    all(g.kameraTier(t).layar is None for t in (1, 2, 4, 5)))

# --- JALUR KAMERA ROSA ---
#
# Tiga hal yang salah tanpa satu pun error:
#   1. jalurnya lebih panjang dari sorotan -> kamera biasa merebut kembali
#      di tengah potret, dan angka auranya mendarat tanpa kamera
#   2. angka auranya mendarat di luar bidikan POTRET -> papannya sedang
#      keluar frame waktu angkanya berhenti
#   3. tetangga yang disembunyikan tidak menjangkau lintasan kamera
#      keliling -> separuh putaran memandang dari dalam badan orang lain
J = g.ROSA.JALUR
_total_jalur = J.naik + J.orbit + J.potret + J.lepas
cek(f"jalur Rosa muat di sorotannya ({_total_jalur:.1f} <= {SOROTAN_MS[3] / 1000:.1f}s)",
    _total_jalur <= SOROTAN_MS[3] / 1000 + 1e-9)
cek(f"jalur Rosa putarannya bulat ({J.putaran})",
    abs(J.putaran - round(J.putaran)) < 1e-9 and J.putaran >= 1,
    "putaran tidak bulat berakhir menyerong, dan bidikan potret berangkat "
    "dengan loncatan")
_k3 = g.kameraTier(3)
_mendarat3 = _k3.tunda + _k3.roll
_awal_potret = J.naik + J.orbit
cek(f"angka Rosa mendarat di bidikan POTRET "
    f"({_awal_potret:.1f} <= {_mendarat3:.1f} <= {_awal_potret + J.potret:.1f})",
    _awal_potret <= _mendarat3 <= _awal_potret + J.potret,
    "papan auranya keluar frame waktu angkanya berhenti")
cek(f"kamera keliling tidak terlalu jauh dan tidak di dalam badan "
    f"(radius {J.radius})",
    4 <= J.radius <= 10)
# 6 = jarak antar-slot. Tetangga terdekat berdiri 6 stud dari orangnya,
# dan lebar badannya sekitar 3 -- radius sembunyi harus melewati lintasan
# kamera ditambah itu.
cek(f"tetangga disembunyikan sampai melewati lintasan kamera "
    f"({J.sepi} >= {J.radius} + 3)",
    J.sepi >= J.radius + 3,
    "kamera keliling lewat di dalam badan tetangga yang masih terlihat")
cek(f"ada tema latar Rosa ({len(list(g.ROSA.TEMA.values()))})",
    len(list(g.ROSA.TEMA.values())) >= 1)
cek("cuma Rosa yang punya jalur kamera sendiri",
    all(g.kameraTier(t).jalur is None for t in (1, 2, 4, 5)))

# --- DENYUT ZOOM ---
#
# Dua hal yang bisa salah tanpa terlihat sampai ada yang bayar 10 koin:
#
#   1. Denyutnya mulai SEBELUM zoom dasarnya selesai mundur. Dua
#      gerakan yang saling berlawanan di waktu yang sama tidak terbaca
#      sebagai dua gerakan -- yang terlihat cuma kamera yang ragu-ragu.
#   2. Rapatannya lebih dekat daripada jarak masuk biasa (ZOOM_MASUK).
#      Client punya DENYUT_MIN sebagai jaring terakhir, tapi jaring itu
#      memotong gerakannya -- yang benar angkanya tidak pernah sampai ke
#      sana.
ZOOM_MASUK = angka("ZOOM_MASUK")

for t, ms in sorted(SOROTAN_MS.items()):
    k = g.kameraTier(t)
    if not k.denyutDalam or k.denyutDalam <= 0:
        continue

    lama_s = ms / 1000
    mundur_selesai = (k.tahan + k.keluar) / lama_s
    cek(f"tier {t}: denyut mulai sesudah zoom dasarnya selesai mundur "
        f"({mundur_selesai:.2f} <= {k.denyutMulai:.2f})",
        k.denyutMulai >= mundur_selesai - 1e-9,
        f"mundur baru selesai di {mundur_selesai:.2f} adegan, "
        f"denyut sudah mulai di {k.denyutMulai:.2f}")

    rapat = k.maks * (1 - k.denyutDalam)
    cek(f"tier {t}: rapatan denyut tidak melewati jarak masuk biasa "
        f"({rapat:.2f} >= {ZOOM_MASUK:.2f})",
        rapat >= ZOOM_MASUK - 1e-9,
        f"denyut membawa kamera ke {rapat:.2f} jarak, lebih dekat "
        f"daripada ZOOM_MASUK {ZOOM_MASUK:.2f} -- dia akan dipotong "
        f"DENYUT_MIN di client")

# Gundukan naik-turun harus BULAT. sin(pi*u*n) cuma pulang ke nol di
# u=1 kalau n bulat; yang tidak bulat meninggalkan kamera di tinggi yang
# bukan tinggi biasa, dan kedatangan berikutnya mewarisi pergeseran itu.
for t in (1, 2, 3, 4, 5):
    n = g.kameraTier(t).naikPutar or 1
    cek(f"tier {t}: gundukan naik-turun bulat ({n})",
        abs(n - round(n)) < 1e-9 and n >= 1,
        f"naikPutar {n} -- adegannya berakhir di tinggi yang bukan "
        f"tinggi biasa")

# Raksasa DULU tidak menunda apa-apa: papannya cuma nama, tidak ada
# angka yang berputar. Sekarang papannya berisi 10.000% dan putarannya
# harus menunggu kamera cukup mundur, sama seperti tier lain -- papan
# yang berputar selagi masih di luar frame atas sama saja dengan tidak
# pernah berputar.
cek("raksasa menunda putaran angkanya seperti tier berbayar lain",
    g.kameraTier(int(angka("GIANT_MIN_TIER"))).tunda > 0,
    "tunda 0 -- angkanya habis berputar sebelum papannya masuk frame")

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
lua.execute(ambil("busurSudut", "src/StarterPlayer/StarterPlayerScripts/KameraClientV2.client.luau")
            .replace("local function", "function", 1))

import math as _m


def puncak(t):
    """Simpangan TERJAUH dari depan yang benar-benar dicapai, derajat."""
    k = g.kameraTier(t)
    amp = _m.radians(k.arcDeg)
    return max(abs(_m.degrees(g.busurSudut(i / 400, amp, k.arcPutar)))
               for i in range(401))


for t in (2, 3, 4, 5):
    p = puncak(t)
    cek(f"tier {t} tidak pernah keluar kerucut depan "
        f"(puncak {p:.0f} <= {BATAS_DEPAN:.0f} derajat)",
        p <= BATAS_DEPAN + 1e-9,
        f"puncaknya {p:.0f} derajat -- di situ kamera sudah menyerong "
        "ke samping badan dan wajahnya menghadap ke arah lain")

# Berangkat DAN pulang dari depan: kalau tidak, adegan berikutnya mulai
# dari sudut sisa milik adegan sebelumnya.
for t in (2, 3, 4, 5):
    k = g.kameraTier(t)
    amp = _m.radians(k.arcDeg)
    cek(f"tier {t} mulai dan selesai di depan",
        abs(g.busurSudut(0, amp, k.arcPutar)) < 1e-9
        and abs(g.busurSudut(1, amp, k.arcPutar)) < 1e-6,
        f"mulai {_m.degrees(g.busurSudut(0, amp, k.arcPutar)):.1f}, "
        f"selesai {_m.degrees(g.busurSudut(1, amp, k.arcPutar)):.1f} derajat")

# Tier AURA (Rosa), bukan tier 2 lagi: sejak Rose jadi tier sendiri, yang
# butuh kamera pelan untuk partikelnya tier 3.
TIER_AURA = int(angka("AURA_VFX_TIER"))
k_aura = g.kameraTier(TIER_AURA)
# Rosa sekarang adegan sinematik 10 detik dengan SATU dorongan zoom. Yang
# dijaga: dorongannya jatuh SESUDAH angka auranya mendarat -- kalau
# sebelumnya, papan auranya ikut terlempar keluar frame atas selagi
# angkanya masih berputar, dan putaran itu yang ditonton.
_mendarat = (k_aura.tunda + k_aura.roll) / (SOROTAN_MS[TIER_AURA] / 1000)
cek(f"tier {TIER_AURA} (aura): dorongan zoom sesudah angka mendarat "
    f"({_mendarat:.2f} <= {k_aura.denyutMulai:.2f})",
    not k_aura.denyutDalam or k_aura.denyutDalam <= 0
    or k_aura.denyutMulai >= _mendarat - 1e-9,
    "kamera merapat selagi angkanya masih berputar")
cek(f"tier {TIER_AURA} (aura) kamera pelan: mundurnya paling panjang di antara yang berbayar",
    k_aura.keluar >= max(g.kameraTier(t).keluar for t in (2, 3, 4, 5)),
    f"keluar {k_aura.keluar}")

# Rose yang paling sering datang: busurnya tidak boleh lebih lebar dari
# tier mana pun yang berbayar, dan tanpa denyut.
k_rose = g.kameraTier(2)
cek("Rose (tier 2) kameranya paling tenang: busur tersempit, tanpa denyut",
    k_rose.arcDeg <= min(g.kameraTier(t).arcDeg for t in (3, 4, 5))
    and (not k_rose.denyutDalam or k_rose.denyutDalam <= 0),
    f"arcDeg {k_rose.arcDeg}, denyut {k_rose.denyutDalam}")

# Naik-turun juga harus pulang ke nol, dengan alasan yang sama.
for t in (2, 3, 4, 5):
    k = g.kameraTier(t)
    cek(f"tier {t} naik-turunnya pulang ke tinggi semula",
        abs(k.naikAmp * _m.sin(_m.pi * 1.0)) < 1e-9)

cek("raksasa naik-turunnya paling jauh",
    g.kameraTier(5).naikAmp > max(g.kameraTier(t).naikAmp for t in (2, 3, 4)),
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

for t in (1, 2, 3, 4):
    cek(f"tier {t} BUKAN raksasa", g.adalahRaksasa(t) is False,
        f"tier {t} ikut jadi raksasa -- dia harus berdiri di barisan")
cek("tier 5 (Doughnut) raksasa", g.adalahRaksasa(5) is True)
cek("tier di atas 5 tetap raksasa", g.adalahRaksasa(6) is True,
    "tier baru di atasnya harus ikut raksasa, bukan diam-diam kembali "
    "jadi badan normal")

# Aura VFX tidak boleh menyentuh raksasa -- dia harus polos.
# Raksasa TIDAK dapat aura VFX (sempat dicoba, lalu dicopot): yang
# membuat dia terbaca ukuran badannya.
cek("aura VFX bukan milik tier raksasa",
    int(angka("AURA_VFX_TIER_MAKS")) < int(angka("GIANT_MIN_TIER")),
    "raksasa harus polos: aura di badan sebesar itu menyaingi ukurannya")
# Kalau suatu saat dinyalakan lagi, partikelnya harus ikut diperbesar --
# tanpa itu aura seukuran orang biasa jadi titik kecil di dada raksasa 4x.
cek("pasangAuraVfx tetap memperbesar partikel sebanding skala badan",
    "pasangAuraVfx(model, tier, skala)" in "\n".join(src)
    and "k.Size = skalaSeq(k.Size, f)" in "\n".join(src),
    "aura seukuran orang biasa di badan 4x")

# Papan raksasa dirapikan jadi nama saja SESUDAH angkanya mendarat dan
# sempat dibaca -- dan semua itu harus selesai di dalam sorotannya,
# kalau tidak angkanya mendarat atau berubah jadi nama selagi kamera
# sudah pergi.
_k5 = g.kameraTier(int(angka("GIANT_MIN_TIER")))
_nama_s = angka("AURA_RAKSASA_NAMA_S")
_habis = _k5.tunda + (_k5.roll or angka("AURA_ROLL")) + _nama_s
cek(f"papan raksasa jadi nama saja di dalam sorotannya "
    f"({_k5.tunda:.1f}+{_k5.roll or angka('AURA_ROLL'):.1f}+{_nama_s:.1f} "
    f"<= {srv.SPOTLIGHT_MS_T5 / 1000:.1f}s)",
    0 < _nama_s and _habis <= srv.SPOTLIGHT_MS_T5 / 1000 + 1e-9,
    f"selesai di {_habis:.1f}s")


# --- FRAMING RAKSASA: dia utuh, DAN barisannya ikut terlihat ---
#
# Bug yang pernah terjadi: kamera membidik setinggi ubun-ubun raksasa
# (GIANT_FOKUS_TINGGI dulu 1,15), jadi dia ikut naik setinggi itu juga --
# dan barisan yang berdiri di lantai jatuh ke luar tepi bawah frame. Yang
# terlihat cuma raksasa menggantung di langit, tanpa panggung.
#
# Yang dihitung di sini persis apa yang dihitung gelung render client:
# posisi kamera = titik bidik + offset sinematik x pengali raksasa x
# zoom, lalu sudut tiap benda terhadap TENGAH layar. Batasnya setengah
# FOV bawaan Roblox (70/2 = 35 derajat).
FOV_SETENGAH = 35.0

SKALA   = angka("GIANT_SKALA_MAKS")
G_JAUH  = angka("GIANT_KAMERA_JAUH")
# Pengali TINGGI kamera, terpisah dari pengali jaraknya. Lihat
# GIANT_KAMERA_TINGGI: satu pengali untuk keduanya menaruh kamera di atas
# kepala raksasanya sendiri.
G_KAMY  = angka("GIANT_KAMERA_TINGGI")
G_TINGGI = angka("GIANT_FOKUS_TINGGI")
S_UP    = angka("SINEMA_UP")
S_BACK  = abs(angka("SINEMA_BACK"))
Z_MASUK = g.kameraTier(int(angka("GIANT_MIN_TIER"))).masuk or angka("ZOOM_MASUK")

# Rig R15: HipHeight ~2 + setengah HumanoidRootPart ~1 = 3 per satuan
# skala (lihat tinggiPivot), dan tinggi badan penuh ~5 per skala.
pivot  = 3.0 * SKALA
badan  = 5.0 * SKALA
bidik  = pivot * G_TINGGI

# Barisan berdiri GIANT_Z stud di depan raksasa, kepalanya ~3 stud.
maju_barisan = angka("GIANT_Z")


def tinggi_kamera(zoom):
    """Ketinggian kamera raksasa, stud dari lantai."""
    return bidik + S_UP * SKALA * G_KAMY * zoom


def sudut_raksasa(zoom):
    """(kepala, kaki, barisan) dalam derajat dari tengah layar, + = atas."""
    tinggi_kam = tinggi_kamera(zoom)
    jarak      = S_BACK * SKALA * G_JAUH * zoom
    # Kamera menunduk sebanyak ini; semua sudut di bawah relatif ke sana.
    tunduk = _m.degrees(_m.atan2(tinggi_kam - bidik, jarak))

    def dari_tengah(y, d):
        return _m.degrees(_m.atan2(y - tinggi_kam, d)) + tunduk

    return (dari_tengah(badan, jarak), dari_tengah(0, jarak),
            dari_tengah(3, max(jarak - maju_barisan, 1)))


# Diperiksa di KEDUA ujung geraknya, bukan salah satu. Yang dikeluhkan
# muncul di ujung DEKAT -- di ujung jauh barisannya sebenarnya sudah
# masuk frame (-25 derajat) bahkan dengan bidikan yang lama, jadi tes
# yang cuma melihat ke sana lolos sementara layarnya tetap salah.
for fase, zoom in (("saat kamera paling dekat", Z_MASUK),
                   ("sesudah mundur penuh", 1.0)):
    kepala, kaki, barisan = sudut_raksasa(zoom)

    # Raksasa utuh kaki sampai kepala -- ini yang menjual ukurannya.
    cek(f"raksasa utuh {fase}",
        kepala <= FOV_SETENGAH and kaki >= -FOV_SETENGAH,
        f"kepala {kepala:+.1f} derajat, kaki {kaki:+.1f} -- di luar "
        f"+/-{FOV_SETENGAH:.0f}; naikkan `masuk` di KAMERA_TIER[5] "
        "(berhenti lebih jauh) atau bidikannya")

    # Dan barisannya ikut kelihatan. Ini yang membedakan "raksasa
    # berdiri di panggung" dari "raksasa menggantung di langit".
    cek(f"barisan ikut terlihat {fase}",
        barisan >= -FOV_SETENGAH,
        f"barisan di {barisan:+.1f} derajat, di luar tepi bawah "
        f"-{FOV_SETENGAH:.0f} -- kameranya membidik terlalu tinggi; "
        "turunkan GIANT_FOKUS_TINGGI")

# Kedua angka itu SEPASANG, dan ini yang menjelaskan kenapa. Membidik
# dada tanpa mengurangi rapatannya memotong kepala; mengurangi rapatan
# tanpa menurunkan bidikan tidak mengembalikan barisannya.
cek("bidikan raksasa di badannya, bukan di atas kepalanya",
    0.5 <= G_TINGGI <= 1.0,
    f"GIANT_FOKUS_TINGGI {G_TINGGI} -- di bawah 0,5 kameranya "
    "membidik lutut, di atas 1,0 dia membidik langit di atas ubun-ubun")
cek("raksasa tidak merapat sedekat tier lain",
    Z_MASUK > angka("ZOOM_MASUK"),
    f"masuk {Z_MASUK} -- badan {SKALA:.0f}x tidak muat di jarak "
    "sedekat tier biasa")

# --- WAJAHNYA HARUS TERLIHAT ---
#
# Bug yang pernah TERJADI: tinggi kamera ikut diskalakan pengali JARAK
# yang sama, jadi pada 14x kamera duduk di 78 stud sementara mata
# raksasanya ada di 64. Kameranya empat belas stud DI ATAS kepalanya,
# dan yang dilihat penonton ubun-ubun.
#
# Tidak ada error, tidak ada yang keluar frame, dan ketiga uji framing di
# atas lolos semua -- badannya memang utuh. Yang hilang cuma wajahnya,
# dan wajah itu satu-satunya yang membuat raksasa terbaca sebagai ORANG
# dan bukan sebagai patung.
MATA = 0.92 * badan   # tinggi mata rig R15, kira-kira

for fase, zoom in (("saat kamera paling dekat", Z_MASUK),
                   ("sesudah mundur penuh", 1.0)):
    ky = tinggi_kamera(zoom)
    cek(f"kamera di BAWAH garis mata raksasa {fase} "
        f"({ky:.0f} < {MATA:.0f})",
        ky < MATA,
        f"kamera {ky:.0f} stud, mata {MATA:.0f} -- penonton memandang "
        "ubun-ubunnya, bukan wajahnya")

# Dan pengali tingginya memang HARUS lebih kecil daripada pengali
# jaraknya. Kalau keduanya dibuat sama lagi, bug di atas kembali persis
# -- dan ketiga uji framing tetap lolos, seperti dulu.
cek(f"pengali tinggi kamera di bawah pengali jaraknya "
    f"({G_KAMY} < {G_JAUH})",
    G_KAMY < G_JAUH,
    "tinggi yang ikut jarak membawa kamera ke atas kepala raksasanya")


# --- KEPALANYA JUGA HARUS MUAT DI KAMERA PANGGUNG BIASA ---
#
# Bug yang pernah TERJADI, dan yang paling sering terlihat karena
# raksasa bertahan lewat reset: sorotannya sendiri cuma tujuh detik,
# sisanya dia berdiri di belakang panggung yang menjalankan kedatangan
# biasa -- dan di kamera BIASA kepalanya terpotong tepi atas frame.
#
# Sebabnya sudut tunduk, bukan jarak. Kamera panggung duduk di
# CAMERA_UP_JAUH dan membidik CAMERA_FOKUS_Y dari |CAMERA_BACK| stud,
# jadi dia menunduk -- dan tiap derajat tunduk itu langsung dipotong
# dari ruang di atas frame, di mana kepala raksasa berada.
#
# Tidak ada error dan tidak ada yang bisa dilihat dari log: raksasanya
# BERDIRI, posisinya benar, cuma bagian atasnya yang di luar layar.
SKALA_NYATA = srv.TIER_EFFECTS[int(angka("GIANT_MIN_TIER"))]["scale"]

# Tinggi badan rig R15 polos, stud per satuan skala. Sama dengan yang
# dipakai uji framing di atas. Topi dan rambut yang menjulang menambah
# di atas ini -- itu yang dibayar oleh sisa margin, bukan oleh uji ini.
TINGGI_PER_SKALA = 5.0
kepala_raksasa = TINGGI_PER_SKALA * SKALA_NYATA

UP_JAUH        = angka("CAMERA_UP_JAUH")
UP_JAUH_GIANT  = angka("CAMERA_UP_JAUH_GIANT")
FOKUS_Y        = angka("CAMERA_FOKUS_Y")
BACK           = abs(angka("CAMERA_BACK"))


def sudut_kepala_raksasa(tinggi_kamera):
    """Sudut kepala raksasa dari tengah layar di kamera panggung biasa,
    derajat, saat kamera sudah mundur penuh. + = di atas tengah."""
    # Barisan tumbuh MENJAUH dari raksasa, jadi slot yang paling dekat
    # kamera juga yang paling jauh darinya -- baris 0 (z = 0) yang
    # paling sempit, dan itu yang dihitung di sini.
    jarak = BACK + angka("GIANT_Z")
    tunduk = _m.degrees(_m.atan2(tinggi_kamera - FOKUS_Y, BACK))
    return _m.degrees(_m.atan2(kepala_raksasa - tinggi_kamera, jarak)) + tunduk


lama = sudut_kepala_raksasa(UP_JAUH)
baru = sudut_kepala_raksasa(UP_JAUH_GIANT)

cek(f"kamera panggung TURUN selama ada raksasa "
    f"({UP_JAUH_GIANT} < {UP_JAUH} stud)",
    UP_JAUH_GIANT < UP_JAUH,
    "tanpa itu sudut tunduknya tetap, dan kepala raksasa tetap di luar "
    "tepi atas frame sepanjang kedatangan biasa")

cek(f"kepala raksasa {SKALA_NYATA:.0f}x muat di kamera panggung "
    f"({baru:.0f} <= {FOV_SETENGAH:.0f} derajat)",
    baru <= FOV_SETENGAH,
    f"kepalanya di {baru:.1f} derajat, tepi atas cuma "
    f"{FOV_SETENGAH:.0f} -- turunkan CAMERA_UP_JAUH_GIANT")

# Dan margin yang tersisa itu jatah topi. Tanpa syarat ini, angka yang
# pas-pasan lolos uji di atas sambil tetap memotong avatar yang kebetulan
# pakai topi tinggi -- persis keluhan yang menghasilkan angka ini.
MARGIN_TOPI = 3.0
cek(f"masih ada jatah untuk topi tinggi "
    f"({FOV_SETENGAH - baru:.1f} >= {MARGIN_TOPI:.1f} derajat)",
    FOV_SETENGAH - baru >= MARGIN_TOPI,
    f"sisa {FOV_SETENGAH - baru:.1f} derajat -- rambut atau topi yang "
    "menjulang langsung memotong kepalanya lagi")

cek(f"dan itu memang yang memperbaikinya (dulu {lama:.0f} derajat, "
    f"di luar {FOV_SETENGAH:.0f})",
    lama > FOV_SETENGAH,
    f"di {UP_JAUH} stud kepalanya sudah muat ({lama:.1f}) -- berarti "
    "angka ini menukar kedalaman barisan tanpa membeli apa pun")


# --- PRA-MUAT: aset avatar diunduh SEBELUM dia masuk panggung ---
#
# "Kakinya tidak ada / rambutnya telat muncul". Yang dijaga urutannya:
# pra-muat harus terjadi sebelum model.Parent = workspace. Terbalik, tidak
# ada yang dimuat lebih awal -- dan jadwal kamera, papan aura, dan gempa
# nova yang berjalan sesudahnya ikut terlambat relatif ke badannya.
_teks = "\n".join(src)
_i_pra = _teks.find("\t\ttungguPramuat(model, username)")
_i_ws = _teks.find("\tmodel.Parent = workspace\n")
cek("pra-muat terjadi sebelum avatarnya masuk panggung",
    0 < _i_pra < _i_ws,
    f"pramuat@{_i_pra}, workspace@{_i_ws}")
_klien = io.open("src/StarterPlayer/StarterPlayerScripts/KameraClientV2.client.luau", encoding="utf-8").read()
cek("client ikut mengunduh aset avatar yang sedang dipra-muat",
    'WaitForChild("AvatarPramuat")' in _klien
    and 'FindFirstChild("AvatarPramuat")' in _teks
    and "model.Parent = folder\n" in _teks,
    "server menunggu, tapi tidak ada client yang memanfaatkan tunggunya")
cek("server menunggu laporan siap dari client, bukan jeda tetap",
    "tungguPramuat(model, username)" in _teks
    and "remote.OnServerEvent" in _teks
    and "task.wait(SPAWN_PRAMUAT_S)" not in _teks,
    "tunggunya kembali jadi angka tetap: koneksi bagus menunggu sia-sia, "
    "koneksi jelek tetap dapat avatar bolong")
cek("client melapor ke server begitu asetnya terunduh",
    'WaitForChild("AvatarPramuatSiap")' in _klien
    and "siap:FireServer(m)" in _klien,
    "server menunggu laporan yang tidak pernah dikirim -- tiap avatar "
    "tertahan penuh SPAWN_PRAMUAT_S")


print("\n7b. Nova: tepat satu tier, dan semua sisi sepakat tier yang mana")
#
# Pelajaran dari raksasa di atas, diterapkan sebelum sempat terjadi: nomor
# tier nova hidup di LIMA tempat (NOVA.TIER di Lua, BEKU_MIN_TIER di
# sebelahnya, TIER_EFFECTS di main.py, TIER3_KOIN di listener, LIKE_TIER),
# dan satu yang tertinggal tidak memunculkan error apa pun -- cuma nova
# yang diam-diam tidak jalan.


def angka_baris(pola):
    """Angka pertama yang cocok dengan `pola` di AvatarQueueV2."""
    rx = re.compile(pola)
    for baris in src:
        m = rx.match(baris)
        if m:
            return float(m.group(1))
    raise SystemExit(f"pola {pola!r} tidak ketemu di AvatarQueueV2")


NOVA_TIER = int(angka_baris(r"^NOVA\.TIER\s*=\s*(\d+)"))
GIANT_MIN = int(angka("GIANT_MIN_TIER"))

# Tabel NOVA-nya sudah dijalankan di bagian 6 (auraMulai tier 3
# memanggil novaTotal), jadi di sini tinggal fungsi penentunya. Bagian 10
# di bawah menguji jadwal adegannya dari tabel yang sama.
lua.execute(ambil("adalahNova").replace("local function", "function", 1))

cek("nova cuma satu tier",
    [t for t in range(1, 8) if g.adalahNova(t)] == [NOVA_TIER],
    f"tier yang nova: {[t for t in range(1, 8) if g.adalahNova(t)]}")
cek("tidak ada tier yang nova sekaligus raksasa",
    not any(g.adalahNova(t) and g.adalahRaksasa(t) for t in range(1, 8)),
    "raksasa 14x yang melayang 13 stud lalu membanting diri menyapu "
    "seluruh panggung")
cek(f"nova (tier {NOVA_TIER}) di bawah raksasa (tier {GIANT_MIN})",
    NOVA_TIER < GIANT_MIN)

# Panggung HARUS beku selama nova. Ini bukan selera: adegannya 10 detik
# dan menyita seluruh layar, dan avatar gratisan yang muncul di tengahnya
# menghabiskan slot panggung untuk kedatangan yang tidak ada yang lihat.
#
# Yang diperiksa SUMBERNYA, bukan nilainya -- dua angka yang hari ini
# sama-sama 3 lolos pemeriksaan nilai, lalu berpisah diam-diam di
# perubahan berikutnya. Persis pelajaran BEKU_MIN_TIER di bagian 7.
baris_beku = next((l for l in src if l.startswith("local BEKU_MIN_TIER")), "")
cek("beku diikat ke NOVA.TIER, bukan angka sendiri",
    "NOVA.TIER" in baris_beku,
    f"tertulis: {baris_beku.strip()!r} -- kalau nova pindah tier, angka "
    "ini tertinggal dan tier yang salah yang membekukan panggung")

lua.execute(f"""
AURA_VFX_ENABLED   = true
AURA_VFX_TIER      = {int(angka("AURA_VFX_TIER"))}
AURA_VFX_TIER_MAKS = {int(angka("AURA_VFX_TIER_MAKS"))}
""")
lua.execute(ambil("layakAuraVfx").replace("local function", "function", 1))
dapat_aura = [t for t in range(1, 8) if g.layakAuraVfx(t)]
cek("aura VFX acak milik Rosa dan nova -- bukan Rose, bukan raksasa",
    dapat_aura == [3, NOVA_TIER], f"yang dapat aura: {dapat_aura}")

efek = srv.TIER_EFFECTS
cek(f"main.py sepakat: tier {NOVA_TIER} = nova",
    "nova" in efek.get(NOVA_TIER, {}).get("effects", []),
    f"TIER_EFFECTS[{NOVA_TIER}] = {efek.get(NOVA_TIER)}")
cek(f"main.py sepakat: tier {GIANT_MIN} = raksasa",
    "giant" in efek.get(GIANT_MIN, {}).get("effects", []),
    f"TIER_EFFECTS[{GIANT_MIN}] = {efek.get(GIANT_MIN)}")

import tiktok_listener as tl

# --- Gift -> tier: NAMA dulu, harga cuma cadangan ---
#
# Bug yang terlihat di siaran: tier dihitung dari JUMLAH koin yang terus
# ditambah, jadi Doughnut (30) lalu Rose (1) = 31 koin = raksasa lagi.
# Sekarang tiap gift menentukan tiernya sendiri.
# Susunan yang digeser: Rose = sinematik (3), Rosa = nova, Doughnut =
# raksasa. Bouquet Flower tidak punya tier sendiri lagi -- ikut harganya.
cek("Rose = tier 3 (sinematik)", tl.tier_dari_gift("Rose", 1)[0] == 3)
cek(f"Rosa = tier {NOVA_TIER} (nova)", tl.tier_dari_gift("Rosa", 10)[0] == NOVA_TIER)
cek(f"Doughnut = tier {GIANT_MIN} (raksasa)",
    tl.tier_dari_gift("Doughnut", 30)[0] == GIANT_MIN)
cek(f"Bouquet Flower ikut harganya (30 koin) -> raksasa",
    tl.tier_dari_gift("Bouquet Flower", 30) == (GIANT_MIN, "koin"))
cek("tier 2 (cakram) tidak dipakai gift apa pun",
    2 not in set(tl.GIFT_TIER.values())
    and 2 not in {tl.tier_dari_koin(k) for k in range(0, 2000)})
cek("nama gift tidak peka huruf besar-kecil dan spasi",
    tl.tier_dari_gift("  rOsA  ", 10)[0] == NOVA_TIER)

# Gift tak dikenal jatuh ke harga SATUANNYA, bukan ke tier 1.
cek("tak dikenal 5 koin -> tier 3", tl.tier_dari_gift("Finger Heart", 5)[0] == 3)
cek("tak dikenal 20 koin -> tier 3", tl.tier_dari_gift("Perfume", 20)[0] == 3)
cek(f"tak dikenal 29.999 koin -> raksasa, bukan tier 1",
    tl.tier_dari_gift("Lion", 29999)[0] == GIANT_MIN)
cek("tak dikenal 0 koin -> tier 1", tl.tier_dari_gift("Gratis", 0)[0] == 1)
# Nova sengaja tidak punya ambang koin: dia cuma lewat Bouquet Flower.
cek("tidak ada harga yang jatuh ke nova",
    NOVA_TIER not in {tl.tier_dari_koin(k) for k in range(0, 2000)},
    "gift tak dikenal bisa jadi nova -- nova cuma untuk Rosa (dan Rose x10)")
# --- Combo: jumlah combo = jumlah spawn, Rose ditampung 10:1 ---
#
# Yang dijaga dua hal, dan yang kedua yang paling penting: penampungan cuma
# boleh terjadi di dalam SATU combo, dan tidak boleh ada jalan dari gift
# murah ke raksasa.
cek("Rose x3 = 3 spawn Rose", tl.rincian_gift("Rose", 3, 1) == [(3, 1)] * 3)
cek("Rose x10 = 1 nova (setara Rosa)", tl.rincian_gift("Rose", 10, 1) == [(NOVA_TIER, 10)])
cek("Rose x25 = 2 nova DULU, lalu 5 Rose",
    tl.rincian_gift("Rose", 25, 1) == [(NOVA_TIER, 10)] * 2 + [(3, 1)] * 5,
    f"dapat {tl.rincian_gift('Rose', 25, 1)}")
cek("Rosa x3 = 3 nova, tidak naik",
    tl.rincian_gift("Rosa", 3, 10) == [(NOVA_TIER, 10)] * 3)
cek(f"Doughnut x3 = 3 raksasa",
    tl.rincian_gift("Doughnut", 3, 30) == [(GIANT_MIN, 30)] * 3)
cek("gift tak dikenal x3 = 3 spawn di tier harganya, tanpa ditampung",
    tl.rincian_gift("Finger Heart", 30, 5) == [(3, 5)] * 30)
cek("gift gratis tidak memberi spawn apa pun", tl.rincian_gift("Kucing", 9, 0) == [])
cek("combo Rose sebesar apa pun tidak pernah sampai raksasa",
    max(t for t, _ in tl.rincian_gift("Rose", 10000, 1)) == NOVA_TIER,
    "Rose x10000 bisa naik melewati Rosa")

cek("ambang koin listener dan main.py sama",
    (tl.TIER2_KOIN, tl.TIER3_KOIN, tl.TIER5_KOIN)
    == (srv.TIER2_KOIN, srv.TIER3_KOIN, srv.TIER5_KOIN),
    f"listener {tl.TIER2_KOIN}/{tl.TIER3_KOIN}/{tl.TIER5_KOIN}, "
    f"main.py {srv.TIER2_KOIN}/{srv.TIER3_KOIN}/{srv.TIER5_KOIN}")
cek(f"tap memberi tier aura ({int(angka('AURA_VFX_TIER'))})",
    tl.LIKE_TIER == int(angka("AURA_VFX_TIER")),
    f"LIKE_TIER {tl.LIKE_TIER}")
cek(f"tap (tier {tl.LIKE_TIER}) tidak bisa sampai ke nova",
    tl.LIKE_TIER < NOVA_TIER,
    "nova dan raksasa cuma bisa dibeli")


print("\n8. Sorotan tidak boleh bertumpuk")
#
# Kasus yang dulu bocor: raksasa disorot, tier yang lebih murah menunggu
# jedanya sendiri -- lalu masuk tepat saat adegan raksasa belum selesai. Kameranya direbut di tengah jalan dan salah satu dari
# keduanya kehilangan sorotannya, tanpa error apa pun.
#
# Yang menjaganya sekarang SPOTLIGHT_NAPAS_S di _ambil_entri.
srv.queue.clear()
srv.last_spotlight_at = None
srv.last_spotlight_lama_s = 0.0
srv.last_spotlight_tier = None

for nama, t in (("raksasa", 5), ("aura", 3), ("gratisan", 1)):
    srv.push(srv.PushRequest(username=nama, tier=t, koin=t * 10))

cek("yang bayar paling dulu disajikan duluan",
    (srv._ambil_entri() or {}).get("username") == "raksasa")
cek("tier 3 ditahan, yang gratisan yang jalan",
    (srv._ambil_entri() or {}).get("username") == "gratisan",
    "tier 3 keluar selagi raksasa masih disorot")

# Jeda yang BERLAKU: yang lebih lama antara jeda tier 2 dan "sorotan
# raksasa habis + napas". Dihitung, bukan ditulis: mana dari keduanya yang
# menang berubah tiap kali angka di .env digeser, dan tes yang menebak
# salah satunya akan gagal karena setelan -- bukan karena bug.
lama_t4 = srv.SPOTLIGHT_MS_T5 / 1000
jeda_berlaku = max(srv._jeda_sorotan(3), lama_t4 + srv.SPOTLIGHT_NAPAS_S)

cek(f"jeda yang berlaku menutupi seluruh sorotan raksasa "
    f"({jeda_berlaku:.1f}s >= {lama_t4:.1f}+{srv.SPOTLIGHT_NAPAS_S:.1f}s)",
    jeda_berlaku >= lama_t4 + srv.SPOTLIGHT_NAPAS_S - 1e-9)

# Sedetik sebelum jeda itu lewat: masih ditahan.
srv.last_spotlight_at -= jeda_berlaku - 1.0
cek("sebelum jedanya lewat, tier 3 masih ditahan",
    srv._ambil_entri() is None,
    "tier 3 masuk selagi sorotan raksasa belum tuntas")

srv.last_spotlight_at -= 1.1
cek("sesudah jedanya lewat, tier 3 baru disorot",
    (srv._ambil_entri() or {}).get("username") == "aura")

srv.queue.clear()
srv.last_spotlight_at = None
srv.last_spotlight_lama_s = 0.0
srv.last_spotlight_tier = None

# --- dua gift orang yang sama TIDAK digabung jadi satu ---
#
# Separuh kedua bug "Doughnut lalu Rose jadi raksasa lagi": main.py dulu
# melebur kiriman kedua ke entri yang sudah menunggu dengan tier TERTINGGI.
# Rose-nya hilang ke dalam raksasa dan tidak pernah tampil.
srv.push(srv.PushRequest(username="sama", tier=5, koin=30, tiktokUser="x"))
srv.push(srv.PushRequest(username="sama", tier=2, koin=1, tiktokUser="x"))
cek("Doughnut lalu Rose untuk nama yang sama = DUA entri, berurutan",
    [(e["username"], e["tier"]) for e in srv.queue] == [("sama", 5), ("sama", 2)],
    f"isi antrian: {[(e['username'], e['tier']) for e in srv.queue]}")

srv.queue.clear()
srv.last_spotlight_at = None
srv.last_spotlight_lama_s = 0.0
srv.last_spotlight_tier = None

# --- tier tinggi menyalip tier rendah yang masih menunggu ---
#
# Rose1-3 sudah/sedang tampil (sudah keluar antrian), Rose4-10 menunggu,
# lalu Rosa dan Doughnut datang. Doughnut tidak boleh menunggu tujuh Rose,
# dan sesama tier tetap urut kirim.
for i in range(4, 11):
    srv.push(srv.PushRequest(username=f"rose{i}", tier=3, koin=1))
srv.push(srv.PushRequest(username="gratisan", tier=1, koin=0))
srv.push(srv.PushRequest(username="rosa", tier=4, koin=1))
srv.push(srv.PushRequest(username="donat1", tier=5, koin=30))
srv.push(srv.PushRequest(username="rose11", tier=3, koin=1))
srv.push(srv.PushRequest(username="donat2", tier=5, koin=30))
_urut = [e["username"] for e in srv.queue]
_harap = (["donat1", "donat2", "rosa"] + [f"rose{i}" for i in range(4, 12)]
          + ["gratisan"])
cek("tier tinggi menyalip, sesama tier urut kirim, gratisan paling belakang",
    _urut == _harap, f"isi antrian: {_urut}")

srv.queue.clear()
srv.last_spotlight_at = None
srv.last_spotlight_lama_s = 0.0
srv.last_spotlight_tier = None

# --- jeda nova cuma berlaku antar nova ---
#
# Rose baru mulai, nova menunggu di depan. Nova cukup menunggu Rose habis
# + napas, bukan 17 detik dari mulainya Rose. Nova kedua tetap kena jeda
# nova penuh.
srv.push(srv.PushRequest(username="rose", tier=3, koin=1))
cek("Rose disajikan", (srv._ambil_entri() or {}).get("username") == "rose")
srv.push(srv.PushRequest(username="nova1", tier=4, koin=1))
srv.push(srv.PushRequest(username="nova2", tier=4, koin=1))
_rose_s = srv.SPOTLIGHT_MS_T3 / 1000 + srv.SPOTLIGHT_NAPAS_S
srv.last_spotlight_at -= _rose_s - 0.1
cek("nova sebelum Rose habis + napas: masih ditahan", srv._ambil_entri() is None)
srv.last_spotlight_at -= 0.2
cek(f"nova sesudah Rose: cukup {_rose_s:.1f}s, bukan jeda nova "
    f"{srv.SPOTLIGHT_GAP_T4_S:.0f}s",
    (srv._ambil_entri() or {}).get("username") == "nova1")
_nova_s = max(srv.SPOTLIGHT_GAP_T4_S,
              srv.SPOTLIGHT_MS_T4 / 1000 + srv.SPOTLIGHT_NAPAS_S)
srv.last_spotlight_at -= _nova_s - 0.1
cek("nova sesudah nova: jeda nova penuh tetap berlaku",
    srv._ambil_entri() is None)
srv.last_spotlight_at -= 0.2
cek("nova kedua keluar sesudah jeda nova",
    (srv._ambil_entri() or {}).get("username") == "nova2")

srv.queue.clear()
srv.last_spotlight_at = None
srv.last_spotlight_lama_s = 0.0
srv.last_spotlight_tier = None


print("\n9. TierNova: jadwal fase dan palet")
#
# Yang diuji fungsi MURNI modulnya -- Total dan Jadwal, yang menentukan
# kapan tiap fase mulai. Bagian yang menyentuh Roblox (tween, partikel,
# Lighting) tidak bisa jalan di sini, tapi kesalahan yang paling mahal
# justru di angka-angka ini:
#
#   1. modul dan server tidak sepakat berapa lama adegannya -> server
#      menahan papan aura selama 10 detik sementara adegannya 12, dan
#      papannya muncul di atas avatar yang masih melayang
#   2. `mendarat` bergeser -> bunyi jatuhnya terdengar saat dia masih di
#      udara, atau sesudah dia sudah lama menyentuh tanah
#
# `game` nil di Lua biasa, jadi modulnya dimuat tanpa service apa pun.
TN = lua.execute(re.sub(r"(\S+) \+= (\S+)", r"\1 = \1 + \2",
                        io.open("src/ReplicatedStorage/TierNova.luau", encoding="utf-8").read()))

NC = g.NOVA.CONFIG
jadwal = TN.Jadwal(NC)
total  = TN.Total(NC)

cek(f"lama adegan = jumlah fasenya ({total:.1f}s)",
    abs(total - (NC.charge + NC.ascend + NC.freeze + NC.slam + NC.impact)) < 1e-9,
    f"Total {total}")

# Fase-fasenya harus BERURUTAN dan tidak ada yang nol. Fase nol tidak
# memunculkan error -- yang terjadi cuma satu bagian cerita yang
# dilewati tanpa ada yang tahu kenapa.
urut = [("charge", jadwal.charge), ("ascend", jadwal.ascend),
        ("freeze", jadwal.freeze), ("slam", jadwal.slam),
        ("mendarat", jadwal.mendarat), ("selesai", jadwal.selesai)]
cek("jadwal fasenya naik terus, tidak ada yang mundur atau kembar",
    all(urut[i][1] < urut[i + 1][1] for i in range(len(urut) - 1)),
    ", ".join(f"{n}={v:.2f}" for n, v in urut))

for nama in ("charge", "ascend", "freeze", "slam", "impact"):
    cek(f"fase {nama} punya durasi", NC[nama] > 0,
        f"{nama} = {NC[nama]} -- fase nol dilewati tanpa jejak")

# Bantingannya harus yang TERPENDEK. Itu bukan detail: empat setengah
# detik naik pelan lalu turun dalam tiga persepuluh detik -- selisih itu
# yang membuat jatuhnya terbaca sebagai berat. Slam yang selama charge
# terbaca sebagai turun pelan, bukan membanting.
cek("banting = fase terpendek",
    NC.slam == min(NC.charge, NC.ascend, NC.freeze, NC.slam, NC.impact),
    f"slam {NC.slam}, terpendek {min(NC.charge, NC.ascend, NC.freeze, NC.slam, NC.impact)}")

# Sesudah membanting, harus ada waktu untuk ledakannya. Ini yang
# membedakan "dia menghantam tanah" dari "dia menghantam tanah LALU
# sesuatu terjadi".
cek(f"ada ledakan sesudah mendarat ({NC.impact:.1f}s)",
    jadwal.selesai - jadwal.mendarat >= 1.0,
    f"cuma {jadwal.selesai - jadwal.mendarat:.2f}s sesudah mendarat")

# Naiknya harus BERTAHAP: ascend lebih tinggi dari charge. Kalau
# dibalik, dia naik lalu turun lalu membanting -- dan yang terlihat cuma
# kebingungan.
cek(f"ascend naik lebih tinggi dari charge "
    f"({NC.naikAscend} > {NC.naikCharge})",
    NC.naikAscend > NC.naikCharge)

# --- TIGA PALET ---
palet = g.NOVA.PALET
n_palet = len(palet)
cek(f"ada {n_palet} palet untuk diundi (minimal 3)", n_palet >= 3,
    f"cuma {n_palet} -- dua orang yang sama-sama kirim 10 koin akan "
    "sering tampil sama persis")

nama_palet = [palet[i].nama for i in range(1, n_palet + 1)]
cek("tiap palet punya nama, dan namanya tidak kembar",
    all(nama_palet) and len(set(nama_palet)) == n_palet,
    f"nama: {nama_palet}")

# Lima warna per palet: modulnya membaca warna(1)..warna(5) untuk orb,
# rune, shell, shockwave, dan kristal. Palet yang lebih pendek tetap
# jalan (indeksnya melingkar), tapi dua peran yang berbeda akan memakai
# warna yang sama -- dan yang hilang justru bedanya.
for i in range(1, n_palet + 1):
    w = palet[i].warna
    cek(f"palet '{palet[i].nama}' punya 5 warna", len(w) == 5,
        f"{len(w)} warna")
    sah = all(len(w[k]) == 3 and all(0 <= w[k][c] <= 255 for c in range(1, 4))
              for k in range(1, len(w) + 1))
    cek(f"palet '{palet[i].nama}' isinya RGB 0-255", sah)

# Paletnya harus benar-benar BERBEDA satu sama lain. Tiga palet yang
# warnanya berdekatan memberi tiga undian yang di layar terbaca sebagai
# satu -- dan seluruh alasan mengundinya hilang.
def rata(ip):
    w = palet[ip].warna
    return tuple(sum(w[k][c] for k in range(1, 6)) / 5 for c in (1, 2, 3))


jarak_terdekat = min(
    sum(abs(a - b) for a, b in zip(rata(x), rata(y)))
    for x in range(1, n_palet + 1) for y in range(x + 1, n_palet + 1))
cek(f"palet-paletnya benar-benar beda warna (jarak terdekat {jarak_terdekat:.0f})",
    jarak_terdekat >= 60,
    "dua palet yang berdekatan terbaca sebagai satu di layar -- "
    "seluruh alasan mengundinya hilang")


print(f"\n10. Adegan nova: jadwalnya muat di sorotan "
      f"{srv.SPOTLIGHT_MS_T4 / 1000:.0f} detik")
#
# Adegannya berurutan -- tunggu aset, lima fase nova, lalu menari -- dan
# tiap bagian punya angkanya sendiri di tempat yang berbeda (NOVA.CONFIG,
# NOVA.TARI, SPAWN_SIAP_MAKS, KAMERA_TIER, SPOTLIGHT_MS_TIER3 di .env).
# Satu angka yang digeser tanpa yang lain tidak memunculkan error apa
# pun: yang terlihat cuma ledakan yang terpotong kamera pergi, atau papan
# aura yang tidak pernah muncul sama sekali.
N = g.NOVA
siap_maks = angka("SPAWN_SIAP_MAKS")
selesai_nova = siap_maks + total
sorotan_t3 = srv.SPOTLIGHT_MS_T4 / 1000

cek(f"nova + menari {N.TARI:.1f}s muat di sorotan "
    f"({selesai_nova:.2f}+{N.TARI:.1f} <= {sorotan_t3:.1f}s)",
    selesai_nova + N.TARI <= sorotan_t3 + 1e-9,
    "kamera pergi sebelum tariannya selesai -- naikkan SPOTLIGHT_MS_TIER4 "
    "atau pendekkan fase-fase di NOVA.CONFIG")

# Papan auranya TIDAK BOLEH dikirim sebelum adegannya selesai, dan ini
# syarat keras, bukan selera: selama nova, client menyembunyikan avatar
# aslinya beserta setiap BillboardGui yang menempel padanya
# (KELAS_MATIKAN). Papan yang dikirim lebih cepat dibuat, lalu ikut
# dimatikan -- dan yang terlihat di layar cuma papan yang tidak pernah
# muncul.
#
# Dibandingkan dengan selesai_nova, BUKAN dengan `total`: adegannya baru
# mulai sesudah client selesai menunggu aset avatarnya, jadi hitungan yang
# lupa SPAWN_SIAP_MAKS meleset setengah detik -- dan setengah detik itu
# persis lebar lubangnya.
aura_mulai = g.kameraTier(NOVA_TIER).auraMulai or 0
cek(f"papan aura menunggu adegannya selesai "
    f"({selesai_nova:.2f} <= auraMulai {aura_mulai:.2f})",
    selesai_nova <= aura_mulai + 1e-9,
    "papannya dikirim selagi avatar aslinya masih disembunyikan client "
    "-- dia dibuat lalu langsung ikut dimatikan, dan tidak pernah "
    "terlihat sama sekali")

cek("bunyi kedatangan ditunda sampai dia membanting diri",
    g.kameraTier(NOVA_TIER).bunyiSaatNova is True,
    "desis jatuhnya terdengar selagi dia masih mengumpulkan tenaga")

# Panggung beku menutupi SELURUH sorotan plus ekornya. Kalau bekunya
# lebih pendek, avatar gratisan muncul di detik-detik terakhir ledakan.
beku_maks = angka("BEKU_MAKS")
beku_ekor = angka("BEKU_EKOR")
cek(f"batas beku memuat sorotan penuh "
    f"({sorotan_t3:.1f}+{beku_ekor:.1f} <= BEKU_MAKS {beku_maks:.0f})",
    sorotan_t3 + beku_ekor <= beku_maks,
    "BEKU_MAKS memotong bekunya di tengah adegan, dan kedatangan "
    "gratisan mulai muncul lagi selagi novanya masih jalan")

# FOV: menyempit waktu mengisi tenaga dan waktu membanting, MELEBAR
# waktu meledak. Tandanya yang penting -- kalau ketiganya menyempit,
# ledakannya kehilangan hentakannya.
cek("FOV menyempit saat charge dan slam, melebar saat impact",
    NC.fovCharge < 0 and NC.fovSlam < 0 and NC.fovImpact > 0,
    f"charge {NC.fovCharge}, slam {NC.fovSlam}, impact {NC.fovImpact}")
cek("bantingan menyempitkan FOV lebih tajam daripada charge",
    NC.fovSlam < NC.fovCharge,
    f"slam {NC.fovSlam} tidak lebih sempit dari charge {NC.fovCharge}")
cek("geseran FOV tidak liar (semuanya di bawah 45 derajat)",
    all(abs(v) < 45 for v in (NC.fovCharge, NC.fovSlam, NC.fovImpact)),
    f"{NC.fovCharge}/{NC.fovSlam}/{NC.fovImpact}")

# Letterbox dua bilah: masing-masing tidak boleh lebih dari seperempat
# layar, kalau tidak yang tersisa cuma celah sempit di tengah.
cek(f"letterbox tidak memakan layar ({NC.letterbox:.2f} x2 = "
    f"{NC.letterbox * 2:.0%})",
    0 <= NC.letterbox <= 0.25,
    f"letterbox {NC.letterbox} -- dua bilah sebesar ini menyisakan "
    "celah sempit di tengah")

print("\n11. Jalur kamera nova: empat bidikan, dan tidak satu pun menembus badan")
#
# Angka-angkanya tinggal di NOVA.KAMERA, dan tiga di antaranya BOHONG
# kalau salah tanda atau salah besaran -- tanpa satu pun error:
#
#   1. naikPutaran bukan bilangan bulat -> orbitnya berakhir di sudut
#      yang bukan depan, dan bidikan berikutnya (di depan wajahnya)
#      berangkat dengan satu loncatan.
#   2. atasNaik di bawah puncaknya -> "kamera di atas" bohong. Di frame
#      pertama dia jatuh, dia justru berada DI ATAS lensa.
#   3. naikCepat terlalu kecil -> orbitnya sampai ke sisi belakang
#      selagi kameranya masih setinggi kepala, dan dia menembus badan
#      orang yang sedang menari.
#
# Ketiganya sudah pernah salah di angka yang pertama kali ditulis.
KAM = g.NOVA.KAMERA

cek("jalur kamera nova punya semua angkanya",
    None not in (KAM.naikRadius, KAM.naikBawah, KAM.naikAtas,
                 KAM.naikPutaran, KAM.naikCepat, KAM.diamRadius,
                 KAM.atasRadius, KAM.atasNaik, KAM.lebarRadius,
                 KAM.lebarNaik, KAM.lepas))

# --- 1. orbit pulang ke depan ---
cek(f"orbit naik bilangan bulat ({KAM.naikPutaran})",
    abs(KAM.naikPutaran - round(KAM.naikPutaran)) < 1e-9
    and KAM.naikPutaran >= 1,
    "orbit yang tidak bulat berakhir di sudut yang bukan depan, dan "
    "bidikan berikutnya berangkat dengan loncatan")

# --- 2. kamera fase jatuh benar-benar DI ATAS dia ---
cek(f"kamera jatuh ada di atas puncaknya "
    f"({KAM.atasNaik} > naikAscend {NC.naikAscend})",
    KAM.atasNaik > NC.naikAscend,
    f"kamera {KAM.atasNaik} stud, dia {NC.naikAscend} stud -- di frame "
    "pertama dia jatuh, dia berada DI ATAS lensa dan yang terlihat cuma "
    "dia melintas turun melewati kamera")

# Dan menunduknya masuk akal di kedua ujung: hampir sejajar kepalanya
# waktu mulai, jelas menunduk waktu dia menghantam tanah. Lurus ke bawah
# (mendekati 90) tidak punya cakrawala dan terbaca sebagai peta.
tunduk_awal = _m.degrees(_m.atan2(KAM.atasNaik - NC.naikAscend, KAM.atasRadius))
tunduk_akhir = _m.degrees(_m.atan2(KAM.atasNaik, KAM.atasRadius))
cek(f"menunduknya bercerita, bukan lurus ke bawah "
    f"({tunduk_awal:.0f} -> {tunduk_akhir:.0f} derajat)",
    0 < tunduk_awal < 45 and 45 < tunduk_akhir < 80,
    f"awal {tunduk_awal:.0f}, akhir {tunduk_akhir:.0f} -- di atas 80 "
    "derajat frame-nya kehilangan cakrawala")

# --- 3. orbit tidak menembus barisan ---
#
# Yang dihitung persis apa yang dihitung kameraNova: posisi kamera di
# tiap titik orbitnya, relatif terhadap titik berdiri avatar nova. Dan
# avatar nova SELALU yang paling dekat kamera (barisan tumbuh ke arah
# -Z, lihat getPosition), jadi semua tetangganya ada di z positif
# relatif dia.
KEPALA = 8.0          # tinggi kepala avatar biasa, stud
LEBAR_BARIS = (int(angka("ROW_SIZE")) - 1) / 2 * angka("SPACING_X") + 3


def kamera_naik(u):
    """(x, y, z) kamera fase naik, relatif titik berdiri avatar nova."""
    a = 2 * _m.pi * u * KAM.naikPutaran
    r = KAM.naikRadius
    v = min(u * KAM.naikCepat, 1)
    tinggi = KAM.naikBawah + (KAM.naikAtas - KAM.naikBawah) * (v * v * (3 - 2 * v))
    return _m.sin(a) * r, tinggi, -_m.cos(a) * r


bahaya = []
for i in range(0, 201):
    u = i / 200
    x, y, z = kamera_naik(u)
    # z > 0 = di belakang dia = tempat barisan berdiri.
    if z > 0 and abs(x) < LEBAR_BARIS and y < KEPALA + 2:
        bahaya.append((u, x, y, z))

cek(f"orbit naik lewat DI ATAS barisan, bukan menembusnya "
    f"({len(bahaya)} titik berbahaya dari 201)",
    not bahaya,
    (f"contoh: u={bahaya[0][0]:.2f} kamera di x={bahaya[0][1]:.1f} "
     f"y={bahaya[0][2]:.1f} z={bahaya[0][3]:.1f} (kepala {KEPALA:.0f}) "
     "-- naikkan naikCepat atau naikAtas") if bahaya else "")

# Mulainya tetap RENDAH -- itu seluruh gunanya sudut ini. Kamera yang
# langsung naik ke 16 stud memandang orang setinggi 5 stud dari atas,
# dan yang dijual di fase ini justru dia menjulang.
cek(f"orbit BERANGKAT dari bawah ({KAM.naikBawah} stud)",
    KAM.naikBawah <= 4,
    f"naikBawah {KAM.naikBawah} -- sudah setinggi dada avatar biasa, "
    "sudut rendahnya hilang")
x0, y0, z0 = kamera_naik(0)
cek(f"orbit berangkat dari DEPAN (z={z0:.0f}, x={x0:.0f})",
    z0 < -1 and abs(x0) < 0.01,
    "kamera berangkat dari samping atau belakang -- adegan berbayar "
    "selalu dimulai dari depan")

# --- BUNYI ADEGAN ---
#
# Tiga hal yang bisa salah tanpa satu pun error, dan ketiganya berakhir
# sebagai "adegannya sunyi" atau "ada dengungan yang tidak mau berhenti":
#
#   1. isyarat menunjuk fase yang tidak ada -> tidak pernah dibunyikan
#   2. tidak ada yang looped di fase charge -> hening empat detik di
#      tengah fase yang paling panjang
#   3. `tunda` melewati lama fasenya -> isyaratnya jatuh sesudah
#      adegannya selesai dan Sound-nya sudah dihapus
SFX = g.NOVA.SFX
FASE_SAH = {"charge", "ascend", "freeze", "impact"}

isyarat = [SFX[i] for i in range(1, len(SFX) + 1)]
cek(f"ada isyarat bunyi untuk nova ({len(isyarat)} baris)", len(isyarat) >= 4,
    "adegan 10 detik tanpa bunyi apa pun")

for c in isyarat:
    cek(f"isyarat '{c.fase}' menunjuk fase yang ada",
        c.fase in FASE_SAH,
        f"fase {c.fase!r} tidak pernah dipanggil mainkanFase -- "
        f"isyaratnya tidak akan pernah dibunyikan")
    cek(f"isyarat '{c.fase}' punya id dan volume",
        bool(c.id) and c.id != "" and 0 < c.vol <= 1.5,
        f"id={c.id!r} vol={c.vol}")
    # Nada di luar rentang ini bukan lagi berkas yang sama yang digeser
    # -- dia jadi derau (terlalu rendah) atau cicitan (terlalu tinggi).
    cek(f"isyarat '{c.fase}' nadanya masuk akal ({c.nada})",
        0.15 <= c.nada <= 3.0, f"nada {c.nada}")

fase_ada = {c.fase for c in isyarat}
for f in ("charge", "ascend", "freeze", "impact"):
    cek(f"fase {f} kebagian bunyi", f in fase_ada,
        f"fase {f} berjalan tanpa suara apa pun")

# Fase charge yang paling panjang HARUS punya isyarat yang looped --
# berkas bawaan Roblox semuanya jauh lebih pendek dari empat detik.
charge = [c for c in isyarat if c.fase == "charge"]
cek("fase charge punya bunyi yang looped",
    any(c.ulang for c in charge),
    f"{len(charge)} isyarat charge, tidak satu pun Looped -- bunyinya "
    "habis di tengah fase dan sisanya hening")
cek("dengungan charge nadanya MELUNCUR, bukan diam",
    any(c.nadaAkhir and c.nadaAkhir != c.nada for c in charge),
    "nada yang diam tidak terbaca sebagai tenaga yang dikumpulkan")

# Ledakannya harus DILAPIS. Satu berkas bawaan Roblox tidak pernah
# terdengar seperti ledakan; yang berat saja terdengar seperti pintu.
dentum = [c for c in isyarat
          if c.fase == "impact" and (c.tunda or 0) == 0]
cek(f"dentuman ledakan dilapis ({len(dentum)} lapis di frame yang sama)",
    len(dentum) >= 2,
    "satu berkas saja tidak pernah terdengar seperti ledakan")

# Gempanya menyusul, TIDAK bertumpuk dengan dentumannya. Bertumpuk, yang
# kedua tidak pernah terdengar sama sekali.
gempa_sfx = [c for c in isyarat if c.fase == "impact" and (c.tunda or 0) > 0]
cek(f"gempa punya isyaratnya sendiri, menyusul dentuman "
    f"({len(gempa_sfx)} isyarat tertunda)",
    len(gempa_sfx) >= 1,
    "gempa tanpa bunyi sendiri -- 80 avatar tersapu tanpa terdengar")
cek("isyarat tertunda tidak melewati lama fasenya",
    all((c.tunda or 0) < NC.impact for c in isyarat if c.fase == "impact"),
    f"ada tunda >= {NC.impact} -- jatuh sesudah adegannya selesai dan "
    "Sound-nya sudah dihapus")


# --- gempa: barisan tersapu, novanya sendiri tidak ---
print("\n12. Gempa: barisan tersapu, avatar novanya sendiri selamat")
#
# Kalau nova tidak dikecualikan, reset yang dipicu hantamannya SENDIRI
# menghapus avatarnya di tengah adegan -- dan AncestryChanged di client
# membatalkan seluruh novanya. Yang terlihat: efeknya berhenti separuh
# jalan tanpa satu pun error.
SLOT_NOVA = int(angka("SLOT_NOVA"))
SLOT_RAKSASA = int(angka("SLOT_RAKSASA"))
DELETE_AFTER = int(angka("DELETE_AFTER"))
SLOT_MENDARAT = int(angka("SLOT_NOVA_MENDARAT"))

cek(f"SLOT_NOVA ({SLOT_NOVA}) di luar jangkauan barisan (1..{DELETE_AFTER})",
    SLOT_NOVA > DELETE_AFTER,
    "nomor yang masih di dalam 1..slotCount akan disapu resetStage -- "
    "justru hal yang nomor ini ada untuk mencegahnya")

# Dan dia memegang nomor itu SEJAK LAHIR, bukan mulai dari ledakannya.
#
# Ini bug yang paling sering terlihat waktu `make mock`: selama sepuluh
# detik adegannya, kedatangan gratisan terus mengisi barisan. Barisan
# yang kebetulan penuh di detik-detik itu memanggil resetStage, dan
# waktu novanya masih memegang slot barisan biasa, reset itu menghapus
# avatarnya di tengah adegan. Yang tersisa di layar cuma kamera yang
# mengorbit panggung kosong -- tanpa satu pun baris di Output.
teks = "\n".join(src)
cek("avatar nova dibukukan di SLOT_NOVA sejak dia di-spawn",
    "local kunci = nova and SLOT_NOVA or slot" in teks
    and "avatars[kunci] = model" in teks,
    "dia masih memegang slot barisan selama adegannya -- resetStage "
    "yang jatuh di tengah sepuluh detik itu menghapusnya, dan yang "
    "terlihat cuma kamera yang bergerak di panggung kosong")

# Nomor yang dipegangnya sendiri berarti gempa tidak perlu lagi
# mengecualikan siapa pun. Parameter `kecuali` yang dulu ada justru bisa
# menunjuk slot milik ORANG LAIN kalau panggungnya sempat di-reset
# selagi adegannya jalan -- dan menyelamatkan orang yang salah.
cek("gempaBarisan tidak lagi punya pengecualian yang bisa salah tunjuk",
    "local function gempaBarisan(pusat)" in teks,
    "gempa masih menerima nomor slot dari luar")

# --- nova TINGGAL di panggung, sebagai orang pertama barisan baru ---
cek(f"nova mendarat di slot {SLOT_MENDARAT} (baris paling depan)",
    SLOT_MENDARAT == 1,
    "dia mendarat di tengah barisan, bukan di tempat yang baru saja "
    "dikosongkan hantamannya sendiri")

# Urutannya mengikat: gempa menyetel slotCount ke nol, novaKeBarisan
# menaruhnya kembali ke satu. Dibalik, slotCount kembali nol sesudah
# dia masuk -- dan kedatangan berikutnya berdiri menembus badannya.
i_gempa = teks.find("gempaBarisan(tujuan.Position)")
# Dicari MULAI dari panggilan gempanya: nama fungsinya juga muncul di
# barisnya sendiri waktu dia dideklarasikan, jauh di atas sini.
i_masuk = teks.find("novaKeBarisan(model, tujuan)", i_gempa)
cek("gempa dulu, baru novanya masuk barisan",
    0 < i_gempa < i_masuk,
    f"urutan di sumbernya: gempa@{i_gempa}, masuk@{i_masuk}")

# Dulu dia dihapus di akhir sorotannya, dan itu yang terlihat sebagai
# "disorot sebentar lalu hilang". Sekarang dia tinggal seperti
# kedatangan biasa; yang menghapusnya nanti resetStage atau nova
# berikutnya.
cek("tidak ada lagi buangNova terjadwal di akhir sorotan",
    "if avatars[SLOT_NOVA] == model then buangNova() end" not in teks,
    "avatarnya masih dihapus sendiri sesudah sorotannya habis")

# Titik mendaratnya cuma boleh punya SATU jawaban. Tiga tempat
# memakainya di detik yang sama -- bantingan salinan di client, pusat
# gempa, dan pemindahan avatar aslinya -- dan tiga jawaban untuk satu
# titik adalah tiga kesempatan untuk tidak sepakat.
cek("titik mendaratnya dihitung sekali dan dipakai bertiga",
    "local tujuan = finalCFrame(model, SLOT_NOVA_MENDARAT)" in teks
    and "tujuan = tujuan," in teks,
    "salah satu dari ketiganya menghitung titiknya sendiri")

klien_src = io.open("src/StarterPlayer/StarterPlayerScripts/KameraClientV2.client.luau", encoding="utf-8").read()
modul_src = io.open("src/ReplicatedStorage/TierNova.luau", encoding="utf-8").read()
cek("client meneruskan titik mendarat itu ke TierNova",
    "config.tujuan = d.tujuan" in klien_src,
    "modulnya tidak pernah tahu dia harus mendarat di tempat lain, jadi "
    "salinannya membanting diri di slot lamanya dan avatar aslinya "
    "muncul di slot 1 -- dua titik yang berbeda")
cek("TierNova memakainya di fase naik DAN fase banting",
    "CFrame = tujuanCF + Vector3.new(0, cfg.naikAscend, 0)" in modul_src
    and "tween(root, cfg.slam, { CFrame = tujuanCF }," in modul_src,
    "badannya melintas tapi tidak mendarat di sana, atau sebaliknya")
cek("kamera nova ikut menggeser titik lantainya",
    "tanahAkhir" in klien_src,
    "orbitnya tetap melingkari titik asal selagi badannya melintas -- "
    "ledakannya terjadi di luar layar")

# --- pesan nova yang kehilangan modelnya ---
#
# Argumen Instance di dalam pesan remote sampai sebagai NIL kalau
# modelnya belum selesai direplikasi ke client itu. Yang terlihat sama
# persis dengan bug resetStage di atas -- kamera bergerak, tidak ada
# yang melayang -- dan tidak ada satu pun error.
cek("server memberi tiap adegan nova nomornya sendiri",
    'model:SetAttribute("NovaId", novaIdBerikut)' in teks
    and "novaId = model:GetAttribute(\"NovaId\")," in teks,
    "client tidak punya cara lain menemukan modelnya kalau referensi "
    "Instance di pesannya sampai nil")
cek("client punya jalur cadangan lewat nomor itu",
    "local function novaCariModel(d)" in klien_src
    and "novaModel[id] = anak" in klien_src,
    "pesan yang modelnya nil langsung menyerah, dan avatarnya tinggal "
    "tersembunyi sampai jaring pengaman NOVA_TAHAN_MAKS_S membukanya")
cek(f"SLOT_NOVA ({SLOT_NOVA}) bukan SLOT_RAKSASA ({SLOT_RAKSASA})",
    SLOT_NOVA != SLOT_RAKSASA,
    "nova dan raksasa saling menimpa di tabel avatars: yang datang "
    "belakangan menghapus yang lain tanpa satu pun error")

# Gempanya dijadwalkan dari server, dan waktunya harus jatuh SESUDAH
# hantaman yang terlihat di layar -- tidak pernah sebelum. Kerumunan
# yang terlempar sebelum orangnya mendarat membalik sebab-akibatnya.
siap = angka("SPAWN_SIAP_MAKS")
gempa_di = siap + jadwal.mendarat
cek(f"gempa jatuh sesudah hantaman, tidak pernah sebelum "
    f"({gempa_di:.2f} >= {jadwal.mendarat:.2f})",
    gempa_di >= jadwal.mendarat - 1e-9,
    "kerumunan terlempar sebelum orangnya menyentuh tanah")
cek(f"telatnya tidak lebih dari {siap:.1f} detik",
    gempa_di - jadwal.mendarat <= siap + 1e-9)

# Dan seluruh lemparannya harus SELESAI sebelum sorotannya habis --
# kalau tidak, badan yang masih melayang dihapus mendadak di udara.
GEMPA_LAMA = angka("GEMPA_LAMA")
cek(f"lemparan gempa selesai di dalam sorotan "
    f"({gempa_di:.2f}+{GEMPA_LAMA:.1f} <= {sorotan_t3:.1f}s)",
    gempa_di + GEMPA_LAMA <= sorotan_t3 + 1e-9,
    "badan yang masih melayang dihapus mendadak di udara")


print("\n13. Karakter penonton tidak ikut terekam")
#
# Siaran ini direkam dengan MASUK ke room-nya, jadi avatar penontonnya
# sendiri ikut terekam kalau tidak disembunyikan. Yang diuji di sini
# BUKAN hasil visualnya (butuh Roblox), melainkan dua urutan di dalam
# sumbernya yang salahnya tidak memunculkan error apa pun.
klien = io.open("src/StarterPlayer/StarterPlayerScripts/KameraClientV2.client.luau", encoding="utf-8").read()

awal_f = klien.find("local function sembunyikanPenonton(")
cek("client punya sembunyikanPenonton", awal_f > 0,
    "karakter penonton tidak pernah disembunyikan -- dia berdiri di "
    "tengah kerumunan dan ikut terekam")

# Batas fungsinya: sampai `end` di kolom 0 berikutnya.
akhir_f = klien.find("\nend\n", awal_f)
badan_f = klien[awal_f:akhir_f] if awal_f > 0 else ""

cek("dipasang untuk karakter yang sudah ada DAN tiap respawn",
    "sembunyikanPenonton(pemain.Character)" in klien
    and "pemain.CharacterAdded:Connect(sembunyikanPenonton)" in klien,
    "yang dipasang cuma salah satu -- respawn memunculkannya kembali, "
    "atau karakter yang sudah terlanjur ada tidak pernah disembunyikan")

# BUG 1: part yang ditembuskan secara LOKAL tetap menjatuhkan bayangan.
# Bayangan orang yang tidak ada, bergerak di lantai panggung, lebih aneh
# daripada orangnya sendiri -- dan asalnya jauh lebih sulit ditebak.
cek("bayangannya ikut dimatikan",
    "CastShadow = false" in badan_f,
    "badannya tembus pandang tapi bayangannya masih jatuh di lantai")

# BUG 2: CanCollide dimatikan SEBELUM di-anchor berarti badannya jatuh
# menembus lantai sampai FallenPartsDestroyHeight, Roblox men-spawn-nya
# lagi, dan begitu terus. Gelung respawn yang tidak terlihat sama sekali
# karena badannya memang sudah tembus pandang.
i_anchor = badan_f.find("Anchored = true")
i_collide = badan_f.find("CanCollide = false")
cek("di-anchor DULU, baru CanCollide dimatikan",
    0 < i_anchor < i_collide,
    f"urutan di sumbernya: anchor@{i_anchor}, collide@{i_collide} -- "
    "dibalik, badannya jatuh menembus lantai lalu respawn terus-menerus")

# Dan nama bawaannya harus mati -- badan yang hilang tapi namanya masih
# melayang di udara justru lebih menarik perhatian.
cek("nama dan health bar bawaannya dimatikan",
    "DisplayDistanceType" in badan_f and "HealthDisplayType" in badan_f,
    "namanya masih melayang di panggung tanpa badan")

# Saklarnya harus sampai ke client, dan client harus punya cadangan
# kalau V2Config gagal ditarik.
cek("saklarnya dikirim server ke client",
    "sembunyiPenonton = SEMBUNYI_PENONTON" in "\n".join(src),
    "client tidak pernah menerima saklarnya")
cek("client punya nilai cadangan kalau V2Config gagal",
    "sembunyiPenonton" in klien.split("local ok, hasil")[0],
    "V2Config yang gagal ditarik membuat CFG.sembunyiPenonton nil, dan "
    "avatarnya muncul lagi di siaran tanpa satu pun petunjuk kenapa")


print()
if gagal:
    print("GAGAL:", ", ".join(gagal))
    sys.exit(1)
print("Semua lolos.")
