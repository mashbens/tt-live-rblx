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
├── src/               # SKRIP ROBLOX STUDIO -- foldernya meniru Explorer di Studio
│   ├── ServerScriptService/AvatarQueueV2.server.luau                 # Script
│   ├── StarterPlayer/StarterPlayerScripts/KameraClientV2.client.luau # LocalScript
│   └── ReplicatedStorage/TierNova.luau                               # ModuleScript
├── default.project.json # peta Rojo: src/ -> Studio
├── aftman.toml        # versi Rojo (dipasang lewat Aftman)
├── test_tier.py       # uji fungsi tier di AvatarQueueV2 (`make test-tier`)
├── test_sync.py       # uji penyamaan tarian di KameraClientV2 (`make test-sync`)
├── lint_lua.py        # cari nil global di ketiga file src/ (`make lint`)
├── Makefile           # semua perintah; `make` saja menampilkan daftarnya
├── requirements.txt
└── README.md
```

Tiga proses: **server antrian** (`make server`), **tunnel** (`make tunnel`),
**listener** (`make listener`). Roblox Studio menembak
`https://rblx.buanaglobalcipta.com`, bukan localhost — Studio tidak bisa
memanggil 127.0.0.1.

Skrip Studio di `src/` tidak di-paste lagi: `make rojo`, lalu di Studio
Plugins > Rojo > Connect -- tiap kali file di `src/` disimpan, Studio ikut
berubah. `URL` di atas `AvatarQueueV2` diarahkan ke `PUBLIC_URL` di Makefile.

### Tunnel (pengganti ngrok)

```
Roblox -> Cloudflare -> nginx (docker di VM)
       -> 172.17.0.1:9000 -> ssh -R (autossh) -> laptop 127.0.0.1:8000
```

- DNS: record A `rblx` di Cloudflare, proxied. Sertifikat pakai wildcard
  `*.buanaglobalcipta.com` yang sudah ada.
- VM: `/root/nignx/config/conf.d/rblx.conf` (nginx) dan
  `/etc/ssh/sshd_config.d/10-tt-rblx-tunnel.conf` (`GatewayPorts clientspecified`).
- Laptop: butuh `autossh`, SSH key yang terdaftar di VM (login tanpa password),
  dan baris `TUNNEL_SSH=user@ip-vm` di `.env`.
- `make status` bilang 502 = VM hidup, tapi `make tunnel` atau `make server`
  di laptop belum jalan.

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
make tunnel                                      # 2. tunnel SSH ke VM buat Roblox Studio
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

Tier ditentukan **nama gift**, dan **tiap gift = satu spawn** di tiernya
sendiri — tidak ada yang dijumlah:

| Tier | Gift | Yang didapat |
|---|---|---|
| 1 | komentar biasa | berdiri, menari |
| 2 | **Rose** | skip lane + cakram biru, sorotan 3 s |
| 3 | **Rosa** / 1.000 tap | AURA (VFX acak 1 dari 3) |
| 4 | **Bouquet Flower** | UPACARA (nova) |
| 5 | **Doughnut** | UKURAN (raksasa) |

Rose lagi = spawn Rose lagi. Bouquet lagi = nova lagi, **tidak** naik ke
raksasa. Dua gift sebelum dia ngetik username = dua spawn, berurutan, tidak ada
yang dilewati.

**Kenapa nama, bukan koin.** Dulu tier dihitung dari JUMLAH koin yang terus
ditambah selama `GIFT_BOOST_TTL_S`, dan jumlah itu tidak pernah turun:
Doughnut (30) lalu Rose (1) = 31 koin = **raksasa lagi**, padahal yang barusan
dikirim cuma Rose. Harga juga tidak bisa lagi jadi satu-satunya penentu:
Bouquet Flower dan Doughnut **sama-sama 30 koin**. Yang dilepas untuk ini,
sengaja: nyicil tidak dihitung lagi — Rose dikirim sepuluh kali terpisah =
sepuluh spawn Rose, bukan satu Rosa.

**Gift yang namanya tidak dikenal** jatuh ke harga satuannya, bukan ke tier 1:
1–9 koin = tier 2, 10–29 = tier 3, ≥30 = raksasa (`TIER2_KOIN`, `TIER3_KOIN`,
`TIER5_KOIN` di `.env`). Nova sengaja tidak punya ambang koin — cuma lewat
Bouquet Flower. Ejaan nama bisa ditimpa lewat
`GIFT_TIER=rose:2,rosa:3,bouquet flower:4,doughnut:5`; nama yang sebenarnya
dikirim TikTok selalu tercetak di log `[gift]`, jadi cocokkan dari situ.

> **Tabel serta penjelasan podium di bagian ini menggambarkan v13.**
>
> Bagian podium di bawah menggambarkan skrip v13 (sudah dihapus dari repo,
> masih ada di riwayat git), tempat
> pembeda tier-nya TEMPAT (podium). Pasangan yang aktif sekarang —
> `AvatarQueueV2` + `KameraClientV2` + ModuleScript
> `TierNova` (semuanya di `src/`) — memakai pembeda yang berbeda:
>
> | | Tier 1 | Tier 2 (Rose) | Tier 3 (Rosa / 1.000 tap) | Tier 4 (Bouquet Flower) | Tier 5 (Doughnut) |
> |---|---|---|---|---|---|
> | Antrian | normal | potong ke depan | potong ke depan | potong ke depan | potong ke depan |
> | Ukuran | 1,0× | 1,0× | 1,0× | 1,0× | **4,0× (raksasa)** |
> | Kedatangan | langsung berdiri | langsung berdiri | langsung berdiri | **adegan nova** (lihat bawah) | langsung berdiri |
> | Di kakinya | — | **cakram biru saja** | cakram + garis tepi biru | — | — |
> | Aura VFX di badan | — | — | **1 dari 3, diacak** | **1 dari 3, diacak** (menyala saat adegannya selesai) — (polos) |
> | Warna efek | — | — | — | **1 dari 3 palet, diacak** (prisma / inferno / glasir) | — |
> | Lantai aura | 0% (0–1000) | **900%** | **950%** | **999%** | **9.999–10.000%**, papannya jadi nama saja sesudah mendarat |
> | Sorotan | — | 3 detik | **10 detik** (adegan sinematik) | 15 detik (0,6 aset + 10,3 nova + 3 menari) | 7 detik |
> | Jeda sorotan | — | 3 s (praktisnya 4,5) | 12 s | 17 s | 11 s |
> | Kamera | — | **paling tenang**: ±10°, gundukan 0,8 stud | **sinematik**: sapuan kanan-kiri-kanan ±24°, dua gundukan naik-turun, dorongan zoom saat angka mendarat; letterbox + warna + kilatan, garis tepi berdenyut | **jalur 4 bidikan**: orbit rendah 360° → depan → atas → shot lebar | ±20°, naik-turun 5 stud |
> | Efek layar penuh | — | — | — | **letterbox, layar abu-abu, bloom, blur** | — |
> | Bunyi | aura saja | denting ringan | bass | **6 isyarat per fase** (lihat bawah) | hentakan berat + **bunyi mendarat sendiri** |
> | Membekukan panggung | — | — | — | **ya** | **ya** |
> | Dampak ke panggung | — | — | — | **menyapu SELURUH barisan** saat mendarat, lalu dia sendiri berdiri di slot 1 | **kamera panggung turun** selama dia berdiri |
>
> **Rose cuma cakram, tanpa garis tepi**, dan itu bukan cuma selera: Roblox
> cuma menggambar sekitar 31 Highlight sekaligus, dan Rose yang paling sering
> datang. Kalau dia ikut memakai jatah garis, border orang yang bayar Rosa
> dilepas duluan untuk memberi tempat ke dia. Cakram itu Part biasa, tidak
> punya jatah semacam itu (`BORDER_GARIS_MIN_TIER`).
>
> **Adegan nova tier 4** (Bouquet Flower, PRISMATIC STARFALL), urutannya:
>
> 1. client menunggu aset avatarnya (≤0,6 s)
> 2. **charge 4,0 s** — letterbox masuk, FOV menyempit 12°, badannya
>    melayang naik 14 stud. Enam orb mengorbit sambil menarik beam ke
>    dadanya, 32 rune berputar di lantai, partikel naik dari tanah.
>    **Kamera rendah memandang ke atas, mengorbit 360° sekali penuh**
> 3. **ascend 1,5 s** — naik ke **45 stud** (sembilan kali tinggi badan),
>    orb mengatup jadi mahkota di atas kepala, lingkaran rune melebar.
>    Selagi naik dia juga **melintas ke atas slot 1** — di situ dia akan
>    membanting diri
> 4. **freeze 1,0 s** — orb tersedot ke dada, kilatan membesar, layar jadi
>    abu-abu dan buram; rune hampir berhenti. **Kamera meluncur ke depan
>    wajahnya dan diam** — satu-satunya detik tenang di seluruh adegan
> 5. **slam 0,6 s** — banting ke tanah **di slot 1** dari 45 stud, FOV
>    menyempit 20°.
>    **Kamera meluncur ke atas kepalanya**, jadi dia jatuh menjauh dari
>    lensa
> 6. **impact 3,2 s** — shell 65 stud, tiga shockwave, pilar cahaya 300
>    stud, delapan petir, 20 kristal melayang lalu jatuh, aftershock kedua
>    di detik 1,4, warna pulih, letterbox keluar. **Kamera mundur ke shot
>    lebar.** Di detik yang sama **seluruh barisan tersapu** — lihat bawah
> 7. avatar aslinya muncul kembali **di slot 1**, aura VFX acaknya
>    menyala, dan dia **menari 3 detik sendirian** di panggung yang sudah
>    kosong — lalu dia **tinggal di sana**, sebagai orang pertama di
>    barisan yang baru. Yang komentar sesudahnya berdiri di sampingnya
>    (slot 2, 3, …), bukan menggantikannya
>
> **Bunyinya** (`NOVA.SFX` di server, dimainkan modulnya sendiri):
>
> | Fase | Bunyi | Nada |
> |---|---|---|
> | charge | `bass.wav`, **looped** | 0,50 → **1,15** (meluncur naik) |
> | ascend | `action_jump.mp3` | 0,65 |
> | freeze | `electronicpingshort.wav` | 0,35 (denting rendah menggantung) |
> | slam | `action_falling.mp3` (lewat `SFX_TIER[4]`) | 1,40 |
> | impact | `bass.wav` + `impact_water.mp3` **dilapis** | 0,30 / 0,45 |
> | gempa | `action_jump_land.mp3`, +0,3 s | 0,45 |
> | aftershock | `impact_water.mp3`, +1,4 s | 0,65 |
>
> Semuanya **bawaan Roblox** (`rbxasset://sounds/*`) — berkas itu ikut
> terpasang di tiap instalasi, jadi tidak ada kemungkinan "Asset is not
> approved for the requester" yang pernah membuat `swoosh.wav` gagal
> diam-diam di file ini. Harganya: pilihannya cuma enam berkas, jadi yang
> membedakan mereka **nada**, bukan berkasnya. Kalau nanti ada asset audio
> sendiri, yang diganti cuma `id`-nya.
>
> Dimainkan **dari dalam modulnya**, bukan dijadwalkan pemanggil: cuma
> modul yang tahu kapan tiap fase benar-benar mulai, dan bunyi yang
> dijadwalkan dari luar meleset sebanyak tunggu aset avatarnya.
>
> **GEMPA: barisan kembali ke slot 1.** Tepat saat dia menghantam tanah,
> semua yang sedang menari terlempar keluar dari titik hantam sambil
> berputar dan memudar, lalu dihapus — dan `slotCount` kembali nol, jadi
> kedatangan berikutnya mengisi dari slot 1 lagi. Yang lebih dekat ke
> titik hantam terlempar lebih jauh.
>
> Lemparannya **tween di server, bukan fisika**: delapan puluh avatar yang
> meragdoll berbarengan menjatuhkan FPS tepat di detik yang paling
> ditonton, dan fisika Roblox tidak deterministik antar client — dengan
> impuls, satu penonton melihat kerumunan terlempar ke kiri dan penonton
> lain ke kanan. Angkanya `GEMPA_LAMA`, `GEMPA_JAUH`, `GEMPA_NAIK`.
>
> Avatar novanya sendiri **tidak ikut tersapu**: dia memegang `SLOT_NOVA`
> (di luar jangkauan `1..slotCount`, seperti `SLOT_RAKSASA`) **sejak
> detik pertama adegannya**, bukan mulai dari hantamannya. Tempatnya di
> barisan tetap dipakai supaya tidak ada yang berdiri menembus badannya,
> tapi nomornya di luar jangkauan setiap gelung barisan.
>
> Itu menutup satu bug yang sering terlihat waktu `make mock`: selama
> sepuluh detik adegannya, kedatangan gratisan terus mengisi barisan, dan
> barisan yang kebetulan **penuh** di detik-detik itu memanggil
> `resetStage` — yang dulu menghapus avatar novanya di tengah adegan.
> `AncestryChanged` di client membatalkan seluruh novanya tanpa satu pun
> error, jadi yang terlihat cuma **kamera yang mengorbit panggung
> kosong**.
>
> Begitu barisannya tersapu dia **pindah ke slot 1** (`novaKeBarisan`) —
> nomor, badan, dan kunci posisinya sekaligus — dan sesudah itu dia
> avatar biasa: yang menghapusnya nanti sama dengan yang menghapus semua
> orang (panggung penuh, atau nova berikutnya). Titik mendaratnya dihitung
> **sekali** di server (`tujuan`) dan dipakai bertiga: pusat gempa,
> pemindahan avatar aslinya, dan bantingan salinan nova di client.
>
> **Kalau pesan novanya kehilangan modelnya.** Argumen `Instance` di dalam
> pesan remote sampai sebagai `nil` kalau modelnya belum selesai
> direplikasi ke client itu — dan gejalanya sama persis: kamera bergerak
> (pesan `fokus` tidak membawa `Instance` apa pun), tidak ada yang
> melayang. Server memberi tiap adegan nomornya sendiri (`NovaId`,
> dipasang sebelum modelnya masuk workspace), dan client menunggu model
> bernomor itu lewat `ChildAdded` sampai 2 detik sebelum menyerah — dengan
> `warn` yang menyebut nomornya, jadi kejadian itu tidak lagi senyap.
>
> Warnanya **diundi 1 dari 3 palet** tiap kedatangan (`NOVA.PALET`), dan
> aura VFX-nya undian kedua yang terpisah — jadi ada sembilan kombinasi
> tampilan. Server yang mengundi keduanya, jadi satu orang tampil sama di
> semua layar.
>
> **Raksasa tier 5 (Doughnut): 9.999–10.000%, dan kepalanya harus muat.**
>
> **Pembaruan:** angkanya sekarang diundi di rentangnya sendiri
> (`AURA_RAKSASA_MIN`..`AURA_RAKSASA`), putarannya punya bunyi sendiri (berkas
> putaran biasa, nada 0,8), bunyi mendaratnya diganti hentakan "angka besar"
> pada nada 0,75 (yang lama — `action_jump_land` pada 0,35 — nyaris tidak
> terdengar di speaker kecil), dan **2,5 detik sesudah angkanya mendarat
> papannya menyusut jadi nama saja** (`AURA_RAKSASA_NAMA_S`). Aura VFX acak
> untuk raksasa sempat dicoba lalu **dicopot** — dia tetap polos. Paragraf di
> bawah menjelaskan versi sebelumnya.
>
> Auranya **tidak diundi sama sekali** — selalu `AURA_RAKSASA` = 10.000%.
> Lantai 1000 yang dulu ada di sana secara teknis benar (yang paling mahal
> tidak boleh punya lantai lebih rendah dari tier di bawahnya), tapi di layar
> dia tidak bercerita apa-apa: 1000% itu angka yang sama yang bisa didapat
> penonton gratisan yang beruntung. Sepuluh ribu tidak bisa dicapai siapa pun
> dengan cara lain, dan dia **melewati `AURA_MAX`** dengan sengaja — undian
> berhenti di 1000, raksasa tidak ikut diundi.
>
> Papannya sekarang **papan penuh** (nama / angka / AURA) dengan putaran angka
> seperti tier lain, bukan lagi satu baris nama. Angkanya berwarna **putih ke
> emas**, satu-satunya warna hangat di panggung ini, dan ambang warnanya di
> 5.000 supaya sudah emas selagi putarannya naik. Mendaratnya punya **bunyi
> sendiri** (`SFX_AURA.HIT_RAKSASA_ID`): berkas mendarat bawaan Roblox pada
> nada 0,35 — turun satu setengah oktaf, jadi dentuman rendah yang panjang.
> Bunyi itu **mengganti** hentakan "angka besar", tidak menumpuk.
>
> **Kepalanya di dua kamera yang berbeda**, dan dua-duanya sempat memotongnya:
>
> - **saat disorot** — yang menentukan JARAK, bukan tinggi kamera (menaikkan
>   kamera ikut menambah sudut tunduk, dan keduanya hampir meniadakan satu
>   sama lain). `GIANT_KAMERA_JAUH` 0,55 → **0,72** dan `masuk` 0,75 → **0,95**:
>   rapatannya praktis dibuang. Raksasa memang tidak butuh merapat — badannya
>   sudah mengisi frame di jarak penuh, dan tiap persen yang dia merapat
>   dibayar dengan kepalanya.
> - **sisa waktunya** — raksasa bertahan lewat reset, jadi sebagian besar
>   umurnya dia berdiri di belakang panggung yang menjalankan kedatangan biasa.
>   Di kamera itu sebabnya **sudut tunduk**: kamera duduk 7 stud dan membidik
>   3,2 stud dari jarak 11, jadi menunduk 19° — dan tiap derajat tunduk
>   dipotong dari ruang di atas frame. Kepala raksasa 4× ada di 20 stud,
>   29 stud di depan kamera: 29° + 19° = 48°, jauh di luar setengah-FOV 35°.
>   Selama ada raksasa berdiri, server mengirim `upJauh` =
>   **`CAMERA_UP_JAUH_GIANT` (3,5)** bersama tiap pesan `fokus`; tunduknya
>   tinggal 1,6° dan kepalanya masuk di 31°, sisa 4° jatah topi.
>
> Yang ditukar untuk yang terakhir: seluruh guna `CAMERA_UP_JAUH` adalah duduk
> **di atas** kepala barisan (~5,8 stud) supaya baris kedua dan ketiga muncul
> di atas bahu baris depannya. Di 3,5 stud kamera ada di bawah garis itu, jadi
> barisan belakang kembali bersembunyi. Makanya angkanya **tidak menggantikan**
> `CAMERA_UP_JAUH` — tanpa raksasa di panggung tidak ada satu pun frame yang
> berubah.
>
> Bidikan kameranya sengaja **tidak** ikut dinaikkan, walaupun itu meratakan
> sudut tunduk yang sama tanpa menurunkan kamera: titik bidik yang sama dipakai
> waktu kamera sedang merapat, dan di jarak 5 stud selisih tiga stud itu 45° —
> kedatangan biasa akan dibidik dari bawah dengan kakinya di luar frame. Tinggi
> kamera aman untuk itu karena dia ikut diskalakan zoom; titik bidiknya tidak.
>
> `make test-tier` menjaga keduanya: framing sorotannya (kepala, kaki, barisan,
> dan garis mata) dan kepala raksasa di kamera panggung biasa, termasuk syarat
> sisa margin 3° untuk topi.
>
> Angkanya di `NOVA.CONFIG` dan `NOVA.TARI` di `AvatarQueueV2`.
> `make test-tier` menjaga seluruh jadwal itu muat di `SPOTLIGHT_MS_TIER4`,
> dan menjaga papan auranya tidak dikirim sebelum avatar aslinya muncul
> kembali — selama adegannya, client menyembunyikan yang asli beserta
> setiap papan yang menempel padanya.
>
> **Tier 4 (nova) butuh ModuleScript** bernama `TierNova` di **ReplicatedStorage**,
> isinya `TierNova`. Adegannya dijalankan client dengan salinan
> lokal avatarnya — server cuma mengirim model, seed, palet, dan setelan
> lewat `V2Event`, jadi semua penonton melihat adegan yang sama. Tanpa
> ModuleScript itu, Output client mencetak `[nova]` dan avatarnya langsung
> berdiri.
>
> **Jalur kameranya** (`NOVA.KAMERA` di server, dijalankan `kameraNova`
> di client) punya empat bidikan berurutan: orbit rendah 360° saat naik,
> lalu depan saat dia menggantung, lalu atas saat dia jatuh, lalu shot
> lebar saat meledak. Kamera sorotan biasa tetap dihitung di belakang
> layar, dan jalur ini melepaskannya lewat `lepas` yang turun dari 1 ke 0
> — jadi tariannya disorot seperti tier lain tanpa satu pun frame yang
> meloncat.
>
> Dua angka di situ yang gampang salah tanpa memunculkan error, dan
> dikunci `make test-tier`: `atasNaik` **harus** di atas `naikAscend`
> (kalau tidak, "kamera di atas" bohong — di frame pertama dia jatuh, dia
> justru di atas lensa), dan `naikCepat` menentukan seberapa cepat kamera
> naik relatif orbitnya — terlalu kecil, dan orbitnya sampai ke sisi
> belakang selagi kameranya masih setinggi kepala, lalu menembus badan
> orang yang sedang menari.
>
> Yang **tidak** pernah diserahkan ke modul: `camera.CFrame` dan
> `camera.FieldOfView` itu sendiri. FOV dan getaran dikemudikan lewat
> callback yang dipasang `KameraClientV2`, supaya kamera tetap punya
> satu penulis. Modul yang menulisnya sendiri akan dibatalkan gelung
> render di frame berikutnya.
>
> Undian aura ≥900% milik penonton gratisan cuma mengganti **bunyi**
> mendaratnya, bukan memberi efek — kalau tidak, aura berhenti menjadi
> penanda tier berbayar. Rinciannya ada di docstring kepala `AvatarQueueV2`
> dan tabel `KAMERA_TIER` di file yang sama.

Tangganya bertambah **kategori**, bukan bertambah angka:

| | Tier 1 — komentar | Tier 2 — ≥1 koin | Tier 3 — ≥10 koin / 1.000 tap |
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

**Satu koin sudah dapat kamera.** Tier 2 disorot 4 detik
(`SPOTLIGHT_MS_TIER2`), tier 3 dan tier 4 tujuh detik.
Semuanya **datar** — tidak satu pun ikut memanjang oleh koin. Kalau ikut memanjang,
orang yang menumpuk gift 1 koin bisa menyamai lama sorotan tier 3, dan 10 koin
kehilangan alasannya.

Yang membedakan tier bukan lamanya, tapi **bentuk gerakannya**. Tier 2
kameranya **pelan**: menahan dekat, mundur panjang (2,4 detik), setengah
sapuan ±22° dan satu gundukan naik — tanpa denyut, karena aura partikel butuh
kamera yang tenang. Tier 3 kameranya dikemudikan adegan nova (bidikan naik
barisan, mundur lebar, mengikuti orangnya melesat); sesudah dia mendarat baru
sorotan tarian biasa yang terlihat. Tier 4 tidak berdenyut sama sekali karena
merapat ke badan 4× berarti kameranya berakhir di dalam tulang keringnya; dia
naik-turun 5 stud supaya badannya terbaca dari kaki ke kepala. Semua angkanya
di `AvatarQueueV2`: `KAMERA_TIER` dan `NOVA.CONFIG`.

Dua angka yang terikat ke panjang sorotan, dan keduanya dijaga
`make test-tier`: `tunda` (kapan putaran angka aura mulai) dan `roll`
(lamanya). Jumlah keduanya harus ≤ panjang sorotan, kalau tidak angkanya
mendarat setelah kamera pergi — momen yang dibayar orangnya jatuh di luar
sorotannya sendiri. Tier 2 memakai tunda 1,0 + roll 2,8 = 3,8 detik di dalam
sorotan 4 detik; tier 3 menahan papannya sampai dia mendarat (`auraMulai` 4,1).

Jedanya juga dipisah per tier: `SPOTLIGHT_GAP_TIER2_S` (6 detik),
`SPOTLIGHT_GAP_TIER3_S` (9), `SPOTLIGHT_GAP_TIER4_S` (11). Tier 2 datang jauh
lebih sering, dan memakai jeda tier yang lebih mahal untuknya berarti sebagian
besar yang bayar 1 koin tidak pernah kebagian kamera. `main.py` mencetak
peringatan saat start kalau jeda sebuah tier lebih pendek dari sorotannya
sendiri.

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

#### Avatar bolong: kaki tidak ada, rambut telat muncul

File mesh dan tekstur avatar diunduh **tiap penonton** dari CDN Roblox, dan
unduhan itu baru mulai saat modelnya sampai. Client menahan avatar paling lama
`SPAWN_SIAP_MAKS` (0,6 detik); yang asetnya belum pernah dimuat tidak sempat,
dan muncul bolong.

Sekarang server **mempra-muat**: model dikirim dulu ke
`ReplicatedStorage.AvatarPramuat` selama `SPAWN_PRAMUAT_S` (1,5 detik) — client
mulai mengunduh asetnya selagi dia tersembunyi — baru dipindah ke panggung.
Tunggunya ada SEBELUM pesan kamera, papan aura, dan jadwal gempa nova dikirim,
jadi seluruh jadwal itu tetap sinkron dengan badannya. Harganya: tiap avatar
muncul 1,5 detik lebih lambat. Naikkan angkanya kalau live-mu masih sering
bolong, turunkan kalau terasa lamban; `0` mematikan pra-muat.

#### Tap-tap layar: podium gratis

**1.000 tap = satu kali tier 3 (setara Rosa, aura)**, tanpa koin sama sekali
(`LIKE_PODIUM` dan `LIKE_TIER` di `.env`). Hitungannya per penonton,
akumulatif, dan berulang: tiap kelipatan 1.000 tercapai dia dapat tier 3 lagi,
dan sisanya **tidak hangus** — 2.100 tap = dua kali plus 100 tap yang jalan
terus ke hitungan berikutnya. Tap tidak pernah bisa sampai ke nova (tier 4)
atau raksasa (tier 5): dua itu cuma bisa dibeli. Hadiah tap juga spawn
**sendiri**, tidak digabung ke gift yang kebetulan sedang menunggu.

Yang dipakai `event.count` (tap dari orang itu), **bukan** `event.total` (total
like ruangan) — kalau yang kedua, satu orang naik podium karena tap ribuan
penonton lain.

Dua urutan yang sama-sama jalan, persis seperti gift:

- **tap dulu, baru username** — haknya disimpan `LIKE_PODIUM_TTL_S` (90 detik),
  menunggu komentar berikutnya dari orang itu
- **username dulu, baru tap** — avatarnya sudah berdiri di kerumunan, jadi
  langsung di-spawn lagi sebagai tier 3 tanpa dia mengetik lagi

**Koinnya tidak ikut dipalsukan.** Jalur tap mendorong tier 3 lewat penanda
tersendiri, bukan dengan pura-pura dia mengirim 10 koin — papan namanya tetap
menampilkan koin yang benar-benar dia keluarkan (0 kalau memang cuma tap).
Kalau tap diterjemahkan jadi koin, papan berbohong ke penonton lain tentang
siapa yang sebenarnya membayar.

**Kenapa jalur ini dulu tidak pernah jalan.** Ambangnya 2.000 tap per orang,
padahal tiga live sungguhan mencatat **296, 641, dan 897 tap sepanjang siaran,
dijumlah dari semua penonton**. TikTok tidak mengirim satu event per tap — tap
digabung dan sebagian tidak pernah dikirim — jadi angka yang sampai ke listener
jauh di bawah yang dirasakan jari penontonnya. Tidak ada satu pun orang yang
pernah bisa mencapai 2.000.

Sekarang 1.000, dan baris `[detak]` listener ikut mencetak **tap terbanyak per
orang** (`tap terbanyak <user> 312/1000`). Kalau angka itu tetap jauh di bawah
ambangnya sepanjang live, turunkan `LIKE_PODIUM` di `.env` sampai jalurnya
benar-benar bisa dicapai — tanpa itu tier dari tap tetap tidak akan muncul.

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

#### Combo: jumlah combo = jumlah spawn

> **Bagian ini dulu bilang koin combo DIJUMLAH.** Itu sudah dibuang — dan
> penjumlahan itu yang membuat Doughnut lalu Rose jadi raksasa lagi.

| Kiriman (satu combo) | Hasil |
|---|---|
| Rose ×3 | 3 spawn Rose |
| Rose ×10 | 1 Rosa |
| Rose ×25 | 2 Rosa **dulu**, lalu 5 Rose |
| Rosa ×3 | 3 spawn Rosa |
| Bouquet Flower ×3 | 3 nova |
| Doughnut ×3 | 3 raksasa (tiap yang baru menggantikan yang sebelumnya) |
| gift tak dikenal ×3 | 3 spawn di tier harganya |

- **Cuma Rose yang ditampung** 10:1 (`GIFT_NAIK=rose:10:3` di `.env`), dan
  naiknya mentok di Rosa — Rose ×10.000 tetap Rosa, tidak pernah nova atau
  raksasa.
- **Penampungan cuma di dalam SATU combo.** Rose ×5 lalu Rose ×5 (dua combo) =
  10 Rose, bukan Rosa. Kiriman terpisah tidak pernah dijumlah.
- Gift streakable baru diproses sekali waktu streak-nya selesai, jadi satu
  combo = satu event dengan jumlahnya.
- **Tidak ada batas spawn per combo** — keputusan yang disengaja. Konsekuensinya:
  Rose ×500 = 50 Rosa yang antre satu per satu (sekitar 8 menit), dan gift
  berbayar dari penonton lain yang datang sesudahnya **menunggu di belakangnya**.
- **Di antrian juga tidak digabung.** Tiap spawn berbayar jadi entri sendiri,
  disisipkan sesudah yang berbayar lain yang sudah menunggu, jadi yang duluan
  dikirim yang duluan tampil.

Angka koin di papan dan log adalah harga yang membeli spawn **itu** (Rosa hasil
tampungan tertulis 10 koin), bukan total combo.

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

Angka tier ditentukan `tiktok_listener.py` (`tier_dari_gift()`), arti visualnya
ditentukan `main.py` (`TIER_EFFECTS`). Skrip Lua tidak menyimpan tabel apa pun
— dia cuma membaca field yang dikirim `/api/next`. Jadi menyetel ukuran atau
efek cukup lewat `.env` + restart server, tanpa sinkron ulang ke Studio.

**Dua urutan sama-sama jalan**, karena orang tidak konsisten:

- **gift dulu, baru username** — tiap gift disimpan di daftar tunggu sampai
  `GIFT_BOOST_TTL_S` (default 90 detik); saat orang itu mengetik username,
  SEMUANYA di-spawn berurutan
- **username dulu, baru gift** — avatarnya di-spawn LAGI sebagai avatar baru
  di tier gift itu; yang lama dibiarkan berdiri sampai reset biasa. Gift
  jadi selalu menghasilkan sesuatu yang terlihat — pendaratan, efek, sorotan.
  Set `UPGRADE_IN_PLACE = true` di skrip Lua kalau mau perilaku lama (dinaikkan
  di tempat, tidak ada yang baru muncul).

Kembar di panggung karena itu normal, dan itu disengaja: rem terhadap spam ada
di sisi listener (`NAME_DEDUPE_S`), bukan di Studio.

Kirim Rose lalu Rosa menghasilkan **dua** spawn — tier 2, lalu tier 3. Tidak
ada lagi yang dijumlah. Rose ×25 menghasilkan tujuh: 2 Rosa lalu 5 Rose.

**Yang bayar menembus semua rem**: cooldown, dedupe, dan batas antrian tidak
berlaku untuk tier 2 ke atas. Ditolak karena "antrian penuh" setelah membayar
itu tidak bisa diterima.

**Sorotan tidak pernah bertabrakan.** Kalau banyak yang kirim gift sekaligus,
`main.py` menahan entri sorotan di antrian dan menyajikan entri biasa dulu,
sampai jedanya terlewat. Syaratnya **dua**, dan yang berlaku yang paling lama:

1. Jeda milik tier entri yang sedang **di depan antrian** —
   `SPOTLIGHT_GAP_TIER2_S` (6 detik, aura), `SPOTLIGHT_GAP_TIER3_S` (9 detik,
   nova), atau `SPOTLIGHT_GAP_TIER4_S` (11 detik, raksasa).
2. Sorotan yang **sedang jalan** harus sudah habis, plus `SPOTLIGHT_NAPAS_S`
   (1,5 detik — napas sekaligus penutup selisih waktu muat avatar).

Syarat kedua itu yang menutup kasus raksasa → tier yang lebih murah: jedanya
dulu sama panjang dengan sorotan raksasa, jadi dia masuk persis saat adegan raksasa
belum selesai — kameranya direbut di tengah jalan dan salah satu dari keduanya
kehilangan sorotannya. Entri yang bukan sorotan tidak pernah ikut tertahan.

**Tier 2 tidak kebal reset** (`KEEP_TIER_FROM = 99`): seluruh barisan kerumunan
dikosongkan tiap reset, jadi tier 1 tidak pernah kehilangan slot ke penyintas
lama. Set `KEEP_TIER_FROM = 2` di skrip Lua kalau mau tier 2 kebal lagi.

Setelan tier di `.env`: `GIFT_TIER`, `TIER2_KOIN` / `TIER3_KOIN` / `TIER5_KOIN`
(cadangan untuk gift tak dikenal), `TIER2_SCALE`..`TIER5_SCALE`,
`SPOTLIGHT_MS_TIER2`..`5`, `SPOTLIGHT_GAP_TIER2_S`..`5`, `SPOTLIGHT_NAPAS_S`,
`GIFT_BOOST_TTL_S`, `LIKE_PODIUM`, `LIKE_TIER`, `LIKE_LOG_EVERY`,
`LIKE_PODIUM_TTL_S`. **Awas `.env` dari zaman empat tier:** arti tiap nomor
bergeser satu (`TIER4_SCALE=4` yang tertinggal membuat NOVA jadi raksasa).
`TIER4_KOIN` tidak dibaca lagi, dan `main.py` memperingatkan kalau dia masih ada —
itu tanda `.env`-nya belum disesuaikan.

### Sisi Roblox Studio

Skripnya di `src/`, disinkron ke Studio oleh Rojo (`make rojo`):
`AvatarQueueV2` di **ServerScriptService**, `KameraClientV2` di
**StarterPlayerScripts**, `TierNova` di **ReplicatedStorage**.


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



## Avatarmu sendiri tidak ikut terekam

Siaran ini direkam dengan **masuk ke room-nya** lalu meng-capture layar —
dan begitu masuk, Roblox men-spawn avatarmu di panggung. Tanpa penanganan
khusus dia ikut terekam: berdiri di tengah kerumunan, dengan nama di atas
kepalanya, dan tidak pernah menari.

`SEMBUNYI_PENONTON` (default `true`, di `AvatarQueueV2`) mematikannya.
Yang dikerjakan client, semuanya **lokal** — `LocalTransparencyModifier`
tidak direplikasi, jadi tidak ada satu pun baris yang mengubah apa yang
dilihat orang lain:

1. seluruh badannya ditembuskan
2. **bayangannya dimatikan** — part yang ditembuskan secara lokal *tetap*
   menjatuhkan bayangan, dan bayangan orang yang tidak ada di lantai
   panggung justru lebih aneh daripada orangnya sendiri
3. nama dan health bar bawaannya dimatikan
4. badannya di-**anchor dulu**, baru `CanCollide` dimatikan — dibalik, dia
   jatuh menembus lantai sampai `FallenPartsDestroyHeight`, Roblox
   men-spawn-nya lagi, dan begitu terus; gelung respawn yang tidak
   terlihat sama sekali karena badannya memang sudah tembus pandang
5. aksesori yang diunduh belakangan (rambut, topi berpartikel) ikut
   disembunyikan, dan semuanya dipasang ulang tiap respawn

Berlaku untuk **siapa pun** yang masuk, bukan cuma kamu — penonton yang
iseng join juga tidak muncul di siaran. Kedua jebakan di nomor 2 dan 4
dikunci `make test-tier`.

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


make tunnel   # https://rblx.buanaglobalcipta.com

129577777879366 - green aura
12010147091 - red aura
10088609715 - rimuru aura

make listener


tier 4 Doughnut
            "Bouquet Flower"
tier 2 rose
tier 3 rosa



-----
1. berikan sound roll dan sound after role untuk giant juga dan kasih ratting randome dari 9.999 sampai 10.000 
2.setelah spwan role di gint atau text aura di giant hapus sisakan usernamenya saja(saya mau coba juga kasih random aura dari 3 pilihan aura)
3. masalah 1 kadang avatar itu kaki tidak ada atau rambut nya telat muncu setelah spawn itu gimana ya?
4. masalah 2 nova kadang tidak keluar hanya kamera nya saya vfx dan sfx tidak keluar itu kenapa?
