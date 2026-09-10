# tt-rblx — komentar TikTok Live → avatar di Roblox Studio

Penonton mengetik username Roblox di komentar live, avatarnya berdiri di
panggung Roblox. Yang mengirim gift dapat perlakuan berbeda: makin besar
koinnya, makin menonjol tempatnya.

```
.
├── main.py            # server antrian: /api/push (isi) + /api/next (Studio ambil)
├── tiktok_listener.py # baca komentar & gift TikTok Live -> isi antrian
├── mock_comments.py   # simulasi komentar live, buat tes tanpa siaran
├── roblox_ssl.py      # cara memanggil API Roblox tanpa request menggantung
├── my_sscript_lua     # SKRIP ROBLOX STUDIO -- paste ke ServerScriptService
├── test_podium.py     # uji pembukuan slot podium (`make test-podium`)
├── Makefile           # semua perintah; `make` saja menampilkan daftarnya
├── requirements.txt
└── README.md
```

Tiga proses: **server antrian** (`make server`), **ngrok** (`make tunnel`),
**listener** (`make listener`). Roblox Studio menembak ngrok, bukan localhost —
Studio tidak bisa memanggil 127.0.0.1.

`my_sscript_lua` tidak dijalankan dari sini: isinya di-paste ke
ServerScriptService di Roblox Studio, dan `URL` di baris atasnya diarahkan ke
domain ngrok kamu.

## Alur antrian

Penonton mengetik username Roblox di komentar live → `tiktok_listener.py`
menyaringnya → `POST /api/push` → Roblox Studio mengambilnya lewat
`GET /api/next`.

### Persiapan

```bash
pip install -r requirements.txt
```

Isi `.env` (sudah ada di `.gitignore`, jangan di-commit):

```
EULERSTREAM_API_KEY=euler_...        # daftar gratis di https://www.eulerstream.com
PUSH_URL=http://127.0.0.1:8000/api/push
```

Tanpa `EULERSTREAM_API_KEY` koneksi masih bisa jalan, tapi gampang kena
rate-limit diam-diam justru saat live sedang ramai.

### Menjalankan

Tiga proses, tiga terminal:

```bash
python -m uvicorn main:app --port 8000            # 1. server antrian
ngrok http --url=<domain-kamu> 8000               # 2. tunnel buat Roblox Studio
python tiktok_listener.py <username_tiktok>       # 3. listener (tanpa @, akun harus live)
```

Uji tanpa perlu ada yang siaran:

```bash
python tiktok_listener.py --self-test "builderman" "halo bang" "@Roblox"
curl localhost:8000/api/peek
```

`--dry-run` memproses komentar sungguhan tapi tidak mengirim ke antrian.

### Kalau log-nya diam saja

Listener sengaja hanya bicara saat ada yang **lolos** saringan. Live yang ramai
obrolan tapi tidak ada yang mengetik username Roblox akan terlihat sama persis
dengan listener yang mati — dua-duanya diam. Untuk memastikan komentarnya
memang masuk:

```bash
python tiktok_listener.py <username_tiktok> --show-comments --dry-run
```

`--show-comments` mencetak setiap komentar yang datang beserta alasan kalau
dilewati. Selain itu ada baris `[detak]` tiap 30 detik yang melaporkan berapa
komentar sudah masuk — kalau angkanya naik, koneksinya sehat.

Pakai `--dry-run` kalau sedang menumpang live orang lain, supaya antrian
produksimu tidak ikut terisi.

> Jangan pakai `--reload` pada `main.py` saat live: antriannya cuma ada di
> memori, dan setiap file di folder ini disentuh, uvicorn restart dan antrian
> hilang.

### Mock: uji tanpa perlu siaran

`mock_comments.py` mengarang lalu lintas komentar yang mirip aslinya — campuran
username, obrolan biasa, salah ketik, dan orang yang sama nyepam berkali-kali.
Pipeline-nya **diimpor** dari `tiktok_listener.py`, bukan disalin, jadi apa pun
yang lolos di mock persis sama dengan yang bakal lolos saat live.

```bash
python -m uvicorn main:app --port 8000        # server antrian harus hidup
python mock_comments.py --count 25 --fast     # 25 komentar, tanpa jeda
python mock_comments.py                       # ngalir pelan, Ctrl+C buat berhenti
```

Di akhir dia menampilkan isi antrian, jadi kelihatan apa yang benar-benar
sampai ke Roblox Studio. `--seed 7` bikin urutannya bisa diulang persis;
`--dry-run` memproses semuanya tapi tidak mengisi antrian.

Cooldown 45 detik bikin sebagian besar komentar mock ditolak (penonton palsunya
cuma 8 orang). Kalau mau lihat antrian terisi cepat, kecilkan sementara:

```bash
USER_COOLDOWN_S=5 NAME_DEDUPE_S=8 python mock_comments.py --count 25 --fast
```

### Saringan komentar

Tiap komentar yang lolos berujung request ke Roblox, jadi urutannya sengaja
dari yang paling murah:

| Langkah | Aturan |
|---|---|
| Format | satu kata, 3–20 karakter, alfanumerik + underscore (`@` di depan ditoleransi) |
| Blacklist | `roblox_blacklist.txt`, satu nama per baris |
| Dedupe nama | username Roblox yang sama ditolak selama `NAME_DEDUPE_S` (default 60 detik) |
| Cooldown | satu penonton hanya boleh summon tiap `USER_COOLDOWN_S` (default 45 detik) |
| Verifikasi | username dicek ke Roblox, yang tidak ada dibuang (hasilnya di-cache) |
| Batas antrian | `main.py` menolak kalau antrian sudah `QUEUE_MAX` (default 30) |

Batas antrian itu bukan soal memori, tapi soal jarak waktu antara orang mengetik
dan avatarnya muncul. Studio mengambil satu nama per polling, jadi panjang
antrian = lama tunggu: 30 nama ≈ 30 detik. Tanpa batas, live ramai bikin
antrian menumpuk sampai ratusan dan penonton sudah pergi sebelum avatarnya
nongol. Saat penuh, yang dibuang adalah komentar yang **baru datang** — siapa
pun yang sudah antri dijamin kebagian.

Verifikasi itu yang menahan komentar obrolan biasa. Tanpa itu, tiap komentar
satu kata (`mantap`, `wkwk`) ikut masuk antrian sebagai "username".

**Batas yang tidak bisa dihilangkan:** sebagian kata obrolan ternyata memang
username Roblox yang terdaftar (`first` dan `wkwkwk` dua-duanya ada), jadi
sesekali tetap ada yang nyelip. Selama trigger-nya username polos, ini harganya.
Kalau nanti terlalu ganggu, ganti trigger jadi berawalan — misal `!rb <username>`
— di `parse_username()`.

Kalau Roblox tidak bisa dihubungi, verifikasi **meloloskan** namanya — antrian
lebih baik kemasukan satu nama meragukan daripada mati total saat Roblox ngadat.

Semua angka di atas bisa ditimpa lewat `.env`: `USER_COOLDOWN_S`,
`NAME_DEDUPE_S`, `VERIFY_ROBLOX=0`, `REQUIRE_SINGLE_WORD=0`, `CACHE_TTL_S`.

### Tier: gift bikin avatar beda

Tier ditentukan **harga gift dalam koin**, bukan nama gift. TikTok mengirim
harganya sendiri di tiap `GiftEvent` (`gift.diamond_count`), jadi tidak ada
gift yang "tidak dikenal": `rose` 1 koin → tier 2, `rosa` 10 koin → tier 3,
dan gift 1.000 koin yang dulu jatuh ke tier 1 sekarang naik ke tier tertinggi.
Ambangnya `TIER2_KOIN` (1), `TIER3_KOIN` (10), dan `TIER4_KOIN` (30) di `.env`.

> **Ada EMPAT tier sekarang, dan tabel di bawah menjelaskan yang v13.**
>
> Tabel serta penjelasan podium di bagian ini menggambarkan `my_sscript_lua`
> (v13), tempat pembeda tier-nya TEMPAT (podium). Pasangan yang aktif
> sekarang — `my_scrip_lua_v2` + `kamera_client_lua_v2` — memakai pembeda
> yang berbeda, dan tier 3 di sana **bukan** raksasa:
>
> | | Tier 1 | Tier 2 (≥1 koin) | Tier 3 (≥10 koin) | Tier 4 (≥30 koin) |
> |---|---|---|---|---|
> | Antrian | normal | potong ke depan | potong ke depan | potong ke depan |
> | Ukuran | 1,0× | 1,0× | 1,0× | **4,0× (raksasa)** |
> | Border | — | biru es | oranye bara | — |
> | Aura VFX di badan | — | — | **1 dari 3, diacak** | — (polos) |
> | Sorotan | — | 4 detik | 7 detik | 9 detik |
> | Busur kamera | — | ±16° | ±26° | ±20° |
> | Naik-turun kamera | — | 1,5 stud | 2,5 stud | **5 stud** |
> | Membekukan panggung | — | — | — | **ya** |
>
> Kameranya **selalu di depan** — tidak ada tier yang memutar ke samping
> badan, apalagi ke belakang. Gerakan adegannya cuma zoom masuk-keluar,
> sapuan kiri-kanan di dalam kerucut depan, dan naik-turun.
>
> Undian aura ≥900% milik penonton gratisan cuma mengganti **bunyi**
> mendaratnya, bukan memberi efek — kalau tidak, aura berhenti menjadi
> penanda tier 3. Rinciannya ada di docstring kepala `my_scrip_lua_v2`
> dan tabel `KAMERA_TIER` di file yang sama.

Tangganya bertambah **kategori**, bukan bertambah angka:

| | Tier 1 — komentar | Tier 2 — ≥1 koin | Tier 3 — ≥10 koin / 2.000 tap |
|---|---|---|---|
| Antrian | normal | potong ke depan | potong ke depan |
| Ukuran | 1,0× | 1,5× | 1,5× |
| Tempat | kerumunan | kerumunan | **podium sendiri di belakang** |
| Nama | warna per-username | emas | 👑 emas + papan di podium |
| Cahaya | — | aura berkilau + kolom cahaya kecil | **kolom cahaya besar dari podium** |
| Efek | — | — | confetti + kembang api + hentakan |
| Kamera | — | **sorotan 5 detik**, mengorbit + mendekat | sorotan 7 detik ke atas, mengorbit + mendekat |
| Reset panggung | ikut terhapus | ikut terhapus | **kebal** (di luar barisan) |

**Tier 3 tidak dibesarkan — yang naik adalah tempatnya.** Ini keputusan
desain, bukan kompromi. Membesarkan avatar mengubah massa (pangkat tiga dari
skalanya), tinggi pivot, jangkauan anggota badan, dan framing kamera
*sekaligus*; tiap kali salah satunya diperbaiki yang lain bergeser — kaki
tenggelam, kaki mengambang, badan memantul, tarian tersendat. Dengan podium,
ukuran avatar tidak pernah berubah, jadi tidak satu pun masalah itu bisa
muncul. Untuk siaran hasilnya juga lebih kuat: "naik podium" itu bahasa status
yang langsung dimengerti penonton, sementara "jadi besar" cuma terbaca sebagai
efek game.

**Satu koin sudah dapat kamera.** Tier 2 disorot 5 detik (`SPOTLIGHT_MS_TIER2`),
tier 3 mulai dari 7 detik dan bisa memanjang oleh koin. Panjang sorotan tier 2
sengaja **datar**: kalau ikut memanjang, orang yang menumpuk gift 1 koin bisa
menyamai lama sorotan tier 3 tanpa pernah naik podium, dan 10 koin kehilangan
alasannya. Yang membedakan tier 3 tetap dua hal sekaligus — podium, dan sorotan
yang bisa memanjang.

Jedanya juga dipisah: `SPOTLIGHT_GAP_TIER2_S` (7 detik) untuk tier 2,
`SPOTLIGHT_GAP_S` (10 detik) untuk tier 3. Tier 2 datang jauh lebih sering, dan
memakai jeda tier 3 untuknya berarti sebagian besar yang bayar 1 koin tidak
pernah kebagian kamera. Batas bawahnya bukan selera: sorotan **plus fade
keluar** (~0,6 detik) harus selesai sebelum jeda habis, kalau tidak Studio
membuang sorotan berikutnya lewat penjaga `spotlightBusy`. `main.py` mencetak
peringatan saat start kalau kombinasi setelanmu melanggar itu.

#### Kedatangan meteor

Kedatangan **gratis** yang paling sering dilihat penonton — gift datang
sesekali, komentar datang terus — jadi yang harus menarik justru yang tidak
dibayar. Avatarnya jatuh dari **55 studs** (dulu 12), makin cepat menjelang
lantai, dengan **ekor cahaya** di belakangnya; mendaratnya dua cincin beruntun
dan **sentakan kamera** singkat.

Menariknya sengaja lewat **gerakan**, bukan lewat emas dan cahaya. Kalau tier 1
dikasih kolom emas atau kembang api, tidak ada lagi yang tersisa untuk dibeli —
jadi ekor, tinggi jatuh, dan cincinnya sama untuk semua orang, dan yang ikut
naik oleh tier cuma kekuatan guncangannya.

| | |
|---|---|
| `METEOR_ENABLED` | `false` = kembali ke jatuh 12 studs seperti dulu |
| `METEOR_HEIGHT` | 55 — di luar layar, jadi dia masuk frame dari tepi atas dengan kecepatan penuh |
| `METEOR_TIME` | 0,7 detik, easing **Quart In** (makin cepat) |
| `METEOR_TRAIL_**` | ekor cahaya: hidup, lebar |
| `SHAKE_TIME` / `SHAKE_POWER` | 0,18 detik, 1,1 studs, meluruh ke nol |

Tiga jalur diacak (lurus, menyerong, berputar), tapi easing-nya **tidak** ikut
diacak: percepatan itu satu-satunya alasan pendaratannya terasa berat, dan
kalau sebagian kedatangan kehilangan itu, sebagian terasa seperti diturunkan
pakai tali.

Guncangannya mundur sendiri kalau ada sorotan jalan (`spotlightBusy`) — dua
penulis untuk satu `Camera.CFrame` berarti dua-duanya patah, dan yang mengalah
harus yang gratis. Tidak ada pemulihan posisi di akhir guncangan, dan itu
disengaja: kekuatannya sudah nol di frame terakhir, sedangkan menulis ulang
`CFrame` di sana justru bisa menyentak balik kamera yang sedang bergerak ke
pendatang berikutnya.

Ikut ketahuan waktu menulis ini: gaya masuk ketiga yang lama **tidak pernah
berputar**. `CFrame.Angles(0, math.rad(360), 0)` itu matriks identitas — sama
persis dengan tanpa putaran. Sekarang 150°.

Tier 1 masih **tanpa suara** (`LAND_SOUND_MIN_TIER = 3`): hentakan tiap
beberapa detik saat live ramai jadi berisik, bukan dramatis. Kalau mau dicoba,
set 1 dan turunkan `LAND_VOLUME` dulu.

#### Tap-tap layar: podium gratis

**2.000 tap = satu podium**, tanpa koin sama sekali (`LIKE_PODIUM` di `.env`).
Hitungannya per penonton, akumulatif, dan berulang: tiap kelipatan 2.000
tercapai dia dapat podium lagi, dan sisanya **tidak hangus** — 4.100 tap = dua
podium plus 100 tap yang jalan terus ke hitungan berikutnya.

Yang dipakai `event.count` (tap dari orang itu), **bukan** `event.total` (total
like ruangan) — kalau yang kedua, satu orang naik podium karena tap ribuan
penonton lain.

Dua urutan yang sama-sama jalan, persis seperti gift:

- **tap dulu, baru username** — haknya disimpan `LIKE_PODIUM_TTL_S` (90 detik),
  menunggu komentar berikutnya dari orang itu
- **username dulu, baru tap** — avatarnya sudah berdiri di kerumunan, jadi
  langsung didorong ulang sebagai tier 3 dan naik podium tanpa dia mengetik lagi

**Koinnya tidak ikut dipalsukan.** Jalur tap mendorong tier 3 lewat penanda
tersendiri, bukan dengan pura-pura dia mengirim 10 koin — papan namanya tetap
menampilkan koin yang benar-benar dia keluarkan (0 kalau memang cuma tap).
Kalau tap diterjemahkan jadi koin, papan berbohong ke penonton lain tentang
siapa yang sebenarnya membayar.

Kenapa 2.000 dan bukan 200: ini jalur gratis, jadi ongkosnya usaha. 2.000 tap
itu menit-menitan menahan jari. Gunanya bukan menyaingi gift, tapi memberi
penonton yang tidak mau bayar satu hal yang bisa dikejar — dan tap-tap itu yang
mendorong live-nya naik di beranda TikTok.

**Suaranya disusun jadi satu kalimat, bukan ditumpuk.** Tiga suara khusus
tier 3 dibunyikan berurutan, karena kalau bersamaan yang terdengar cuma satu
gumpalan ribut dan tidak satu pun terbaca sebagai apa:

| Waktu | Suara | Setelan |
|---|---|---|
| 0,00 s | hentakan mendarat (nada diturunkan ke 0,55) | `LAND_SOUND_ID` |
| 0,35 s | sorakan "wow" — reaksi, jadi **sesudah** hentakan | `WOW_SOUND_ID`, `WOW_DELAY` |
| lalu ×3 | kembang api, ikut tiap letusan | `FIREWORK_SOUND_ID` |

Nada kembang api diacak ±8% tiap letusan: tiga letusan dengan rekaman yang sama
persis terdengar seperti satu suara diulang, digeser sedikit terdengar seperti
tiga roket berbeda. Ketiga ID di-preload **satu per satu** saat Play, jadi kalau
ada yang salah Output langsung menyebut ID mana.

Yang terjadi saat gift `rosa` masuk:

1. podium emas **naik dari dalam tanah** (1,6 detik) selagi avatarnya disiapkan
2. avatarnya turun dan mendarat di atasnya, hentakan + confetti + kembang api
3. **kolom cahaya** memudar masuk dari podium ke langit
4. kamera mengorbit sambil mendekat selama 7 detik, lalu pulang ke kerumunan
5. dia berdiri di sana sampai tergantikan — reset panggung tidak menyentuhnya

Kalau lima podium sudah terisi lalu ada `rosa` lagi, yang **paling lama
tenggelam kembali ke tanah** dan tempatnya langsung ditempati yang baru.

#### Satu orang = satu podium

Penonton yang mengirim `rosa` berkali-kali **memakai ulang podiumnya sendiri**,
bukan mengambil slot baru. Podiumnya turun lalu naik lagi lengkap dengan
sorotan, jadi gift keduanya tetap terasa — yang tidak terjadi cuma penumpukan.

Tanpa ini, satu orang yang mengirim `rosa` lima kali memborong kelima podium,
semuanya bertuliskan nama yang sama, dan pembayar berikutnya tidak kebagian
tempat sama sekali. Orang bayar lalu tidak terjadi apa-apa itu kerusakan paling
mahal yang bisa dilakukan sistem gift.

Kunci pemiliknya **nama TikTok**, bukan username Roblox — satu orang yang
memanggil dua username berbeda tetap satu pemilik. Push manual lewat `/docs`
tidak punya nama TikTok, jadi username Roblox yang dipakai; kalau tidak, semua
push manual dianggap satu orang yang sama dan saling menimpa podium.

#### Combo: koinnya dijumlah, bukan bikin avatar kembar

TikTok mendorong orang menekan tombol gift berkali-kali, jadi combo bukan kasus
langka — itu cara mayoritas orang mengirim. Yang dilakukan combo: **koinnya
ditambahkan**, dan tier dihitung ulang dari total itu.

Artinya `rose` 1 koin dikirim sepuluh kali dalam satu jendela = 10 koin =
**podium**, sama persis dengan sekali `rosa`. Orang yang nyicil tidak lagi kalah
dari orang yang sekali kirim. Yang menahan angkanya membesar sepanjang siaran
itu jendela `GIFT_BOOST_TTL_S`: begitu lewat, hitungannya mulai dari nol lagi.

Yang combo **tidak** lakukan: menambah avatar. Rose x5 tidak men-spawn lima
avatar kembar. Alasannya tiga — `slotOf` di skrip Lua memetakan satu username ke
satu slot (kembarannya jadi yatim saat naik tier atau saat reset), lima klon
memakan lima dari `DELETE_AFTER` slot sehingga yang bayar justru mengusir
penonton lain sampai memicu reset, dan lima avatar identik berjejer terbaca
sebagai bug duplikat, bukan hadiah.

Yang terlihat dari besarnya kiriman:

| | Efeknya |
|---|---|
| **Papan nama (tier 2)** | tertulis `builderman  5 koin` |
| **Papan podium (tier 3)** | tertulis `builderman  10 koin` |
| **Sorotan** | 7 s → sampai 14 s (`KOIN_SPOT_PER`, dibatasi `KOIN_SPOT_MAX_MUL`) |
| **Kembang api** | 3 letusan → sampai 8 |

Yang paling bekerja dari semuanya justru **angka di papan**: efek yang lebih
ramai dinikmati si pengirim, tapi angka yang terbaca itu yang bikin penonton
lain ikut mengirim. Angka itu **koin, bukan jumlah gift** — `x5` rose (5 koin)
terbaca lebih besar daripada `x1` rosa (10 koin) padahal yang kedua bayar dua
kali lipat, dan koin satu-satunya angka yang adil dibandingkan antar-gift.

Batasnya bukan hiasan. `KOIN_SPOT_MAX_MUL` menjaga sorotan terpanjang tetap
lebih pendek dari `SPOTLIGHT_GAP_S` — kalau lebih panjang, sorotan berikutnya
mulai selagi yang sekarang masih jalan dan Studio membuangnya, jadi orang yang
membayar tidak dapat sorotan sama sekali. `main.py` mencetak peringatan saat
start kalau kombinasi setelanmu melanggar itu. `KOIN_SPOT_CAP` (500) membatasi
koin yang **diperhitungkan untuk sorotan** — angka koinnya sendiri tidak
dipangkas, jadi yang kirim 1.000 koin tetap tertulis 1.000 di papan.

Kiriman berikutnya dari orang yang sama untuk nama yang sama **digabung di
antrian**, bukan jadi entri kedua — dua entri untuk satu orang keluar terbalik
(yang terbaru duluan, karena tier 2 ke atas masuk lewat `appendleft`), jadi
penonton melihat angka besar dulu lalu angka kecil menggantikannya. Terbaca
seperti angkanya turun.

**Arah panggung** (sering salah dikira terbalik): kamera berdiri di sisi **Z
negatif** dan menghadap ke Z positif. Jadi Z makin negatif = makin dekat kamera
(depan), Z makin positif = makin jauh (belakang), dan **kanan layar = X
negatif**. Barisan kerumunan tumbuh ke arah kamera: baris pertama di `Z = 0`,
berikutnya −8, −16, … — jadi baris paling belakang selalu `Z = 0` berapa pun
`DELETE_AFTER`-nya.

#### Papan nama cuma di baris depan

`PLATE_FRONT_ROW_ONLY = true`: begitu ada orang mengisi **baris berikutnya**,
seluruh papan nama baris sebelumnya lepas sekaligus. Yang lepas cuma **papan
namanya** — avatarnya tetap berdiri, tetap menari, dan tetap dihitung sampai
reset panggung biasa. `DELETE_AFTER` tidak berubah (100).

Sebabnya kerumunan tumbuh ke arah kamera: baris yang lebih baru selalu berdiri
lebih dekat, jadi papan nama baris belakang menembus badan mereka dan saling
menumpuk sampai layar penuh tulisan yang tidak satu pun kebaca. Dengan aturan
ini yang terbaca selalu delapan nama paling baru.

**Podium tidak ikut aturan ini.** Nomor slotnya di luar barisan kerumunan
(≥ `GIANT_BASE`), dan pembersihan cuma menyapu nomor 1…`slotCount` — jadi nama
di atas kepala dan papan di badan podium bertahan sampai podiumnya sendiri
tenggelam.

Papan namanya **menyusut** dulu (`PLATE_FADE_OUT`, 0,25 detik) sebelum dibuang:
nama yang lenyap satu frame terbaca seperti kedip atau bug, sementara yang
menyusut terbaca sebagai "gilirannya sudah lewat" — gerakan yang sama persis
dengan waktu dia muncul, dibalik. Set `PLATE_FRONT_ROW_ONLY = false` untuk
kembali ke perilaku lama (semua nama tampil terus).

Setelan podium di skrip Lua:

| | |
|---|---|
| `PODIUM_ENABLED` | matikan untuk kembali ke barisan biasa |
| `PODIUM_HEIGHT` | tinggi permukaan podium dari lantai (9) |
| `PODIUM_RADIUS` | jari-jari alas (6) |
| `PODIUM_RISE` / `PODIUM_SINK` | lama naik / tenggelam |
| `PODIUM_COLOR` / `PODIUM_GLOW` | emas badan / emas tepi |
| `PODIUM_BEAM_HEIGHT` / `PODIUM_BEAM_ALPHA` | kolom cahaya |
| `GIANT_TIER_FROM` | tier berapa ke atas yang dapat podium (3) |
| `GIANT_MAX` | berapa podium sekaligus (5) |
| `BACK_GAP_ROWS` | jarak ke belakang dalam "kotak" (6 → `BACK_Z = 48`) |
| `BACK_SPACING_X` | jarak antar podium — **harus > 2 × `PODIUM_RADIUS`** |
| `SPOT_CAM_**` | jarak & tinggi kamera sorotan podium, dalam studs |
| `SPOT2_CAM_**` | idem, untuk sorotan tier 2 yang berdiri di lantai |
| `SPOT_CAM_BIAS` | seberapa menyerong kamera untuk yang berdiri di pinggir |

Tier 2 juga dapat kolom cahaya (`effects: ["sparkle", "beam"]`), tapi sengaja
lebih kecil di ketiga ukurannya — lebih pendek (55 vs 140), lebih tipis, lebih
samar. Kalau disamakan, tier 2 dan tier 3 tidak terbedakan dari jauh, dan itu
menghapus alasan orang membayar lebih. Pembeda utamanya tetap podium: kolom
tier 2 berdiri di lantai bersama kerumunan, kolom tier 3 berdiri di atas podium.
Setelannya `BEAM2_HEIGHT`, `BEAM2_RADIUS`, `BEAM2_ALPHA`, `BEAM2_COLOR`.

Podium diisi **dari tengah lalu melebar** (0, +1, −1, +2, −2, …), bukan dari
ujung kiri — kalau tidak, podium pertama berdiri sendirian di pinggir layar
sementara tengah panggung kosong. Barisannya lima (`BACK_ROW_SIZE`), jadi ada
satu titik tengah yang jelas dan dua sayap di tiap sisi.

**Kamera menyerong ke arah yang berlawanan dari yang disorot.** Karena
barisannya melebar dari tengah, podium sayap berdiri jauh di kanan atau kiri
panggung; kamera yang tetap lurus dari depan menaruhnya di pinggir layar dengan
separuh frame berisi lantai kosong. Jadi sorotan untuk podium **kanan** dimulai
dari sebelah **kiri** dan memandang menyerong ke kanan, dan sebaliknya — yang
disorot berada di tengah frame, dan sisa barisan berbaris di belakangnya jadi
latar. Yang di tengah tidak digeser sama sekali.

Besar geserannya sebanding dengan seberapa ke pinggir dia berdiri: ±`SPOT_CAM_BIAS`
(28°) di ujung, nol di tengah. Lebar barisannya dihitung dari setelan yang
berlaku (`BACK_ROW_SIZE` × `BACK_SPACING_X` untuk podium, `ROW_SIZE` × `SPACING_X`
untuk kerumunan), jadi mengubah jumlah kolom tidak membuat sudutnya salah.
Set `SPOT_CAM_BIAS = 0` kalau mau kamera selalu lurus dari depan seperti dulu.

Sorotan tier 2 memakai set angka sendiri (`SPOT2_CAM_**`): lebih dekat, lebih
rendah, busur lebih pendek. Orangnya berdiri di lantai, bukan di atas podium
setinggi 9 studs — angka podium terlalu jauh dan terlalu tinggi untuknya, dan
busur 80° dalam 5 detik terbaca seperti kamera panik, bukan kamera yang
memperkenalkan seseorang. Bidikannya juga tidak diturunkan 4 studs seperti
podium; di lantai itu bikin kamera membidik tanah dan kepalanya kepotong.

**Tinggi berdiri diukur, tidak ditebak.** `tinggiPivot()` membacanya dari rig:
`Humanoid.HipHeight + HumanoidRootPart.Size.Y/2`, **sesudah `ScaleTo` dan
sesudah `SETTLE_TIME`**, lalu mendudukkan telapak kakinya tepat di permukaan
tempatnya berdiri — lantai untuk kerumunan, permukaan podium untuk tier 3
(`lantaiSlot()`). Sengaja **bukan** `GetBoundingBox`: kotak pembungkus ikut
membungkus aksesori, jadi rambut panjang / sayap / ekor mengangkat avatarnya
sebanyak itu.

Angka tier ditentukan `tiktok_listener.py` (`tier_dari_koin()`), arti visualnya
ditentukan `main.py` (`TIER_EFFECTS`). Skrip Lua tidak menyimpan tabel apa pun
— dia cuma membaca field yang dikirim `/api/next`. Jadi menyetel ukuran atau
efek cukup lewat `.env` + restart server, tanpa paste ulang ke Studio.

**Dua urutan sama-sama jalan**, karena orang tidak konsisten:

- **gift dulu, baru username** — koinnya disimpan sampai `GIFT_BOOST_TTL_S`
  (default 90 detik), dipakai saat orang itu mengetik username
- **username dulu, baru gift** — avatarnya di-spawn LAGI sebagai avatar baru
  bertier lebih tinggi; yang lama dibiarkan berdiri sampai reset biasa. Gift
  jadi selalu menghasilkan sesuatu yang terlihat — pendaratan, efek, sorotan.
  Set `UPGRADE_IN_PLACE = true` di skrip Lua kalau mau perilaku lama (dinaikkan
  di tempat, tidak ada yang baru muncul).

Kembar di panggung karena itu normal, dan itu disengaja: rem terhadap spam ada
di sisi listener (`NAME_DEDUPE_S`), bukan di Studio.

Kirim `rose` lalu `rosa` menghasilkan tier 3 (11 koin), bukan turun ke 2 —
koin dijumlah, jadi totalnya tidak pernah bisa turun.

**Yang bayar menembus semua rem**: cooldown, dedupe, dan batas antrian tidak
berlaku untuk tier 2 ke atas. Ditolak karena "antrian penuh" setelah membayar
itu tidak bisa diterima.

**Sorotan tidak pernah bertabrakan.** Kalau banyak yang kirim gift sekaligus,
`main.py` menahan entri sorotan di antrian dan menyajikan entri biasa dulu,
sampai jedanya terlewat. Jedanya dihitung dari tier entri yang sedang **di
depan antrian**: `SPOTLIGHT_GAP_TIER2_S` (7 detik) kalau yang di depan tier 2,
`SPOTLIGHT_GAP_S` (10 detik) kalau tier 3. Entri yang bukan sorotan tidak
pernah ikut tertahan.

**Tier 2 tidak kebal reset** (`KEEP_TIER_FROM = 99`): seluruh barisan kerumunan
dikosongkan tiap reset, jadi tier 1 tidak pernah kehilangan slot ke penyintas
lama. Set `KEEP_TIER_FROM = 2` di skrip Lua kalau mau tier 2 kebal lagi.

Setelan tier di `.env`: `GIFT_BOOST_TTL_S`, `SPOTLIGHT_GAP_S`, `SPOTLIGHT_MS`,
`SPOTLIGHT_GAP_TIER2_S`, `SPOTLIGHT_MS_TIER2`, `LIKE_PODIUM`, `LIKE_LOG_EVERY`,
`LIKE_PODIUM_TTL_S`, `TIER2_SCALE`, `TIER3_SCALE`.

### Sisi Roblox Studio

Skrip lengkapnya ada di `my_sscript_lua` — copas ke **ServerScriptService**.


Yang perlu disetel di sana: `URL`, `DANCE_ID`, `FLOOR_Y` (permukaan lantai
panggungmu; default 0), dan setelan podium di atas.

Semua avatar `CanCollide = false` dan Humanoid-nya dipindah ke state `Physics`.
Mereka cuma pajangan: posisinya dipegang `BodyPosition`, jadi tabrakan dan mesin
keadaan Humanoid cuma jadi gaya liar yang bikin tarian bergetar.

`BodyPosition`/`BodyGyro` disetel **per massa** (`P = massa × 3000`,
`D = massa × 160`, sekitar 1,45× redaman kritis). Massanya dijumlah sendiri dari
`GetMass()` tiap part, bukan dibaca dari `AssemblyMass` — properti itu baru
terisi setelah fisika memproses satu langkah sesudah `Anchored` dilepas.

### Endpoint antrian (`main.py`)

| Endpoint | Balasan |
|---|---|
| `POST /api/push` | `{username}` → `{ok, queued, size}` |
| `GET /api/next` | `{username, displayName, size}` — mengambil satu dan menghapusnya |
| `GET /api/peek` | isi antrian tanpa menghapus (debug) |
| `DELETE /api/clear` | kosongkan antrian |


## Catatan teknis

**Kenapa ada `_NoALPNContext` di `roblox_ssl.py`.** Ini bukan hiasan — tanpa
itu `httpx` menggantung sampai timeout saat memanggil Roblox. Sudah
diverifikasi lewat raw socket TLS:

| ALPN yang ditawarkan | Hasil |
|---|---|
| `["http/1.1"]` (default httpx) | hang sampai timeout |
| `["h2", "http/1.1"]` (dipakai curl) | 200 OK |
| tidak menawarkan ALPN sama sekali | 200 OK |

Edge Roblox rupanya menggantungkan koneksi kalau ALPN menegosiasikan
`http/1.1` secara eksplisit. Masalahnya `httpcore` **selalu** memanggil
`set_alpn_protocols()` pada SSL context yang kita berikan, jadi `verify=<ctx>`
biasa tidak cukup — override-nya harus di level class. Efeknya request kita
jadi setara `urllib` (yang memang tidak mengirim ekstensi ALPN dan jalan
normal ke Roblox).

Diukur ulang 29 Agustus 2026 dari folder ini, `users.roblox.com`:

| | Hasil |
|---|---|
| `httpx.post(..., verify=_make_ssl_context())` | 200 OK, **0,41 detik** |
| `httpx.post(...)` polos | **ReadTimeout, 8,09 detik** |

Karena itu `roblox_ssl.py` berdiri sebagai file sendiri: `main.py` DAN
`tiktok_listener.py` dua-duanya memanggil Roblox, dan `main.py` sempat
memanggilnya tanpa konteks ini. Yang bikin tidak ketahuan berbulan-bulan:
ada `try/except` yang menjatuhkannya balik ke username mentah, jadi yang
terlihat cuma `displayName` yang "kebetulan" selalu sama dengan username.

---

## Coretan

Ditinggalkan apa adanya: username buat tes, dan asset id animasi.

armydad405 
benssky2
burungkakatua_13

Jamal Brazil Groove: 117119421748582Jamal Dance: 72213123467340

game:GetObjects("rbxassetid://96976207749910")[1].Parent = workspace


ngrok http --url=deluxe-sash-retired.ngrok-free.dev 8000

129577777879366 - green aura
12010147091 - red aura
10088609715 - rimuru aura