--[[
	Roblox Avatar Queue Viewer  --  V2 (versi sederhana)
	Di Studio: ServerScriptService.AvatarQueueV2 (Script). Jangan di-paste:
	`make rojo` lalu Connect di plugin Rojo, file ini yang disinkron.

	PASANGANNYA: KameraClientV2 (StarterPlayerScripts, LocalScript) dan
	ModuleScript TierNova (ReplicatedStorage) -- ikut disinkron Rojo.

	PENTING: MATIKAN script lama.
	Kalau script v13 dan KameraClient lama masih aktif, dua
	server script sama-sama menaruh avatar di panggung dan dua client
	script sama-sama menulis workspace.CurrentCamera tiap frame --
	kameranya bergetar dan panggungnya dobel. Hapus, atau klik kanan >
	Disable, dua-duanya sebelum menjalankan yang ini.

	BEDANYA DENGAN V13

	Yang DIBUANG (ini inti "simple saja"):
	- meteor: tidak ada jatuh dari langit, tidak ada ekor, tidak ada
		guncangan kamera. Avatar langsung berdiri lalu menari.
	- podium, raksasa, kembang api, kolom cahaya.
	- kamera sinematik 5 gaya dan shake.

	TIER (dibawa kembali, tapi konsepnya BARU)

	LIMA tier, ditentukan NAMA GIFT (listener), bukan jumlah koin -- tiap
	gift satu spawn di tiernya sendiri, tidak ada yang dijumlah. Dulu empat;
	tier "border saja" 1 koin pernah dibuang, dan kembali sebagai Rose.

	  tier 1  komentar biasa     berdiri, menari, aura acak penuh. Tidak
	                             disorot. Undian >= 900% cuma mengganti
	                             BUNYI mendaratnya.
	  tier 2  Rose               SKIP LANE + CAKRAM BIRU di kakinya, tanpa
	                             garis tepi dan tanpa aura VFX. Sorotan 3
	                             detik, kamera paling tenang. Lantai aura
	                             900%.
	  tier 3  Rosa / 1.000 tap   AURA. Border + efek partikel di badan,
	                             satu dari tiga DIACAK tiap kedatangan.
	                             Sorotan 4 detik dengan kamera PELAN.
	                             Lantai aura 950%.
	  tier 4  Bouquet Flower     NOVA, adegan 15 detik. Dia melayang naik
	                             sambil dikelilingi orb dan rune, naik
	                             lebih tinggi jadi mahkota, waktu berhenti
	                             (layar abu-abu), lalu dia membanting diri
	                             ke tanah: shockwave, pilar cahaya, petir,
	                             kristal. Warnanya diundi satu dari TIGA
	                             palet (NOVA.PALET). Mendaratnya di SLOT
	                             1 -- barisan lama tersapu gempa di detik
	                             yang sama, dan dia yang membuka barisan
	                             yang baru. Sesudah itu dia menari 3
	                             detik dan TETAP berdiri di sana seperti
	                             kedatangan biasa. Aura VFX acak, tanpa
	                             border. Efek dijalankan client
	                             (ModuleScript TierNova). Lantai aura
	                             999% -- praktis dijamin. Lihat NOVA.
	  tier 5  Doughnut           UKURAN, dan CUMA itu. Raksasa 4x berdiri
	                             di belakang barisan, tidak ikut menari,
	                             cuma melambai. Polos, tanpa aura VFX.
	                             Cuma ADA SATU pada satu waktu; yang baru
	                             mengganti yang lama.
	                             Kameranya naik-turun paling jauh. Angka
	                             auranya 9.999-10.000%, tidak bisa
	                             dicapai dengan cara lain -- berputar
	                             dengan bunyi putaran dan bunyi mendarat
	                             miliknya sendiri, lalu papannya menyusut
	                             jadi NAMA SAJA. Selama dia berdiri,
	                             kamera panggung turun supaya kepalanya
	                             muat di frame (CAMERA_UP_JAUH_GIANT).

	Tangganya dibangun dari hal yang JENISNYA berbeda -- aura, lalu gerak,
	lalu ukuran -- bukan dari "efek yang makin banyak". Penonton tidak
	menghitung efek; yang mereka ingat satu kalimat per tier ("yang itu
	lari dari belakang"), dan kalimat itu harus ada lebih dulu daripada
	efeknya.

	KAMERANYA SELALU MEMANDANG DARI DEPAN. Tidak ada tier yang kameranya
	memutar ke samping badan, apalagi ke belakang. Adegan nova naik
	mengikuti orangnya yang melayang, tapi tetap memandang dari depan.

	Panggung BERHENTI di kedatangan tier 4 dan 5 (BEKU_MIN_TIER): spawnAvatar
	dijalankan langsung di gelung utama, jadi tidak ada kedatangan baru
	yang diambil sampai raksasanya selesai berdiri.

	Ambang koin dan panjang sorotannya milik main.py (.env), bukan file
	ini -- di sini cuma bentuk visualnya. Semuanya bisa dimatikan lewat
	TIER_ENABLED di bagian PENGATURAN.

	Yang DITAMBAH:
	- AURA: tiap kedatangan dapat angka acak 0-1000%, ditampilkan
		besar di TENGAH LAYAR (bukan di atas kepala): tiga baris,
		username / persen / "AURA".
	- MUSIK + TARIAN BERPASANGAN: satu playlist di bawah. Tiap lagu
		punya DANCE_ID-nya sendiri; begitu lagunya ganti, seluruh
		panggung ganti tarian bersamaan.

	KAMERA

	Tidak ada potongan sama sekali -- tidak satu pun frame yang
	meloncat. Yang ada tiga gerakan yang saling menumpuk:

	1. AYUNAN pelan kiri-kanan, terus-menerus. Sengaja cuma 8 derajat:
	   yang lebar terbaca sebagai kamera gelisah, bukan panggung hidup.
	2. ZOOM tiap kedatangan -- merapat dulu, menahan sebentar, lalu
	   mundur ke jarak biasa. Ini sumber gerakan utamanya sekarang:
	   ayunan bergerak terus (melelahkan), zoom bergerak sekali per
	   kedatangan lalu berhenti (bercerita).
	3. ADEGAN BERBAYAR: busur depan dan naik-turun selama sorotan
	   (KAMERA_TIER), plus FOV, getaran, dan bidikan yang naik mengikuti
	   nova tier 4 -- ketiganya dikemudikan ModuleScript TierNova lewat
	   callback yang dipasang client.
	   (Orbit yang dulu ada di sini sudah dibuang, lihat di bawah.)

	Kameranya SELALU memandang yang terakhir datang, kecuali selama
	adegan berbayar: di situ kedatangan gratisan tidak bisa menyeretnya
	pergi (penjaga di KameraClientV2).

	TAMPILAN

	Bagian VISUAL di bawah menyetel Lighting, Atmosphere, dan efek
	pasca-proses (bloom, color correction, sun rays, depth of field)
	sekali waktu server hidup. Tidak menyentuh gameplay, tata letak,
	model, atau mekanik mana pun -- cuma cara panggungnya digambar.

	Satu hal MUNGKIN harus dipencet manual, tergantung versi Studio:
	Lighting > Technology. Roblox tidak mengizinkan script mengubahnya
	(Command Bar pun ditolak), jadi tempatnya cuma panel Properties,
	dalam keadaan Stop: klik Lighting > Properties > Technology >
	Future. Tanpa itu bayangannya kotak-kotak dan sisa penyetelan di
	bawah cuma memoles gambar yang dasarnya sudah kasar.

	Kalau Technology TIDAK ADA di Properties, jangan dicari-cari:
	berarti tempat ini sudah pakai Unified Lighting (beta yang menyala
	sendiri lewat "auto-enable upcoming features"). Di situ Technology
	dihapus dan diganti LightingStyle, dan pencahayaannya memang sudah
	lebih baru daripada Future -- tidak ada yang perlu disetel. Script
	di bawah mengenali keadaan ini sendiri dan diam.

	Cara pakai:
	1. Nyalakan Allow HTTP Requests (File > Game Settings > Security)
	2. Jalankan FastAPI + tunnel seperti biasa (make server / make tunnel)
	3. Cek URL di bawah = PUBLIC_URL di Makefile
	4. Isi PLAYLIST di bawah (asset musik + dance yang berpasangan)
	5. Tekan Play, lalu baca satu baris [visual] di Output
--]]

local Players      = game:GetService("Players")
local Lighting     = game:GetService("Lighting")
local HttpService  = game:GetService("HttpService")
local RunService   = game:GetService("RunService")
-- Dipakai SATU tempat saja: lemparan gempa waktu nova menghantam tanah
-- (gempaBarisan). Sisa file ini sengaja tidak menganimasikan apa pun di
-- server -- yang bergerak digerakkan client.
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider   = game:GetService("ContentProvider")
-- Jalur kedua pengambilan asset aura VFX, lihat muatAuraVfx. Diambil
-- lewat GetService, bukan dipanggil sebagai global: InsertService yang
-- nil cuma memunculkan error di dalam pcall dan aura badannya mati
-- diam-diam tanpa satu pun petunjuk kenapa.
local InsertService     = game:GetService("InsertService")

-- ============ PENGATURAN ============

local URL           = "https://rblx.buanaglobalcipta.com"
local POLL_INTERVAL = 1

-- Susunan barisan
local ROW_SIZE      = 5
local SPACING_X     = 8
local SPACING_Z     = 8
local BASE_Y        = 5
local FLOOR_Y       = 0

-- Kapasitas panggung. Setelah penuh, panggung dikosongkan dan avatar
-- berikutnya mulai lagi dari slot 1. 0 = tidak pernah dikosongkan.
local DELETE_AFTER  = 80
local RESET_DELAY   = 2

-- Sembunyikan avatar PENONTON supaya tidak ikut berdiri di tengah frame.
local HIDE_PLAYER_AVATAR = false

-- Papan nama kecil di atas kepala.
--
-- DIMATIKAN sejak aura pindah ke atas kepala: papan aura sudah memuat
-- username di baris pertamanya, dan dua tulisan nama pada satu kepala
-- cuma saling menumpuk. Nyalakan lagi kalau AURA_DI_KEPALA dimatikan
-- dan auranya dikembalikan ke tengah layar.
-- Dikelompokkan jadi satu TABEL, bukan konstanta lepas satu per satu.
--
-- Bukan gaya penulisan: Lua membatasi 200 variabel lokal per fungsi, dan
-- seluruh file ini SATU fungsi (chunk utamanya). File ini pernah
-- menembus batas itu, dan yang muncul bukan peringatan halus --
-- script-nya menolak dikompilasi sama sekali:
--
--     too many local variables (limit is 200) in main function
--
-- Satu tabel = satu variabel lokal, isinya sebanyak yang kamu mau. Cara
-- memakainya tidak berubah, cuma titiknya menggantikan garis bawah.
local PLATE = {}

PLATE.ENABLED = false
PLATE.OFFSET  = 2.2
PLATE.WIDTH   = 130
PLATE.HEIGHT  = 24
PLATE.DIST    = 200
-- Font papan nama. FontFace, bukan Enum.Font: Enum.Font isinya keluarga
-- bawaan Roblox yang dipakai semua game, dan bobot hurufnya tidak bisa
-- dipilih. Montserrat Bold geometris dan bersih -- huruf UI game modern,
-- masih terbaca waktu dikecilkan jadi papan setinggi 24 pixel.
PLATE.FONT = Font.new("rbxasset://fonts/families/Montserrat.json",
	Enum.FontWeight.Bold)

-- ============ AURA ============
--
-- Angka acak murni, tidak dipengaruhi tier/koin. Kalau nanti mau yang
-- bayar dapat angka lebih tinggi, tempat menyetelnya cuma satu fungsi:
-- lihat hitungAura di bawah.
local AURA_MIN   = 0
local AURA_MAX   = 1000

-- Lama tulisan aura menetap di layar, detik. Sengaja lebih pendek dari
-- jarak antar kedatangan (POLL_INTERVAL sekitar 1 detik + waktu load
-- avatar ~2-3 detik) supaya layar sempat kosong lagi di antaranya.
--
-- Ikut dinaikkan bersama AURA_ROLL. Angka ini mencakup putarannya, jadi
-- yang tersisa untuk membaca hasil akhirnya cuma AURA_TIME - AURA_ROLL:
-- kalau ditinggal di 3.5 sementara putarannya 3 detik, angka finalnya
-- cuma sempat terbaca setengah detik lalu memudar. (Cuma berlaku untuk
-- aura di TENGAH LAYAR; papan di atas kepala menetap sampai avatarnya
-- dihapus, tidak memakai angka ini.)
local AURA_TIME  = 6

-- Lama angkanya berhitung naik dari 0 ke angka akhirnya. Ini yang bikin
-- angkanya terbaca sebagai "diundi", bukan sekadar ditulis.
--
-- Dinaikkan 0.6 -> 3 detik. Setengah detik terbaca sebagai angka yang
-- langsung muncul; tiga detik cukup lama untuk penonton sempat menebak
-- dan ikut bersorak sebelum angkanya mendarat -- dan itu yang bikin
-- mereka mengetik di kolom komentar.
local AURA_ROLL  = 3

-- --- Bunyi saat angkanya berputar ---
--
-- Dibunyikan di CLIENT, bukan di sini: Sound yang dibuat server memang
-- ikut direplikasi, tapi jaraknya dihitung dari tempat benda itu
-- ditaruh. Papan aura berpindah-pindah mengikuti siapa yang datang, dan
-- kamera penonton tidak berada di tempat karakternya berdiri -- jadi
-- bunyi yang di sini akan terdengar keras-pelan tanpa alasan yang bisa
-- ditebak. Yang dipasang client tidak punya posisi sama sekali: sama
-- kerasnya untuk semua orang, seperti bunyi antarmuka.
--
-- Kosongkan ("") untuk mematikannya.
-- Dikelompokkan jadi satu TABEL, bukan konstanta lepas satu per satu.
--
-- Bukan gaya penulisan, dan bukan pilihan: Lua membatasi 200 variabel
-- lokal per fungsi, dan seluruh file ini SATU fungsi (chunk utamanya).
-- File ini SUDAH menembus batas itu waktu bunyi mendarat raksasa
-- ditambahkan, dan yang muncul bukan peringatan halus -- script-nya
-- menolak dikompilasi sama sekali:
--
--     too many local variables (limit is 200) in main function
--
-- Sebelas konstanta jadi satu. Cara memakainya tidak berubah, cuma
-- titiknya menggantikan garis bawah. Alasan lengkapnya di PLATE.
local SFX_AURA = {}

SFX_AURA.ID  = "rbxassetid://15627079894"
SFX_AURA.VOL = 0.7

-- Kecepatan putar bunyinya. 1 = asli, 2 = dua kali lebih cepat (dan
-- nadanya ikut naik satu oktaf -- PlaybackSpeed menggeser keduanya
-- sekaligus, persis seperti kaset diputar cepat).
--
-- Dikembalikan ke 1 waktu bunyinya diganti dengan yang panjang. Angka
-- 1.8 dulu ada alasannya: bunyi lamanya di bawah satu detik dan harus
-- diulang-ulang, jadi dipercepat supaya ulangannya terdengar rapat.
-- Bunyi yang panjang tidak diulang sama sekali -- mempercepatnya cuma
-- menaikkan nada tanpa satu pun manfaat.
SFX_AURA.SPEED = 1

-- Ulang bunyinya kalau dia habis sebelum angkanya mendarat.
--
-- DIMATIKAN: bunyi yang sekarang lebih panjang dari AURA_ROLL, jadi
-- tidak pernah sampai ke ujungnya -- tidak ada yang perlu diulang.
-- Nyalakan lagi kalau nanti diganti bunyi pendek (di bawah satu detik);
-- tanpa itu, putaran tiga detik akan hening di dua detik terakhirnya,
-- dan hening di tengah putaran terbaca sebagai "sudah selesai" padahal
-- angkanya masih naik.
SFX_AURA.LOOP = false

-- Potong bunyinya tepat saat angkanya mendarat.
--
-- Ini yang membuat bunyi dan angka berhenti BERSAMAAN. Tanpa ini, bunyi
-- yang panjang masih berlanjut ketika angkanya sudah diam -- dan telinga
-- membaca itu sebagai "masih mengundi", padahal hasilnya sudah tertulis
-- di layar.
--
-- Matikan (false) cuma kalau bunyimu punya ekor penutup yang memang
-- ingin kamu dengar utuh; dia akan dibiarkan habis sendiri. Kalau
-- SFX_AURA.LOOP menyala, mematikan yang ini berarti tidak ada satu pun
-- yang menghentikannya -- dia berputar sampai sesi berakhir.
SFX_AURA.IKUT_ROLL = true

-- --- Bunyi saat angkanya MENDARAT ---
--
-- Dibunyikan tepat di detik angkanya berhenti, menggantikan bunyi
-- putaran yang dipotong di saat yang sama. Dua bunyi ini satu pasang:
-- yang satu berhenti, yang satu mulai, di frame yang sama -- dan
-- pergantian itulah yang terdengar sebagai "mendarat". Kalau yang ini
-- dikosongkan (""), putarannya cuma berhenti begitu saja.
--
-- Pilih yang PENDEK (di bawah ~1.5 detik) dan hentakannya di frame
-- pertama. Bunyi yang punya jeda hening di depannya akan terdengar
-- telat dari angkanya, dan yang panjang akan ketiban undian orang
-- berikutnya -- pollingnya cuma satu detik.
SFX_AURA.HIT_ID  = "rbxassetid://73557803481217"
SFX_AURA.HIT_VOL = 0.8

-- Bunyi mendarat KHUSUS untuk angka besar, dan yang di atas TIDAK ikut
-- dibunyikan kalau yang ini kena.
--
-- Bukan dua bunyi bertumpuk: yang biasa itu hentakan pendek yang sama
-- untuk semua orang, jadi kalau keduanya jalan bersamaan yang terdengar
-- cuma hentakan biasa yang kebetulan lebih ramai -- dan angka 950
-- kehilangan satu-satunya penanda yang membedakannya dari 200. Yang
-- besar MENGGANTI, bukan menambah.
SFX_AURA.HIT_TINGGI_ID  = "rbxassetid://136357088509992"
SFX_AURA.HIT_TINGGI_VOL = 0.9

-- Bunyi mendarat KHUSUS RAKSASA, dan cuma dia yang pernah kebagian.
--
-- MENGGANTI dua-duanya di atas, tidak menambah -- alasannya sama
-- dengan kenapa yang tinggi mengganti yang biasa. Dan raksasa memang
-- selalu kena yang "tinggi" sekarang (10.000 jauh di atas
-- AURA_TINGGI_MIN), jadi tanpa bunyi sendiri angka yang tidak ada
-- duanya di panggung mendarat dengan hentakan yang sama persis dengan
-- penonton gratisan yang kebetulan dapat 950.
--
-- DIGANTI dari action_jump_land.mp3 pada nada 0,35. Berkas itu pendek
-- sekali, dan diturunkan satu setengah oktaf dia jadi dengung rendah
-- yang di speaker laptop atau HP nyaris tidak terdengar -- dari sisi
-- penonton, raksasa tidak punya bunyi mendarat sama sekali.
--
-- Sekarang memakai hentakan "angka besar" yang SUDAH terbukti terdengar
-- di siaran, pada nada 0,75: cukup rendah untuk terdengar lebih berat dan
-- berbeda dari milik penonton gratisan, tapi masih di rentang yang
-- keluar dari speaker kecil. Kalau nanti ada asset audio sendiri yang
-- lebih megah, yang diganti cuma baris id ini.
SFX_AURA.HIT_RAKSASA_ID   = SFX_AURA.HIT_TINGGI_ID
SFX_AURA.HIT_RAKSASA_VOL  = 1.0
SFX_AURA.HIT_RAKSASA_NADA = 0.75

-- Bunyi PUTARAN angka khusus raksasa. Berkasnya sama dengan putaran
-- milik semua orang (SFX_AURA.ID), yang dibedakan nadanya: 0,8 membuat
-- putarannya terdengar lebih berat dan lebih lambat, jadi dari telinga
-- saja penonton tahu yang sedang diundi bukan angka biasa.
--
-- Sound TERSENDIRI di client, bukan PlaybackSpeed yang ditukar pada Sound
-- putaran biasa: undian raksasa dan undian orang lain bisa menempel, dan
-- menukar nada Sound yang sedang berbunyi membuat putaran orang lain ikut
-- berubah nada di tengah jalan.
SFX_AURA.ROLL_RAKSASA_NADA = 0.8

-- --- BUNYI KEDATANGAN TIER BERBAYAR ---
--
-- Dibunyikan sekali, tepat saat orangnya berdiri. Beda dari bunyi aura
-- di atas: yang itu menempel pada UNDIAN ANGKA (berputar lalu mendarat),
-- yang ini menandai KEDATANGANNYA -- dan keduanya memang terdengar
-- bersusun, karena memang dua kejadian yang berbeda.
--
-- KENAPA rbxasset://, BUKAN rbxassetid://.
--
-- `rbxasset://` itu berkas yang IKUT TERPASANG bersama Roblox: tidak
-- lewat katalog, tidak bisa dihapus pemiliknya, tidak kena moderasi,
-- dan tidak butuh izin apa pun. Dia jalan di Studio maupun di game yang
-- sudah terbit, hari ini dan tahun depan.
--
-- `rbxassetid://` sebaliknya menunjuk ke katalog: kalau id-nya salah,
-- di-private, atau ditarik, yang terjadi BUKAN error -- cuma hening.
-- Itu jenis kegagalan yang paling mahal dilacak, dan tidak ada cara
-- memverifikasi sebuah id tanpa membuka Studio.
--
-- Jadi kalau mau ganti dengan bunyi katalog pilihanmu sendiri, taruh
-- id-nya di DEPAN daftar kandidat. Yang di belakangnya tetap jadi
-- jaring pengaman: client mencoba satu per satu dari atas dan memakai
-- yang PERTAMA benar-benar berhasil dimuat, lalu mencetak yang mana.
--
-- NADA DAN VOLUME-nya sengaja beda jauh antar tier. Itu bukan hiasan:
-- kalau ternyata ketiganya jatuh ke berkas cadangan yang sama, ketiga
-- tier masih terdengar berbeda -- yang mahal terdengar lebih berat dan
-- lebih rendah, yang murah lebih tinggi dan lebih ringan.
local SFX_TIER = {
	-- Tier 2 (Rose): yang PALING sering datang di antara yang berbayar,
	-- jadi bunyinya yang paling ringan -- satu denting pendek bernada
	-- tinggi. Rose datang tiap beberapa detik saat live ramai, dan bunyi
	-- yang berisi sesering itu jadi derau.
	[2] = {
		vol = 0.5, nada = 1.3,
		kandidat = {
			"rbxasset://sounds/electronicpingshort.wav",
			"rbxasset://sounds/bass.wav",
		},
	},
	-- Tier 3 (Rosa, aura): bunyinya berisi tapi tidak berat -- bunyi
	-- berat tiap beberapa detik melelahkan telinga dalam sepuluh menit.
	[3] = {
		vol = 0.7, nada = 1.0,
		kandidat = {
			"rbxasset://sounds/bass.wav",
			"rbxasset://sounds/impact_water.mp3",
			"rbxasset://sounds/electronicpingshort.wav",
		},
	},
	-- Tier 4 (Bouquet, nova): desis angin jatuh. Dibunyikan client tepat saat dia
	-- MEMBANTING DIRI ke tanah, bukan saat avatarnya dibuat -- di detik
	-- itu dia masih mengumpulkan tenaga di udara dan belum ada yang
	-- terjadi (bunyiSaatNova di KAMERA_TIER).
	--
	-- action_falling.mp3 = bunyi angin jatuh bawaan Humanoid, dan untuk
	-- nova namanya kebetulan tepat: yang dibunyikan memang orang yang
	-- sedang jatuh. Dipilih karena berkas action_* dipakai SETIAP
	-- karakter Roblox, jadi pasti ikut terpasang. swoosh.wav yang dulu di
	-- sini ternyata TIDAK ada di instalasi Studio: "Asset is not approved
	-- for the requester", dan bunyinya jatuh ke ping cadangan.
	--
	-- Nada dinaikkan (1,4): angin jatuh aslinya panjang dan rendah;
	-- dipercepat dia jadi desis pendek yang terdengar membelah udara.
	[4] = {
		vol = 0.9, nada = 1.4,
		kandidat = {
			"rbxasset://sounds/action_falling.mp3",
			"rbxasset://sounds/action_jump.mp3",
			"rbxasset://sounds/electronicpingshort.wav",
		},
	},
	-- Tier 5 (Doughnut, raksasa): paling berat dan paling rendah. Nada
	-- 0,6 menurunkan berkas yang sama hampir satu oktaf -- itu yang membuat
	-- raksasa terdengar seperti sesuatu yang BESAR mendarat, bukan seperti
	-- notifikasi yang kebetulan lebih keras.
	[5] = {
		vol = 0.9, nada = 0.6,
		kandidat = {
			"rbxasset://sounds/action_jump_land.mp3",
			"rbxasset://sounds/bass.wav",
			"rbxasset://sounds/impact_water.mp3",
		},
	},
}

-- Dari angka berapa sebuah undian dihitung "tinggi".
--
-- Sekarang cuma menentukan BUNYI MENDARAT, tidak lagi ikut menentukan
-- aura VFX di badan. Aura badan jadi milik tier 2 dan 3 saja (lihat
-- AURA_VFX_TIER), dan itu keputusan yang sengaja:
--
-- Kalau penonton gratisan dengan undian besar juga dapat aura, aura
-- berhenti menjadi penanda "ini yang kirim 1 koin" -- padahal itu
-- penanda orang yang membayar. Yang
-- gratisan tetap dapat sesuatu untuk undian besarnya, cuma bentuknya
-- BUNYI, bukan efek yang menyaingi tier berbayar.
local AURA_TINGGI_MIN = 900

-- DI MANA auranya ditulis.
--
-- kepala = melayang di atas kepala avatarnya sendiri (BillboardGui,
--          benda dunia). Ikut bergerak bersama kameranya, dan tiap
--          avatar punya angkanya masing-masing yang menetap -- penonton
--          bisa membandingkan satu sama lain.
-- layar  = besar di tengah layar (ScreenGui), satu per satu, lalu
--          hilang. Lebih dramatis untuk satu orang, tapi menutupi
--          panggung dan angka sebelumnya hilang begitu ada yang datang.
--
-- Boleh dua-duanya true. Boleh dua-duanya false (aura mati, tinggal
-- panggung menari).
local AURA_DI_KEPALA = true
local AURA_DI_LAYAR  = false

-- --- Papan aura di atas kepala ---
--
-- Tinggi papan dari kepala, dalam studs.
local AURA_KEPALA_Y  = 3.2

-- Ukuran papannya dalam pixel. Ini yang menentukan besar hurufnya:
-- ketiga barisnya TextScaled, jadi mereka mengisi jatah tingginya
-- masing-masing. Papan dunia menyusut sendiri kalau kamera menjauh --
-- angka ini ukurannya saat kamera dekat.
local AURA_KEPALA_W  = 190
local AURA_KEPALA_H  = 96

-- Sejauh apa papannya masih digambar (studs). Lewat dari ini dia hilang
-- sendiri, jadi barisan paling belakang tidak ikut memenuhi layar.
local AURA_KEPALA_JAUH = 220

-- Papan aura HANYA di baris paling depan.
--
-- Avatarnya tidak disentuh: yang di belakang tetap berdiri dan tetap
-- menari, cuma papannya yang dilepas begitu ada orang mengisi baris di
-- depannya. Kerumunan tumbuh ke arah kamera, jadi baris yang lebih baru
-- selalu lebih dekat -- dan papan baris belakang menembus badan mereka,
-- saling menumpuk, sampai layar penuh tulisan yang tidak satu pun
-- kebaca.
local AURA_DEPAN_SAJA = true

-- Lama papan menyusut sebelum dibuang. 0 = hilang seketika.
--
-- Dikasih waktu sedikit karena papan yang lenyap satu frame terbaca
-- seperti kedip/bug, sementara yang memudar terbaca sebagai "gilirannya
-- sudah lewat".
local AURA_FADE_OUT   = 0.3

-- --- Aura di tengah layar (kalau AURA_DI_LAYAR dinyalakan) ---
--
-- Letak tulisan aura di layar, dihitung dari TEPI ATAS, dalam pecahan
-- tinggi layar. 0 = mepet atas, 0.5 = tepat setengah layar ke bawah.
--
-- Pecahan, bukan pixel: layar HP penonton dan layar Studio jauh berbeda
-- tingginya, dan angka pixel yang pas di satu layar meleset di layar
-- lain. Pecahan selalu jatuh di tempat yang sama secara relatif.
--
-- Diturunkan dari 0.22: kepala avatar barisan depan berada di sekitar
-- sepertiga layar, dan tulisan yang mulai di 0.22 menutupi mereka.
local AURA_Y     = 0.12

-- Tinggi blok tiga barisnya, juga pecahan tinggi layar. Ini yang
-- menentukan BESAR HURUFNYA -- ketiga baris pakai TextScaled, jadi
-- mereka mengisi jatah tingginya masing-masing. Naikkan untuk tulisan
-- lebih besar; tapi ingat blok ini mulai di AURA_Y, jadi AURA_Y +
-- AURA_H tidak boleh lewat dari 1 kalau tidak baris "AURA" terpotong
-- di bawah layar.
local AURA_H     = 0.32

-- ============ TIER ============
--
-- Tier datang dari server (/api/next), bukan dihitung di sini. main.py
-- yang memutuskan siapa tier berapa; di file ini cuma bentuk visualnya.
-- Ringkasan keempat tier ada di kepala file ini.
--
-- Ambang koin dan panjang sorotannya milik main.py (.env). Semuanya
-- bisa dimatikan sekaligus lewat TIER_ENABLED.
local TIER_ENABLED = true

-- --- BORDER (tier 2 ke atas) ---
--
-- Dua cara sekaligus, dan dua-duanya bisa dimatikan sendiri-sendiri.
-- Sengaja dua karena keduanya kebaca di jarak yang berbeda: garis tepi
-- hilang kalau kameranya mundur, cakram lantai justru baru kelihatan
-- utuh dari jauh.
local BORDER_ENABLED = true
local BORDER_GARIS   = true
local BORDER_CAKRAM  = true

-- Dari tier berapa GARIS TEPI ikut dipasang. Di bawahnya cuma cakram.
--
-- Rose (tier 2) cuma dapat cakram biru di kakinya -- itu yang diminta:
-- "skip lane dan bawah biru saja". Dan ada alasan kedua yang bukan selera:
-- Roblox cuma menggambar sekitar 31 Highlight sekaligus (BORDER_MAKS_GARIS),
-- dan Rose yang paling sering datang. Kalau dia ikut memakai jatah garis,
-- border orang yang bayar Rosa dilepas duluan untuk memberi tempat ke dia.
-- Cakram itu Part biasa, tidak punya jatah semacam itu.
local BORDER_GARIS_MIN_TIER = 3

-- Satu warna per tier. Ini bahasa yang paling cepat dibaca penonton --
-- lebih cepat daripada ukuran, apalagi daripada angka.
-- Nama konstantanya peninggalan zaman empat tier: T2 = warna tier
-- berbayar biasa (Rose dan Rosa sekarang), T3 = warna tier 4 ke atas.
local BORDER_T2_WARNA = Color3.fromRGB(120, 200, 255)  -- biru es
local BORDER_T3_WARNA = Color3.fromRGB(255, 140,  56)  -- oranye bara

-- Highlight TIDAK punya properti ketebalan -- Roblox menggambar
-- garisnya dengan lebar tetap, dan satu-satunya yang bisa disetel dua
-- transparansi di bawah ini.
local BORDER_ISI         = 0.92  -- transparansi isian (1 = garis saja)
local BORDER_GARIS_ALPHA = 0     -- transparansi garisnya (0 = pekat)

-- Garis tengah cakram, studs. Jangan lewat dari SPACING_X (8):
-- tetangga sebelahnya berdiri sejauh itu, dan cakram yang lebih lebar
-- akan bertindihan jadi satu genangan cahaya, bukan lingkaran per orang.
-- Raksasa mengalikannya sendiri dengan skalanya.
local BORDER_CAKRAM_D     = 5.5
local BORDER_CAKRAM_TIPIS = 0.15
local BORDER_CAKRAM_ALPHA = 0.55
local BORDER_CAKRAM_LAMPU = 14     -- jangkauan PointLight, 0 = mati

-- Lama border sebelum pudar, detik. 0 = menetap sampai panggung reset.
--
-- Tier 2 diberi umur, dan itu BUKAN selera. Roblox cuma menggambar
-- sekitar 31 Highlight sekaligus; lewat dari itu sisanya diam-diam
-- TIDAK DIGAMBAR -- tanpa error, tanpa peringatan. Dengan DELETE_AFTER
-- = 60, panggung yang penuh orang tier 2 pasti menembus batas itu, dan
-- yang kamu lihat cuma "border kadang muncul kadang tidak" yang
-- mustahil dilacak.
--
-- Tier 3 tidak memakai border sama sekali, jadi jatah itu praktis cuma
-- diperebutkan tier 2.
local BORDER_T2_UMUR = 15
local BORDER_T3_UMUR = 0
local BORDER_PUDAR   = 0.8

-- Pengaman kedua: begitu jumlah garis tepi hidup menyentuh angka ini,
-- yang PALING TUA dilepas. Ditaruh di bawah 31 supaya masih ada ruang
-- untuk Highlight dari tempat lain (plugin, efek bawaan).
local BORDER_MAKS_GARIS = 24

-- --- TIER 4: RAKSASA ---
--
-- Satu raksasa saja pada satu waktu. Yang baru menggantikan yang lama.
--
-- Bukan penghematan: dua raksasa 10x berdiri berdampingan saling
-- menutupi, dan yang ketiga sudah keluar frame. Yang membuat raksasa
-- terasa besar itu SENDIRIAN-nya -- begitu ada dua, keduanya cuma jadi
-- latar belakang.
local GIANT_ENABLED = true

-- Skalanya dibaca dari field `scale` milik /api/next (TIER4_SCALE di
-- .env). Angka di bawah cuma batas atas kalau server mengirim sesuatu
-- yang liar -- rig 40x bikin fisikanya meledak dan lantainya tembus.
local GIANT_SKALA_MAKS = 14

-- Di mana dia berdiri. Z POSITIF = di belakang barisan.
--
-- Arahnya gampang terbalik, jadi ini alasannya: barisan tumbuh ke arah
-- -Z (getPosition), dan kamera duduk di CAMERA_BACK yang juga negatif
-- -- artinya kamera ada di sisi -Z dan memandang ke +Z. Yang paling
-- JAUH dari kamera adalah z terbesar. Raksasa di z negatif akan berdiri
-- tepat di depan lensa dan menutupi seluruh panggung.
-- Jaraknya IKUT skalanya, dan ini yang gampang salah kalau skalanya
-- diturunkan.
--
-- Pada 10x, z=26 pas: badan setinggi 50 stud tetap menjulang walaupun
-- jauh. Pada 3x badannya cuma ~15 stud, dan di jarak yang sama dia
-- menyusut jadi sosok kecil di kejauhan -- terbaca sebagai "raksasanya
-- tidak muncul", padahal dia berdiri di sana. Jadi begitu skalanya
-- dikecilkan, dia harus DIDEKATKAN.
--
-- 18 = lebih dari dua baris di belakang baris depan (SPACING_Z = 8): masih jelas
-- di luar barisan, tapi masih mengisi frame.
local GIANT_X = 0
local GIANT_Z = 18

-- TIDAK ADA EFEK APA PUN di raksasa. Tidak ada border, tidak ada
-- cakram cahaya, tidak ada aura api, tidak ada animasi naik dari tanah.
-- Dia cuma berdiri, besar, di belakang barisan.
--
-- Ini bukan penyederhanaan selera -- ini yang MEMPERBAIKI bugnya.
--
-- Versi sebelumnya menyembunyikan raksasa 400 stud di bawah tanah
-- dulu, lalu menaikkannya dengan BodyPosition supaya dia terlihat
-- tumbuh dari lantai. Begitu satu langkah di jalur itu gagal, dia
-- tinggal di bawah tanah SELAMANYA -- dan yang tersisa di layar cuma
-- cakram cahayanya, yang memang ditaruh di permukaan lantai lepas dari
-- posisi badannya. Persis "raksasanya tidak muncul, cuma ada lingkaran
-- besar bersinar".
--
-- Sekarang dia di-spawn persis seperti avatar lain: langsung berdiri di
-- tempatnya. Jalur itu sudah terbukti jalan enam puluh kali per sesi
-- untuk kerumunan biasa, dan raksasa tidak lagi punya jalur khusus yang
-- bisa gagal sendirian.

-- Emote-nya. Melambai, bukan menari.
--
-- Dua alasan, dan yang kedua yang menentukan: (1) badan 10x yang
-- ngedance gerakannya menyapu belasan stud tiap ketukan dan terbaca
-- sebagai kacau, bukan sebagai keren; (2) seluruh panggung sudah
-- menari serempak, jadi raksasa yang ikut menari cuma jadi salah satu
-- dari mereka, kebetulan lebih besar. Yang DIAM di antara yang bergerak
-- justru yang ditonton.
--
-- R15Wave (507770239) bawaan Roblox. Alternatif yang juga sudah dicek
-- ada: 507770677 R15Cheer, 507770453 R15Point, 507770818 R15Laugh.
local GIANT_EMOTE_ID    = "rbxassetid://507770239"
local GIANT_EMOTE_SPEED = 0.55   -- dilambatkan: gerakan raksasa yang
                                 -- secepat orang biasa terlihat gugup

-- Berapa kali lipat kamera harus mundur untuk raksasa.
--
-- Tanpa ini kamera sinematik (12 stud) berakhir DI DALAM tulang
-- keringnya. Dikali skalanya sendiri terlalu jauh -- pada 10x dia jadi
-- 120 stud dan raksasanya kembali jadi titik kecil; setengahnya pas.
--
-- 0,55 -> 0,72. Yang dikeluhkan: KEPALANYA tidak terlihat waktu dia
-- disorot. Sebabnya bukan tingginya kamera -- sudut kepala terhadap
-- tengah layar hampir tidak berubah kalau kamera dinaikkan atau
-- diturunkan (yang ikut berubah sudut tunduknya, dan keduanya saling
-- meniadakan). Yang benar-benar menentukan JARAK.
--
-- Dan angka 5 stud per satuan skala yang dipakai menghitungnya itu rig
-- POLOS. Avatar bertopi tinggi atau berambut menjulang bisa 6-7 stud
-- per skala, dan selisih satu stud itu tiga sampai empat derajat --
-- persis selisih antara kepala yang muat dan kepala yang terpotong.
-- Mundur ke 0,72 membeli sekitar lima derajat ruang di atas kepalanya,
-- dan itu yang menanggung topi.
local GIANT_KAMERA_JAUH = 0.72   -- pengali terhadap skala avatarnya

-- Seberapa TINGGI kamera duduk untuk raksasa. Pengali terhadap skalanya,
-- persis seperti GIANT_KAMERA_JAUH di atas -- tapi ANGKANYA SENDIRI, dan
-- itu seluruh intinya.
--
-- Sebelumnya tidak ada angka ini: tinggi kamera ikut diskalakan oleh
-- pengali jarak yang sama. Akibatnya pada 14x kamera duduk di 78 stud
-- sementara MATA raksasanya ada di 64 -- kameranya empat belas stud DI
-- ATAS kepalanya, dan yang dilihat penonton ubun-ubun, bukan wajah.
-- Raksasa yang tidak pernah terlihat wajahnya kehilangan satu-satunya
-- hal yang membuat dia terbaca sebagai ORANG dan bukan sebagai patung.
--
-- 0,37 menaruh kamera di 62 stud saat mundur penuh dan 55 saat merapat
-- -- di bawah garis mata di kedua-duanya, jadi wajahnya menghadap lensa
-- sepanjang sorotan.
--
-- Pasangannya GIANT_FOKUS_TINGGI dan `masuk` di KAMERA_TIER[4]: ketiga
-- angka itu satu kesatuan, dan test_tier.py memeriksa hasil GABUNGANNYA
-- -- wajah terlihat, badan utuh, barisan tetap di dalam frame -- bukan
-- angkanya satu per satu.
local GIANT_KAMERA_TINGGI = 0.37

-- DI MANA kamera membidik raksasa, sebagai pecahan tinggi pivot-nya.
--
-- Dulu 1,15 -- di ATAS titik tengah badan. Angka itu dipilih supaya
-- kepalanya muat waktu kamera sedang paling dekat, dan memang berhasil
-- untuk itu; yang tidak dihitung waktu itu BARISANNYA. Kamera yang
-- membidik setinggi 48 stud ikut naik setinggi itu juga, dan dari sana
-- barisan yang berdiri di lantai jatuh ke tepi bawah frame (-45 derajat
-- saat menahan, di luar setengah-FOV 35) -- panggungnya hilang, yang
-- tersisa cuma raksasa menggantung di langit.
--
-- 0,80 membidik dada, bukan ubun-ubun: barisan naik ke dalam frame di
-- seluruh adegan. Kepalanya tetap muat karena rapatannya sekalian
-- dikurangi -- lihat `masuk` di KAMERA_TIER[4].
--
-- Turun 0,85 -> 0,80 bersama GIANT_KAMERA_TINGGI: kamera duduk di
-- bidikan + tinggi, jadi menurunkan bidikannya ikut menurunkan
-- kameranya, dan itu yang membawanya ke bawah garis mata raksasa.
--
-- Ketiganya sepasang-sepasang; menurunkan yang ini sendirian memotong
-- kepalanya. Yang menjaga kombinasinya test_tier.py.
local GIANT_FOKUS_TINGGI = 0.80

-- Dari tier berapa seseorang jadi raksasa.
--
-- Turun 5 -> 4 waktu tier "border saja" dibuang. Semua yang bergantung pada
-- "raksasa atau bukan" (slot, skala, emote, beku, papan nama saja) ikut
-- pindah lewat adalahRaksasa di bawah, tanpa satu pun angka lain diubah.
--
-- Naik 4 -> 5 waktu Rose kembali jadi tier sendiri (tier 2) dan semua yang
-- di atasnya naik satu nomor. Raksasa = Doughnut.
local GIANT_MIN_TIER = 5

-- SATU-SATUNYA tempat yang menjawab "tier ini raksasa atau bukan".
--
-- Dulu jawabannya ditulis dua kali: sekali di gelung utama (yang
-- memilih SLOT-nya) dan sekali di spawnAvatar (yang MEMPERBESAR
-- badannya). Waktu raksasa dipindah dari tier 3 ke tier 4, cuma satu
-- dari keduanya ikut berubah -- dan akibatnya tertukar: tier 3 berdiri
-- di belakang barisan dengan badan normal, tier 4 jadi raksasa DI DALAM
-- barisan.
--
-- Yang bikin itu mahal untuk dilacak: tidak ada error, tidak ada nil,
-- dan kedua tempat itu masing-masing masih terbaca masuk akal kalau
-- dibaca sendirian. Lint tidak bisa menangkapnya, dan uji pun tidak --
-- yang salah bukan kodenya, tapi dua kode yang tidak sepakat.
--
-- Ditaruh di sini, bukan di dekat spawnAvatar, supaya dia berada tepat
-- di bawah angka yang mengaturnya.
local function adalahRaksasa(tier)
	if not (TIER_ENABLED and GIANT_ENABLED) then return false end
	return (tonumber(tier) or 1) >= GIANT_MIN_TIER
end

-- --- TIER 3: NOVA (PRISMATIC STARFALL) ---
--
-- Menggantikan DASH. Yang dijual tier 3 sekarang bukan lagi kecepatan
-- (zigzag menerobos kerumunan) tapi UPACARA: orangnya melayang naik,
-- mengumpulkan tenaga, waktu berhenti, lalu dia membanting diri ke tanah
-- dan panggungnya meledak. Harganya tidak berubah, tetap TIER3_KOIN.
--
-- Adegan 15 detik (SPOTLIGHT_MS_TIER3 di .env), urutannya:
--
--   0,0 - ~0,6   client menunggu aset avatarnya (SPAWN_SIAP_MAKS)
--   CHARGE  4,0  letterbox masuk, FOV menyempit, badan melayang naik 14
--                stud, enam orb mengorbit sambil menarik beam ke dada,
--                32 rune berputar di lantai, partikel naik dari tanah.
--                KAMERA rendah memandang ke atas, mengorbit 360 derajat
--   ASCEND  1,5  naik ke 45 stud, orb mengatup jadi mahkota di atas
--                kepala, lingkaran rune melebar dan berputar makin cepat.
--                Selagi naik dia juga MELINTAS ke atas slot 1 -- di situ
--                dia akan membanting diri (NOVA.CONFIG, `tujuan`)
--   FREEZE  1,0  orb tersedot ke dada, kilatan membesar, layar jadi
--                abu-abu dan buram -- waktu berhenti. KAMERA meluncur ke
--                depan wajahnya dan diam
--   SLAM    0,6  banting ke tanah SLOT 1 dari 45 stud, FOV menyempit.
--                KAMERA meluncur ke atas kepalanya -- dia jatuh menjauh
--   IMPACT  3,2  shell, tiga shockwave, pilar cahaya, delapan petir,
--                kristal melayang lalu jatuh, aftershock kedua, warna
--                pulih, letterbox keluar. KAMERA mundur ke shot lebar.
--                Di detik yang sama BARISAN TERSAPU: semua yang sedang
--                menari terlempar keluar dan dihapus, panggung kembali
--                ke slot 1 (gempaBarisan)
--   TARI    3,0  dia menari SENDIRIAN di panggung kosong, disorot
--                (NOVA.TARI) -- lalu dia TINGGAL, sebagai orang pertama
--                di barisan yang baru (novaKeBarisan). Yang komentar
--                sesudahnya berdiri di sampingnya, slot 2, 3, ...
--
-- Aura VFX acaknya (AURA_VFX_TIER) menyala saat adegannya selesai --
-- selama nova berlangsung client menyembunyikan avatar aslinya bersama
-- seluruh efek yang menempel padanya.
--
-- SERVER TIDAK MENGGERAKKAN APA PUN. Avatarnya tetap di-spawn persis
-- seperti yang lain -- langsung di slot, dikunci BodyPosition -- dan yang
-- dikirim ke client cuma satu pesan "nova" berisi model, seed, palet, dan
-- setelan di bawah. Client yang menyembunyikan avatar aslinya, memainkan
-- adegannya dengan SALINAN lokalnya (ModuleScript TierNova), lalu
-- memunculkan yang asli kembali -- di slot 1, tempat salinannya tadi
-- mendarat.
--
-- Kenapa tidak digerakkan di server: posisi avatar dijaga BodyPosition,
-- dan badan yang ditarik-tarik tween sambil dilawan pegas itu yang dulu
-- membuat raksasa tersangkut di bawah tanah (lihat catatan raksasa). Nova
-- di client tidak menyentuh fisika server sama sekali -- kalau adegannya
-- gagal di satu layar, yang terjadi di layar itu cuma avatar yang langsung
-- berdiri seperti tier lain.
--
-- Client TIDAK BISA memicu nova sendiri: V2Event tidak punya
-- OnServerEvent sama sekali, jadi satu-satunya yang bisa mengirim "nova"
-- script ini.
--
-- Seed-nya diundi di sini dan dikirim ke semua client, jadi petir, kristal,
-- dan PALET warnanya sama persis di tiap layar.
--
-- Satu TABEL, bukan konstanta lepas -- batas 200 variabel lokal, lihat
-- catatan di PLATE.
local NOVA = {}

NOVA.ENABLED = true

-- Tier yang dapat nova. TEPAT tier ini, bukan "ke atas": raksasa (tier 5)
-- sengaja tidak ikut -- badan 14x yang melayang 13 stud lalu membanting
-- diri menyapu seluruh panggung, dan yang dia jual justru diamnya.
-- Naik 3 -> 4 bersama semua tier di atas Rose. Nova = Bouquet Flower.
NOVA.TIER = 4

-- Setelan yang diteruskan apa adanya ke TierNova.Play. Nama kolomnya nama
-- config modul itu, supaya tidak ada terjemahan di tengah jalan.
--
-- Kelima angka fase JUMLAHNYA lama seluruh adegan, dan angka itu terikat
-- ke sorotan 15 detik. test_tier.py menjaganya: SPAWN_SIAP_MAKS + seluruh
-- fase + TARI <= sorotan.
NOVA.CONFIG = {
	-- Fase paling panjang, dan itu memang bentuknya: yang dijual di sini
	-- penantian. Dipendekkan, ledakannya datang sebelum penonton sempat
	-- bertanya-tanya apa yang sedang dikumpulkan.
	charge = 4.0,
	ascend = 1.5,
	freeze = 1.0,
	-- Bantingannya tetap yang TERPENDEK dari semuanya -- lima setengah
	-- detik naik pelan lalu turun dalam 0,6 detik, dan selisih itu yang
	-- bikin jatuhnya terbaca sebagai berat.
	--
	-- Naik 0,3 -> 0,6 waktu tingginya dinaikkan ke 45 stud. Dua alasan:
	-- jatuh 45 stud dalam 0,3 detik itu 150 stud/detik, cepat sampai
	-- badannya cuma jadi garis kabur; dan kamera harus sempat meluncur
	-- dari depan wajahnya ke atas kepalanya selama dia jatuh (lihat
	-- NOVA.KAMERA). 0,6 detik memberi ruang untuk keduanya tanpa
	-- membuat jatuhnya terasa pelan.
	slam   = 0.6,
	impact = 3.2,

	-- Tinggi melayangnya, stud.
	--
	-- 13 -> 45 (sembilan kali tinggi badan, hampir setinggi raksasa
	-- 14x). Yang membuat angka setinggi ini bisa dipakai kamera
	-- adegannya sendiri: kamera nova TIDAK lagi cuma menumpang di
	-- kamera sorotan biasa -- dia punya jalur sendiri yang ikut naik,
	-- jadi badannya tidak pernah menyusut jadi titik di langit.
	--
	-- naikCharge dinaikkan sebanding (7 -> 14): dia separuh jalan,
	-- dan separuh jalan dari 45 bukan 7.
	naikCharge = 14,
	naikAscend = 45,

	orbCount   = 6,
	runeCount  = 32,
	shardCount = 20,
	boltCount  = 8,

	-- Efek SELURUH LAYAR: letterbox, layar abu-abu saat freeze, bloom,
	-- blur. Dia yang membuat fase freeze terbaca sebagai waktu berhenti
	-- dan bukan cuma sebagai orb yang menghilang.
	--
	-- Ini menyentuh frame siaran, bukan cuma satu avatar. Kalau overlay
	-- TikTok-nya nanti bertabrakan dengan bilah hitamnya, yang dimatikan
	-- `letterbox` di bawah (jadi 0), bukan saklar ini -- warna dan
	-- blur-nya tidak mengambil ruang layar sama sekali.
	layar     = true,
	letterbox = 0.12,

	fovCharge = -12,
	fovSlam   = -20,
	fovImpact = 20,
}

-- --- JALUR KAMERA ADEGAN NOVA ---
--
-- Dikirim ke client bersama pesan "nova"; client yang menjalankannya
-- (kameraNova di KameraClientV2).
--
-- INI MEMBALIK KEPUTUSAN YANG SEMPAT TERTULIS DI FILE INI. Waktu nova
-- baru menggantikan dash, kameranya sengaja dibiarkan jadi kamera
-- sorotan biasa ditambah FOV dan getaran -- alasannya nova terjadi di
-- tempat orangnya berdiri, jadi kamera yang sudah menghadap ke sana
-- tidak perlu diganti. Itu benar untuk nova yang naik 13 stud.
--
-- Pada 45 stud tidak lagi: kamera yang diam di tanah memandang orang
-- setinggi sembilan badan cuma memperlihatkan telapak kakinya. Jadi
-- adegannya sekarang punya EMPAT bidikan yang berurutan, dan tiap
-- bidikan menjawab satu pertanyaan yang berbeda:
--
--   NAIK    kamera RENDAH memandang ke atas, mengorbit 360 derajat
--           sekali penuh selama dia naik. Sudut rendah yang membuat
--           dia terbaca menjulang; orbitnya yang membuat penonton
--           melihat dia dari segala sisi sebelum apa pun terjadi.
--
--           Kameranya IKUT NAIK (naikBawah -> naikAtas) dan itu bukan
--           cuma soal framing: pada stud ke-2 dia sejajar lutut
--           kerumunan, dan orbit di ketinggian itu menembus badan
--           orang yang sedang menari. Naik ke 16 stud membawanya lewat
--           DI ATAS kepala mereka sebelum orbitnya sampai ke sisi
--           belakang.
--
--   DIAM    dia menggantung di puncak, kamera meluncur ke DEPAN
--           wajahnya dan berhenti. Satu-satunya detik tenang di
--           seluruh adegan, dan itu yang membuat bantingan sesudahnya
--           terasa mendadak.
--
--   JATUH   kamera meluncur ke ATAS kepalanya dan memandang ke bawah,
--           jadi dia jatuh MENJAUH dari lensa. Ini yang membuat 45
--           stud terbaca sebagai jarak, bukan sebagai angka.
--
--   LEDAKAN mundur ke shot lebar supaya shockwave, pilar, dan barisan
--           yang berceceran muat dalam satu frame.
--
-- Sesudah itu kamera meluncur balik (`lepas`) ke sorotan biasa yang
-- sudah berjalan di belakang layar, jadi tariannya disorot seperti
-- tier lain -- dan tidak ada satu pun frame yang meloncat.
NOVA.KAMERA = {
	-- --- NAIK ---
	naikRadius  = 26,   -- sejauh ini dari titik berdirinya, stud
	naikBawah   = 2.0,  -- tinggi kamera saat dia baru mulai naik
	naikAtas    = 16,   -- tinggi kamera sesudah naiknya selesai
	naikPutaran = 1,    -- berapa KALI mengelilingi. 1 = 360 derajat pas

	-- Seberapa CEPAT kameranya naik, relatif terhadap orbitnya. 3 =
	-- tinggi penuh dicapai pada sepertiga putaran pertama.
	--
	-- Ini bukan penghalusan selera, ini yang mencegah kamera menembus
	-- badan orang. Orbitnya melingkari titik berdiri avatar nova, dan
	-- avatar nova selalu yang PALING DEKAT kamera (barisan tumbuh ke
	-- arah -Z), jadi separuh putaran pertama lewat di ruang kosong di
	-- depannya -- tapi separuh keduanya lewat DI ATAS barisan. Kepala
	-- avatar biasa ada di sekitar 8 stud.
	--
	-- Kalau tingginya dinaikkan rata sepanjang orbit, di sudut 180
	-- derajat kamera baru sampai 9 stud: satu stud di atas ubun-ubun,
	-- dan satu stud itu habis oleh rambut atau topi. Dengan 3, dia sudah
	-- di 16 stud sebelum sampai ke sisi belakang. Diuji di test_tier.py.
	naikCepat   = 3,

	-- --- DIAM DI PUNCAK ---
	diamRadius = 20,
	diamTurun  = 3,     -- sedikit di bawah matanya, jadi tetap mendongak

	-- --- JATUH ---
	--
	-- atasNaik HARUS di atas puncaknya (naikAscend 45), kalau tidak
	-- "kamera di atas" bohong: di frame pertama dia jatuh, dia justru
	-- berada di ATAS lensa dan yang terlihat cuma dia melintas turun
	-- melewati kamera. 52 = tujuh stud di atas ubun-ubunnya.
	--
	-- atasRadius digeser cukup jauh, bukan tepat di atas kepalanya:
	-- bidikan lurus ke bawah tidak punya cakrawala sama sekali dan
	-- terbaca sebagai peta, bukan sebagai orang yang jatuh. Pada 22
	-- stud, kamera mulai hampir sejajar kepalanya (13 derajat menunduk)
	-- lalu berakhir menunduk 67 derajat waktu dia menghantam tanah --
	-- menunduknya sendiri yang menceritakan jatuhnya.
	atasRadius = 22,
	atasNaik   = 52,

	-- --- LEDAKAN ---
	lebarRadius = 46,
	lebarNaik   = 20,
	lebarMundur = 1.2,  -- detik mundurnya ke shot lebar

	lepas = 1.0,        -- detik meluncur balik ke sorotan biasa
}

-- --- TIGA PALET, DIUNDI TIAP KEDATANGAN ---
--
-- Alasannya sama persis dengan AURA_VFX_IDS: dua orang yang sama-sama
-- kirim 10 koin harus tampil BERBEDA. Satu skema warna yang selalu sama
-- berhenti diperhatikan sesudah beberapa kedatangan, dan yang hilang
-- bukan cuma kebaruan -- hilang juga alasan untuk mengirim lagi ("kali
-- ini dapat yang merah").
--
-- Yang mengundi SERVER, dan hasilnya dikirim ke semua client: kalau tiap
-- client mengundi sendiri, satu orang tampil pink di satu layar dan biru
-- di layar sebelahnya.
--
-- Lima warna per palet karena itu yang dibaca modulnya: orb, rune, dan
-- kristal memutar kelimanya, dan ColorSequence pelanginya memakai
-- kelimanya berurutan. Urutannya BUKAN sekadar gradasi -- warna ke-3
-- jadi warna lampu dan shell, ke-1 dan ke-2 jadi shockwave, jadi taruh
-- yang paling mewakili paletnya di posisi 3.
NOVA.PALET = {
	{ nama = "prisma", warna = {
		{ 255, 120, 220 }, { 120, 200, 255 }, { 180, 120, 255 },
		{ 255, 220, 130 }, { 130, 255, 200 } } },
	{ nama = "inferno", warna = {
		{ 255, 140,  60 }, { 255,  80,  60 }, { 255, 110,  40 },
		{ 255, 205, 100 }, { 180,  40,  40 } } },
	{ nama = "glasir", warna = {
		{ 150, 230, 255 }, { 210, 245, 255 }, {  90, 170, 255 },
		{ 255, 255, 255 }, { 120, 130, 255 } } },
}

-- --- BUNYI ADEGAN NOVA ---
--
-- Daftar DATAR, bukan tabel bertingkat per fase, dan itu yang membuat
-- pelapisan jadi gratis: dua baris dengan `fase` yang sama berbunyi
-- bersamaan. Dentuman ledakannya memang dua lapis -- satu berat di
-- bawah, satu pecah di atasnya -- dan satu berkas saja tidak pernah
-- terdengar seperti ledakan.
--
-- SEMUANYA BAWAAN ROBLOX (rbxasset://sounds/*), dan itu batasan yang
-- disengaja: berkas-berkas itu ikut terpasang di TIAP instalasi, jadi
-- tidak ada kemungkinan "Asset is not approved for the requester" yang
-- pernah membuat swoosh.wav gagal diam-diam di file ini (lihat SFX_TIER).
--
-- Harganya: pilihannya cuma enam berkas. Yang dipakai di bawah semuanya
-- berkas yang SAMA dengan yang sudah dipakai tier lain, dibedakan lewat
-- NADA saja. bass.wav pada 0,30 bukan lagi bass -- dia dentuman; pada
-- 0,50 naik ke 1,15 dia jadi dengungan yang mengisi tenaga. Kalau nanti
-- ada asset audio sendiri, yang diganti cuma `id`-nya.
--
--   fase   kapan dibunyikan: charge / ascend / freeze / impact
--   tunda  detik SESUDAH fase itu mulai. nil = langsung
--   ulang  Looped. Untuk berkas yang lebih pendek daripada fasenya;
--          dihentikan sendiri waktu fase berikutnya mulai
--   nada, nadaAkhir  kalau keduanya ada, nadanya MELUNCUR dari yang
--          pertama ke yang kedua sepanjang fase itu
NOVA.SFX = {
	-- CHARGE: dengungan yang naik pelan. Ini satu-satunya yang looped --
	-- bass.wav jauh lebih pendek dari empat detik, dan hening di tengah
	-- fase mengisi tenaga terbaca sebagai "sudah selesai" padahal
	-- orbnya masih berkumpul.
	--
	-- Nada yang MELUNCUR 0,50 -> 1,15 yang mengerjakan seluruh
	-- pekerjaannya: dengungan yang naik terus-menerus itu satu-satunya
	-- cara memberi tahu telinga bahwa sesuatu sedang dikumpulkan.
	{ fase = "charge", id = "rbxasset://sounds/bass.wav",
	  vol = 0.35, nada = 0.50, nadaAkhir = 1.15, ulang = true },

	-- ASCEND: whoosh naik. Nada di bawah 1 memanjangkannya, jadi dia
	-- menutupi satu setengah detik penuh alih-alih berhenti di tengah.
	{ fase = "ascend", id = "rbxasset://sounds/action_jump.mp3",
	  vol = 0.55, nada = 0.65 },

	-- FREEZE: satu denting rendah. Ping bawaan pada 0,35 tidak lagi
	-- terdengar seperti notifikasi -- dia jadi denting panjang yang
	-- menggantung, dan menggantung itu persis yang sedang terjadi.
	{ fase = "freeze", id = "rbxasset://sounds/electronicpingshort.wav",
	  vol = 0.6, nada = 0.35 },

	-- IMPACT, lapis 1: dentuman berat. bass.wav pada 0,30 turun hampir
	-- dua oktaf dari nada aslinya.
	{ fase = "impact", id = "rbxasset://sounds/bass.wav",
	  vol = 1.0, nada = 0.30 },
	-- IMPACT, lapis 2: pecahnya, di frame yang sama. Yang berat saja
	-- terdengar seperti pintu ditutup; yang pecah saja terdengar ringan.
	{ fase = "impact", id = "rbxasset://sounds/impact_water.mp3",
	  vol = 0.9, nada = 0.45 },

	-- GEMPA: gemuruh barisan yang tersapu, menyusul 0,3 detik sesudah
	-- dentumannya.
	--
	-- Bunyi SENDIRI, bukan dijadikan satu dengan dentuman di atas, dan
	-- itu yang membuat "dia mendarat" dan "panggungnya hancur" terdengar
	-- sebagai DUA kejadian. Dijadikan satu, yang kedua tidak pernah
	-- terdengar sama sekali -- dia tertutup yang pertama.
	--
	-- 0,3 detik juga kira-kira sama dengan telatnya lemparan di server
	-- (SPAWN_SIAP_MAKS), jadi bunyinya jatuh berdekatan dengan badan
	-- yang benar-benar mulai terlempar.
	{ fase = "impact", tunda = 0.3,
	  id = "rbxasset://sounds/action_jump_land.mp3",
	  vol = 0.85, nada = 0.45 },

	-- AFTERSHOCK: gemuruh kedua, sejalan dengan cincin dan petir kedua
	-- di dalam modulnya (task.delay 1,4).
	{ fase = "impact", tunda = 1.4,
	  id = "rbxasset://sounds/impact_water.mp3",
	  vol = 0.55, nada = 0.65 },
}

-- Lama menari sesudah adegannya selesai, detik. Tidak dikirim ke mana pun
-- -- tariannya tarian panggung biasa. Angka ini JANJI yang dijaga
-- test_tier.py: sisa sorotan sesudah nova harus paling tidak sepanjang ini.
NOVA.TARI = 3.0

-- Lama SELURUH adegan, detik. Ditulis sebagai penjumlahan, bukan 10:
-- angka yang ditulis terpisah tertinggal begitu salah satu fase digeser,
-- dan yang membaca ini auraMulai di KAMERA_TIER[3] -- papan aura yang
-- muncul terlalu cepat tersembunyi bersama avatar aslinya.
-- Nomor urut adegan nova. Naik satu tiap kedatangan nova (tier 4), dan cuma
-- dipakai client untuk mencocokkan pesan "nova" dengan model yang
-- sedang dia tahan -- lihat SetAttribute("NovaId") di spawnAvatar.
local novaIdBerikut = 0

local function novaTotal()
	local c = NOVA.CONFIG
	return c.charge + c.ascend + c.freeze + c.slam + c.impact
end

-- SATU-SATUNYA tempat yang menjawab "tier ini nova atau bukan". Alasannya
-- sama dengan adalahRaksasa: jawaban yang ditulis dua kali akan berpisah
-- diam-diam di perubahan berikutnya.
local function adalahNova(tier)
	if not (TIER_ENABLED and NOVA.ENABLED) then return false end
	return (tonumber(tier) or 1) == NOVA.TIER
end

-- --- PANGGUNG BERHENTI SELAMA SINEMATIK ---
--
-- Tidak ada yang di-spawn selama adegannya berlangsung, jadi kamera
-- boleh nempel penuh ke satu orang tanpa ada yang datang di belakangnya
-- dan mencuri perhatian.
--
-- Yang boleh menghentikan panggung CUMA raksasa. Tier 2 datang tiap
-- beberapa detik saat live ramai, dan memberi HAK ITU ke tier 2 berarti
-- antrian gratisan berhenti berjalan sebagian besar waktu.
--
-- Tier 3 IKUT sejak nova menggantikan dash, dan itu perubahan yang
-- disengaja: nova 10 detik menyita seluruh layar (letterbox, warna
-- abu-abu, ledakan setinggi 300 stud), dan avatar gratisan yang muncul
-- di barisan di tengah itu bukan cuma tidak terlihat -- dia menghabiskan
-- slot panggung untuk kedatangan yang memang tidak ada yang melihat.
-- Harganya: tiap 10 koin, antrian gratisan berhenti ~16 detik.
local BEKU_ENABLED   = true
-- Diikatkan ke NOVA.TIER, bukan ditulis sebagai angka: niatnya satu
-- kalimat tentang ADEGAN SINEMATIK YANG PALING MURAH, bukan tentang angka
-- 3. Angka yang ditulis terpisah tertinggal waktu tier-nya bergeser -- dan
-- itu sudah sekali terjadi di file ini (lihat adalahRaksasa).
--
-- Dulu terikat ke GIANT_MIN_TIER (4). Turun ke 3 waktu nova menggantikan
-- dash: nova menyita seluruh layar selama 10 detik, dash tidak.
--
-- Tetap "min", bukan daftar: tier 4 di atasnya ikut terbawa, dan itu
-- memang benar -- raksasa juga tidak boleh diganggu.
local BEKU_MIN_TIER  = NOVA.TIER

-- Tambahan waktu beku SESUDAH sorotannya habis, detik. Jeda napas
-- supaya orang berikutnya tidak muncul di frame yang sama dengan avatar
-- sinematik yang baru saja selesai.
local BEKU_EKOR      = 0.8

-- Batas atas berapa lama panggung boleh beku sekali adegan.
--
-- Pengaman, bukan penyetelan. spotlightMs dihitung dari koin, dan kalau
-- suatu saat KOIN_SPOT_MAX_MUL di .env dinaikkan tanpa sengaja, angka
-- itu langsung jadi lama panggung ini mati. Salah ketik satu digit
-- tidak boleh berarti siaran diam semenit.
-- Sorotan nova (tier 4) sekarang 15 detik + BEKU_EKOR 0,8 = 15,8, jadi 20 masih
-- longgar. Diuji di test_tier.py supaya angka ini tidak diam-diam jadi
-- yang memotong nova kalau fase-fasenya dipanjangkan lagi.
local BEKU_MAKS      = 20

-- --- LANTAI AURA UNTUK YANG BAYAR ---
--
-- Aura tetap diundi, cuma titik terendahnya yang naik. Ini menutup satu
-- lubang yang kelihatan konyol di layar: orang kirim 10 koin, jadi
-- raksasa setinggi tiga orang -- lalu auranya keluar 4%. Seluruh
-- kesannya dibatalkan oleh satu angka.
--
-- Yang gratisan tidak disentuh: tetap 0-1000, tetap boleh dapat 998%.
-- Kalau lantainya dinaikkan untuk semua orang, angka besar berhenti
-- terasa besar.
--
-- --- APA YANG DILEPAS WAKTU ANGKA INI DINAIKKAN ---
--
-- Lantai 550/600 dulu dipilih supaya yang bayar tidak pernah dapat angka
-- memalukan TAPI juga tidak dijamin menang: penonton gratisan masih bisa
-- mengalahkan mereka, dan justru itu yang bikin panggungnya seru.
--
-- 900/999/1000 melepas separuh dari itu dengan sengaja. Tier 2 masih
-- bisa dikalahkan gratisan (900-1000 lawan 0-1000), tapi tier 3 dan 4
-- praktis TIDAK: 999 berarti dua kemungkinan saja, dan 1000 berarti
-- satu. Yang dibeli 10 koin sekarang bukan lagi undian yang bagus --
-- melainkan angka yang pasti.
--
-- Ini keputusan produk, bukan kelalaian, dan ditulis di sini supaya
-- siapa pun yang membaca lantai 999 tahu apa yang ditukar untuk itu.
-- Kalau kontesnya mau dikembalikan, yang diturunkan angka-angka di
-- bawah -- bukan AURA_MAX.
local AURA_LANTAI_T2 = 900   -- Rose
-- Rosa. Di ATAS Rose, walaupun tipis: tier yang lebih mahal tidak boleh
-- punya lantai yang lebih rendah atau sama dengan tier di bawahnya
-- (dijaga test_tier.py). Kalau dua-duanya 900, yang bayar 10 koin tidak
-- dapat satu pun kepastian lebih daripada yang bayar 1.
local AURA_LANTAI_T3 = 950   -- Rosa / tap
local AURA_LANTAI_T4 = 999   -- Bouquet, nova

-- Raksasa diundi di rentangnya SENDIRI: 9.999% atau 10.000%.
--
-- Dulu selalu tepat 10.000. Diubah atas permintaan jadi rentang setipis
-- ini: tetap tidak bisa dicapai siapa pun dengan cara lain, tapi angkanya
-- sekarang benar-benar DIUNDI -- putarannya punya sesuatu untuk ditunggu.
--
-- Angka ini KELUAR dari skala semua orang lain, dan itu seluruh
-- gunanya. Lantai 1000 yang dulu ada di sini secara teknis benar --
-- yang paling mahal tidak boleh punya lantai lebih rendah daripada
-- tier di bawahnya -- tapi di layar dia tidak bercerita apa-apa: 1000%
-- itu angka yang sama yang bisa didapat penonton gratisan yang
-- beruntung, jadi raksasa membayar paling mahal untuk angka yang bukan
-- miliknya sendiri.
--
-- Sepuluh ribu tidak bisa dicapai siapa pun dengan cara lain. Dia
-- bukan "undian yang bagus" lagi, dan memang bukan: yang dibeli 30
-- koin sekarang ANGKA YANG TIDAK ADA DUANYA di panggung.
--
-- Konsekuensinya, ditulis di sini supaya tidak jadi kejutan: dia
-- melewati AURA_MAX. Jadi "langit-langit 1000 berlaku untuk semua
-- orang" sudah tidak benar lagi -- yang benar, undian berhenti di
-- 1000, dan raksasa tidak ikut diundi.
local AURA_RAKSASA_MIN = 9999
local AURA_RAKSASA     = 10000

-- Berapa detik angka raksasa yang sudah mendarat dibiarkan terbaca
-- sebelum papannya dirapikan jadi NAMA SAJA.
--
-- Papan tiga baris di atas kepala setinggi belasan stud itu papan reklame
-- yang menyaingi badannya sendiri kalau dibiarkan selamanya. Tapi putaran
-- angkanya justru yang ditonton -- jadi angkanya tampil, mendarat, sempat
-- dibaca, BARU papannya menyusut jadi satu baris nama.
local AURA_RAKSASA_NAMA_S = 2.5

-- --- AURA VFX YANG MENEMPEL DI BADAN ---
--
-- Beda dari "aura" yang lain di file ini: yang itu ANGKA (0-1000%) di
-- papan atas kepala, yang ini efek partikel sungguhan yang menempel di
-- badan avatarnya.
--
-- Siapa yang dapat: tier 3 (Rosa, aura) DAN tier 4 (Bouquet, nova). Rentang, bukan
-- "ke atas", dan bukan juga lewat besarnya undian.
--
-- Tier 3 dapat juga karena itu yang diminta untuk yang dijual 10 koin --
-- dan sekarang dia dapat DUA undian: palet nova (NOVA.PALET) dan aura
-- ini. Keduanya terpisah, jadi ada sembilan kombinasi tampilan.
--
-- Auranya tidak ikut melayang: selama nova, client menyembunyikan badan
-- aslinya BERSAMA partikelnya (KELAS_MATIKAN), dan salinan yang melayang
-- cuma berisi part badan -- jadi orb dan rune-nya tetap bersih, dan
-- auranya menyala tepat saat avatar aslinya muncul kembali.
--
-- Raksasa (tier 5) TIDAK dapat. Sempat dicoba, lalu dicopot atas
-- permintaan: yang membuat dia terbaca UKURAN badannya, dan aura di badan
-- sebesar itu cuma menyaingi satu-satunya hal yang jadi intinya.
--
-- Kalau mau dicoba lagi, cukup naikkan AURA_VFX_TIER_MAKS ke 5 --
-- pasangAuraVfx sudah memperbesar partikelnya sebanding skala badan, jadi
-- auranya tidak akan jadi titik kecil di dada raksasa 4x.
local AURA_VFX_ENABLED   = true
-- Rosa (3) dan Bouquet/nova (4). Rose (2) sengaja TIDAK: dia cuma skip
-- lane dan cakram biru.
local AURA_VFX_TIER      = 3
local AURA_VFX_TIER_MAKS = 4

-- Diacak satu dari tiga tiap kedatangan.
--
-- Bukan satu aura tetap untuk semua tier 2: dengan tiga pilihan, dua
-- orang yang sama-sama kirim 10 koin tampil berbeda, dan itu memberi
-- alasan untuk mengirim lagi ("kali ini dapat yang merah"). Satu asset
-- yang selalu sama berhenti diperhatikan setelah beberapa kedatangan.
-- `redam` = seberapa jauh efeknya DIKECILKAN supaya avatarnya tetap
-- terbaca. Tanpa ini dua dari tiga aura menutupi badan orangnya, dan
-- yang ditonton jadi partikelnya, bukan orang yang membayar.
--
-- Semua knob-nya PENGALI atau TAMBAHAN terhadap nilai asli asset-nya,
-- bukan angka mutlak: aura yang dibuat orang lain punya skala yang
-- berbeda-beda, dan angka mutlak yang cocok untuk satu asset akan
-- mematikan asset yang lain.
--
--   rate     pengali banyaknya partikel per detik. 0,45 = 45% dari asli
--   tembus   TAMBAHAN transparansi, 0..1. 0,35 = 35% lebih tembus
--            pandang daripada aslinya
--   ukuran   pengali ukuran partikel
--   zOffset  digeser sejauh ini di sumbu kedalaman kamera. NEGATIF =
--            partikelnya digambar DI BELAKANG badan. Ini knob yang
--            paling ampuh untuk "avatarnya ketutupan" -- yang lain cuma
--            menipiskan, yang ini benar-benar memindahkan partikelnya
--            ke belakang orangnya.
--   terang   pengali Brightness untuk lampu yang ikut di dalam asset.
--            Lampu yang terlalu terang memutihkan wajah avatarnya.
--
-- Angka di bawah TITIK AWAL, bukan hasil pengukuran -- saya tidak bisa
-- melihat asset-nya dari sini. Kalau masih ketutupan, turunkan `rate`
-- dan naikkan `tembus`; kalau jadi terlalu tipis, kebalikannya.
--
-- Hijau tidak diredam sama sekali: dia yang tidak dikeluhkan.
local AURA_VFX_IDS = {
	{ nama = "green",  id = "rbxassetid://129577777879366" },
	{ nama = "red",    id = "rbxassetid://12010147091",
	  redam = { rate = 0.45, tembus = 0.35, ukuran = 0.80,
	            zOffset = -1.2, terang = 0.55 } },
	{ nama = "rimuru", id = "rbxassetid://10088609715",
	  redam = { rate = 0.50, tembus = 0.30, ukuran = 0.85,
	            zOffset = -1.0, terang = 0.60 } },
}

-- Naikkan seluruh titik sebuah NumberSequence ke arah 1 (makin tembus).
--
-- Dikerjakan per titik, bukan dengan satu angka datar: bentuk
-- transparansi sepanjang umur partikel (muncul -> pudar) itu yang bikin
-- efeknya tidak terlihat seperti balok, dan menimpanya dengan satu nilai
-- akan membuang bentuk itu.
local function tembuskanSeq(seq, tambah)
	if not tambah or tambah <= 0 then return seq end
	local titik = {}
	for _, k in ipairs(seq.Keypoints) do
		local v = math.clamp(k.Value + (1 - k.Value) * tambah, 0, 1)
		-- Envelope tidak boleh melewati jarak nilai ke tepi 0/1, dan
		-- nilainya barusan digeser mendekat ke 1 -- jadi dia harus ikut
		-- dijepit, kalau tidak Roblox menolak seluruh sequence-nya.
		local env = math.min(k.Envelope, v, 1 - v)
		table.insert(titik, NumberSequenceKeypoint.new(k.Time, v, env))
	end
	return NumberSequence.new(titik)
end

local function skalaSeq(seq, f)
	if not f or f == 1 then return seq end
	local titik = {}
	for _, k in ipairs(seq.Keypoints) do
		table.insert(titik,
			NumberSequenceKeypoint.new(k.Time, k.Value * f, k.Envelope * f))
	end
	return NumberSequence.new(titik)
end

-- Diterapkan SEKALI pada salinan induk waktu asset dimuat, bukan tiap
-- kedatangan: hasilnya sama persis, dan yang per-kedatangan tinggal
-- Clone yang gratis.
local function redamEfek(e, r)
	if not r then return end

	if e:IsA("ParticleEmitter") then
		-- pcall per properti, bukan satu pcall untuk semuanya: emitter
		-- dari asset orang lain kadang punya properti yang dikunci, dan
		-- satu yang gagal tidak boleh membatalkan peredaman yang lain.
		pcall(function() if r.rate then e.Rate = e.Rate * r.rate end end)
		pcall(function() e.Transparency = tembuskanSeq(e.Transparency, r.tembus) end)
		pcall(function() e.Size = skalaSeq(e.Size, r.ukuran) end)
		pcall(function() if r.zOffset then e.ZOffset = e.ZOffset + r.zOffset end end)
	elseif e:IsA("Light") then
		pcall(function() if r.terang then e.Brightness = e.Brightness * r.terang end end)
	elseif e:IsA("Fire") or e:IsA("Smoke") then
		pcall(function() if r.ukuran then e.Size = e.Size * r.ukuran end end)
		pcall(function() if r.tembus then e.Opacity = e.Opacity * (1 - r.tembus) end end)
	end
end

-- Sampai kapan efeknya menempel.
--
-- 0 = SEUMUR AVATARNYA: dia hilang waktu avatarnya dihapus panggung,
-- tidak sedetik pun sebelum itu. Ini yang dipakai, dan alasannya bukan
-- kemudahan.
--
-- Kalau efeknya dibikin ada masa habisnya, ada rentang waktu di mana
-- avatar orang yang BARU BAYAR masih berdiri di panggung tapi sudah
-- kelihatan sama persis seperti yang gratisan. Dari sisi dia, uangnya
-- sudah keluar dan efeknya dicabut sementara dia masih ditonton -- itu
-- hasil terburuk dari semua pilihan yang ada di sini.
--
-- Umur avatar sendiri sudah dibatasi (DELETE_AFTER), dan yang dapat
-- efek ini cuma sebagian dari slot yang jumlahnya tetap. Jadi tidak ada
-- yang bisa menumpuk tanpa batas -- batasnya sudah dijaga di tempat
-- lain, dan tidak perlu dijaga dua kali.
--
-- Angka > 0 = efeknya dilepas setelah sekian detik. Disediakan kalau
-- ternyata partikelnya terlalu berat waktu panggung penuh.
local AURA_VFX_LAMA = 0

-- Di bagian badan mana efeknya ditempel, urutan pencarian.
--
-- HumanoidRootPart dulu: dia di tengah badan dan tidak ikut animasi
-- tangan, jadi efeknya tidak ikut terayun waktu avatarnya menari.
local AURA_VFX_BAGIAN = { "HumanoidRootPart", "Torso", "UpperTorso", "Head" }

-- --- LAYAR SINEMATIK UNTUK ROSA (tier 3) ---
--
-- Versi ringan dari layar nova: bilah hitam atas-bawah (letterbox) yang
-- masuk dan keluar selama sorotannya. Dijalankan client (layarSinema di
-- KameraClientV2); yang dikirim cuma pilihannya.
--
-- TIGA pilihan, ganti lewat MODE_ROSA:
--
--   "tipis"  A. letterbox SETENGAH tebal nova, tanpa apa pun lagi
--   "warna"  B. A + layar sedikit lebih hangat dan berpendar
--   "penuh"  C. letterbox setebal nova + warna + sekejap layar abu-abu
--               dan buram di tengah sorotan, seperti fase freeze nova
--   "mati"      tanpa efek layar
--
-- Bawaannya "tipis", dan itu bukan selera. Rosa datang dari TIGA jalan
-- (Rosa, 1.000 tap, tiap 10 Rose dalam satu combo) dengan jeda sorotan
-- cuma 6 detik. Efek layar yang lebih berat terasa seperti layar yang
-- gelisah saat live ramai, menutupi overlay TikTok di atas dan bawah, dan
-- membuat nova (Bouquet, 30 koin) kehilangan satu-satunya hal yang
-- membedakan layarnya dari Rosa (10 koin). Coba "warna" dan "penuh" di
-- siaran, lalu pilih yang tidak mengganggu.
--
-- TANPA slow-mo, sengaja: tarian semua avatar disamakan terus-menerus di
-- client, dan satu avatar yang diperlambat akan dilawan penyamaan itu --
-- hasilnya tarian yang tersendat, bukan gerak lambat.
--
-- Satu TABEL, bukan konstanta lepas -- batas 200 variabel lokal, lihat
-- catatan di PLATE.
local LAYAR = {}

-- "warna" sejak sorotan Rosa jadi 10 detik: jedanya ikut naik ke 12 detik,
-- jadi alasan utama "tipis" -- layar yang berkedip tiap beberapa detik --
-- sudah jauh berkurang.
LAYAR.MODE_ROSA = "warna"

-- Isi tiap pilihan.
--
--   letterbox  tinggi tiap bilah, pecahan tinggi layar. Nova 0,12.
--   warna      layar sedikit lebih hangat dan berpendar
--   kilat      kilatan cahaya tepat saat angka auranya MENDARAT -- dia
--              yang membuat detik mendarat terasa sebagai puncak adegan
--   garis      garis tepi avatarnya BERDENYUT selama sorotan
--   beku       sekejap abu-abu + buram di tengah sorotan
--
-- Masuk 0,5 detik dan keluar 0,5 detik, lebih cepat dari nova (0,8 +
-- 0,6): sorotan Rosa cuma 4 detik, dan waktu masuk-keluar nova memakan
-- sepertiganya.
LAYAR.PILIHAN = {
	tipis = { letterbox = 0.06, masuk = 0.6, keluar = 0.6, garis = true },
	warna = { letterbox = 0.08, masuk = 0.6, keluar = 0.6, garis = true,
	          warna = true, kilat = true },
	penuh = { letterbox = 0.12, masuk = 0.6, keluar = 0.6, garis = true,
	          warna = true, kilat = true, beku = true },
}

-- --- PANGGUNG ROSA: JALUR KAMERA + LATAR SINEMATIK ---
--
-- Rosa punya jalur kamera SENDIRI, seperti nova (NOVA.KAMERA), yang menimpa
-- kamera sorotan biasa selama adegannya. Dijalankan client (kameraRosa dan
-- panggungRosa di KameraClientV2); di sini cuma angkanya.
--
-- Yang dijual adegan ini PENAMPILAN orangnya -- badan, kulit, pakaian --
-- jadi kameranya dekat dan memperlihatkannya dari segala sisi:
--
--   0,0 - 2,6   DARI BAWAH   kamera rendah dekat lantai memandang kakinya,
--                            lalu naik dan mendekat sampai setinggi dada
--   2,6 - 6,0   KELILING     satu putaran penuh di jarak dekat (7 stud) --
--                            depan, samping, belakang pakaiannya
--   6,0 - 8,6   POTRET       naik ke wajah, lalu dorong masuk pelan. Angka
--                            aura berputar di sini dan MENDARAT di 8,5
--   8,6 - 10,0  LEPAS        meluncur balik ke kamera sorotan biasa
--
-- LATAR SINEMATIK selama adegan, semuanya LOKAL di tiap client:
--
--   - panggung sekitarnya diredupkan, dan orangnya disiram lampu sorot
--     dari atas plus cahaya dari belakang yang memisahkan siluetnya
--   - partikel cahaya melayang pelan di sekitarnya
--   - avatar tetangga dalam radius `sepi` DISEMBUNYIKAN sementara
--
-- Yang terakhir bukan hiasan. Jarak antar-slot cuma 8 stud, dan kamera
-- yang mengelilingi di jarak 7 stud lewat PERSIS di dalam badan tetangga
-- kanan-kiri dan belakangnya. Tanpa disembunyikan, separuh putaran yang
-- terlihat cuma bidang warna dari dalam badan orang lain.
--
-- Semua angka jarak dan tinggi dalam STUD, kecuali yang disebut pecahan:
-- pecahan dihitung terhadap tinggi badan avatarnya sendiri, jadi avatar
-- pendek dan tinggi sama-sama terbingkai utuh.
local ROSA = {}

ROSA.JALUR = {
	-- Lama tiap bidikan, detik. Jumlahnya HARUS muat di sorotan Rosa
	-- (SPOTLIGHT_MS_TIER3, 10 detik) -- dijaga test_tier.py.
	naik   = 2.6,
	orbit  = 3.4,
	potret = 2.6,
	lepas  = 1.4,
	masuk  = 0.4,   -- meluncur dari kamera biasa ke jalur ini

	-- DARI BAWAH
	naikJauh  = 10,    -- mulai sejauh ini di depannya
	naikBawah = 0.6,   -- dan serendah ini dari lantai
	naikBidik = 0.30,  -- memandang setinggi ini (pecahan badan): kaki

	-- KELILING. radius = "jangan terlalu jauh".
	radius      = 7,
	tinggiOrbit = 0.55,  -- pecahan badan: setinggi dada
	bidikOrbit  = 0.55,
	orbitNaik   = 1.2,   -- naik sedikit di tengah putaran, lalu turun
	putaran     = 1,     -- BULAT: pulang ke depan tanpa loncatan

	-- POTRET
	potretJauh   = 9,     -- mundur sedikit supaya papan auranya masuk
	potretDekat  = 6.5,   -- lalu dorong masuk pelan
	potretTinggi = 0.80,  -- pecahan badan
	potretBidik  = 0.8,   -- stud DI ATAS kepalanya: kepala + papan aura

	-- LATAR
	sepi  = 14,    -- tetangga dalam radius ini disembunyikan
	redup = 0.7,   -- ExposureCompensation diturunkan sebanyak ini
}

-- Tiga tema warna latarnya, DIUNDI tiap Rosa -- alasannya sama dengan
-- NOVA.PALET: dua orang yang sama-sama kirim Rosa harus tampil berbeda.
-- Triplet RGB: lampu sorot, cahaya belakang, partikel, dan warna layar.
ROSA.TEMA = {
	{ nama = "emas", sorot = { 255, 214, 150 }, belakang = { 255, 160, 70 },
	  partikel = { 255, 226, 160 }, layar = { 255, 236, 214 } },
	{ nama = "neon", sorot = { 255, 150, 230 }, belakang = { 90, 200, 255 },
	  partikel = { 210, 160, 255 }, layar = { 246, 226, 255 } },
	{ nama = "es",   sorot = { 200, 228, 255 }, belakang = { 110, 160, 255 },
	  partikel = { 225, 242, 255 }, layar = { 226, 238, 255 } },
}

-- --- KAMERA SINEMATIK ---
--
-- Selama sorotan tier 3 dan 4, kamera berhenti mengayun dan MENGORBIT
-- penuh mengelilingi orangnya. Tier 2 TIDAK mengorbit -- dia cuma
-- menahan dekat. Bedanya sengaja di jenis gerakan, bukan di lamanya:
-- dua gerakan yang sama dengan durasi berbeda tidak terbaca sebagai dua
-- tingkat, cuma sebagai satu tingkat yang kadang lebih panjang.
--
-- Yang memutuskan mengorbit atau tidak field `orbit` dari /api/next,
-- bukan angka di sini.
--
-- Perpindahan masuk-keluar mode ini TIDAK meloncat: sudut kameranya
-- disimpan sebagai satu angka yang terus dijalankan, dan yang berganti
-- cuma KECEPATAN putarnya (lihat gelung RenderStepped di client).
local SINEMA_ENABLED = true
local SINEMA_ORBIT_S = 14    -- lama satu putaran penuh, detik

-- Sengaja TIDAK lebih dekat dari CAMERA_BACK (-11).
--
-- Godaannya merapat, karena adegan berbayar "harusnya" lebih intim.
-- Yang membuat itu salah bukan badannya -- titik pandang kamera ikut
-- naik bersama dia (lihat ikutiFokus), jadi sedekat apa pun dia tetap
-- di tengah frame. Yang butuh jarak KERUMUNAN DI BAWAHNYA: seluruh
-- alasan mengangkat dia 13 stud adalah supaya penonton melihat dia
-- terpisah dari barisan orang lain, dan barisan itu harus ikut masuk
-- frame untuk perbandingannya ada.
local SINEMA_BACK    = -12
local SINEMA_UP      = 5.5

-- ============ KAMERA ============
--
-- Cuma satu gerakan: mengayun kiri-kanan mengitari titik fokus.
-- Titik fokusnya avatar yang terakhir datang, dan kamera selalu
-- memandang ke situ.
-- Diperdekat dari -18/5. Yang datang harus mengisi frame, bukan berdiri
-- sebagai titik kecil di tengah panggung -- dan papan aura di atas
-- kepalanya baru kebaca kalau kameranya sedekat ini.
--
-- Jangan lebih dekat dari sekitar -8: baris kerumunan berjarak
-- SPACING_Z = 8, jadi kamera yang masuk lebih dekat dari itu berakhir
-- DI DALAM badan avatar yang berdiri di depan si fokus.
local CAMERA_BACK      = -11   -- jarak mundur (negatif = di belakang)

-- Tinggi kamera saat MERAPAT (zoom masuk).
--
-- Diturunkan 4 -> 2.5. Kamera yang duduk tinggi harus MENUNDUK untuk
-- memandang titik fokusnya, dan sudut tunduk itu yang memotong kaki:
-- badan avatar jadi miring di frame, kepalanya di tengah, telapaknya
-- keluar lewat tepi bawah. Dari 2,5 sumbu pandangnya nyaris mendatar --
-- avatarnya berdiri tegak di layar, utuh dari kepala sampai kaki.
local CAMERA_UP        = 2.5

-- Tinggi kamera saat MUNDUR PENUH (zoom keluar).
--
-- Dua angka, bukan satu, karena dua jarak itu mengerjakan dua hal yang
-- berbeda -- dan satu ketinggian tidak bisa melayani keduanya:
--
--   dekat  yang penting SATU ORANG utuh. Kamera harus rendah, hampir
--          sejajar mata, kalau tidak kakinya terpotong.
--   jauh   yang penting KERUMUNANNYA. Barisan berdiri sejajar dan
--          sama tinggi, jadi dari ketinggian mata yang terlihat cuma
--          baris paling depan -- sisanya bersembunyi persis di
--          belakang badan mereka. Kamera harus naik dan menunduk
--          supaya kepala baris kedua, ketiga, keempat muncul di atas
--          bahu baris di depannya.
--
-- Perpindahannya ikut zoom, jadi tidak ada gerakan tambahan yang harus
-- dijadwalkan: dia naik sambil mundur, dan turun lagi sambil merapat.
local CAMERA_UP_JAUH   = 7

-- Tinggi kamera saat mundur penuh SELAMA ADA RAKSASA BERDIRI.
--
-- Yang dikeluhkan: kepala raksasa tidak terlihat waktu panggung
-- menjalankan kedatangan biasa -- yang gratisan menari di depan, dan
-- raksasa di belakang mereka terpotong di tepi atas frame.
--
-- Sebabnya SUDUT TUNDUK, bukan jaraknya. Kamera duduk di 7 stud dan
-- membidik 3,2 stud dari jarak 11 stud, jadi dia menunduk 19 derajat --
-- dan 19 derajat itu langsung dipotong dari ruang di atas frame. Kepala
-- raksasa 4x ada di sekitar 20 stud, 29 stud di depan kamera (11 ke
-- titik fokus + GIANT_Z 18): 29 derajat di atas garis pandang, ditambah
-- 19 derajat tunduk = 48, jauh di luar setengah-FOV 35.
--
-- 3,5 stud membuat tunduknya tinggal 1,6 derajat, dan kepalanya masuk
-- di 31 derajat -- sisa empat derajat itu jatah topi dan rambut yang
-- menjulang (sekitar dua stud pada skala 4).
--
-- YANG DITUKAR UNTUK ITU, supaya tidak ditemukan sebagai kejutan:
-- seluruh gunanya CAMERA_UP_JAUH adalah duduk DI ATAS kepala barisan
-- (sekitar 5,8 stud) supaya baris kedua dan ketiga muncul di atas bahu
-- baris depannya. Di 3,5 stud kamera berada DI BAWAH garis kepala itu,
-- jadi barisan belakang kembali bersembunyi di belakang baris depan.
--
-- Bidikan kameranya TIDAK ikut dinaikkan, walaupun menaikkannya
-- meratakan sudut tunduk yang sama tanpa menurunkan kamera sama
-- sekali. Alasannya: titik bidik yang sama dipakai waktu kamera sedang
-- MERAPAT, dan di jarak 5 stud selisih tiga stud itu 45 derajat --
-- kedatangan biasa akan dibidik dari bawah, kakinya jauh di luar tepi
-- frame. Tinggi kamera aman untuk itu karena dia ikut diskalakan zoom;
-- titik bidiknya tidak.
--
-- Makanya angka ini TIDAK menggantikan CAMERA_UP_JAUH, cuma dipakai
-- selama ada raksasa. Tanpa raksasa di panggung tidak ada satu pun
-- frame yang berubah; begitu ada, panggung memang berhenti bercerita
-- tentang kedalaman barisan dan mulai bercerita tentang dia.
local CAMERA_UP_JAUH_GIANT = 3.5

-- Setinggi apa kamera MEMANDANG, diukur dari lantai.
--
-- Ini bukan tempat avatarnya berdiri (itu BASE_Y) -- ini titik yang
-- ditaruh kamera di tengah layar. Dulu keduanya dipakai angka yang
-- sama, dan itu salahnya: BASE_Y = 5 kira-kira setinggi KEPALA avatar,
-- jadi yang duduk di tengah frame kepalanya dan kakinya jatuh di bawah
-- tepi layar -- apalagi waktu zoom sedang merapat.
--
-- 3,2 kira-kira setinggi dada. Dari situ kepala dan telapak kaki
-- berjarak sama dari tengah, jadi dua-duanya masuk.
local CAMERA_FOKUS_Y   = 3.2
-- Diturunkan 22 -> 8.
--
-- Dua puluh dua derajat itu hampir seperempat lingkaran bolak-balik
-- tiap sembilan detik, dan di layar penuh itu terbaca sebagai kamera
-- yang gelisah -- bukan sebagai panggung yang hidup. Delapan derajat
-- masih cukup untuk membuat gambarnya tidak beku, tapi tidak lagi
-- menyeret mata penonton ke kiri dan ke kanan sepanjang siaran.
--
-- Ayunan bukan lagi satu-satunya gerakan sejak ada zoom di bawah, jadi
-- dia memang tidak perlu sebesar dulu. Diturunkan lagi 8 -> 5 bersama
-- SPAWN_LURUS di bawah: dua-duanya menyerang keluhan yang sama, yaitu
-- avatar yang datang dilihat dari sudut, bukan dari depan.
local CAMERA_SWEEP_DEG = 5     -- lebar ayunan, derajat ke kiri dan kanan
local CAMERA_SWEEP_S   = 9     -- lama satu ayunan penuh (kiri-kanan-kiri)
local CAMERA_MOVE_S    = 0.8   -- lama kamera berpindah ke fokus baru

-- --- ZOOM: merapat waktu ada yang datang, lalu mundur lagi ---
--
-- Tiap kedatangan, kamera mulai DEKAT lalu ditarik mundur ke jarak
-- biasa. Ini yang menggantikan ayunan lebar sebagai sumber gerakan:
-- ayunan menggerakkan seluruh gambar terus-menerus (melelahkan), zoom
-- bergerak sekali per kedatangan dan berhenti (bercerita).
--
-- Urutan yang dirasakan penonton: wajah orangnya dulu, baru panggung
-- tempat dia berdiri. Kebalikannya -- mundur dulu lalu merapat -- juga
-- gerakan, tapi dia menyembunyikan orangnya justru di detik dia datang.
--
-- Cuma dipicu kedatangan BARU. Pesan "ikut" yang mengejar avatar
-- melayang tidak menyentuh ini; kalau ikut, zoom-nya akan diulang tujuh
-- kali per detik dan kamera tidak pernah sempat mundur.
local ZOOM_ENABLED = true

-- Sedekat apa awalnya, sebagai pecahan dari jarak biasa. 0.45 = mulai
-- di 45% jarak normal (kira-kira setengah badan mengisi frame).
--
-- Jangan di bawah ~0.3: pada CAMERA_BACK -11 itu berarti 3,3 stud, dan
-- di jarak segitu kamera sudah masuk ke dalam kepala avatar yang
-- berdiri di depan si fokus.
local ZOOM_MASUK = 0.45

-- Berapa lama dia MENAHAN dekat sebelum mulai mundur, detik.
--
-- Ada supaya "zoom in lalu zoom out" benar-benar terasa dua gerakan.
-- Tanpa jeda ini keduanya menyatu jadi satu tarikan mundur, dan bagian
-- dekatnya -- yang justru gunanya -- lewat sebelum sempat dilihat.
--
-- Diturunkan 1,6 -> 1,0, dan itu bukan selera: papan aura di atas
-- kepala butuh AURA_ROLL (3 detik) untuk angkanya berputar naik, dan
-- selama kamera masih merapat papan itu berada di luar frame atas.
-- Menahan terlalu lama berarti undian yang jadi inti panggung ini lewat
-- tanpa terlihat. Satu detik cukup untuk wajahnya terbaca; sisanya
-- jatah papan.
local ZOOM_TAHAN = 1.0

-- Lama mundurnya, detik. Ini yang dipakai tier 1 dan 2.
--
-- Sempat 2,8 lalu dipercepat jadi 1,8 supaya kamera sudah di jarak
-- penuh pada detik 2,8, tepat sebelum putaran angkanya mendarat di
-- detik 3,0. Sekarang diperlambat lagi jadi 3,2 karena mundur secepat
-- itu terbaca sebagai sentakan, bukan gerakan kamera.
--
-- KONSEKUENSINYA, dan ini bukan tebakan: selama kamera masih merapat,
-- papan aura di atas kepala berada di luar frame ATAS. Dengan tahan 1,0
-- + mundur 3,2 kamera baru sampai jarak penuh di detik 4,2, sementara
-- putaran angkanya (AURA_ROLL) mendarat di detik 3,0 -- jadi sebagian
-- putaran itu lewat sebelum papannya masuk frame.
--
-- Kalau ternyata angkanya jadi kurang kebaca, yang diturunkan
-- ZOOM_TAHAN (1,0 -> 0,5), BUKAN angka ini: yang dikeluhkan mundurnya
-- yang menyentak, dan menahan lebih singkat memindahkan waktu itu ke
-- gerakan yang justru diminta lebih lambat.
local ZOOM_KELUAR = 3.2

-- Lama mundurnya untuk RAKSASA (tier 5), detik.
--
-- Dipisah dari angka di atas: raksasa punya gerakan naik-turun yang
-- paling besar dari semua tier (naikAmp di KAMERA_TIER), dan mundur
-- yang kelamaan bertabrakan dengan itu -- dua gerakan besar sekaligus,
-- dan yang terlihat cuma kamera yang tidak bisa diam.
local ZOOM_KELUAR_GIANT = 1.8

-- --- PARAMETER KAMERA PER TIER ---
--
-- Satu tabel, bukan konstanta tersebar: keempat tier sekarang punya
-- bentuk adegan yang berbeda, dan angka yang berserakan membuat
-- "kenapa tier 3 terasa sama seperti tier 2" jadi pertanyaan yang harus
-- dijawab dengan membaca enam tempat.
--
--   masuk   SEDEKAT APA rapatan awalnya, sebagai pecahan jarak penuh.
--           nil = pakai ZOOM_MASUK (0,45) seperti tier lain. Dinaikkan
--           cuma oleh tier yang badannya tidak muat di jarak sedekat
--           itu -- raksasa; lihat [4].
--   tahan   berapa lama menahan dekat sebelum mundur, detik
--   keluar  lama mundurnya, detik
--   maks    MUNDUR SAMPAI SEJAUH APA, sebagai pecahan jarak penuh.
--           1.00 = sejauh biasa. Di bawah 1 = berhenti lebih dekat --
--           ini yang bikin adegan berbayar tetap terasa "dekat" tanpa
--           kameranya menempel.
--   arcDeg  seberapa jauh kamera menyimpang KE SAMPING dari depan,
--           derajat. Ini batas keras: kamera bergerak di dalam kerucut
--           depan sebesar +/- angka ini dan tidak pernah lebih.
--   arcPutar berapa kali dia menyapu kiri-kanan-pulang selama adegan.
--   naikAmp seberapa jauh kamera naik lalu turun lagi selama adegan,
--           stud. Puncaknya di tengah adegan, pulang ke nol di akhir.
--   naikPutar berapa GUNDUKAN naik-turun itu selama adegan.
--           1 = naik lalu pulang (satu gundukan, ini yang lama).
--           2 = naik, pulang, TURUN di bawah tinggi biasa, pulang lagi.
--           Selalu bilangan bulat: kalau tidak, adegannya berakhir di
--           tinggi yang bukan tinggi biasa, dan pergeseran itu diwarisi
--           kedatangan berikutnya.
--   tunda   berapa lama putaran angka aura ditahan sebelum mulai,
--           detik. Lihat penjelasan panjang di bawah tabel.
--   roll    lama putaran angka auranya, detik. Biasanya AURA_ROLL;
--           tier yang sorotannya pendek memakai yang lebih pendek,
--           supaya angkanya MENDARAT sebelum kameranya pergi. Uji di
--           test_tier.py menjaga auraMulai + tunda + roll <= lama
--           sorotan.
--   auraMulai  berapa detik SERVER menahan pesan aura sebelum dikirim.
--           Beda dari `tunda`: tunda menahan putaran angkanya, tapi
--           papannya sendiri langsung muncul. Ini menahan papannya
--           juga -- dipakai nova, yang avatar aslinya (beserta papan
--           apa pun yang menempel padanya) disembunyikan client selama
--           adegannya berlangsung. nil = 0.
--
-- --- DENYUT ZOOM (masuk, mundur, MASUK LAGI) ---
--
-- Zoom dasarnya cuma satu gerakan: masuk saat datang, lalu mundur.
-- Ketiga angka di bawah menambahkan rapatan KEDUA di tengah-akhir
-- adegan, jadi bentuknya jadi masuk -> mundur -> masuk lagi -> mundur.
--
--   denyutDalam  seberapa dalam rapatan itu, pecahan jarak saat itu.
--                0 = tidak ada denyut sama sekali (semua tier sekarang;
--                mesinnya dibiarkan untuk dicoba lagi).
--                0.35 = merapat sampai 35% lebih dekat dari jaraknya.
--                Batas atasnya: maks x (1 - denyutDalam) tidak boleh
--                lebih kecil dari ZOOM_MASUK, kalau tidak rapatannya
--                dipotong DENYUT_MIN di client. Diuji di test_tier.py.
--   denyutMulai  kapan denyutnya mulai, pecahan lama adegan. 0.42 =
--                sesudah zoom dasarnya selesai mundur. Menabrakkan
--                keduanya bikin gerakannya saling membatalkan -- yang
--                terlihat cuma kamera yang ragu-ragu.
--   denyutUlang  berapa kali merapat di dalam jendela itu. 1 = sekali.
--
-- Kameranya TETAP MEMBIDIK avatarnya selama denyut: yang berubah cuma
-- jaraknya. Tingginya ikut diskalakan bersama jarak (lihat gelung
-- render di client), jadi sudut tunduknya tidak berubah waktu merapat
-- -- kalau tidak, tiap rapatan ikut memotong kakinya.
--
-- ORBIT SUDAH TIDAK DIPAKAI, begitu juga jalur tiga sudut milik raksasa
-- (serong kiri -> serong kanan -> belakang) yang sempat ada di sini.
--
-- Keduanya membawa kamera ke SAMPING lalu ke BELAKANG avatarnya, dan
-- dari sana yang terlihat cuma punggung: wajah, papan aura, dan border
-- semuanya menghadap ke arah lain. Panggung ini dibangun untuk ditonton
-- dari depan, jadi gerakan adegannya sekarang dikurung di kerucut depan
-- -- zoom masuk-keluar, geser kiri-kanan, naik-turun, dan itu saja.
--
-- Batas terlebar +/-26 derajat, dipilih supaya tidak pernah mendekati
-- samping (90 derajat). Di 26 derajat wajah dan papan auranya masih
-- menghadap kamera sepenuhnya.
--
-- Yang membedakan tier sekarang BENTUK adegannya, bukan lamanya:
--   tier 2  Rose: paling tenang, 3 detik, seperempat sapuan kecil
--   tier 3  Rosa: kamera PELAN, mundur panjang, setengah sapuan, satu gundukan
--   tier 4  selama nova (10 detik pertama) kamera dikemudikan TierNova
--           lewat callback client -- FOV, getaran, dan bidikan yang naik
--           mengikuti badannya; tabel di bawah cuma mengatur sorotan
--           tarian 3 detik sesudah adegannya selesai
--   tier 5  mundur penuh, naik-turun paling jauh
-- --- MUNCUL UTUH, BUKAN BERTAHAP ---
--
-- Masalahnya: avatar datang POLOS dulu, beberapa detik kemudian
-- rambutnya muncul, lalu bajunya. Terlihat seperti avatarnya rusak.
--
-- Sebabnya bukan di kode ini. CreateHumanoidModelFromDescription
-- membuat rig-nya seketika, tapi isinya cuma RUJUKAN -- MeshId rambut,
-- TextureId baju. File-nya sendiri baru diunduh dari CDN Roblox oleh
-- TIAP PENONTON, saat modelnya sudah kelihatan di layar mereka. Jadi
-- urutan yang terlihat itu urutan kedatangan file-nya.
--
-- Karena unduhannya terjadi di client, obatnya juga harus di client:
-- dia menyembunyikan avatar yang baru datang, menunggu asetnya siap
-- (ContentProvider:PreloadAsync), lalu memunculkannya utuh.
--
-- BATAS WAKTUNYA SENGAJA PENDEK. Ini pertukaran langsung: makin lama
-- menunggu makin kecil peluang masih ada yang belum siap, tapi
-- avatarnya juga makin telat muncul -- dan sorotan tier 2 cuma 3 detik.
-- 0,6 detik menangkap sebagian besar aset yang sudah ada di cache atau
-- dekat, tanpa memakan porsi sorotan yang terasa.
--
-- Yang lewat dari batas ini tetap dimunculkan, apa adanya. Menunggu
-- sampai benar-benar siap berarti satu aset yang gagal diunduh bikin
-- avatarnya TIDAK PERNAH muncul -- jauh lebih buruk daripada popping.
-- --- KARAKTER PENONTON DISEMBUNYIKAN ---
--
-- Siaran ini direkam dengan MASUK ke room-nya lalu meng-capture layar.
-- Masalahnya: begitu masuk, Roblox men-spawn avatar KAMU di panggung --
-- dan avatar itu ikut terekam, berdiri di tengah kerumunan dengan nama
-- di atas kepalanya. Kameranya scriptable jadi dia tidak selalu di
-- tengah frame, tapi dia ADA, dan penonton TikTok tidak punya cara tahu
-- kenapa ada satu orang yang tidak pernah menari.
--
-- Yang dikerjakan client (lihat sembunyikanPenonton di
-- KameraClientV2), dan SEMUANYA lokal -- tidak ada satu pun yang
-- mengubah apa yang dilihat orang lain:
--
--   1. seluruh badannya ditembuskan (LocalTransparencyModifier)
--   2. BAYANGANNYA dimatikan. Ini yang paling gampang terlewat: part
--      yang ditembuskan secara lokal TETAP menjatuhkan bayangan, dan
--      bayangan orang yang tidak ada di lantai panggung justru lebih
--      aneh daripada orangnya sendiri
--   3. nama dan health bar bawaannya dimatikan
--   4. badannya di-anchor lalu CanCollide dimatikan -- urutannya
--      begitu, bukan sebaliknya: CanCollide yang dimatikan duluan bikin
--      dia jatuh menembus lantai sampai FallenPartsDestroyHeight, lalu
--      Roblox men-spawn-nya lagi, dan begitu terus
--   5. aksesori yang baru diunduh belakangan (rambut, topi berpartikel)
--      ikut disembunyikan, dan semuanya dipasang ulang tiap respawn
--
-- Berlaku untuk SIAPA PUN yang masuk, bukan cuma kamu: penonton yang
-- iseng join juga tidak boleh muncul di siaran.
local SEMBUNYI_PENONTON = true

local SPAWN_SIAP      = true
local SPAWN_SIAP_MAKS = 0.6

-- PRA-MUAT: model avatar dikirim ke semua penonton SELAGI TERSEMBUNYI
-- (ReplicatedStorage) selama ini, detik, baru dipindah ke panggung.
--
-- Masalah yang ditutup: "kakinya tidak ada" atau "rambutnya telat
-- muncul". File mesh dan teksturnya diunduh TIAP PENONTON dari CDN
-- Roblox, dan unduhan itu baru mulai saat modelnya sampai. Client
-- menahan avatarnya paling lama SPAWN_SIAP_MAKS (0,6 detik) -- avatar
-- yang asetnya belum pernah dimuat tidak sempat, dan muncul bolong.
--
-- Kenapa bukan SPAWN_SIAP_MAKS saja yang dinaikkan: angka itu dipakai
-- SESUDAH avatarnya tercatat di panggung. Pesan kamera, papan aura, dan
-- jadwal gempa nova sudah terkirim -- menahan badannya lebih lama berarti
-- angka aura berputar di atas badan yang belum terlihat, dan barisan
-- tersapu gempa sebelum nova-nya menghantam tanah.
--
-- Dengan pra-muat, tunggunya dipindah ke SEBELUM semua itu: tidak ada satu
-- pun pesan yang dikirim sampai modelnya masuk panggung, jadi seluruh
-- jadwal di belakangnya tetap sama persis -- cuma bergeser bersama.
-- Harganya: tiap avatar muncul sekian detik lebih lambat dari sebelumnya.
--
-- ReplicatedStorage direplikasi utuh ke semua client, streaming menyala
-- atau tidak. 0 = matikan pra-muat.
local SPAWN_PRAMUAT_S = 1.5
local SPAWN_SIAP_FADE = 0.12

-- Ditaruh di ATAS KAMERA_TIER, bukan di dekat kode spawn yang memakainya:
-- auraMulai tier 4 (nova) di bawah menjumlahkannya (nova baru mulai sesudah
-- client selesai menunggu aset), dan Lua membaca file ini dari atas ke
-- bawah -- konstanta yang dideklarasikan sesudah tabelnya nil di dalam
-- tabel itu, tanpa satu pun error yang memberitahu.

local KAMERA_TIER = {
	-- Tier 1 tidak punya adegan: dia cuma dapat zoom masuk-keluar biasa
	-- dan mundur sampai jarak penuh. Busurnya 0 -- ayunan panggung yang
	-- biasa sudah menggerakkan gambarnya.
	[1] = { tahan = 1.0, keluar = ZOOM_KELUAR,       maks = 1.00,
		arcDeg = 0,  arcPutar = 0,   naikAmp = 0,   naikPutar = 1,
		tunda = 1.2, roll = AURA_ROLL,
		denyutDalam = 0, denyutMulai = 0.5, denyutUlang = 1 },

	-- Tier 2 (Rose): 3 detik, dan kameranya yang PALING tenang dari semua
	-- yang berbayar. Dia yang paling sering datang, jadi gerakan yang
	-- bagus sekali pun jadi melelahkan kalau diulang tiap beberapa detik.
	--
	--   0,0 - 0,5  menahan dekat
	--   0,5 - 2,0  mundur sampai 75% jarak
	--   sepanjang  seperempat sapuan +/-10 derajat, gundukan kecil 0,8 stud
	--
	-- tunda 0,5 + roll 2,2 = 2,7: angkanya mendarat sebelum sorotan 3
	-- detik habis (dijaga test_tier.py).
	[2] = { tahan = 0.5, keluar = 1.5,               maks = 0.75,
		arcDeg = 10, arcPutar = 0.5, naikAmp = 0.8, naikPutar = 1,
		tunda = 0.5, roll = 2.2,
		denyutDalam = 0, denyutMulai = 0.5, denyutUlang = 1 },

	-- Tier 3 (Rosa, aura): ADEGAN SINEMATIK 10 detik dengan JALUR KAMERA
	-- SENDIRI -- dari bawah, mengelilingi dekat, potret. Lihat ROSA.JALUR.
	--
	-- Selama adegannya kamera dikemudikan jalur itu, jadi angka zoom,
	-- busur, dan naik-turun di baris ini cuma CADANGAN (dipakai kalau
	-- client versi lama tidak mengenal jalurnya) dan lapisan di bawah yang
	-- dituju jalur itu waktu dia melepaskan kamera.
	--
	-- Angka auranya ditunda ke bidikan POTRET: tunda 6,0 + roll 2,5 =
	-- mendarat di 8,5, saat kamera memandang wajah dan papannya. Selama
	-- bidikan dari bawah dan keliling, papan itu keluar-masuk frame -- dan
	-- putaran yang tidak terlihat sama saja dengan tidak diundi.
	--
	-- Tanpa denyut zoom lagi (denyutDalam 0): dorongan masuk sekarang
	-- bagian dari jalurnya sendiri, dan dua dorongan yang bertumpuk
	-- terbaca sebagai kamera yang tidak yakin ke mana dia menuju.
	[3] = { tahan = 1.0, keluar = 2.5,               maks = 0.80,
		arcDeg = 24, arcPutar = 1.5, naikAmp = 3.0, naikPutar = 2,
		tunda = 6.0, roll = 2.5,
		jalur = ROSA.JALUR,
		-- Letterbox dan kawan-kawannya. nil kalau MODE_ROSA "mati" atau
		-- salah ketik -- dan salah ketik diperingatkan saat server mulai.
		layar = LAYAR.PILIHAN[LAYAR.MODE_ROSA],
		denyutDalam = 0, denyutMulai = 0.55, denyutUlang = 1 },

	-- Tier 4 (Bouquet, nova). Selama adegannya (10 detik) kameranya dipegang
	-- TierNova di client, jadi angka di sini baru TERLIHAT sesudah
	-- adegannya selesai: sorotan tarian 3 detik terakhir.
	--
	-- maks 0,75 dan busur kecil: dia sedang menari, dan kamera yang ikut
	-- menyapu lebar di atas tarian cuma jadi dua gerakan yang bertabrakan.
	--
	-- auraMulai = tunggu aset + novaTotal() + napas. Ini BUKAN selera,
	-- ini syarat: selama nova, client menyembunyikan avatar ASLINYA
	-- beserta semua BillboardGui yang menempel padanya (KELAS_MATIKAN).
	-- Papan aura yang dikirim lebih cepat dari ini dibuat, lalu ikut
	-- dimatikan -- dan putaran angkanya, tiga detik yang paling ditonton,
	-- habis selagi papannya belum kelihatan.
	--
	-- SPAWN_SIAP_MAKS ikut dijumlah karena adegannya baru MULAI sesudah
	-- client selesai menunggu aset avatarnya: hitungan yang lupa itu
	-- meleset setengah detik, dan setengah detik itu persis lebar
	-- lubangnya.
	--
	-- 0,6 + 10,3 + 0,1 = 11,0; + tunda 0,1 + roll 2,4 = 13,5, masih di
	-- dalam sorotan 15 detik (dijaga test_tier.py, yang juga mengunci
	-- auraMulai >= tunggu aset + novaTotal()).
	--
	-- bunyiSaatNova: bunyi kedatangannya dibunyikan client saat dia
	-- MEMBANTING DIRI ke tanah, bukan saat avatarnya dibuat.
	[4] = { tahan = 0.3, keluar = 1.2,               maks = 0.75,
		arcDeg = 12, arcPutar = 1.0, naikAmp = 1.0, naikPutar = 1,
		tunda = 0.1, roll = 2.4,
		auraMulai = SPAWN_SIAP_MAKS + novaTotal() + 0.1,
		bunyiSaatNova = true,
		denyutDalam = 0, denyutMulai = 0.5, denyutUlang = 1 },

	-- Raksasa mundur sampai JARAK PENUH: badan 4x tidak muat di 70%, dan
	-- yang dia jual justru ukurannya.
	--
	-- naikAmp-nya paling besar: badan setinggi empat orang dibaca dari
	-- kaki ke kepala, jadi kamera yang naik-turun memperlihatkan ukurannya
	-- jauh lebih baik daripada kamera yang bergeser ke samping.
	--
	-- TANPA denyut: merapat ke badan 4x berarti kameranya berakhir di
	-- dalam tulang keringnya -- yang terlihat cuma satu bidang warna.
	--
	-- masuk 0,75 (bukan 0,45 seperti yang lain): pada 45% jarak, badan
	-- 14x mengisi 62 derajat dari 70 derajat FOV -- pas-pasan, dan cuma
	-- pas selama kamera membidik setinggi ubun-ubunnya. Begitu bidikannya
	-- diturunkan ke dada supaya barisannya ikut terlihat
	-- (GIANT_FOKUS_TINGGI), sisa 8 derajat itu habis dan yang terpotong
	-- kepalanya.
	--
	-- 0,65 -> 0,75 waktu kameranya diturunkan ke bawah garis mata
	-- (GIANT_KAMERA_TINGGI). Kamera yang lebih rendah harus MEMANDANG
	-- LEBIH KE ATAS untuk memuat kepalanya, dan sudut itu diambil dari
	-- jatah yang sama yang dipakai barisan di tepi bawah. Berhenti
	-- sedikit lebih jauh mengembalikan jatahnya: margin tersempit di
	-- detik dia paling dekat justru naik dari 3,9 ke 5,6 derajat.
	--
	-- masuk 0,75 -> 0,95, dan tunda 0 -> 0,8.
	--
	-- Yang pertama melanjutkan apa yang dikerjakan GIANT_KAMERA_JAUH di
	-- atas: rapatannya praktis dibuang. Raksasa tidak butuh rapatan --
	-- badannya sudah mengisi frame di jarak penuh, dan setiap persen
	-- yang dia merapat langsung dibayar dengan kepalanya.
	--
	-- Yang kedua akibat papannya sekarang berisi ANGKA: tunda 0 dulu
	-- benar karena tidak ada yang berputar, cuma nama. Sekarang
	-- putarannya harus menunggu kameranya cukup mundur, sama seperti
	-- tier lain. 0,8 + roll 3,0 = 3,8, masih separuh dari sorotan 7
	-- detik (dijaga test_tier.py).
	[5] = { masuk = 0.95, tahan = 0.8, keluar = ZOOM_KELUAR_GIANT, maks = 1.00,
		arcDeg = 20, arcPutar = 1.0, naikAmp = 5.0, naikPutar = 1,
		tunda = 0.8, roll = AURA_ROLL,
		denyutDalam = 0, denyutMulai = 0.5, denyutUlang = 1 },
}

-- KENAPA putaran angka aura DITUNDA.
--
-- Papan aura melayang di atas kepala avatarnya, dan selama kamera masih
-- merapat papan itu berada di luar frame ATAS. Putaran angkanya makan
-- AURA_ROLL detik, jadi kalau dia mulai bersamaan dengan spawn, bagian
-- yang paling ditonton -- angkanya naik lalu mendarat -- habis sebelum
-- papannya masuk frame.
--
-- Penundaannya kira-kira sepanjang tahan + separuh mundur: begitu
-- angkanya mulai berputar, kamera sudah cukup jauh untuk papannya
-- terlihat, dan mendaratnya jatuh saat kamera sudah tenang.
--
-- Raksasa 0 karena papannya cuma berisi NAMA -- tidak ada angka yang
-- berputar, jadi tidak ada yang perlu ditunggu.
local function kameraTier(tier)
	return KAMERA_TIER[tier] or KAMERA_TIER[1]
end

-- Pandang LURUS ke orang yang baru datang.
--
-- Ayunan kiri-kanan jalan terus-menerus, jadi waktu ada yang muncul
-- kameranya kebetulan sedang berada di suatu sudut -- dan avatar yang
-- baru datang dilihat menyerong, bukan dari depan. Yang paling terasa
-- justru di detik pertama, satu-satunya detik yang pasti ditonton.
--
-- Yang dilakukan: begitu ada kedatangan, sudut ayunannya digeser ke NOL
-- (tepat di belakang si avatar, memandang punggung kamera ke depannya),
-- lalu dilepas pelan supaya dia kembali mengayun sendiri.
--
-- Perpindahannya TIDAK meloncat, dan tidak butuh mesin baru: dia
-- memakai sudutBias yang sudah ada -- angka yang sama yang dipakai
-- orbit untuk mengambil alih ayunan tanpa satu pun frame yang lompat.
local SPAWN_LURUS = true

-- ============ MUSIK + TARIAN ============
--
-- Satu baris = satu lagu DAN tarian pasangannya. Begitu lagunya ganti,
-- seluruh avatar di panggung ganti tarian bersamaan -- termasuk yang
-- sudah berdiri sejak lagu sebelumnya.
--
-- `dance` boleh dikosongkan ("") -> dipakai DANCE_FALLBACK.
-- `musik` boleh dikosongkan ("") -> tarian ganti tanpa ada lagu (kalau
-- musiknya kamu putar dari luar Roblox, misalnya OBS).
--
-- Cara cari ID: View > Toolbox > Audio / Marketplace, klik kanan
-- hasilnya > Copy Asset ID. Audio berlisensi (bukan milikmu) sering
-- tidak bisa diputar di game yang di-publish -- kalau di Studio bunyi
-- tapi di game senyap, itu sebabnya.
local MUSIC_ENABLED = true
local MUSIC_VOLUME  = 0.5

-- Jeda hening antar lagu, detik.
local MUSIC_GAP     = 1.5

local DANCE_FALLBACK = "rbxassetid://106865236633450"

local PLAYLIST = {
	{ nama = "Lagu 1", musik = "", dance = "rbxassetid://106865236633450" },
	{ nama = "Lagu 2", musik = "", dance = "rbxassetid://106865236633450" },
	{ nama = "Lagu 3", musik = "", dance = "rbxassetid://106865236633450" },
}

-- Kalau satu lagu gagal dimuat, TimeLength-nya 0 dan Ended tidak pernah
-- menyala -- tanpa batas ini playlist berhenti selamanya di lagu itu.
local MUSIC_MAX_S = 300

-- Kendali lagu dari luar Roblox (opsional, MATI secara default).
--
-- Kalau dinyalakan, script ini ikut menanyakan URL .. "/api/music" tiap
-- polling dan menuruti jawabannya:
--     { "action": "next" }   -> lompat ke lagu berikutnya
--     { "index": 2 }         -> lompat ke lagu nomor 2 (mulai dari 1)
--     { }                    -> tidak melakukan apa-apa
--
-- Endpoint-nya BELUM ADA di main.py. Biarkan false sampai dibuat;
-- dinyalakan tanpa endpoint-nya cuma menghasilkan warning tiap detik.
local MUSIC_API = false

-- HUD diagnosa kecil di pojok kiri atas layar penonton: jumlah frame,
-- CameraType, berapa studs kamera bergeser, dan titik fokusnya. Matikan
-- kalau sudah beres -- ini alat servis, bukan bagian dari tampilan.
local DEBUG_HUD = true

-- Sinkronisasi tarian (dikerjakan client, angkanya disetel di sini).
--
-- Diperketat 3 -> 0.6 detik. Avatar yang baru berdiri SELALU mulai
-- menari dari detik nol -- animasi direplikasi sebagai perintah "mainkan
-- sekarang", bukan sebagai posisi waktu -- jadi jeda penyamaan itu
-- persis lamanya dia terlihat menari sendiri di luar barisan. Tiga detik
-- itu terlalu lama untuk tidak disadari; setengah detik nyaris tidak.
--
-- Jangan diturunkan ke bawah ~0.3: menyetel TimePosition membuat
-- gerakannya meloncat sedikit, dan menyamakan terlalu sering justru
-- terlihat seperti tersendat.
local RESYNC_EVERY = 0.6
local DRIFT_LIMIT  = 0.04

-- Cara mengoreksi yang melenceng.
--
-- Dulu satu-satunya cara menulis TimePosition, dan itu SELALU
-- meloncat: selisih 0,05 detik pun jadi sentakan kecil yang terlihat
-- tiap RESYNC_EVERY. Yang digeser sekarang kecepatannya -- yang
-- ketinggalan diputar sedikit lebih cepat sampai menyusul sendiri.
--
--   KP          seberapa kuat koreksinya. Naikkan = cepat menyusul
--               tapi mudah kebablasan lalu berayun; turunkan = halus
--               tapi lama.
--   SPEED_MAKS  batas perubahan kecepatan. 0.15 = paling banyak
--               15% lebih cepat/lambat. Di atas ~0.3 koreksinya
--               sendiri mulai kelihatan sebagai gerakan aneh.
--   SNAP        di atas selisih ini, tetap diloncatkan. Dipakai avatar
--               yang baru berdiri (mulai dari detik nol) dan yang baru
--               mendarat dari adegan melayang -- mengejar selisih
--               sebesar itu dengan 15% butuh belasan detik, dan selama
--               itu dia menari sendiri di tengah barisan.
local SYNC_KP         = 0.6
local SYNC_SPEED_MAKS = 0.15
local SYNC_SNAP       = 0.35

-- ============ VISUAL / PENCAHAYAAN ============
--
-- Semua yang di bawah ini CUMA tampilan: Lighting, Atmosphere, dan
-- efek pasca-proses. Tidak ada satu pun yang menyentuh posisi avatar,
-- kamera, musik, atau panggung.
--
-- Dipasang SEKALI waktu server hidup, bukan tiap frame. Lighting itu
-- service yang direplikasi, jadi satu kali set di server = semua
-- penonton ikut, tanpa ada gelung yang jalan terus.
-- Dikelompokkan jadi satu TABEL, bukan konstanta lepas satu per satu.
--
-- Bukan gaya penulisan: Lua membatasi 200 variabel lokal per fungsi, dan
-- seluruh file ini SATU fungsi (chunk utamanya). File ini pernah
-- menembus batas itu, dan yang muncul bukan peringatan halus --
-- script-nya menolak dikompilasi sama sekali:
--
--     too many local variables (limit is 200) in main function
--
-- Satu tabel = satu variabel lokal, isinya sebanyak yang kamu mau. Cara
-- memakainya tidak berubah, cuma titiknya menggantikan garis bawah.
local VISUAL = {}

VISUAL.ENABLED = true

-- Jam di langit. 15-16 = sore: mataharinya miring, jadi avatarnya
-- punya bayangan panjang dan wajahnya kena cahaya dari samping.
-- Tengah hari (12) bikin cahaya jatuh lurus dari atas -- rata, tanpa
-- kedalaman, dan itu yang bikin map terlihat "default".
VISUAL.JAM       = 15.2
VISUAL.LINTANG   = 12      -- kemiringan lintasan matahari

-- Terang keseluruhan dan bukaan "lensa"-nya. Exposure dinaikkan
-- sedikit saja: di atas ~0.4 warna terangnya mulai putih pecah.
VISUAL.TERANG    = 2.2
VISUAL.EXPOSURE  = 0.15

-- Kelembutan bayangan. Cuma berlaku di Technology = Future.
-- 0 = tepi bayangan setajam pisau (terlihat palsu), 1 = kabur.
VISUAL.BAYANG    = 0.22

-- Kabut udara. Ini yang bikin baris belakang terlihat LEBIH JAUH, bukan
-- cuma lebih kecil. Jangan di atas ~0.45: panggungnya ikut berkabut.
VISUAL.KABUT     = 0.30

-- Efek pasca-proses. 0 = matikan efeknya.
VISUAL.BLOOM     = 0.45    -- pendar di bagian paling terang
VISUAL.SUNRAYS   = 0.06    -- berkas matahari; di atas 0.15 norak
VISUAL.KONTRAS   = 0.14
VISUAL.SATURASI  = 0.06    -- sengaja kecil: "vivid" bukan "lebay"

-- Depth of field: baris belakang sedikit buram, yang di depan tajam.
-- Angkanya menempel ke CAMERA_BACK -- kamera duduk ~11 studs dari
-- avatar yang sedang disorot, dan barisan mundur 6 studs per baris.
VISUAL.DOF       = true
VISUAL.DOF_FOKUS = 12      -- jarak bidang fokus, studs
VISUAL.DOF_TAJAM = 26      -- radius yang tetap tajam
VISUAL.DOF_BURAM = 0.12    -- kekuatan buram di belakangnya

-- Turunkan mutu otomatis di HP / perangkat lemot.
--
-- Client menghitung FPS-nya SEKALI di detik-detik pertama, lalu
-- mematikan efek yang paling mahal kalau ternyata tidak kuat. Sekali,
-- bukan terus-menerus: pengukuran yang jalan selamanya justru ikut
-- memakan frame yang mau diselamatkan.
VISUAL.AUTO      = true
VISUAL.FPS_MIN   = 32

-- --- Warna lantai (Baseplate) ---
--
-- Cuma WARNA. Ukuran, posisi, dan bentuk lantainya tidak disentuh sama
-- sekali -- avatar tetap berdiri di tempat yang persis sama.
--
-- Lantai bawaan Roblox itu dua lapis, dan ini sering bikin bingung:
--   1. Part "Baseplate" -- warna dasarnya
--   2. Texture di permukaan atasnya -- pola kotak-kotaknya
-- Mengubah warna partnya saja tidak cukup: polanya digambar di atasnya
-- dan tetap abu bawaan, jadi lantainya terlihat "setengah berubah".
-- Dua-duanya disetel di bawah.
-- Dikelompokkan jadi satu TABEL, bukan konstanta lepas satu per satu.
--
-- Bukan gaya penulisan: Lua membatasi 200 variabel lokal per fungsi, dan
-- seluruh file ini SATU fungsi (chunk utamanya). File ini pernah
-- menembus batas itu, dan yang muncul bukan peringatan halus --
-- script-nya menolak dikompilasi sama sekali:
--
--     too many local variables (limit is 200) in main function
--
-- Satu tabel = satu variabel lokal, isinya sebanyak yang kamu mau. Cara
-- memakainya tidak berubah, cuma titiknya menggantikan garis bawah.
local LANTAI = {}

LANTAI.ENABLED = true

-- Nama part lantainya. Ganti kalau di map-mu namanya bukan "Baseplate".
LANTAI.NAMA    = "Baseplate"

-- Warna dasar dan warna kotak-kotaknya.
--
-- Sengaja abu KEBIRUAN, bukan abu netral: lantai netral memantulkan
-- warna apa adanya dan bikin panggung terasa seperti studio foto.
-- Sedikit biru di lantai membuat cahaya sore yang hangat dari atas
-- punya lawan, dan itu yang bikin gambarnya terasa punya kedalaman.
--
-- Gelap juga disengaja. Lantai terang memantul ke bawah badan avatar
-- dan menghapus bayangannya sendiri -- dan bayangan itu satu-satunya
-- yang menempelkan mereka ke tanah.
LANTAI.WARNA  = Color3.fromRGB(48, 52, 62)   -- warna dasar
LANTAI.GARIS  = Color3.fromRGB(74, 80, 94)   -- pola kotaknya

-- Material. SmoothPlastic = permukaan bersih tanpa butiran, dan dia
-- menangkap pantulan langit dari EnvironmentSpecularScale di atas --
-- ini yang bikin lantainya terlihat seperti panggung, bukan seperti
-- tanah. Kosongkan (nil) kalau mau materialnya dibiarkan apa adanya.
LANTAI.MATERIAL = Enum.Material.SmoothPlastic

-- ====================================

if HIDE_PLAYER_AVATAR then
	Players.CharacterAutoLoads = false
	for _, pemain in ipairs(Players:GetPlayers()) do
		if pemain.Character then pemain.Character:Destroy() end
	end
end

-- Remote dibuat lewat kode, bukan di-insert manual: satu objek yang
-- salah nama = kamera mati tanpa satu pun error di Output.
local V2Event = ReplicatedStorage:FindFirstChild("V2Event")
	or Instance.new("RemoteEvent")
V2Event.Name   = "V2Event"
V2Event.Parent = ReplicatedStorage

local V2Config = ReplicatedStorage:FindFirstChild("V2Config")
	or Instance.new("RemoteFunction")
V2Config.Name   = "V2Config"
V2Config.Parent = ReplicatedStorage

-- Tempat avatar menunggu selagi asetnya diunduh penonton. Lihat
-- SPAWN_PRAMUAT_S. Namanya dibaca client (KameraClientV2).
local folderPramuat = ReplicatedStorage:FindFirstChild("AvatarPramuat")
	or Instance.new("Folder")
folderPramuat.Name   = "AvatarPramuat"
folderPramuat.Parent = ReplicatedStorage

local avatars   = {}   -- slot -> model
local tracks    = {}   -- slot -> AnimationTrack
local slotCount = 0
local resetting = false
-- Naik tiap kali barisan dikosongkan (resetStage, gempa nova). Lihat
-- pemakaiannya di spawnAvatar.
local barisanGen = 0

-- Garis tepi yang sedang hidup, urut dari yang paling tua. Roblox cuma
-- menggambar sekitar 31 Highlight sekaligus, jadi daftar ini yang
-- memutuskan siapa yang dilepas duluan waktu penuh.
local borderHidup = {}

local laguIndex = 0    -- 0 = belum ada lagu yang jalan
local laguSound = nil

-- ============ POSISI & TINGGI ============

-- Nomor slot raksasa dipisah jauh dari nomor kerumunan (1, 2, 3, ...).
--
-- Dengan nomor terpisah, raksasa tidak pernah ikut menggeser urutan
-- barisan: dia tidak menghabiskan jatah DELETE_AFTER, tidak mendorong
-- siapa pun mundur satu baris, dan tidak membuat orang berikutnya
-- berdiri di tempat yang seharusnya kosong. Cuma ada satu pada satu
-- waktu, jadi satu nomor cukup.
local SLOT_RAKSASA = 9999

-- Nomor slot avatar nova SELAMA adegannya.
--
-- Dia memegang nomor ini sejak detik pertama, bukan mulai dari
-- ledakannya. Itu perubahan yang disengaja, dan ini sebabnya: selama
-- sepuluh detik adegannya, kedatangan gratisan terus mengisi barisan.
-- Waktu nova masih memegang slot barisan biasa, barisan yang kebetulan
-- penuh di detik-detik itu memanggil resetStage -- dan resetStage
-- menghapus avatarnya di tengah adegan. AncestryChanged di client
-- membatalkan seluruh novanya, jadi yang tersisa cuma kamera yang
-- mengorbit panggung kosong. Itu persis "novanya kadang tidak muncul,
-- cuma kameranya yang bergerak".
--
-- Nomor ini di luar 1..slotCount, jadi tidak ada satu pun gelung
-- barisan -- resetStage maupun gempaBarisan -- yang bisa menyentuhnya.
--
-- Yang tetap diambil dari barisan cuma TEMPATnya: slotCount ikut naik
-- seperti kedatangan biasa, supaya orang berikutnya tidak berdiri
-- menembus badannya selagi dia mengisi tenaga. Slot itu kosong di tabel
-- `avatars`, dan memang tidak ada yang perlu berdiri di sana.
--
-- Perginya nomor ini juga cuma satu detik: saat dia menghantam tanah,
-- barisannya disapu gempa dan dia PINDAH ke slot 1 (novaKeBarisan) --
-- jadi sesudah adegannya dia berdiri sebagai orang pertama di barisan
-- yang baru, bukan dihapus. Lihat catatan di novaKeBarisan.
local SLOT_NOVA = 9998

-- Slot yang ditempati avatar nova sesudah mendarat: paling depan,
-- paling dekat kamera, dan sesudah gempa memang satu-satunya yang ada.
local SLOT_NOVA_MENDARAT = 1

local function getPosition(slot)
	if slot == SLOT_RAKSASA then
		return Vector3.new(GIANT_X, BASE_Y, GIANT_Z)
	end
	local i   = slot - 1
	local row = math.floor(i / ROW_SIZE)
	local col = i % ROW_SIZE
	local x = (col - (ROW_SIZE - 1) / 2) * SPACING_X
	local z = -row * SPACING_Z
	return Vector3.new(x, BASE_Y, z)
end

-- Jarak pivot ke telapak kaki, DIUKUR dari rig-nya sendiri.
--
-- HipHeight didefinisikan Roblox persis sebagai jarak sisi bawah
-- HumanoidRootPart ke tanah. Kotak pembungkus tidak dipakai karena dia
-- ikut membungkus aksesori: rambut panjang atau ekor yang menjulur ke
-- bawah membuat avatarnya terangkat sebanyak itu.
local function tinggiPivot(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hum and hrp then
		local ok, hasil = pcall(function()
			return hum.HipHeight + hrp.Size.Y / 2
		end)
		if ok and hasil and hasil > 0 then return hasil end
	end
	return nil
end

-- Titik yang DIPANDANG kamera untuk sebuah slot.
--
-- Sengaja fungsi sendiri, tidak menumpang getPosition: keduanya
-- kebetulan punya X dan Z yang sama, tapi artinya beda dan tingginya
-- beda. getPosition = tempat kaki avatarnya berdiri; yang ini = tempat
-- kamera menaruh titik tengah layarnya. Waktu keduanya masih satu
-- fungsi, menurunkan bidikan kamera berarti ikut memindahkan avatarnya.
local function titikPandang(slot)
	local p = getPosition(slot)
	return Vector3.new(p.X, CAMERA_FOKUS_Y, p.Z)
end

local function finalCFrame(model, slot)
	local p = getPosition(slot)
	local y = FLOOR_Y + (tinggiPivot(model) or BASE_Y)
	return CFrame.new(p.X, y, p.Z)
end

-- Kunci posisi TANPA Anchored.
--
-- Anchored menghentikan Motor6D, jadi avatarnya diam seperti patung
-- meskipun track:Play() dipanggil dan tidak ada error. Ketiga angka
-- pegasnya dikali massa supaya selisih tahannya tidak bergantung ukuran
-- avatar.
local function lockInPlace(model, hrp, targetCF)
	local massa = 0
	pcall(function()
		for _, bagian in ipairs(model:GetDescendants()) do
			if bagian:IsA("BasePart") then massa += bagian:GetMass() end
		end
	end)
	massa = math.max(massa, 1)

	local bp = Instance.new("BodyPosition")
	bp.Name     = "PositionLock"
	bp.MaxForce = Vector3.new(1, 1, 1) * (massa * workspace.Gravity * 200)
	bp.P        = massa * 3000
	bp.D        = massa * 160
	bp.Position = targetCF.Position
	bp.Parent   = hrp

	local bg = Instance.new("BodyGyro")
	bg.Name      = "RotationLock"
	bg.MaxTorque = Vector3.new(1, 1, 1) * (massa * 5000)
	bg.P         = massa * 3000
	bg.D         = massa * 200
	bg.CFrame    = targetCF
	bg.Parent    = hrp
end

-- ============ NAMEPLATE ============

-- Warna nama dari huruf-hurufnya sendiri: orang yang sama selalu dapat
-- warna yang sama, dan tetangganya hampir pasti beda. Tidak perlu ada
-- daftar warna yang disimpan.
--
-- Rentang HUE-nya dikunci ke 190-290 derajat (biru muda -> ungu), bukan
-- lingkaran penuh. Sebelumnya nama bisa keluar hijau lumut atau coklat
-- -- warna yang di atas kepala avatar terbaca seperti bug, bukan gaya.
-- Yang dipakai gradien dua warna dari titik itu, jadi hurufnya
-- berpindah warna dari atas ke bawah.
local function gradienNama(username)
	local hash = 0
	for i = 1, #username do
		hash = (hash * 31 + string.byte(username, i)) % 360
	end
	local h = (190 + (hash % 100)) / 360

	local atas  = Color3.fromHSV(h, 0.55, 1)
	local bawah = Color3.fromHSV(((h * 360 + 55) % 360) / 360, 0.70, 1)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, atas),
		ColorSequenceKeypoint.new(1, bawah),
	}), Color3.fromHSV(((h * 360 + 30) % 360) / 360, 0.75, 1)
end

local function createNameplate(model, username)
	if not PLATE.ENABLED then return end

	local head = model:FindFirstChild("Head")
	if not head then return end

	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local gui = Instance.new("BillboardGui")
	gui.Name        = "Nameplate"
	gui.Size        = UDim2.new(0, PLATE.WIDTH, 0, PLATE.HEIGHT)
	gui.StudsOffset = Vector3.new(0, PLATE.OFFSET, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = PLATE.DIST
	gui.Parent      = head

	local warna, glow = gradienNama(username)

	-- Glow-nya label KEMBAR di belakang, bukan efek: Roblox tidak punya
	-- blur untuk GUI. Huruf yang sama, warna neon, stroke tebal dan
	-- setengah tembus -- dari jarak main yang terlihat cuma "namanya
	-- bercahaya". Dibuat duluan supaya digambar di bawah (ZIndex).
	local glowLbl = Instance.new("TextLabel")
	glowLbl.Name                   = "Glow"
	glowLbl.Size                   = UDim2.new(1, 0, 1, 0)
	glowLbl.BackgroundTransparency = 1
	glowLbl.Text                   = username
	glowLbl.TextColor3             = glow
	glowLbl.FontFace               = PLATE.FONT
	glowLbl.TextScaled             = true
	glowLbl.TextTransparency       = 0.55
	glowLbl.TextStrokeTransparency = 1
	glowLbl.ZIndex                 = 1
	glowLbl.Parent                 = gui

	local glowStroke = Instance.new("UIStroke")
	glowStroke.Color           = glow
	glowStroke.Thickness       = 4
	glowStroke.Transparency    = 0.5
	glowStroke.ApplyStrokeMode  = Enum.ApplyStrokeMode.Contextual
	glowStroke.LineJoinMode    = Enum.LineJoinMode.Round
	glowStroke.Parent          = glowLbl

	local label = Instance.new("TextLabel")
	label.Size                   = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text                   = username
	label.TextColor3             = Color3.fromRGB(255, 255, 255)
	label.FontFace               = PLATE.FONT
	label.TextScaled             = true
	-- TextStroke bawaan dimatikan: dia menebalkan huruf jadi blok hitam
	-- bergerigi. UIStroke sudutnya bulat dan tebalnya bisa pecahan.
	label.TextStrokeTransparency = 1
	label.ZIndex                 = 2
	label.Parent                 = gui

	local gradien = Instance.new("UIGradient")
	gradien.Color    = warna
	gradien.Rotation = 90
	gradien.Parent   = label

	local garis = Instance.new("UIStroke")
	garis.Color           = Color3.fromRGB(10, 12, 24)
	garis.Thickness       = 1.5
	garis.Transparency    = 0.15
	garis.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	garis.LineJoinMode    = Enum.LineJoinMode.Round
	garis.Parent          = label
end

-- ============ TARIAN ============

local function danceSekarang()
	local lagu = PLAYLIST[laguIndex]
	local id   = lagu and lagu.dance
	if id and id ~= "" then return id end
	return DANCE_FALLBACK
end

local function playDance(model, animId)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end

	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = hum
	end

	local anim = Instance.new("Animation")
	anim.AnimationId = animId or danceSekarang()
	anim.Parent = model

	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if not ok then
		warn("Gagal load animasi:", track)
		return nil
	end

	track.Looped = true
	-- Play(0) = tanpa fade-in. Fade default 0,1 detik bikin gerakan awal
	-- terlihat meleset dari yang lain.
	track:Play(0)
	return track
end

-- Ganti tarian SELURUH panggung. Dipanggil tiap lagu berganti.
local function gantiTarianSemua()
	local id = danceSekarang()

	for slot, model in pairs(avatars) do
		-- Yang sedang mengambang dilewati: dia memang sengaja tidak
		-- menari, dan tarian baru di sini akan menghidupkannya kembali
		-- di tengah udara. Dia menyusul sendiri waktu mendarat.
		-- Raksasa juga dilewati: dia sengaja melambai, bukan menari,
		-- dan lagu yang berganti tidak boleh diam-diam menariknya
		-- masuk ke koreografi kerumunan.
		if model.Parent and slot ~= SLOT_RAKSASA then
			local lama = tracks[slot]
			if lama then pcall(function() lama:Stop(0.15) end) end
			tracks[slot] = playDance(model, id)
		end
	end
end

-- ============ MUSIK ============

local function putarLagu(index)
	if not MUSIC_ENABLED or #PLAYLIST == 0 then return end

	-- Berputar balik ke awal setelah lagu terakhir.
	laguIndex = ((index - 1) % #PLAYLIST) + 1
	local lagu = PLAYLIST[laguIndex]

	if laguSound then
		laguSound:Destroy()
		laguSound = nil
	end

	-- Tarian diganti DULU, sebelum lagunya bunyi: kalau sesudah,
	-- ada sepersekian detik di mana lagu baru berjalan di atas gerakan
	-- lagu lama.
	gantiTarianSemua()

	if lagu.musik and lagu.musik ~= "" then
		local s = Instance.new("Sound")
		s.Name    = "Musik"
		s.SoundId = lagu.musik
		s.Volume  = MUSIC_VOLUME
		s.Looped  = false
		-- Sound yang diparent SERVER ke workspace direplikasi ke semua
		-- client, jadi semua penonton mendengar lagu yang sama pada
		-- posisi yang sama.
		s.Parent  = workspace
		s:Play()
		laguSound = s
	end

	V2Event:FireAllClients("musik", {
		nama  = lagu.nama or ("Lagu " .. laguIndex),
		index = laguIndex,
	})

	print(("Lagu %d/%d: %s"):format(laguIndex, #PLAYLIST,
		lagu.nama or "(tanpa nama)"))
end

local function laguBerikutnya()
	putarLagu(laguIndex + 1)
end

-- Gelung playlist.
--
-- Yang dipakai Sound.Ended, dengan MUSIC_MAX_S sebagai jaring pengaman:
-- asset yang gagal dimuat tidak pernah menyalakan Ended, dan tanpa batas
-- itu playlist berhenti selamanya di lagu yang rusak.
local function startMusicLoop()
	if not MUSIC_ENABLED or #PLAYLIST == 0 then return end

	task.spawn(function()
		putarLagu(1)

		while true do
			local mulai   = os.clock()
			local sekarang = laguIndex
			local s        = laguSound

			if s then
				local selesai = false
				local conn = s.Ended:Connect(function() selesai = true end)

				while not selesai
					and laguIndex == sekarang
					and os.clock() - mulai < MUSIC_MAX_S do
					task.wait(0.2)
				end
				conn:Disconnect()
			else
				-- Lagu tanpa asset (musik diputar dari luar Roblox):
				-- tariannya tetap berganti tiap MUSIC_MAX_S supaya
				-- playlist tidak macet di satu gerakan.
				while laguIndex == sekarang
					and os.clock() - mulai < MUSIC_MAX_S do
					task.wait(0.2)
				end
			end

			-- Dilewati kalau lagunya sudah keburu diganti dari luar
			-- (MUSIC_API): yang mengganti sudah memanggil putarLagu
			-- sendiri, dan memanggilnya lagi di sini akan melompat dua.
			if laguIndex == sekarang then
				task.wait(MUSIC_GAP)
				if laguIndex == sekarang then
					laguBerikutnya()
				end
			end
		end
	end)
end

-- ============ AURA VFX ============
--
-- Kelas yang bisa dipindah SENDIRIAN ke bagian badan dan tetap bekerja.
--
-- Sengaja tidak semua isi asset diambil. Beam dan Trail menunjuk ke
-- Attachment lain lewat properti (Attachment0/Attachment1), dan
-- referensi itu putus begitu emitternya dicabut dari susunan aslinya --
-- yang tersisa Beam yang tidak menggambar apa pun. Yang di daftar ini
-- semuanya berdiri sendiri: cukup punya BasePart sebagai induk.
--
-- Praktisnya asset aura hampir seluruhnya ParticleEmitter, jadi yang
-- hilang sedikit. Kalau nanti auranya terlihat kurang dari aslinya,
-- di situ sebabnya -- bukan di ukuran atau posisinya.
local AURA_VFX_KELAS = {
	ParticleEmitter = true,
	PointLight      = true,
	SpotLight       = true,
	SurfaceLight    = true,
	Fire            = true,
	Smoke           = true,
	Sparkles        = true,
}

local AURA_VFX_TANDA = "AuraVfx"

-- Diambil SEKALI lalu disimpan.
--
-- Bukan penghematan yang dicari-cari: pengambilan asset itu panggilan
-- jaringan yang bisa makan ratusan milidetik, dan spawnAvatar dipanggil
-- dari gelung utama yang tidak boleh tertahan. Sekali ambil di
-- kedatangan pertama, sesudahnya cuma Clone yang gratis.
-- Diambil SEKALI per asset lalu disimpan.
--
-- Bukan penghematan yang dicari-cari: pengambilan asset itu panggilan
-- jaringan yang bisa makan ratusan milidetik, dan spawnAvatar dipanggil
-- dari gelung utama yang tidak boleh tertahan. Sekali ambil per asset,
-- sesudahnya cuma Clone yang gratis.
--
-- Dikunci per ID, bukan satu variabel: ketiga aura diambil terpisah, dan
-- satu yang gagal tidak boleh mematikan dua yang lain.
local auraVfxAsli  = {}   -- [id] = Folder berisi emitter
local auraVfxGagal = {}   -- [id] = true kalau sudah pernah gagal

local function muatAuraVfx(id, redam)
	if auraVfxAsli[id] then return auraVfxAsli[id] end
	-- Sudah pernah gagal? Jangan dicoba lagi tiap kedatangan -- kalau
	-- asset-nya memang tidak bisa diambil, mencobanya seratus kali cuma
	-- menahan gelung utama seratus kali dengan hasil yang sama.
	if auraVfxGagal[id] then return nil end

	local wadah = nil

	-- Dua jalan, karena keduanya gagal di keadaan yang berbeda:
	-- GetObjects jalan di Studio tapi ditolak di server yang sudah
	-- terbit, InsertService:LoadAsset sebaliknya butuh asset-nya
	-- dimiliki atau gratis. Yang mana pun yang berhasil, dipakai.
	local ok, hasil = pcall(function()
		return game:GetObjects(id)
	end)
	if ok and typeof(hasil) == "table" and hasil[1] then
		wadah = hasil[1]
	else
		local ok2, hasil2 = pcall(function()
			return InsertService:LoadAsset(tonumber(id:match("%d+")))
		end)
		if ok2 and hasil2 then wadah = hasil2 end
	end

	if not wadah then
		auraVfxGagal[id] = true
		warn(("[aura-vfx] gagal mengambil %s. Cek asset-nya publik atau " ..
			"dimiliki akun ini."):format(id))
		return nil
	end

	-- Kumpulkan emitternya jadi satu wadah datar. Susunan aslinya tidak
	-- dipakai lagi: yang dipasang ke avatar emitter satu-satu, bukan
	-- modelnya.
	local kotak = Instance.new("Folder")
	local jumlah = 0
	for _, d in ipairs(wadah:GetDescendants()) do
		if AURA_VFX_KELAS[d.ClassName] then
			local k = d:Clone()
			-- Diredam di sini, pada salinan INDUK yang disimpan cache.
			-- Jadi tiap kedatangan cuma meng-clone yang sudah diredam,
			-- dan biayanya nol saat live.
			redamEfek(k, redam)
			k.Parent = kotak
			jumlah += 1
		end
	end
	pcall(function() wadah:Destroy() end)

	if jumlah == 0 then
		auraVfxGagal[id] = true
		warn(("[aura-vfx] %s berhasil diambil tapi tidak ada emitter di " ..
			"dalamnya (dicari: ParticleEmitter/Light/Fire/Smoke/Sparkles)."):
			format(id))
		return nil
	end

	auraVfxAsli[id] = kotak
	print(("[aura-vfx] %s siap -- %d emitter, %s."):format(id, jumlah,
		redam and ("diredam rate x%.2f, +%.2f tembus, ukuran x%.2f, zOffset %+.1f")
			:format(redam.rate or 1, redam.tembus or 0,
				redam.ukuran or 1, redam.zOffset or 0)
			or "tanpa peredaman"))
	return kotak
end

-- Siapa yang dapat aura di badan: tier AURA_VFX_TIER sampai
-- AURA_VFX_TIER_MAKS. Lihat catatan di sana.
local function layakAuraVfx(tier)
	if not AURA_VFX_ENABLED then return false end
	return tier >= AURA_VFX_TIER and tier <= AURA_VFX_TIER_MAKS
end

-- Satu aura acak yang BERHASIL dimuat, beserta namanya.
--
-- Kalau yang keundi ternyata gagal diambil, dicoba yang lain -- bukan
-- langsung menyerah. Satu asset yang dihapus atau di-private tidak boleh
-- membuat sepertiga kedatangan tier 2 kehilangan auranya, dan mulai dari
-- titik acak menjaga pilihannya tetap rata saat semuanya sehat.
local function pilihAuraVfx()
	local n = #AURA_VFX_IDS
	if n == 0 then return nil, nil end

	local mulai = math.random(1, n)
	for i = 0, n - 1 do
		local pilihan = AURA_VFX_IDS[((mulai - 1 + i) % n) + 1]
		local asli = muatAuraVfx(pilihan.id, pilihan.redam)
		if asli then return asli, pilihan.nama end
	end
	return nil, nil
end

-- Mengembalikan NAMA auranya kalau terpasang, atau nil kalau tidak.
-- Namanya dipakai log di spawnAvatar: "dapat aura" tanpa menyebut yang
-- mana tidak bisa menjawab "kenapa yang merah tidak pernah keluar".
local function pasangAuraVfx(model, tier, skala)
	if not layakAuraVfx(tier) then return nil end
	local asli, nama = pilihAuraVfx()
	if not asli then return nil end

	-- Bagian badan yang tidak ikut terayun animasi tangan, lihat
	-- AURA_VFX_BAGIAN.
	local bagian = nil
	for _, n in ipairs(AURA_VFX_BAGIAN) do
		local b = model:FindFirstChild(n)
		if b and b:IsA("BasePart") then
			bagian = b
			break
		end
	end
	-- Masih tidak ketemu? Ambil BasePart apa pun. Rig R6 dan R15 punya
	-- nama bagian yang berbeda, dan daftar di atas belum tentu menutup
	-- rig yang belum pernah lewat sini.
	if not bagian then
		bagian = model:FindFirstChildWhichIsA("BasePart", true)
	end
	if not bagian then return nil end

	local dipasang = 0
	for _, e in ipairs(asli:GetChildren()) do
		local k = e:Clone()
		-- Ditandai supaya bisa dicari lagi waktu mau dilepas. Nama
		-- aslinya dibuang: dua emitter dari asset yang sama sering
		-- bernama sama persis, dan yang dicari nanti tandanya.
		k.Name   = AURA_VFX_TANDA

		-- Badan yang diperbesar (raksasa) dapat partikel yang ikut
		-- diperbesar. Ukuran, kecepatan, dan jangkauan lampu -- tiga-
		-- tiganya harus ikut, kalau tidak partikel besar yang tetap
		-- lambat terlihat seperti mengambang di tempat.
		local f = tonumber(skala) or 1
		if f > 1 then
			if k:IsA("ParticleEmitter") then
				pcall(function() k.Size = skalaSeq(k.Size, f) end)
				pcall(function()
					k.Speed = NumberRange.new(k.Speed.Min * f, k.Speed.Max * f)
				end)
			elseif k:IsA("Light") then
				pcall(function() k.Range = k.Range * f end)
			elseif k:IsA("Fire") or k:IsA("Smoke") then
				pcall(function() k.Size = k.Size * f end)
			end
		end

		k.Parent = bagian
		dipasang += 1
	end
	if dipasang == 0 then return nil end

	-- Ada masa habisnya? Lihat AURA_VFX_LAMA -- default 0 = ikut umur
	-- avatarnya, jadi cabang ini tidak jalan.
	if AURA_VFX_LAMA > 0 then
		task.delay(AURA_VFX_LAMA, function()
			if not bagian.Parent then return end
			for _, d in ipairs(bagian:GetChildren()) do
				if d.Name == AURA_VFX_TANDA then d:Destroy() end
			end
		end)
	end

	return nama
end

-- ============ AURA ============

local function hitungAura(tier)
	local bawah = AURA_MIN

	-- Untuk yang IKUT DIUNDI, yang naik cuma LANTAINYA -- langit-
	-- langitnya tetap AURA_MAX. Jadi yang bayar tidak pernah dapat angka
	-- memalukan, tapi juga tidak dijamin menang: yang gratisan masih
	-- bisa mengalahkan dia, dan justru itu yang bikin panggungnya seru.
	--
	-- Raksasa satu-satunya yang TIDAK ikut diundi sama sekali (lihat
	-- cabang pertama di bawah). Dia keluar dari kalimat di atas dengan
	-- sengaja, bukan lolos dari situ -- alasannya di AURA_RAKSASA.
	--
	-- Dibaca dari tier TERTINGGI ke terendah. Dibalik, tier 4 akan
	-- berhenti di cabang tier 2 yang juga cocok dan angkanya sendiri
	-- tidak pernah terpakai.
	if TIER_ENABLED and tier then
		if tier >= GIANT_MIN_TIER then
			-- Keluar lebih awal: raksasa diundi di rentangnya sendiri,
			-- tidak dijepit AURA_MAX, tidak dipengaruhi apa pun di
			-- bawah. Lihat AURA_RAKSASA.
			return math.random(AURA_RAKSASA_MIN, AURA_RAKSASA)
		elseif tier >= 4 then
			bawah = math.max(bawah, AURA_LANTAI_T4)
		elseif tier >= 3 then
			bawah = math.max(bawah, AURA_LANTAI_T3)
		elseif tier >= 2 then
			bawah = math.max(bawah, AURA_LANTAI_T2)
		end
	end

	if bawah > AURA_MAX then bawah = AURA_MAX end
	return math.random(bawah, AURA_MAX)
end

-- `model` ikut dikirim supaya client bisa menempelkan papan auranya di
-- kepala avatar yang benar. Instance boleh lewat RemoteEvent apa adanya;
-- yang sampai di sana referensi ke objek yang sama, bukan salinan.
--
-- Papannya dibuat CLIENT, bukan server, walaupun BillboardGui itu benda
-- dunia yang seharusnya bisa dibuat sekali di server. Alasannya angka
-- yang berhitung naik: animasi itu mengubah Text puluhan kali per
-- detik, dan kalau dibuat di server tiap perubahan itu satu paket
-- replikasi ke SEMUA penonton -- untuk sesuatu yang hasil akhirnya sama
-- di semua layar. Dibuat client, animasinya gratis dan semulus frame
-- rate masing-masing.
local function tampilkanAura(model, nama, persen, slot, tier)
	V2Event:FireAllClients("aura", {
		model  = model,
		nama   = nama,
		persen = persen,
		lama   = AURA_TIME,
		-- Per tier, bukan AURA_ROLL untuk semua: tier yang sorotannya
		-- pendek (tier 2, 3 detik) butuh putaran yang lebih pendek juga,
		-- kalau tidak angkanya mendarat setelah kameranya pergi. Lihat
		-- `roll` di KAMERA_TIER.
		roll   = kameraTier(tier).roll or AURA_ROLL,
		-- Berapa lama putaran angkanya ditahan sebelum mulai. Papannya
		-- sendiri muncul langsung; yang ditunda cuma hitungannya, supaya
		-- tidak berputar selagi papannya masih di luar frame atas.
		-- Alasan panjangnya ada di atas KAMERA_TIER.
		tunda  = kameraTier(tier).tunda,
		-- CATATAN: papan raksasa dulu CUMA berisi username -- tanpa
		-- angka, tanpa kata AURA (`namaSaja`). Alasannya: papan tiga
		-- baris di atas kepala setinggi belasan stud jadi papan reklame
		-- yang menyaingi badannya sendiri, dan yang menjual raksasa
		-- ukurannya.
		--
		-- DIBALIK atas permintaan, dan sekarang justru dia yang paling
		-- butuh papannya: angkanya 10.000% (AURA_RAKSASA), satu-satunya
		-- angka di panggung yang tidak bisa dicapai siapa pun dengan
		-- cara lain. Menyembunyikannya berarti yang bayar paling mahal
		-- adalah satu-satunya yang angkanya tidak pernah terlihat --
		-- dan putaran angka itu justru bagian yang ditonton.
		--
		-- Yang tetap berlaku cuma `tetap` di bawah: dia berdiri di luar
		-- barisan, jadi pembukuan baris tidak menyentuhnya.

		-- Penanda untuk bunyi mendaratnya yang eksklusif. Dikirim
		-- sebagai penanda, bukan disimpulkan client dari besarnya
		-- angka: "siapa yang raksasa" sudah punya satu jawaban di file
		-- ini (adalahRaksasa), dan ambang angka di client akan jadi
		-- jawaban kedua yang diam-diam bisa tidak sepakat.
		raksasa = (slot == SLOT_RAKSASA) or nil,
		-- Sesudah putarannya mendarat dan sempat dibaca selama ini, papan
		-- raksasa dirapikan jadi NAMA SAJA. Lihat AURA_RAKSASA_NAMA_S.
		namaSesudah = (slot == SLOT_RAKSASA) and AURA_RAKSASA_NAMA_S or nil,

		-- Papan raksasa tidak ikut aturan "hanya baris depan".
		--
		-- Dia berdiri di luar barisan, dan nomor barisnya kalau dipaksa
		-- dihitung akan keluar sebagai angka raksasa juga -- yang di
		-- client berarti SEMUA papan lain dianggap ada di belakangnya
		-- dan dilepas sekaligus. Penanda ini membuat dia diam saja:
		-- tidak melepas siapa pun, dan tidak dilepas siapa pun.
		tetap  = (slot == SLOT_RAKSASA) or nil,
		-- Nomor barisnya, bukan nomor slotnya: client cuma perlu tahu
		-- siapa yang berdiri di DEPAN siapa, dan itu urusan baris.
		-- Menghitungnya di sini supaya client tidak perlu tahu ROW_SIZE
		-- sama sekali.
		baris  = math.floor((slot - 1) / ROW_SIZE),
	})
end

-- ============ TIER: BORDER, AKSESORI, MELAYANG ============

local function warnaTier(tier)
	if tier >= NOVA.TIER then return BORDER_T3_WARNA end
	return BORDER_T2_WARNA
end

local function umurBorder(tier)
	if tier >= NOVA.TIER then return BORDER_T3_UMUR end
	return BORDER_T2_UMUR
end

-- Lepas satu border, memudar dulu kalau sempat.
--
-- Highlight tidak bisa di-tween (Roblox tidak mengizinkan properti
-- Highlight jadi target TweenService), jadi pudarnya ditulis tangan
-- dengan gelung Heartbeat. Cakramnya tween biasa.
local function lepasBorder(rec, seketika)
	if not rec or rec.lepas then return end
	rec.lepas = true

	for i, lain in ipairs(borderHidup) do
		if lain == rec then table.remove(borderHidup, i) break end
	end

	local waktu = seketika and 0 or BORDER_PUDAR

	task.spawn(function()
		if waktu > 0 then
			local mulai = os.clock()
			while os.clock() - mulai < waktu do
				local t = (os.clock() - mulai) / waktu
				if rec.garis and rec.garis.Parent then
					rec.garis.OutlineTransparency =
						BORDER_GARIS_ALPHA + (1 - BORDER_GARIS_ALPHA) * t
					rec.garis.FillTransparency =
						BORDER_ISI + (1 - BORDER_ISI) * t
				end
				if rec.cakram and rec.cakram.Parent then
					rec.cakram.Transparency =
						BORDER_CAKRAM_ALPHA + (1 - BORDER_CAKRAM_ALPHA) * t
				end
				RunService.Heartbeat:Wait()
			end
		end

		if rec.garis  then rec.garis:Destroy()  end
		if rec.cakram then rec.cakram:Destroy() end
	end)
end

-- Pasang border untuk satu avatar. Mengembalikan catatannya supaya
-- pemanggil bisa ikut menaikkan cakramnya waktu adegan Matrix jalan.
local function pasangBorder(model, slot, tier, kakiY, skala)
	if not (TIER_ENABLED and BORDER_ENABLED and tier >= 2) then return nil end

	local warna = warnaTier(tier)
	local rec   = { slot = slot, tier = tier }
	-- Cakram raksasa harus ikut membesar. Cakram 5,5 stud di bawah kaki
	-- selebar 8 stud bukan lingkaran cahaya, cuma titik di antara dua
	-- telapak -- dan dari kamera yang mundur 60 stud dia hilang sama
	-- sekali.
	local d = BORDER_CAKRAM_D * (skala or 1)

	if BORDER_GARIS and tier >= BORDER_GARIS_MIN_TIER then
		-- Yang paling tua dilepas duluan waktu penuh. Tanpa ini, yang
		-- KE-32 dan seterusnya cuma tidak digambar -- dan yang hilang
		-- justru border baru, milik orang yang barusan bayar.
		while #borderHidup >= BORDER_MAKS_GARIS do
			lepasBorder(borderHidup[1], true)
		end

		local h = Instance.new("Highlight")
		h.Name                = "BorderTier"
		h.Adornee             = model
		h.OutlineColor        = warna
		h.OutlineTransparency = BORDER_GARIS_ALPHA
		h.FillColor           = warna
		h.FillTransparency    = BORDER_ISI
		-- Occluded (terhalang badan) sebagai KEADAAN DIAM, dan itu
		-- kebalikan dari sebelumnya.
		--
		-- Dulu semua border AlwaysOnTop, alasannya: kerumunan tumbuh ke
		-- arah kamera, jadi yang bayar lima menit lalu berdiri di
		-- belakang orang-orang baru, dan border yang bisa terhalang
		-- berarti dia membayar untuk sesuatu yang hilang saat panggung
		-- ramai. Alasan itu masih benar.
		--
		-- Tapi akibatnya: SEMUA border tembus badan sepanjang waktu.
		-- Waktu tier 3 disorot, garis-garis milik barisan di depannya
		-- ikut menumpuk di frame -- persis di lima detik yang paling
		-- ditonton, dan justru mengotori adegan orang yang baru bayar.
		--
		-- Jadi hak "tembus badan" dipindah: bukan milik semua border
		-- sepanjang waktu, tapi milik border orang yang SEDANG DISOROT
		-- selama sorotannya (dipasang di spawnAvatar). Waktu dia sudah
		-- terkubur di kerumunan, dia bukan fokus lagi -- dan di situ
		-- border yang terhalang tidak merugikan siapa pun.
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent    = model
		rec.garis   = h

		table.insert(borderHidup, rec)
	end

	if BORDER_CAKRAM then
		local c = Instance.new("Part")
		c.Name         = "CakramTier"
		c.Shape        = Enum.PartType.Cylinder
		-- Cylinder Roblox tidur di sumbu X: sisi bundarnya menghadap
		-- +X/-X. Diputar 90 derajat di sumbu Z supaya bundarnya
		-- menghadap ke atas, jadi cakram, bukan tiang.
		c.Size         = Vector3.new(BORDER_CAKRAM_TIPIS * (skala or 1),
			d, d)
		c.Anchored     = true
		c.CanCollide   = false
		c.CanQuery     = false
		c.CanTouch     = false
		c.CastShadow   = false
		c.Material     = Enum.Material.Neon
		c.Color        = warna
		c.Transparency = BORDER_CAKRAM_ALPHA
		c.CFrame       = CFrame.new(model:GetPivot().Position.X, kakiY + 0.05,
			model:GetPivot().Position.Z) * CFrame.Angles(0, 0, math.rad(90))
		c.Parent       = workspace
		rec.cakram     = c

		if BORDER_CAKRAM_LAMPU > 0 then
			local l = Instance.new("PointLight")
			l.Color     = warna
			l.Range     = BORDER_CAKRAM_LAMPU * (skala or 1)
			l.Brightness = 2
			l.Parent    = c
		end
	end

	local umur = umurBorder(tier)
	if umur > 0 then
		task.delay(umur, function() lepasBorder(rec) end)
	end

	return rec
end

-- --- RAKSASA (tier 3) ---

-- Buang raksasa yang sedang berdiri.
--
-- Langsung dihapus, tanpa animasi tenggelam. Versi sebelumnya
-- menurunkannya pelan-pelan lewat BodyPosition supaya pergantiannya
-- terlihat halus -- tapi itu jalur khusus yang sama yang membuat
-- raksasa bisa tersangkut di bawah tanah, dan satu detik kehalusan
-- tidak sebanding dengan itu.
-- Hapus avatar nova yang tersisa sesudah adegannya.
--
-- Dipisah dari buangRaksasa walau isinya mirip: yang satu dipanggil
-- karena ada raksasa BARU (giliran yang lama habis), yang ini karena
-- sorotannya sendiri sudah selesai. Dua sebab yang berbeda, dan
-- menyatukannya berarti mengubah salah satunya ikut mengubah yang lain.
local function buangNova()
	local lama = avatars[SLOT_NOVA]
	if not lama then return end

	local t = tracks[SLOT_NOVA]
	if t then pcall(function() t:Stop() end) end

	avatars[SLOT_NOVA] = nil
	tracks[SLOT_NOVA]  = nil

	if lama.Parent then lama:Destroy() end
end

local function buangRaksasa()
	local lama = avatars[SLOT_RAKSASA]
	if not lama then return end

	local t = tracks[SLOT_RAKSASA]
	if t then pcall(function() t:Stop() end) end

	avatars[SLOT_RAKSASA] = nil
	tracks[SLOT_RAKSASA]  = nil

	if lama.Parent then lama:Destroy() end
end

-- ============ KAMERA ============

-- Titik yang dipandang kamera. Cuma satu pesan: "pandang ke sini".
-- Ayunan kiri-kanannya jalan terus-menerus di client.
-- `lamaS` diisi cuma untuk kedatangan bertier. Selama itu client
-- berhenti mengayun dan mengorbit penuh; sesudahnya dia kembali sendiri
-- tanpa perlu pesan kedua. Sengaja begitu: pesan "sudah selesai" yang
-- hilang di jaringan akan meninggalkan kamera terkunci selamanya,
-- sementara batas waktu yang sudah ada di tangan client tidak bisa
-- hilang.
-- `orbit` memisahkan sorotan tier 2 dari tier 3/4: yang satu cuma
-- menahan dekat, yang lain mengelilingi. `jauh` mengalikan jarak
-- kameranya -- dipakai raksasa, yang tidak muat di frame pada jarak
-- biasa.
-- `k` tabel dari kameraTier(tier). Seluruh bentuk adegannya dikirim
-- per kedatangan, jadi client tidak perlu tahu tier sama sekali -- dia
-- cuma menjalankan angka yang diberikan. Itu yang membuat menambah tier
-- kelima nanti tidak menyentuh file client sama sekali.
local function fokusKamera(pos, lamaS, orbit, jauh, k, tier, jauhY, model)
	V2Event:FireAllClients("fokus", {
		pos      = pos,
		-- Avatarnya sendiri, cuma untuk tier yang punya efek layar: garis
		-- tepinya yang dibuat berdenyut di client (LAYAR, `garis`).
		model    = (k.layar or k.jalur) and model or nil,
		-- Jalur kamera sendiri dan tema latarnya (Rosa). nil untuk tier
		-- lain. Temanya diundi DI SINI supaya sama di semua layar.
		jalur    = k.jalur,
		tema     = k.jalur and ROSA.TEMA[math.random(1, #ROSA.TEMA)] or nil,
		-- Detik ke berapa angka auranya MENDARAT, dihitung dari pesan ini.
		-- Kilatan layarnya dijadwalkan ke sini supaya jatuh di frame yang
		-- sama dengan hentakan mendaratnya.
		layarKilat = k.layar and ((k.tunda or 0) + (k.roll or AURA_ROLL))
			or nil,
		-- Tinggi kamera saat mundur penuh. Dikirim per kedatangan,
		-- bukan sekali lewat V2Config, karena jawabannya BERUBAH: dia
		-- turun selama ada raksasa berdiri supaya kepala raksasanya
		-- masuk frame. Lihat CAMERA_UP_JAUH_GIANT.
		--
		-- Raksasa bertahan sampai ada raksasa berikutnya, jadi sekali
		-- dia datang semua pesan sesudahnya membawa angka yang sama --
		-- tidak ada keadaan yang harus disimpan di client selain nilai
		-- terakhir yang dia terima.
		upJauh   = avatars[SLOT_RAKSASA] and CAMERA_UP_JAUH_GIANT
			or CAMERA_UP_JAUH,
		sinema   = (lamaS and lamaS > 0) and true or nil,
		lama     = lamaS,
		-- Dipakai client cuma untuk memilih bunyi kedatangannya (lihat
		-- SFX_TIER). Bentuk gerakan kameranya TIDAK dibaca dari angka
		-- ini -- semuanya sudah dikirim sebagai angka jadi di bawah,
		-- supaya client tetap tidak perlu tahu arti tier.
		tier     = tier,
		-- Bunyi kedatangannya dibunyikan client sendiri NANTI (nova: saat
		-- dia membanting diri ke tanah), jadi pesan ini tidak boleh ikut
		-- membunyikannya.
		bunyiNanti = k.bunyiSaatNova and true or nil,
		orbit    = orbit and true or nil,
		jauh     = (jauh and jauh > 1) and jauh or nil,
		-- Pengali TINGGI kamera, terpisah dari pengali jaraknya di atas.
		-- nil = tingginya ikut jaraknya, seperti semua tier selain
		-- raksasa. Lihat GIANT_KAMERA_TINGGI.
		jauhY    = (jauhY and jauhY > 1) and jauhY or nil,
		-- Efek layar sinematik selama sorotan (letterbox, warna, sekejap
		-- abu-abu). nil untuk tier yang tidak punya -- lihat LAYAR.
		layar      = k.layar,
		zoomTahan  = k.tahan,
		zoomKeluar = k.keluar,
		-- Sedekat apa rapatan awalnya. nil untuk tier yang memakai
		-- ZOOM_MASUK biasa -- dan client yang membaca nil jatuh ke
		-- CFG.zoomMasuk, jadi pesan tier lain tidak ikut membesar.
		zoomMasuk  = k.masuk,
		-- Mundur sampai sejauh apa, pecahan jarak penuh. Lihat `maks`
		-- di KAMERA_TIER.
		zoomMaks   = k.maks,
		-- Busur DEPAN: seberapa jauh menyimpang ke samping (derajat),
		-- berapa kali menyapu, dan seberapa jauh naik-turun (stud).
		--
		-- Kamera tidak pernah keluar dari kerucut depan ini -- lihat
		-- KAMERA_TIER untuk alasannya.
		arcDeg     = (k.arcDeg and k.arcDeg > 0) and k.arcDeg or nil,
		arcPutar   = k.arcPutar,
		naikAmp    = (k.naikAmp and k.naikAmp ~= 0) and k.naikAmp or nil,
		-- Berapa gundukan naik-turunnya. nil untuk yang cuma satu
		-- (client jatuh ke 1), jadi pesan tier lain tidak ikut membesar.
		naikPutar  = (k.naikPutar and k.naikPutar > 1) and k.naikPutar or nil,
		-- Denyut zoom: masuk lagi di paruh kedua adegan. Cuma tier 3
		-- yang punya, jadi ketiganya nil untuk yang lain -- dan client
		-- yang membaca nil TIDAK berdenyut sama sekali.
		denyutDalam = (k.denyutDalam and k.denyutDalam > 0)
			and k.denyutDalam or nil,
		denyutMulai = k.denyutMulai,
		denyutUlang = k.denyutUlang,
	})
end

local function titikPanggung()
	for slot = slotCount, 1, -1 do
		local m = avatars[slot]
		if m and m.Parent then return titikPandang(slot) end
	end
	return Vector3.new(0, CAMERA_FOKUS_Y, 0)
end

-- ============ PANGGUNG ============

-- --- GEMPA: barisan tersapu hantaman nova ---
--
-- Dipanggil TEPAT saat avatar nova menghantam tanah. Semua yang sedang
-- menari di barisan terlempar keluar dari titik hantam, berputar,
-- memudar, lalu dihapus -- dan panggungnya kembali kosong dari slot 1.
--
-- Avatar novanya sendiri tidak perlu dikecualikan di sini. Dia memegang
-- SLOT_NOVA sejak lahir, di luar 1..slotCount, jadi gelung di bawah
-- memang tidak bisa menyentuhnya. Versi sebelumnya menerima parameter
-- `kecuali` untuk itu -- dan parameter itulah yang dulu bisa menunjuk
-- slot milik orang lain kalau panggungnya sempat di-reset selagi
-- adegannya jalan, yang berarti menyelamatkan orang yang salah.
--
-- KENAPA TWEEN, BUKAN FISIKA SUNGGUHAN
--
-- Melepas kunci lalu mendorong badannya dengan impuls memang lebih
-- nyata, tapi harganya delapan puluh avatar meragdoll berbarengan --
-- tepat di detik yang paling ditonton dari seluruh siaran, dan tepat
-- saat client juga sedang menggambar shockwave, pilar cahaya, delapan
-- petir, dan dua puluh kristal. Yang pertama jatuh FPS-nya.
--
-- Tween juga menyelesaikan hal yang tidak bisa diselesaikan fisika:
-- hasilnya SAMA di tiap layar. Fisika Roblox tidak deterministik antar
-- client, jadi dengan impuls, satu penonton melihat kerumunan terlempar
-- ke kiri dan penonton lain ke kanan.
--
-- Kuncinya tetap harus dibuang lebih dulu: BodyPosition menarik badan
-- kembali ke slotnya dengan gaya ratusan kali beratnya, dan tween yang
-- melawan itu tidak bergerak satu stud pun.
local GEMPA_LAMA   = 0.8    -- lama terlemparnya, detik
local GEMPA_JAUH   = 55     -- sejauh ini dari titik hantam, stud
local GEMPA_NAIK   = 22     -- dan setinggi ini di puncak lemparannya

local function gempaBarisan(pusat)
	local kena = 0

	for slot = 1, slotCount do
		local model = avatars[slot]
		if model and model.Parent then
			local track = tracks[slot]
			if track then pcall(function() track:Stop() end) end

			local hrp = model:FindFirstChild("HumanoidRootPart")
			if hrp then
				-- Kunci posisi dibuang, lalu badannya di-anchor supaya
				-- tween yang menulis CFrame tidak dilawan fisika.
				-- Sisa badannya ikut lewat Motor6D.
				for _, nama in ipairs({ "PositionLock", "RotationLock" }) do
					local m = hrp:FindFirstChild(nama)
					if m then m:Destroy() end
				end

				-- Supaya mereka tidak saling menabrak selagi terlempar.
				-- Tanpa ini yang terlihat bukan kerumunan yang tersapu,
				-- tapi tumpukan badan yang saling mendorong di tempat.
				for _, x in ipairs(model:GetDescendants()) do
					if x:IsA("BasePart") then x.CanCollide = false end
				end

				-- Yang di-anchor CUMA root-nya, bukan semua part.
				--
				-- Part yang tersambung Motor6D membentuk satu assembly:
				-- begitu root-nya di-anchor, seluruh assembly ikut
				-- kinematik dan menyeret mengikuti CFrame root. Kalau
				-- SETIAP part di-anchor sendiri-sendiri, tiap part jadi
				-- assembly-nya sendiri -- root-nya terbang, badannya
				-- tertinggal berdiri di tempat.
				hrp.Anchored = true

				-- Arahnya MENJAUH dari titik hantam, dan yang lebih
				-- dekat terlempar lebih jauh -- itu yang membuatnya
				-- terbaca sebagai gelombang yang berasal dari satu
				-- titik, bukan sebagai semua orang meloncat bersamaan.
				local ke = hrp.Position - pusat
				ke = Vector3.new(ke.X, 0, ke.Z)
				local jarak = ke.Magnitude
				if jarak < 0.5 then
					-- Tepat di titik hantam: arahnya diundi, kalau
					-- tidak dia satu-satunya yang tidak ikut terlempar.
					local a = math.random() * math.pi * 2
					ke = Vector3.new(math.cos(a), 0, math.sin(a))
					jarak = 1
				else
					ke = ke / jarak
				end
				local kuat = math.clamp(1 - jarak / 90, 0.35, 1)

				local tujuan = CFrame.new(hrp.Position
						+ ke * (GEMPA_JAUH * kuat)
						+ Vector3.new(0, GEMPA_NAIK * kuat, 0))
					* CFrame.Angles(math.random() * 6,
						math.random() * 6, math.random() * 6)

				TweenService:Create(hrp,
					TweenInfo.new(GEMPA_LAMA, Enum.EasingStyle.Quad,
						Enum.EasingDirection.Out),
					{ CFrame = tujuan }):Play()

				-- Memudar bareng terlemparnya, jadi yang sampai ke tepi
				-- frame sudah hampir tidak ada -- bukan badan utuh yang
				-- mendadak dihapus.
				for _, x in ipairs(model:GetDescendants()) do
					if x:IsA("BasePart") and x.Transparency < 1 then
						TweenService:Create(x,
							TweenInfo.new(GEMPA_LAMA * 0.9),
							{ Transparency = 1 }):Play()
					end
				end
			end

			-- Dihapus SESUDAH lemparannya selesai, bukan sekarang.
			--
			-- Ini yang gampang salah: Destroy() di baris ini membuat
			-- seluruh tween di atas tidak pernah tergambar satu frame
			-- pun -- yang terlihat cuma kerumunan yang LENYAP di detik
			-- hantaman. Referensinya sudah dilepas dari `avatars` di
			-- bawah, jadi tidak ada lagi yang bisa memakainya selama
			-- dia terbang.
			local pergi = model
			task.delay(GEMPA_LAMA + 0.1, function()
				if pergi.Parent then pergi:Destroy() end
			end)
			kena = kena + 1
		end

		avatars[slot] = nil
		tracks[slot]  = nil
	end

	-- Cakram lantai dan border hidup di luar model avatarnya, jadi
	-- menghapus badannya saja meninggalkan lingkaran menyala di panggung
	-- kosong. Alasan lengkapnya di resetStage.
	for i = #borderHidup, 1, -1 do
		lepasBorder(borderHidup[i], true)
	end
	for _, benda in ipairs(workspace:GetChildren()) do
		if benda.Name == "CakramTier" then benda:Destroy() end
	end

	slotCount = 0
	barisanGen += 1
	print(("[nova] gempa -- %d avatar tersapu, barisan kembali ke slot 1")
		:format(kena))
end

-- --- AVATAR NOVA MASUK BARISAN ---
--
-- Dipanggil tepat sesudah gempaBarisan, di detik yang sama: dia
-- menghantam tanah, barisannya tersapu habis, dan dia sendiri berdiri
-- sebagai orang PERTAMA di barisan yang baru.
--
-- Ini menggantikan buangNova() yang dulu dijadwalkan di akhir
-- sorotannya. Yang dulu terjadi: adegan sepuluh detik, sorotan, lalu
-- orangnya menghilang begitu saja dari panggung -- padahal yang bayar
-- paling mahal justru dia. Sekarang dia tinggal seperti kedatangan
-- biasa, dan yang menghapusnya nanti sama dengan yang menghapus semua
-- orang: panggung penuh (resetStage) atau nova berikutnya.
--
-- Dulu itu tidak bisa dilakukan, dan alasannya sudah hilang sekarang:
-- avatar novanya berdiri di slot barisan LAMAnya (n(x)), yang beberapa
-- kedatangan kemudian diisi orang lain -- dua badan di satu titik.
-- Sekarang dia mendarat di slot 1, dan slotCount dimulai dari dia, jadi
-- orang berikutnya dapat slot 2 seperti seharusnya.
--
-- Badannya ikut dipindah, bukan cuma nomornya: kunci posisinya
-- (BodyPosition/BodyGyro) diarahkan ulang ke titik yang sama dengan
-- yang dipakai salinan nova di client untuk membanting diri, jadi waktu
-- client memunculkan kembali avatar aslinya di akhir adegan, dia sudah
-- berdiri persis di tempat salinannya mendarat.
local function novaKeBarisan(model, tujuan)
	if avatars[SLOT_NOVA] ~= model then return end

	avatars[SLOT_NOVA_MENDARAT] = model
	tracks[SLOT_NOVA_MENDARAT]  = tracks[SLOT_NOVA]
	avatars[SLOT_NOVA] = nil
	tracks[SLOT_NOVA]  = nil
	slotCount = SLOT_NOVA_MENDARAT

	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp then
		local bp = hrp:FindFirstChild("PositionLock")
		local bg = hrp:FindFirstChild("RotationLock")
		if bp then bp.Position = tujuan.Position end
		if bg then bg.CFrame   = tujuan end
	end
	model:PivotTo(tujuan)

	print(("[nova] %s mendarat di slot %d -- dia yang membuka barisan baru")
		:format(model.Name, SLOT_NOVA_MENDARAT))
end

local function resetStage()
	if resetting then return end
	resetting = true

	local dihapus = 0

	-- RAKSASA TIDAK IKUT DIHAPUS.
	--
	-- Nomornya di luar 1..slotCount, jadi gelung di bawah memang tidak
	-- menyentuhnya -- dan itu sekarang disengaja. Dia cuma berganti
	-- kalau ADA GIFT RAKSASA BARU; tidak ada hal lain di panggung ini
	-- yang boleh menurunkannya.
	--
	-- Reset apa pun -- panggung penuh, atau nanti kalau ada tier baru
	-- yang mengosongkannya -- cuma menyapu BARISAN. Raksasa berdiri di
	-- belakang, di luar barisan, dan dia tetap di sana: gilirannya
	-- berakhir waktu ada raksasa berikutnya, bukan sebelum itu.
	--
	-- Yang menghapusnya cuma satu tempat: buangRaksasa().

	for slot = 1, slotCount do
		local track = tracks[slot]
		if track then pcall(function() track:Stop() end) end

		local model = avatars[slot]
		if model and model.Parent then
			model:Destroy()
			dihapus += 1
		end

		avatars[slot] = nil
		tracks[slot]  = nil
	end

	-- Cakram lantai hidup di workspace, BUKAN di dalam model avatarnya
	-- -- dia harus bisa bergerak sendiri waktu adegan Matrix jalan.
	-- Artinya menghapus avatarnya saja meninggalkan cakram menyala di
	-- panggung kosong. Ini yang membersihkannya.
	for i = #borderHidup, 1, -1 do
		lepasBorder(borderHidup[i], true)
	end
	for _, benda in ipairs(workspace:GetChildren()) do
		if benda.Name == "CakramTier" then benda:Destroy() end
	end

	slotCount = 0
	barisanGen += 1
	resetting = false
	print(("Panggung dikosongkan (%d avatar)."):format(dihapus))
end

-- username (huruf kecil) -> userId. Sebuah userId tidak pernah berubah,
-- jadi nama yang muncul dua kali -- dan saat live itu sering -- cuma
-- boleh memakan satu panggilan.
local idCache = {}

-- userId untuk sebuah nama.
--
-- Jalur utamanya: dibaca dari /api/next. main.py sudah memanggil
-- users.roblox.com untuk displayName, dan satu panggilan itu membawa
-- id-nya sekalian -- gratis, dan sudah di-cache di sisi Python.
--
-- Kenapa itu penting: GetUserIdFromNameAsync punya rate limit sendiri
-- yang jauh lebih ketat daripada polling antrian. Begitu kena, dia
-- membalas HTTP 429 untuk SEMUA nama berikutnya -- termasuk nama yang
-- valid -- jadi panggung mendadak kosong total padahal antriannya penuh.
-- Persis itu yang terjadi waktu `make mock` mengisi antrian sekaligus.
--
-- Jalur cadangannya tetap ada (server versi lama tidak mengirim userId),
-- dan di situ kegagalan dicoba ulang dengan jeda MEMANJANG: 429 artinya
-- "kamu terlalu cepat", jadi mengulang seketika cuma memperpanjang
-- hukumannya.
local function cariUserId(username, dariServer)
	if type(dariServer) == "number" and dariServer > 0 then
		return dariServer
	end

	local key = string.lower(username)
	if idCache[key] then return idCache[key] end

	local jeda = 2
	for percobaan = 1, 3 do
		local ok, id = pcall(function()
			return Players:GetUserIdFromNameAsync(username)
		end)

		if ok and id then
			idCache[key] = id
			return id
		end

		if percobaan == 3 then
			-- Dilempar ulang, bukan dikembalikan nil: pemanggilnya
			-- membungkus spawnAvatar dengan pcall dan sudah mencetak
			-- pesan gagalnya.
			error(tostring(id), 0)
		end

		warn(("userId '%s' gagal (percobaan %d), ulang %d detik lagi: %s")
			:format(username, percobaan, jeda, tostring(id)))
		task.wait(jeda)
		jeda *= 2
	end
end

local function spawnAvatar(entry, slot)
	local username = entry.username

	-- Semua angka tier datang dari /api/next. Kalau server-nya versi
	-- lama (atau TIER_ENABLED dimatikan), semuanya jatuh ke tier 1 dan
	-- bagian di bawah ini tidak satu pun menyala.
	local tier   = TIER_ENABLED and tonumber(entry.tier) or 1
	if not tier or tier < 1 then tier = 1 end
	local lamaMs = tonumber(entry.spotlightMs) or 0
	local sorot  = (entry.spotlight == true) and lamaMs > 0
	local lamaS  = sorot and (lamaMs / 1000) or 0
	local orbit  = (entry.orbit == true)

	-- Raksasa. Skalanya datang dari server (TIER4_SCALE di .env) dan
	-- cuma DIBATASI di sini -- rig 40x membuat massanya melonjak
	-- ~64.000 kali dan pegas penahannya tidak sanggup lagi: badannya
	-- melorot menembus lantai beberapa detik setelah mendarat.
	--
	-- Angka cadangan 4 di bawah cuma dipakai kalau server tidak
	-- mengirim `scale` sama sekali (versi lama). Disamakan dengan
	-- TIER4_SCALE di .env supaya keduanya tidak pernah bercerita beda.
	--
	-- Lewat adalahRaksasa(), BUKAN dengan menulis ulang syaratnya di
	-- sini. Alasannya ada di komentar fungsi itu -- ringkasnya, versi
	-- sebelumnya menulis syarat ini dua kali dan keduanya sempat tidak
	-- sepakat, yang membuat tier 3 dan tier 4 tertukar tempat.
	local raksasa = adalahRaksasa(tier)
	local nova    = adalahNova(tier)
	local skala   = 1
	if raksasa then
		skala = math.clamp(tonumber(entry.scale) or 4, 1, GIANT_SKALA_MAKS)
	end

	-- Dipotong di sini, bukan di gelung utama, supaya kamera dan
	-- panggung memakai angka yang PERSIS sama. Dua tempat yang
	-- memotong angka yang sama adalah cara paling rapi untuk suatu
	-- saat punya kamera yang masih mengorbit setelah orangnya mendarat.
	if lamaS > BEKU_MAKS then lamaS = BEKU_MAKS end

	-- Dicatat SEBELUM yield pertama. Lihat pemeriksaannya di bawah.
	local genBarisan = barisanGen

	local userId = cariUserId(username, entry.userId)
	local desc   = Players:GetHumanoidDescriptionFromUserId(userId)

	local model  = Players:CreateHumanoidModelFromDescription(
		desc, Enum.HumanoidRigType.R15)

	model.Name = username

	-- ScaleTo, bukan mengubah skala di HumanoidDescription.
	--
	-- HumanoidDescription punya HeightScale/WidthScale, tapi mereka
	-- dibatasi rentang yang dianggap wajar untuk avatar pemain --
	-- sepuluh kali lipat lewat jauh dari itu dan diam-diam dipangkas.
	-- ScaleTo tidak punya batas dan ikut menyesuaikan Motor6D serta
	-- HipHeight, jadi animasinya tetap benar dan kakinya tetap
	-- menyentuh lantai.
	if raksasa and skala > 1 then
		-- Tingginya diukur SEBELUM dan SESUDAH, lalu dibandingkan.
		--
		-- Dulu baris ini cuma `pcall(... ScaleTo ...)` tanpa membaca
		-- hasilnya, dan itu kesalahan yang mahal: ada DUA cara ScaleTo
		-- gagal, dan dua-duanya diam.
		--
		--   a. dia melempar error  -> ditelan pcall
		--   b. dia jalan tapi tidak mengubah apa pun
		--
		-- Yang terlihat di layar untuk keduanya sama: avatar seukuran
		-- orang biasa berdiri sendirian jauh di belakang barisan --
		-- yaitu "raksasanya tidak muncul". Sekarang keduanya bicara.
		local sebelum = select(2, model:GetBoundingBox()).Y
		local okSkala, errSkala = pcall(function()
			model:ScaleTo(skala)
		end)
		local sesudah = select(2, model:GetBoundingBox()).Y

		if not okSkala then
			warn(("[raksasa] ScaleTo(%.1f) DITOLAK: %s -- dia akan " ..
				"berdiri seukuran orang biasa."):format(skala, tostring(errSkala)))
		elseif sebelum > 0 and sesudah / sebelum < skala * 0.8 then
			warn(("[raksasa] ScaleTo(%.1f) jalan tapi tingginya cuma " ..
				"naik %.1fx (%.1f -> %.1f stud). Rig-nya menolak " ..
				"diperbesar sebanyak itu; turunkan TIER5_SCALE di .env.")
				:format(skala, sesudah / math.max(sebelum, 0.01),
					sebelum, sesudah))
		else
			print(("[raksasa] skala %.1fx -- tinggi %.1f -> %.1f stud")
				:format(skala, sebelum, sesudah))
		end
	end

	-- Pivot dipaksa ke HumanoidRootPart. Kalau PrimaryPart kosong, pivot
	-- jatuh ke tengah kotak pembungkus -- yang ikut bergeser kalau
	-- avatarnya pakai topi tinggi.
	local hrp = model:FindFirstChild("HumanoidRootPart")
	if hrp then model.PrimaryPart = hrp end

	-- Tabrakan dimatikan: mereka cuma pajangan, posisinya dipegang
	-- BodyPosition. Anggota badan yang menyerempet tetangga waktu menari
	-- cuma jadi gaya dorong yang harus dilawan.
	for _, bagian in ipairs(model:GetDescendants()) do
		if bagian:IsA("BasePart") then bagian.CanCollide = false end
	end

	if hrp then hrp.Anchored = true end

	-- Langsung berdiri di slotnya. Tidak ada jatuh, tidak ada meteor.
	--
	-- Raksasa lewat jalur yang PERSIS SAMA. Dia tidak lagi disembunyikan
	-- di bawah tanah untuk dinaikkan belakangan -- lihat catatan di
	-- bagian TIER 3 soal kenapa jalur khusus itu dibuang.
	model:PivotTo(finalCFrame(model, slot))

	-- Ditandai SEBELUM masuk workspace, bukan sesudah: atribut ikut
	-- terkirim bersama modelnya, jadi client sudah tahu "yang ini akan
	-- nova" di frame pertama dia melihatnya -- dan menahannya tetap
	-- tersembunyi. Kalau ditandai sesudahnya, avatar aslinya sempat
	-- berdiri sekejap di slot, lalu hilang waktu salinan novanya
	-- mengambil alih -- satu kedipan yang terbaca sebagai bug.
	--
	-- NovaId ikut dipasang di sini, dan itu jaring pengaman untuk satu
	-- kegagalan yang tidak memunculkan satu pun error: referensi
	-- Instance di dalam pesan remote sampai sebagai NIL kalau modelnya
	-- belum selesai direplikasi ke client itu. Yang terlihat waktu itu
	-- terjadi persis "novanya tidak muncul, cuma kameranya yang
	-- bergerak" -- kameranya jalan karena pesan `fokus` tidak membawa
	-- Instance apa pun. Dengan nomor ini, client bisa menunggu
	-- modelnya datang lewat ChildAdded dan tetap menjalankan adegannya.
	if nova then
		novaIdBerikut += 1
		model:SetAttribute("TierNova", true)
		model:SetAttribute("NovaId", novaIdBerikut)

		-- Persistent: modelnya dikirim UTUH ke semua client, dan tidak
		-- pernah dicabut lagi -- walaupun StreamingEnabled menyala.
		--
		-- Dengan streaming, client cuma menerima benda di sekitar
		-- KARAKTER penontonnya. Kamera panggung ini scriptable dan jauh
		-- dari karakter itu, jadi avatar nova bisa belum sampai, sampai
		-- sepotong, atau dicabut di tengah adegan -- dan ketiganya
		-- berakhir sama: avatarnya berdiri tanpa efek, "kadang-kadang",
		-- tergantung di mana karakter penontonnya kebetulan berdiri.
		--
		-- Tidak berbuat apa-apa kalau streaming mati, jadi aman dipasang
		-- tanpa syarat. pcall karena properti ini tidak ada di versi
		-- Roblox yang sangat lama.
		pcall(function()
			model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		end)
	end

	-- Pra-muat dulu, baru panggung. Lihat SPAWN_PRAMUAT_S.
	if SPAWN_PRAMUAT_S > 0 then
		model.Parent = folderPramuat
		task.wait(SPAWN_PRAMUAT_S)
		-- Dihapus selagi menunggu (tidak ada yang melakukannya sekarang,
		-- tapi task.wait di tengah fungsi ini membuka jendela untuk itu).
		if not model.Parent then return end
	end

	model.Parent = workspace

	createNameplate(model, username)

	-- Satu frame: HipHeight baru final setelah modelnya masuk workspace,
	-- dan tinggi yang meleset sedikit langsung terlihat sebagai kaki
	-- mengambang atau terbenam.
	RunService.Heartbeat:Wait()
	if not model.Parent then return end

	-- Barisan dikosongkan selagi avatar ini dimuat.
	--
	-- Slotnya dipesan gelung utama SEBELUM semua yield di atas (unduh
	-- deskripsi + SPAWN_PRAMUAT_S). Kalau di tengahnya resetStage atau
	-- gempa nova menyetel slotCount kembali ke awal, nomor lama ini
	-- dipakai lagi oleh kedatangan berikutnya: dua badan di satu titik,
	-- dan satunya tidak pernah terhapus reset mana pun karena barisnya
	-- di tabel avatars sudah ditimpa. Dia diberi tempat baru di barisan
	-- yang baru -- orangnya tetap tampil, cuma pindah antrian.
	if slot ~= SLOT_RAKSASA and barisanGen ~= genBarisan then
		slotCount += 1
		print(("[slot] %s dimuat selagi barisan dikosongkan -- slot %d -> %d")
			:format(username, slot, slotCount))
		slot = slotCount
	end

	local target = finalCFrame(model, slot)
	model:PivotTo(target)

	if hrp then
		hrp.Anchored = false
		lockInPlace(model, hrp, target)
	end

	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		-- Nametag bawaan Roblox -- nama kecil abu-abu di bawah papan
		-- aura, yang bikin username tertulis DUA KALI.
		--
		-- Dulu baris ini tinggal di dalam createNameplate, jadi dia ikut
		-- mati waktu PLATE.ENABLED dimatikan -- dan nametag bawaannya
		-- hidup lagi. Sekarang di sini: berlaku untuk semua avatar,
		-- lepas dari papan nama mana pun yang dipakai.
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType   = Enum.HumanoidHealthDisplayType.AlwaysOff

		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
		-- Mesin keadaan Humanoid terus mendorong badan supaya berdiri
		-- setinggi HipHeight, dan dorongan itu tarik-menarik dengan
		-- BodyPosition -- hasilnya tarian yang bergetar. Physics
		-- mematikannya; animasi tetap jalan karena digerakkan Motor6D.
		pcall(function()
			hum:ChangeState(Enum.HumanoidStateType.Physics)
		end)
		pcall(function() hum.EvaluateStateMachine = false end)
	end

	-- Nova dibukukan di SLOT_NOVA, bukan di slot barisannya.
	--
	-- Tempatnya di barisan tetap dipakai (slotCount sudah naik di gelung
	-- utama, dan finalCFrame di atas menaruh badannya di sana), yang
	-- tidak dipakai cuma satu baris tabel ini. Alasannya di SLOT_NOVA:
	-- selama sepuluh detik adegannya, barisan yang kebetulan penuh
	-- memanggil resetStage, dan reset itu dulu menghapus avatarnya di
	-- tengah adegan.
	local kunci = nova and SLOT_NOVA or slot
	if nova then buangNova() end
	avatars[kunci] = model

	-- Raksasa MELAMBAI, bukan menari. Alasan lengkapnya di
	-- GIANT_EMOTE_ID; ringkasnya, yang diam di antara yang bergerak
	-- justru yang ditonton.
	if raksasa then
		local emote = playDance(model, GIANT_EMOTE_ID)
		if emote then
			pcall(function() emote:AdjustSpeed(GIANT_EMOTE_SPEED) end)
		end
		tracks[kunci] = emote
	else
		tracks[kunci] = playDance(model, danceSekarang())
	end

	-- Raksasa TIDAK dapat border maupun cakram lantai.
	--
	-- Cakram itu justru satu-satunya yang sempat terlihat waktu
	-- raksasanya sendiri tersangkut di bawah tanah: dia ditaruh di
	-- permukaan lantai lepas dari posisi badannya, jadi yang tampil
	-- cuma lingkaran besar bersinar tanpa siapa pun berdiri di atasnya.
	--
	-- Dan memang tidak dibutuhkan: yang membuat tier 3 terbaca UKURAN
	-- badannya. Menambahkan lingkaran di kakinya cuma menyaingi satu-
	-- satunya hal yang jadi intinya.
	-- Border cuma untuk tier 2. Raksasa tidak dapat: yang membuatnya
	-- terbaca ukuran badannya, dan lingkaran di kakinya cuma menyaingi
	-- itu.
	-- Nova juga tidak: Highlight di badan yang disembunyikan client
	-- selama adegannya tetap digambar -- yang terlihat jadi garis tepi
	-- kosong berdiri di slot selagi orangnya melayang di atasnya. Dan
	-- kalaupun tidak, dia punya outline putihnya sendiri di dalam
	-- TierNova, yang dua-duanya menyala berarti dua garis tepi.
	if not raksasa and not nova then
		local rec = pasangBorder(model, slot, tier, FLOOR_Y, skala)

		-- Yang sedang disorot boleh menembus badan, selama sorotannya.
		--
		-- Ini pengecualian dari Occluded di pasangBorder, dan
		-- alasannya ada di sana. Dibalikkan sesudah adegannya supaya
		-- dia tidak ikut mengotori adegan orang berikutnya.
		if rec and rec.garis and lamaS and lamaS > 0 then
			local garis = rec.garis
			garis.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			task.delay(lamaS, function()
				-- Border-nya bisa sudah dilepas (jatah Highlight penuh,
				-- atau umurnya habis) selagi ditunggu.
				if garis.Parent then
					garis.DepthMode = Enum.HighlightDepthMode.Occluded
				end
			end)
		end
	end


	-- Kamera dikasih tahu berapa lama dia harus nempel SEBELUM
	-- auranya keluar: angka aura butuh AURA_ROLL detik untuk berputar,
	-- dan kalau kameranya baru pindah sesudah itu, putarannya sudah
	-- setengah jalan waktu orangnya masuk frame.
	-- Nova dibidik di slot tempat dia MENDARAT, bukan di slot tempat dia
	-- mulai. Selama adegannya kamera dipegang jalur nova di client, jadi
	-- angka ini baru terlihat sesudah adegan itu melepaskannya -- dan di
	-- detik itu orangnya sudah pindah ke slot 1 (novaKeBarisan). Yang
	-- lama membuat kamera pulang ke slot kosong tempat dia dulu berdiri,
	-- sementara orangnya menari di ujung lain panggung.
	local fokusPos = titikPandang(nova and SLOT_NOVA_MENDARAT or slot)
	local jauh     = 1
	local jauhY    = 1
	if raksasa then
		-- Dipandang di TENGAH BADAN, bukan di titik berdirinya.
		-- Kamera yang membidik kakinya menampilkan sepatu setinggi
		-- layar dan kepalanya jauh di luar frame atas.
		local tp = tinggiPivot(model) or (BASE_Y * skala)
		fokusPos = Vector3.new(GIANT_X,
			FLOOR_Y + tp * GIANT_FOKUS_TINGGI, GIANT_Z)
		jauh     = math.max(1, skala * GIANT_KAMERA_JAUH)
		jauhY    = math.max(1, skala * GIANT_KAMERA_TINGGI)
	end
	-- Orbit dimatikan untuk SEMUA tier sekarang. Penandanya dari
	-- /api/next sengaja tetap dibaca, jadi dia bisa dinyalakan kembali
	-- dari main.py tanpa menyentuh file ini.
	--
	-- Alasannya ada di atas KAMERA_TIER: orbit membawa kamera ke samping
	-- lalu ke belakang, dan dari belakang yang terlihat cuma punggung --
	-- wajah, papan aura, dan border semuanya menghadap ke arah lain.
	-- Gerakan adegannya sekarang busur depan.
	local orbitKamera = (not raksasa) and orbit or false
	local kam = kameraTier(tier)
	fokusKamera(fokusPos, lamaS, orbitKamera, jauh, kam, tier, jauhY, model)

	if nova then
		-- Seed diundi SEKALI di sini dan dikirim ke semua client, jadi
		-- petir dan kristalnya jatuh sama persis di tiap layar. Batasnya
		-- 2^31 - 2 karena TierNova memakai Park-Miller dengan modulus
		-- 2^31 - 1.
		local seed  = math.random(1, 2147483646)
		-- Paletnya diundi TERPISAH dengan math.random, bukan diturunkan
		-- dari seed di atas lewat sisa bagi. Dua alasan, dan yang kedua
		-- yang menentukan:
		--
		--   1. seed itu milik Park-Miller di dalam modul; bit rendahnya
		--      berkorelasi dengan nilainya sendiri, jadi `seed % 3`
		--      menghasilkan undian yang berat sebelah
		--   2. tidak ada yang perlu dihemat. Paletnya toh dikirim UTUH
		--      (warnanya, bukan nomornya), jadi tidak ada kesempatan bagi
		--      dua client untuk tidak sepakat -- yang menyeberang cuma
		--      satu tabel warna yang sudah jadi
		local palet = NOVA.PALET[math.random(1, #NOVA.PALET)]

		-- Di mana dia MEMBANTING DIRI, yang belum tentu tempat dia
		-- mulai melayang.
		--
		-- Dihitung di server dan dikirim, bukan ditentukan client:
		-- gempa, pemindahan slot, dan bantingan salinannya di client
		-- harus jatuh di satu titik yang sama persis, dan tiga jawaban
		-- untuk satu titik adalah tiga kesempatan untuk tidak sepakat.
		--
		-- Slot 1 dan bukan slot asalnya: gempa di detik yang sama
		-- menyapu seluruh barisan, jadi sesudah hantaman panggungnya
		-- memang kosong -- dan yang paling masuk akal berdiri di tempat
		-- paling depan sesudah itu adalah orang yang baru saja
		-- membuatnya kosong.
		local tujuan = finalCFrame(model, SLOT_NOVA_MENDARAT)

		V2Event:FireAllClients("nova", {
			model  = model,
			-- Cadangan kalau `model` di atas sampai sebagai nil karena
			-- modelnya belum direplikasi. Lihat SetAttribute("NovaId").
			novaId = model:GetAttribute("NovaId"),
			tujuan = tujuan,
			seed   = seed,
			config = NOVA.CONFIG,
			-- Jalur kamera adegannya, lihat NOVA.KAMERA.
			kamera = NOVA.KAMERA,
			-- Bunyi per fase, lihat NOVA.SFX. Dimainkan modulnya sendiri
			-- karena dia yang tahu kapan tiap fase mulai -- bunyi yang
			-- dijadwalkan dari luar akan meleset sebanyak tunggu aset.
			sfx    = NOVA.SFX,
			-- Warnanya, bukan nomornya: client tidak pernah perlu tahu
			-- ada berapa palet, dan menambah palet keempat tidak
			-- menyentuh satu baris pun di sana.
			palet  = palet,
			-- Untuk bunyi kedatangannya, yang dibunyikan client saat dia
			-- membanting diri ke tanah.
			tier   = tier,
		})
		print(("[nova] %s dapat palet '%s' (seed %d)")
			:format(username, palet.nama, seed))

		-- --- GEMPA: barisan disapu tepat saat dia menghantam tanah ---
		--
		-- Dijadwalkan dari SINI, bukan dipicu pesan balik dari client:
		-- V2Event sengaja tidak punya OnServerEvent sama sekali (lihat
		-- catatan di NOVA), dan membuka satu cuma untuk ini berarti
		-- client mana pun bisa menyapu panggung kapan saja.
		--
		-- SPAWN_SIAP_MAKS ikut dijumlah karena adegannya baru MULAI
		-- sesudah client selesai menunggu aset avatarnya. Ini membuat
		-- gempanya jatuh 0 sampai 0,6 detik SESUDAH hantaman yang
		-- terlihat, tidak pernah sebelum -- dan arah itu yang benar:
		-- gelombang kejut yang sampai ke kerumunan sepersekian detik
		-- setelah hantamannya terbaca masuk akal, sedangkan kerumunan
		-- yang terlempar sebelum orangnya mendarat tidak.
		local mendarat = NOVA.CONFIG.charge + NOVA.CONFIG.ascend
			+ NOVA.CONFIG.freeze + NOVA.CONFIG.slam
		task.delay(SPAWN_SIAP_MAKS + mendarat, function()
			-- Dia bisa sudah pergi selagi ditunggu (nova berikutnya
			-- lewat buangNova, atau modelnya gagal). Nomornya sendiri
			-- tidak bisa direbut barisan, jadi satu syarat ini cukup.
			if avatars[SLOT_NOVA] ~= model or not model.Parent then return end

			-- Urutannya mengikat: gempa mengosongkan barisan dan
			-- menyetel slotCount ke nol, dan novaKeBarisan yang
			-- menaruhnya kembali ke satu. Dibalik, kedatangan
			-- berikutnya akan berdiri menembus badannya.
			gempaBarisan(tujuan.Position)
			novaKeBarisan(model, tujuan)
		end)

		-- Dan sesudah itu dia TINGGAL. Lihat novaKeBarisan -- dia jadi
		-- orang pertama di barisan yang baru, dan yang menghapusnya
		-- nanti sama dengan yang menghapus semua orang.
	end

	local persen = hitungAura(tier)

	-- Aura di BADAN, beda dari papan angka di bawah ini. Milik tier 2-3
	-- saja, dan diacak satu dari tiga -- lihat AURA_VFX_IDS.
	--
	-- Tetap dipanggil di sini walau tidak lagi butuh `persen`: log di
	-- bawah menyebut angkanya, dan satu baris yang memuat tier, aura,
	-- dan undian sekaligus itu yang bisa menjawab "kenapa yang ini
	-- kelihatan beda" tanpa perlu membuka apa pun.
	local auraNama = pasangAuraVfx(model, tier, skala)
	if auraNama then
		print(("[aura-vfx] %s dapat aura '%s' (tier %s, %d%%)")
			:format(username, auraNama, tostring(tier), persen))
	end

	-- Ditahan untuk tier yang punya auraMulai (nova): papannya baru boleh
	-- muncul setelah avatar aslinya dimunculkan kembali. Model yang keburu dihapus di masa
	-- tunggu (reset panggung) tidak dikirimi apa pun.
	-- Slot yang dipakai papannya juga slot MENDARAT untuk nova: papan
	-- membawa nomor barisnya, dan client memakai nomor itu untuk
	-- memutuskan siapa yang masih di baris depan. Nomor baris lama
	-- membuat papan orang yang berdiri paling depan dianggap ada di
	-- belakang, lalu dilepas oleh kedatangan berikutnya.
	local slotPapan = nova and SLOT_NOVA_MENDARAT or slot

	local auraMulai = tonumber(kam.auraMulai) or 0
	if auraMulai > 0 then
		local namaTampil = entry.displayName or username
		task.delay(auraMulai, function()
			if model.Parent then
				tampilkanAura(model, namaTampil, persen, slotPapan, tier)
			end
		end)
	else
		tampilkanAura(model, entry.displayName or username, persen,
			slotPapan, tier)
	end

	local dari = entry.tiktokUser and (" <- " .. entry.tiktokUser) or ""
	local cap  = ""
	if tier >= 2 then
		cap = (" -- tier %d, %d koin, sorotan %.1fs")
			:format(tier, tonumber(entry.koin) or 0, lamaS)
	end
	print(("[%d/%d] %s tampil -- aura %d%% (userId: %d)%s%s")
		:format(slot, DELETE_AFTER, username, persen, userId, dari, cap))

	-- Adegan Matrix ditaruh PALING AKHIR dan sengaja memblokir: gelung
	-- utama memanggil spawnAvatar tier 3 tanpa task.spawn, jadi selama
	-- fungsi ini belum kembali, tidak ada satu pun kedatangan baru yang
	-- diambil. Itulah "panggung ikut berhenti" -- tidak butuh flag
	-- kedua, tidak ada keadaan yang bisa nyangkut kalau adegannya
	-- error di tengah.
	if raksasa then
		-- Di mana dia BENAR-BENAR berdiri. Tidak ada lagi yang bisa
		-- gagal di antara sini dan penempatannya, tapi baris ini tetap
		-- ada: dia yang menjawab "raksasanya tidak muncul" tanpa perlu
		-- menebak sama sekali.
		local pos = model:GetPivot().Position
		local tinggi = select(2, model:GetBoundingBox()).Y
		print(("[raksasa] berdiri di (%.0f, %.0f, %.0f), tinggi %.1f stud, " ..
			"kamera mundur %.1fx")
			:format(pos.X, pos.Y, pos.Z, tinggi, jauh))
		if pos.Y < FLOOR_Y then
			warn("[raksasa] posisinya DI BAWAH lantai -- dia tidak akan " ..
				"terlihat.")
		end
	end

	return model
end

-- ============ SERVER API ============

local function ambilJson(path)
	local ok, res = pcall(function()
		return HttpService:RequestAsync({
			Url     = URL .. path,
			Method  = "GET",
			Headers = { ["ngrok-skip-browser-warning"] = "true" },
		})
	end)
	if not ok then
		warn("Request gagal:", res)
		return nil
	end
	if res.StatusCode ~= 200 then
		warn("HTTP", res.StatusCode, path)
		return nil
	end

	local decoded, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
	if not decoded then
		warn("Body bukan JSON valid:", res.Body)
		return nil
	end
	return data
end

local function fetchNext()
	local data = ambilJson("/api/next")
	if data and data.username then return data end
	return nil
end

local function cekMusikApi()
	if not MUSIC_API then return end
	local data = ambilJson("/api/music")
	if not data then return end

	if data.action == "next" then
		laguBerikutnya()
	elseif type(data.index) == "number" and data.index >= 1 then
		putarLagu(data.index)
	end
end

-- ============ ANGKA KAMERA UNTUK CLIENT ============
--
-- DITARIK client saat dia mulai, bukan didorong lewat PlayerAdded:
-- PlayerAdded di server sering menyala sebelum LocalScript-nya sempat
-- jalan, dan paket ke client yang belum mendengarkan hilang begitu saja.
-- Sudah ada client yang menarik config?
--
-- Ini satu-satunya bukti yang bisa dilihat dari SISI SERVER bahwa
-- LocalScript kameranya benar-benar jalan. Tanpa penanda ini, "kamera
-- tidak bergerak" dan "LocalScript tidak pernah dieksekusi" terlihat
-- sama persis di Output -- dua-duanya cuma senyap.
local adaClient = false

V2Config.OnServerInvoke = function(pemain)
	adaClient = true
	print(("Kamera client menyambung: %s"):format(pemain.Name))

	return {
		up       = CAMERA_UP,
		upJauh   = CAMERA_UP_JAUH,
		back     = CAMERA_BACK,
		sweepDeg = CAMERA_SWEEP_DEG,
		sweepS   = CAMERA_SWEEP_S,
		moveS    = CAMERA_MOVE_S,
		fokus    = titikPanggung(),

		auraTime = AURA_TIME,
		auraRoll = AURA_ROLL,
		auraSfx     = SFX_AURA.ID,
		auraSfxVol  = SFX_AURA.VOL,
		auraSfxSpeed = SFX_AURA.SPEED,
		auraSfxRoll = SFX_AURA.IKUT_ROLL,
		auraSfxLoop = SFX_AURA.LOOP,
		auraSfxHit    = SFX_AURA.HIT_ID,
		auraSfxHitVol = SFX_AURA.HIT_VOL,
		-- Bunyi mendarat khusus angka besar. MENGGANTI yang di atas,
		-- tidak menambah -- lihat SFX_AURA.HIT_TINGGI_ID.
		auraSfxHitTinggi    = SFX_AURA.HIT_TINGGI_ID,
		auraSfxHitTinggiVol = SFX_AURA.HIT_TINGGI_VOL,
		-- Bunyi mendarat khusus raksasa. MENGGANTI dua-duanya di atas
		-- -- lihat SFX_AURA.HIT_RAKSASA_ID.
		auraSfxHitRaksasa     = SFX_AURA.HIT_RAKSASA_ID,
		auraSfxHitRaksasaVol  = SFX_AURA.HIT_RAKSASA_VOL,
		auraSfxHitRaksasaNada = SFX_AURA.HIT_RAKSASA_NADA,
		auraSfxRollRaksasaNada = SFX_AURA.ROLL_RAKSASA_NADA,
		-- Bunyi kedatangan per tier. Dikirim sebagai tabel utuh, bukan
		-- dipecah jadi sfxTier2/sfxTier3/...: menambah tier kelima nanti
		-- cukup menambah satu baris di SFX_TIER, tanpa menyentuh baris
		-- ini maupun file client.
		sfxTier = SFX_TIER,
		auraTinggiMin       = AURA_TINGGI_MIN,
		auraY    = AURA_Y,
		auraH    = AURA_H,

		auraKepala   = AURA_DI_KEPALA,
		auraLayar    = AURA_DI_LAYAR,
		auraKepalaY  = AURA_KEPALA_Y,
		auraKepalaW  = AURA_KEPALA_W,
		auraKepalaH  = AURA_KEPALA_H,
		auraKepalaJauh = AURA_KEPALA_JAUH,
		auraDepanSaja  = AURA_DEPAN_SAJA,
		auraFadeOut    = AURA_FADE_OUT,

		-- Kamera sinematik selama sorotan. Client yang menjalankan
		-- gerakannya; angkanya tetap tinggal di file ini seperti yang
		-- lain.
		sinema       = SINEMA_ENABLED,
		sinemaOrbitS = SINEMA_ORBIT_S,
		sinemaBack   = SINEMA_BACK,
		sinemaUp     = SINEMA_UP,

		zoom       = ZOOM_ENABLED,
		zoomMasuk  = ZOOM_MASUK,
		zoomTahan  = ZOOM_TAHAN,
		zoomKeluar = ZOOM_KELUAR,
		spawnLurus = SPAWN_LURUS,

		sembunyiPenonton = SEMBUNYI_PENONTON,

		spawnSiap     = SPAWN_SIAP,
		spawnSiapMaks = SPAWN_SIAP_MAKS,
		spawnSiapFade = SPAWN_SIAP_FADE,

		debug    = DEBUG_HUD,

		-- Penyamaan tarian dikerjakan client (TimePosition tidak
		-- direplikasi dari server), tapi angkanya disetel di sini.
		resyncEvery = RESYNC_EVERY,
		driftLimit  = DRIFT_LIMIT,
		syncKp        = SYNC_KP,
		syncSpeedMaks = SYNC_SPEED_MAKS,
		syncSnap      = SYNC_SNAP,

		-- Mutu visual: yang mengukur kuat-tidaknya perangkat cuma bisa
		-- client (server tidak menggambar apa pun), tapi ambangnya
		-- disetel di sini bersama angka yang lain.
		visualAuto   = VISUAL.AUTO,
		visualFpsMin = VISUAL.FPS_MIN,
		visualBloom  = VISUAL.BLOOM,
	}
end

-- Peringatan kalau sampai 8 detik tidak ada client yang menyambung.
--
-- 8 detik itu jauh lebih lama daripada yang dibutuhkan: LocalScript di
-- StarterPlayerScripts jalan beberapa ratus milidetik setelah pemain
-- masuk. Lewat dari itu, dia memang tidak akan datang.
task.delay(8, function()
	if adaClient then return end

	-- Berapa pemain yang benar-benar ada di server ini.
	--
	-- Angka ini memisahkan dua hal yang di log terlihat sama:
	--   0 pemain  -> ini mode RUN, bukan PLAY. Run menjalankan server
	--                saja: tidak ada pemain, jadi tidak ada PlayerGui,
	--                tidak ada Camera milik pemain, dan tidak satu pun
	--                LocalScript di StarterPlayerScripts dieksekusi.
	--                Avatar tetap muncul dan log server tetap jalan --
	--                persis seperti sekarang.
	--   1 pemain  -> ini PLAY, pemainnya ada, tapi LocalScript-nya yang
	--                tidak jalan (Disabled, salah ClassName, atau salah
	--                folder).
	local jumlah = #Players:GetPlayers()

	warn("=====================================================")
	warn(("TIDAK ADA CLIENT KAMERA yang menyambung dalam 8 detik. " ..
		"(pemain di server: %d)"):format(jumlah))

	if jumlah == 0 then
		warn("")
		warn("PEMAINNYA NOL. Itu berarti kamu menekan RUN, bukan PLAY.")
		warn("Run menjalankan server saja -- tidak ada pemain, jadi")
		warn("tidak satu pun LocalScript dijalankan. Tekan PLAY (F5).")
		warn("=====================================================")
		return
	end

	warn("Kamera TIDAK akan bergerak dan aura TIDAK akan muncul,")
	warn("karena dua-duanya dikerjakan LocalScript, bukan script ini.")
	warn("")
	warn("Periksa berurutan:")
	warn("1. StarterPlayer > StarterPlayerScripts berisi KameraClientV2")
	warn("2. ClassName-nya LocalScript (lihat Properties, bukan namanya)")
	warn("3. Properti Disabled-nya TIDAK dicentang")
	warn("4. Kamu menekan PLAY, bukan Run  (Run tidak membuat pemain,")
	warn("   jadi tidak satu pun LocalScript dijalankan)")
	warn("5. Filter Output menampilkan pesan Client, bukan Server saja")
	warn("=====================================================")
end)

-- ============ VISUAL / PENCAHAYAAN ============
--
-- Dipasang sekali, waktu server hidup. Sesudah ini tidak ada satu baris
-- pun dari bagian ini yang jalan lagi -- tidak ada gelung, tidak ada
-- koneksi event, tidak ada beban per frame. Yang mahal di grafis Roblox
-- itu MENGGAMBAR-nya (dikerjakan mesin, di client), bukan menyetel
-- propertinya.

-- Ambil efek yang SUDAH ada sebelum bikin baru.
--
-- Kalau map-nya sudah punya ColorCorrection buatan tangan, yang terjadi
-- tanpa ini bukan "efeknya diganti" tapi DUA efek menumpuk: kontras dan
-- saturasinya dihitung dua kali, dan hasilnya map yang gosong. Roblox
-- tidak melarang efek sejenis lebih dari satu.
local function efek(kelas, nama)
	local x = Lighting:FindFirstChild(nama)
		or Lighting:FindFirstChildOfClass(kelas)
	if not x then
		x = Instance.new(kelas)
	end
	x.Name   = nama
	x.Parent = Lighting
	return x
end

local function pasangVisual()
	if not VISUAL.ENABLED then return end

	-- Technology TIDAK bisa disentuh dari script biasa. Bukan cuma
	-- ditulis -- DIBACA pun tidak boleh:
	--
	--   The current thread cannot read 'Technology'
	--   (lacking capability RobloxScript)
	--
	-- Jadi dua-duanya masuk pcall, dan pcall pembacaan itu bukan
	-- kehati-hatian berlebihan: versi pertama bagian ini membaca
	-- Lighting.Technology di luar pcall untuk menyusun pesan
	-- peringatannya, error itu melempar keluar dari pasangVisual, dan
	-- akibatnya SELURUH penyetelan di bawah tidak pernah jalan --
	-- gagal memasang lampu gara-gara mau memberi tahu kenapa lampunya
	-- mungkin gagal dipasang.
	--
	-- Command Bar Studio pun ditolak, jadi tidak ada jalan lewat script
	-- sama sekali: satu-satunya tempat menyetelnya panel Properties.
	--
	-- KECUALI kalau tempat ini sudah pakai Unified Lighting. Di situ
	-- Technology dihapus sepenuhnya dan diganti LightingStyle, dan
	-- memberi tahu orang "setel Technology ke Future" jadi salah arah:
	-- properti yang disuruh dicari memang sudah tidak ada, dan
	-- pencahayaannya justru sudah lebih baru daripada Future.
	--
	-- Jadi yang ditanya duluan LightingStyle. Ada = tidak usah bicara
	-- soal Technology lagi.
	local okGaya, gaya = pcall(function() return Lighting.LightingStyle end)

	if okGaya and gaya ~= nil then
		print(("[visual] Unified Lighting aktif (LightingStyle = %s) -- "
			.. "Technology tidak dipakai lagi, tidak ada yang perlu disetel")
			:format((tostring(gaya):gsub("Enum.LightingStyle.", ""))))
	else
		local okTulis = pcall(function()
			Lighting.Technology = Enum.Technology.Future
		end)

		if not okTulis then
			local okBaca, tech = pcall(function() return Lighting.Technology end)
			if okBaca and tech == Enum.Technology.Future then
				-- Sudah Future dari Studio; tidak ada yang perlu dikatakan.
			else
				if okBaca then
					warn(("[visual] Lighting.Technology = %s.")
						:format((tostring(tech):gsub("Enum.Technology.", ""))))
				else
					warn("[visual] Lighting.Technology tidak bisa dibaca script.")
				end
				warn("[visual] Setel manual di Studio (keadaan Stop):")
				warn("[visual] klik Lighting > Properties > Technology > Future.")
				warn("[visual] Tidak ketemu propertinya? Berarti Unified")
				warn("[visual] Lighting menyala di Beta Features -- itu lebih")
				warn("[visual] baru dari Future, biarkan saja.")
			end
		end
	end

	-- --- Cahaya dasar ---
	Lighting.Brightness           = VISUAL.TERANG
	Lighting.ExposureCompensation = VISUAL.EXPOSURE
	Lighting.ClockTime            = VISUAL.JAM
	Lighting.GeographicLatitude   = VISUAL.LINTANG
	Lighting.GlobalShadows        = true

	-- Ambient = cahaya yang mengisi bagian yang TIDAK kena matahari.
	-- Dibiarkan kebiruan, tidak abu netral: bayangan di dunia nyata
	-- memang biru (yang menyinarinya langit, bukan matahari). Ini
	-- perbedaan kecil yang paling terasa antara "render" dan "Roblox".
	--
	-- Jangan dinaikkan lagi: ambient terang = bayangan hilang, dan
	-- panggungnya jadi rata seperti sticker.
	Lighting.Ambient        = Color3.fromRGB(28, 30, 38)
	Lighting.OutdoorAmbient = Color3.fromRGB(96, 104, 120)

	-- Warna cahaya matahari (atas) dan pantulan tanah (bawah). Hangat
	-- di atas, dingin di bawah -- kontras suhu warna, bukan kontras
	-- gelap-terang. Ini yang bikin gambar terasa "sinematik" tanpa
	-- filter apa pun.
	Lighting.ColorShift_Top    = Color3.fromRGB(30, 22, 10)
	Lighting.ColorShift_Bottom = Color3.fromRGB(10, 14, 26)

	-- Pantulan langit di permukaan mengkilap. Specular penuh, diffuse
	-- ditahan: diffuse tinggi + OutdoorAmbient di atas sama-sama
	-- menyiram cahaya rata, dan dua-duanya kencang = tercuci.
	--
	-- Satu pcall PER properti, bukan satu pcall untuk bertiga: yang
	-- pertama gagal di dalam satu pcall bersama berarti dua sisanya
	-- tidak pernah dicoba. Pelajaran yang sama dengan Technology di
	-- atas, sekarang dipakai di sini juga.
	for prop, nilai in pairs({
		EnvironmentDiffuseScale  = 0.75,
		EnvironmentSpecularScale = 1,
		ShadowSoftness           = VISUAL.BAYANG,
	}) do
		local okSet = pcall(function() Lighting[prop] = nilai end)
		if not okSet then
			warn(("[visual] %s tidak bisa disetel di tempat ini")
				:format(prop))
		end
	end

	-- Kabut lama (FogStart/FogEnd) dimatikan. Dia diabaikan selama ada
	-- Atmosphere, tapi kalau nanti Atmosphere-nya dihapus, angka bawaan
	-- (FogEnd 100000) yang tertinggal lebih aman daripada kabut abu.
	Lighting.FogEnd = 100000

	-- --- Atmosphere: kedalaman ---
	--
	-- Bukan sekadar kabut. Dia menghitung udara di antara kamera dan
	-- benda, jadi barisan belakang tidak cuma mengecil tapi juga
	-- memucat -- satu-satunya petunjuk jarak yang dipunyai mata di
	-- layar datar.
	local udara = efek("Atmosphere", "Atmosphere")
	udara.Density = VISUAL.KABUT
	udara.Offset  = 0.20
	udara.Color   = Color3.fromRGB(202, 208, 220)
	udara.Decay   = Color3.fromRGB(104, 112, 128)
	udara.Glare   = 0.25
	udara.Haze    = 1.4

	-- --- Warna: kontras & saturasi ---
	--
	-- Angkanya kecil semua, dan itu disengaja. Saturasi 0.3 dan kontras
	-- 0.5 memang langsung terlihat "wah" di screenshot pertama, tapi
	-- kulit avatar jadi oranye dan baju merah kehilangan lipatannya.
	-- Yang dicari di sini: penonton tidak sadar ada filter.
	local warna = efek("ColorCorrectionEffect", "VisualColor")
	warna.Brightness = 0
	warna.Contrast   = VISUAL.KONTRAS
	warna.Saturation = VISUAL.SATURASI
	warna.TintColor  = Color3.fromRGB(255, 251, 246)
	warna.Enabled    = true

	-- --- Bloom: pendar ---
	--
	-- Threshold di atas 1 penting: di bawah itu SEMUA yang putih ikut
	-- berpendar, termasuk baju avatar, dan gambarnya berkabut susu.
	-- Dengan 1.15 yang berpendar cuma yang benar-benar lebih terang
	-- dari putih -- matahari, pantulan, dan angka aura yang bergradien.
	local pendar = efek("BloomEffect", "VisualBloom")
	pendar.Intensity = VISUAL.BLOOM
	pendar.Size      = 22
	pendar.Threshold = 1.15
	pendar.Enabled   = VISUAL.BLOOM > 0

	-- --- Berkas matahari ---
	--
	-- Sangat tipis. Efek ini mudah sekali jadi murahan: begitu
	-- berkasnya kelihatan sebagai "garis", yang tertangkap penonton
	-- bukan mataharinya tapi efeknya.
	local berkas = efek("SunRaysEffect", "VisualSunRays")
	berkas.Intensity = VISUAL.SUNRAYS
	berkas.Spread    = 0.85
	berkas.Enabled   = VISUAL.SUNRAYS > 0

	-- --- Kedalaman lensa ---
	--
	-- Fokusnya dipatok ke jarak kamera-ke-avatar (CAMERA_BACK = -11),
	-- jadi yang datang SELALU tajam dan kerumunan di belakangnya
	-- meluruh pelan. Buramnya cuma 0.12: ini pemisah latar, bukan
	-- foto makro.
	--
	-- Papan aura tidak ikut buram -- BillboardGui digambar sesudah
	-- pasca-proses, bukan sebelum.
	local lensa = efek("DepthOfFieldEffect", "VisualDOF")
	lensa.FocusDistance = VISUAL.DOF_FOKUS
	lensa.InFocusRadius = VISUAL.DOF_TAJAM
	lensa.FarIntensity  = VISUAL.DOF_BURAM
	lensa.NearIntensity = 0      -- 0 mati: kamera tidak pernah sedekat itu
	lensa.Enabled       = VISUAL.DOF

	print(("[visual] terpasang -- jam %.1f, kabut %.2f, bloom %.2f, dof %s")
		:format(VISUAL.JAM, VISUAL.KABUT, VISUAL.BLOOM,
			VISUAL.DOF and "aktif" or "mati"))
end

-- Warna lantai. Terpisah dari pasangVisual karena ini menyentuh BENDA
-- di workspace, bukan service Lighting -- dan yang menyentuh benda
-- orang lain harus lebih hati-hati soal apa yang ditemukannya.
local function warnaiLantai()
	if not LANTAI.ENABLED then return end

	local lantai = workspace:FindFirstChild(LANTAI.NAMA)

	-- Tidak ketemu? Berhenti dengan pesan yang menyebut APA yang dicari.
	-- "Baseplate" cuma nama bawaan template; map yang dibangun sendiri
	-- sering menamainya Floor, Ground, atau Panggung -- dan tanpa nama
	-- yang disebut di sini, yang terbaca cuma "warnanya tidak berubah"
	-- tanpa petunjuk sama sekali.
	if not lantai or not lantai:IsA("BasePart") then
		warn(("[lantai] part '%s' tidak ada di workspace -- warna lantai "
			.. "dilewati. Ganti LANTAI.NAMA ke nama part lantaimu.")
			:format(LANTAI.NAMA))
		return
	end

	lantai.Color = LANTAI.WARNA
	if LANTAI.MATERIAL then
		lantai.Material = LANTAI.MATERIAL
	end

	-- Pola kotak-kotaknya. Dicari sebagai Texture DAN Decal: template
	-- Baseplate memakai Texture (yang berulang), tapi map yang lantainya
	-- dibuat sendiri sering pakai Decal (satu gambar diregangkan).
	--
	-- Yang diubah Color3-nya, bukan gambarnya: Texture punya tint, jadi
	-- pola yang sama bisa jadi warna apa saja tanpa mengganti asset.
	local dicat = 0
	for _, anak in ipairs(lantai:GetChildren()) do
		if anak:IsA("Texture") or anak:IsA("Decal") then
			anak.Color3 = LANTAI.GARIS
			dicat += 1
		end
	end

	if dicat == 0 then
		print("[lantai] warna dasar diganti; tidak ada Texture/Decal "
			.. "di lantainya, jadi tidak ada pola untuk diwarnai")
	else
		print(("[lantai] warna diganti -- dasar + %d pola"):format(dicat))
	end
end

-- ============ MULAI ============

-- Dibungkus pcall: bagian visual ini murni hiasan, dan tidak ada satu
-- pun alasan sebuah properti Lighting yang ditolak boleh menghentikan
-- script yang tugas aslinya menaruh avatar di panggung.
local okVisual, errVisual = pcall(pasangVisual)
if not okVisual then
	warn("[visual] gagal dipasang, panggung tetap jalan:", errVisual)
end

local okLantai, errLantai = pcall(warnaiLantai)
if not okLantai then
	warn("[lantai] gagal diwarnai, panggung tetap jalan:", errLantai)
end

print("V2 -- polling:", URL)
print(("Playlist: %d lagu, musik %s"):format(
	#PLAYLIST, MUSIC_ENABLED and "aktif" or "dimatikan"))
print(("Aura: %d-%d%%, tampil %.1f detik"):format(AURA_MIN, AURA_MAX, AURA_TIME))
if TIER_ENABLED then
	print(("Tier: border %s, panggung beku dari tier %d")
		:format(BORDER_ENABLED and "on" or "off",
			BEKU_ENABLED and BEKU_MIN_TIER or 99))
	print(("Lantai aura: Rose = %d%%, Rosa = %d%%, nova = %d%%; raksasa " ..
		"TIDAK diundi -- selalu %d%%")
		:format(AURA_LANTAI_T2, AURA_LANTAI_T3, AURA_LANTAI_T4, AURA_RAKSASA))
	print(("Border: tier %d cuma cakram, garis tepi dari tier %d")
		:format(2, BORDER_GARIS_MIN_TIER))
	if LAYAR.MODE_ROSA ~= "mati" and not LAYAR.PILIHAN[LAYAR.MODE_ROSA] then
		warn(("[layar] LAYAR.MODE_ROSA = '%s' tidak dikenal -- Rosa jalan " ..
			"tanpa efek layar. Pilihannya: tipis, warna, penuh, mati.")
			:format(tostring(LAYAR.MODE_ROSA)))
	else
		print(("Layar Rosa: %s"):format(LAYAR.MODE_ROSA))
	end
	-- Kamera per tier ikut dicetak: kalau nanti "tier 3 terasa sama
	-- seperti tier 2", baris ini yang menjawabnya tanpa perlu membuka
	-- file -- dan yang paling sering jadi sebabnya justru busur yang
	-- kebetulan disetel sama lebarnya.
	for _, t in ipairs({ 2, 3, 4, 5 }) do
		local k = kameraTier(t)
		print(("Kamera tier %d: tahan %.1fs, mundur %.1fs sampai %d%% jarak, " ..
			"busur depan %s, naik-turun %.1f stud x%d gundukan, %s, " ..
			"angka %.1fs ditunda %.1fs")
			:format(t, k.tahan, k.keluar, math.floor(k.maks * 100 + 0.5),
				(k.arcDeg and k.arcDeg > 0)
					and ("+/-%d derajat x%.1f sapuan"):format(k.arcDeg, k.arcPutar)
					or "tidak menyapu",
				k.naikAmp or 0, k.naikPutar or 1,
				(k.denyutDalam and k.denyutDalam > 0)
					and ("denyut %d%% x%d dari %d%% adegan")
						:format(math.floor(k.denyutDalam * 100 + 0.5),
							k.denyutUlang or 1,
							math.floor((k.denyutMulai or 0) * 100 + 0.5))
					or "tanpa denyut",
				k.roll or AURA_ROLL,
				k.tunda))
	end
	print(("Aura VFX: %s, tier %d-%d, %d pilihan diacak")
		:format(AURA_VFX_ENABLED and "on" or "off",
			AURA_VFX_TIER, AURA_VFX_TIER_MAKS, #AURA_VFX_IDS))
	print(("Tier %d: nova %s -- charge %.1fs + ascend %.1fs + freeze %.1fs " ..
		"+ slam %.1fs + impact %.1fs = %.1fs, lalu menari %.1fs; " ..
		"%d palet diacak, layar %s (ModuleScript TierNova di client)")
		:format(NOVA.TIER, NOVA.ENABLED and "on" or "off",
			NOVA.CONFIG.charge, NOVA.CONFIG.ascend, NOVA.CONFIG.freeze,
			NOVA.CONFIG.slam, NOVA.CONFIG.impact, novaTotal(), NOVA.TARI,
			#NOVA.PALET, NOVA.CONFIG.layar and "on" or "off"))
	print(("Bunyi nova: %d isyarat (charge/ascend/freeze/impact), " ..
		"semuanya bawaan Roblox yang digeser nadanya"):format(#NOVA.SFX))
	print(("Karakter penonton: %s")
		:format(SEMBUNYI_PENONTON
			and "disembunyikan (badan, bayangan, nama) -- aman di-capture"
			or "TERLIHAT -- avatarmu sendiri ikut terekam di siaran"))
	print(("Tier %d: raksasa %s (batas %dx) di z=%d, emote %s, tanpa efek " ..
		"dan tanpa aura VFX, bertahan lewat reset")
		:format(GIANT_MIN_TIER, GIANT_ENABLED and "on" or "off", GIANT_SKALA_MAKS,
			GIANT_Z, GIANT_EMOTE_ID ~= "" and "on" or "off"))
	print(("Raksasa: papan %d%% dengan putaran %.1fs, bunyi mendarat " ..
		"sendiri (nada %.2f), dan kamera panggung turun ke %d stud " ..
		"selama dia berdiri (biasanya %d)")
		:format(AURA_RAKSASA, kameraTier(GIANT_MIN_TIER).roll or AURA_ROLL,
			SFX_AURA.HIT_RAKSASA_NADA, CAMERA_UP_JAUH_GIANT, CAMERA_UP_JAUH))
	print(("Kamera raksasa: bidik %.0f%% tinggi pivot, jarak %.2fx skala, " ..
		"tinggi %.2fx skala (di bawah garis mata -- wajahnya menghadap lensa)")
		:format(GIANT_FOKUS_TINGGI * 100, GIANT_KAMERA_JAUH,
			GIANT_KAMERA_TINGGI))
else
	print("Tier: DIMATIKAN (TIER_ENABLED = false)")
end

if MUSIC_ENABLED then
	task.spawn(function()
		for i, lagu in ipairs(PLAYLIST) do
			if lagu.musik and lagu.musik ~= "" then
				local ok, err = pcall(function()
					ContentProvider:PreloadAsync({ lagu.musik })
				end)
				if not ok then
					warn(("Lagu %d gagal dimuat: %s (%s)")
						:format(i, tostring(lagu.musik), tostring(err)))
				end
			end
		end
	end)
end

startMusicLoop()

while true do
	local entry = fetchNext()

	if entry then
		local tierMasuk = TIER_ENABLED and (tonumber(entry.tier) or 1) or 1
		local slot

		if adalahRaksasa(tierMasuk) then
			-- Raksasa memakai nomornya sendiri dan MENGGANTIKAN yang
			-- sedang berdiri. Barisan tidak disentuh sama sekali:
			-- slotCount tidak naik, jadi orang berikutnya tetap
			-- mendapat tempat yang seharusnya.
			buangRaksasa()
			slot = SLOT_RAKSASA

		else
			if DELETE_AFTER > 0 and slotCount >= DELETE_AFTER then
				task.wait(RESET_DELAY)
				resetStage()
			end

			slotCount += 1
			slot = slotCount
		end

		-- Tier 3 dan 4 dijalankan LANGSUNG di gelung ini, bukan di task
		-- terpisah. Itu satu-satunya bedanya, dan itu yang membekukan
		-- panggung: spawnAvatar baru kembali setelah adegan Matrix-nya
		-- selesai, jadi fetchNext berikutnya memang tidak terjadi.
		--
		-- Antrian tidak ikut membeku -- dia menumpuk di main.py, dan
		-- SPOTLIGHT_GAP_S di sana sudah menahan sesama gift supaya
		-- tidak menempel. Yang menumpuk cuma tier 1, dan mereka dibatasi
		-- QUEUE_MAX; begitu beku selesai mereka keluar satu per detik
		-- seperti biasa, bukan sekaligus.
		local beku = BEKU_ENABLED and TIER_ENABLED
			and tierMasuk >= BEKU_MIN_TIER
			and entry.spotlight == true

		local function jalankan()
			local ok, err = pcall(spawnAvatar, entry, slot)
			if not ok then
				warn(("Gagal load '%s': %s")
					:format(tostring(entry.username), tostring(err)))
			end
		end

		if beku then
			jalankan()
			task.wait(BEKU_EKOR)
		else
			task.spawn(jalankan)
		end
	end

	cekMusikApi()
	task.wait(POLL_INTERVAL)
end
