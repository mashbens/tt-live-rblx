--[[
    Kamera + Aura Client  --  pasangan dari AvatarQueueV2

    Di Studio: StarterPlayer.StarterPlayerScripts.KameraClientV2
               (LocalScript). Disinkron Rojo dari file ini -- `make rojo`.

    MATIKAN KameraClient yang lama. Dua LocalScript yang sama-sama
    menulis workspace.CurrentCamera tiap frame bikin kameranya bergetar
    di antara dua tujuan.

    KENAPA HARUS DIPISAH DARI SCRIPT SERVER

    `workspace.CurrentCamera` milik client: tiap pemain punya Camera
    sendiri, dan tidak satu pun direplikasi ke server. Di Studio (Play)
    server dan client jalan di satu proses jadi kode kamera dari server
    kebetulan kena; di game yang sudah di-publish, server tidak punya
    Camera sama sekali -- tidak ada error, penonton cuma memandang
    avatarnya sendiri.

    Hal yang sama berlaku untuk ScreenGui (aura harus di layar TIAP
    penonton) dan untuk AnimationTrack.TimePosition (penyamaan tarian).

    TIDAK ADA ANGKA UNTUK DISETEL DI FILE INI.
    Semuanya (CAMERA_*, AURA_*, RESYNC_*) tinggal di AvatarQueueV2 dan
    ditarik lewat V2Config.
--]]

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")
local Lighting          = game:GetService("Lighting")
local ContentProvider   = game:GetService("ContentProvider")

-- Salah taruh? Berhenti di sini dengan pesan yang jelas.
--
-- Kalau file ini di-paste ke ServerScriptService sebagai Script, yang
-- muncul di Output cuma "InvokeServer can only be called from the
-- client" sepuluh baris di bawah -- pesan yang tidak menyebut sama
-- sekali bahwa masalahnya letak file, bukan kodenya.
if not RunService:IsClient() then
	warn("KameraClientV2 jalan di SERVER. File ini harus " ..
		"LocalScript di StarterPlayer > StarterPlayerScripts " ..
		"(nama: KameraClientV2), bukan Script di ServerScriptService.")
	return
end

-- WaitForChild, bukan FindFirstChild: LocalScript sering jalan lebih
-- dulu daripada script server yang membuat remote-nya.
local V2Event  = ReplicatedStorage:WaitForChild("V2Event")
local V2Config = ReplicatedStorage:WaitForChild("V2Config")

-- Ditarik, bukan menunggu didorong: PlayerAdded di server sering menyala
-- sebelum LocalScript ini jalan.
--
-- Dibungkus pcall dengan nilai cadangan lengkap. Kalau panggilan ini
-- error (server belum sempat memasang OnServerInvoke, script server
-- di-disable, remote-nya sisa dari run sebelumnya), baris ini dulu
-- mematikan SELURUH LocalScript -- termasuk gelung kameranya. Yang
-- terlihat cuma "kamera tidak bergerak", tanpa satu pun petunjuk bahwa
-- yang gagal sebenarnya pengambilan angka.
local CADANGAN = {
	up = 2.5, upJauh = 7, back = -11, sweepDeg = 5, sweepS = 9, moveS = 0.8,
	auraTime = 3.5, auraRoll = 0.6, auraY = 0.12, auraH = 0.32,
	auraKepala = true, auraLayar = false,
	auraKepalaY = 3.2, auraKepalaW = 190, auraKepalaH = 96,
	auraKepalaJauh = 220, auraDepanSaja = true, auraFadeOut = 0.3,
	auraSfx = "", auraSfxVol = 0.7, auraSfxRoll = true,
	auraSfxSpeed = 1, auraSfxLoop = false,
	auraSfxHit = "", auraSfxHitVol = 0.8,
	auraSfxHitTinggi = "", auraSfxHitTinggiVol = 0.9,
	auraSfxHitRaksasa = "", auraSfxHitRaksasaVol = 1.0,
	auraSfxHitRaksasaNada = 0.75, auraSfxRollRaksasaNada = 0.8,
	auraTinggiMin = 900,
	-- Kosong = tidak ada bunyi kedatangan. Cadangan ini cuma dipakai
	-- kalau V2Config gagal ditarik; daftar aslinya ada di SFX_TIER.
	sfxTier = {},
	sinema = true, sinemaOrbitS = 14, sinemaBack = -12, sinemaUp = 5.5,
	zoom = true, zoomMasuk = 0.45, zoomTahan = 1.0, zoomKeluar = 1.8,
	spawnLurus = true,
	spawnSiap = true, spawnSiapMaks = 0.6, spawnSiapFade = 0.12,
	sembunyiPenonton = true,
	resyncEvery = 3, driftLimit = 0.04,
	syncKp = 0.6, syncSpeedMaks = 0.15, syncSnap = 0.35,
	visualAuto = true, visualFpsMin = 32, visualBloom = 0.45,
}

local ok, hasil = pcall(function()
	return V2Config:InvokeServer()
end)

local CFG = ok and hasil or CADANGAN
if not ok then
	warn("V2Config gagal ditarik, pakai angka cadangan:", hasil)
end
for k, v in pairs(CADANGAN) do
	if CFG[k] == nil then CFG[k] = v end
end

local pemain = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- Penanda "aku hidup".
--
-- Kamera yang diam punya dua sebab yang kelihatan sama persis di layar:
-- (a) LocalScript-nya tidak jalan sama sekali, (b) dia jalan tapi
-- gelungnya salah. Tanpa baris ini tidak ada cara membedakannya -- dan
-- keduanya butuh perbaikan yang sama sekali berbeda.
--
-- Kalau baris ini TIDAK muncul di Output (tab Client), berarti (a):
-- filenya bukan LocalScript, atau bukan di StarterPlayerScripts, atau
-- kamu menekan Run, bukan Play (Run tidak membuat pemain, jadi tidak
-- ada satu pun LocalScript yang dijalankan).
print(("KameraClientV2 aktif -- ayunan %s derajat / %s detik, fokus awal %s")
	:format(tostring(CFG.sweepDeg), tostring(CFG.sweepS), tostring(CFG.fokus)))

-- ============ MEMPERTAHANKAN KENDALI KAMERA ============
--
-- Kamera bawaan Roblox (PlayerModule) menyetel CameraType kembali ke
-- Custom setiap kali karakter di-load -- dan itu terjadi SESUDAH script
-- ini jalan. Jadi yang dipasang penjaga, bukan satu perintah.
local dijaga = {}

local function jagaKamera(cam)
	if not cam then return end
	cam.CameraType = Enum.CameraType.Scriptable
	if dijaga[cam] then return end
	dijaga[cam] = true

	cam:GetPropertyChangedSignal("CameraType"):Connect(function()
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			cam.CameraType = Enum.CameraType.Scriptable
		end
	end)
end

jagaKamera(camera)

workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
	if workspace.CurrentCamera then
		camera = workspace.CurrentCamera
		jagaKamera(camera)
	end
end)

pemain.CharacterAdded:Connect(function()
	-- Satu frame jeda: kamera bawaan menyetel Custom sesudah
	-- CharacterAdded menyala.
	task.defer(function() jagaKamera(workspace.CurrentCamera) end)
end)

-- ============ KAMERA: AYUNAN KIRI-KANAN ============
--
-- Satu gelung, terus-menerus, tanpa potongan:
--   posisi = fokus + (offset diputar sin(t) derajat mengelilingi fokus)
--   arah   = selalu memandang fokus
--
-- Yang berubah saat ada kedatangan cuma TITIK FOKUSNYA, dan itu pun
-- digeser halus (bukan diloncatkan) supaya panggungnya tidak tersentak.
local fokusTarget = CFG.fokus or Vector3.new(0, 5, 0)
local fokusKini   = fokusTarget

local offsetDasar = Vector3.new(0, CFG.up, CFG.back)

-- Tinggi kamera saat MUNDUR PENUH, dari pesan `fokus` yang terakhir.
--
-- Tidak diambil dari CFG sekali di awal, karena angkanya berubah: dia
-- turun selama ada raksasa berdiri supaya kepala raksasanya masuk
-- frame (CAMERA_UP_JAUH_GIANT di server). Server yang memutuskan;
-- client cuma menyimpan yang terakhir dia dengar.
--
-- Nilai awalnya dari CFG supaya frame-frame sebelum kedatangan pertama
-- tetap memakai tinggi yang benar.
local upJauhKini = CFG.upJauh or CFG.up

-- ============ MODE SINEMATIK ============
--
-- Selama sorotan (tier 2/3), kamera berhenti mengayun dan MENGORBIT
-- penuh sambil merapat sedikit. Server cuma mengirim satu pesan berisi
-- lama detiknya; client yang menghitung sisanya, dan dia kembali ke
-- ayunan biasa sendiri begitu waktunya habis.
local offsetSinema = Vector3.new(0, CFG.sinemaUp, CFG.sinemaBack)

-- Kapan mode ini berakhir (os.clock). 0 = sedang tidak menyala.
local sinemaSampai = 0

-- Apakah adegan yang sedang jalan MENGORBIT. Tier 2 tidak: dia cuma
-- menahan dekat. Bedanya harus di jenis gerakan, bukan cuma di lamanya
-- -- dua gerakan yang sama dengan durasi berbeda tidak terbaca sebagai
-- dua tingkat.
local sinemaOrbit = false

-- Pengali jarak kamera untuk adegan ini. Dipakai raksasa, yang pada
-- jarak biasa tidak muat di frame -- kameranya berakhir di dalam tulang
-- keringnya.
local sinemaJauh = 1

-- Pengali TINGGI kamera, TERPISAH dari pengali jarak di atas.
--
-- Dulu tidak ada: offsetSinema dikali satu angka, jadi kamera yang
-- mundur berkali lipat untuk raksasa ikut NAIK berkali lipat juga.
-- Akibatnya pada 14x kamera duduk empat belas stud di atas kepala
-- raksasanya, dan yang dilihat penonton ubun-ubun -- bukan wajah.
--
-- Diisi dari pesan server (jauhY, lihat GIANT_KAMERA_TINGGI di sana).
-- Untuk tier lain nilainya sama dengan sinemaJauh, jadi perilakunya
-- persis seperti sebelum angka ini ada.
local sinemaJauhY = 1

-- Busur depan adegan yang sedang jalan, dari server (KAMERA_TIER).
--
--   arcRad    amplitudo simpangan ke samping, RADIAN. 0 = tidak
--             menyapu. Ini batas keras: kamera tidak pernah lebih jauh
--             dari ini dari depan.
--   arcPutar  berapa kali menyapu kiri-kanan-pulang selama adegan.
--   naikAmp   seberapa jauh kamera naik lalu turun lagi, STUD.
--
-- Dipisah dari sinemaOrbit dan bukan jadi nilai di dalamnya: orbit itu
-- KECEPATAN sudut (berputar terus, tanpa batas), busur itu POSISI sudut
-- yang dikurung. Keduanya menulis sudut kamera dengan cara yang tidak
-- bisa dicampur, dan menyatukannya berarti tiap pembacaan harus tahu
-- mana yang sedang berlaku.
local arcRad   = 0
local arcPutar = 1
local naikAmp  = 0

-- Berapa GUNDUKAN naik-turun selama adegan. 1 = naik lalu pulang (satu
-- gundukan). 2 = naik, pulang, turun di bawah tinggi biasa, pulang lagi
-- -- itu yang dipakai tier 3, dan yang membuat gerakannya memakai
-- keempat arah, bukan cuma kiri-kanan.
--
-- Selalu bilangan bulat dari server: sin(pi*u*n) cuma pulang ke nol di
-- u=1 kalau n bulat, dan adegan yang berakhir di tinggi yang bukan
-- tinggi biasa mewariskan pergeseran itu ke kedatangan berikutnya.
local naikPutar = 1

-- --- DENYUT ZOOM ---
--
-- Rapatan KEDUA di paruh akhir adegan, jadi bentuk jaraknya masuk ->
-- mundur -> masuk lagi -> mundur. Milik tier 3; untuk tier lain
-- denyutDalam-nya 0 dan seluruh bagian ini tidak pernah jalan.
--
--   denyutDalam  seberapa dalam rapatannya, pecahan jarak saat itu
--   denyutMulai  kapan mulai, pecahan lama adegan (0.42 = sesudah zoom
--                dasarnya selesai mundur)
--   denyutUlang  berapa kali merapat di dalam jendela itu
--
-- Yang diubah CUMA jaraknya. Bidikannya tetap di avatarnya -- kamera
-- selalu dibangun dengan CFrame.new(posisi, fokusKini) di ujung gelung,
-- jadi tidak ada satu pun gerakan di file ini yang bisa melepas
-- bidikan itu.
local denyutDalam = 0
local denyutMulai = 0.5
local denyutUlang = 1

-- Batas terdekat yang boleh dicapai denyut, pecahan jarak penuh.
--
-- Bukan kehati-hatian berlebihan: denyutDalam 0,40 di atas maks 0,70
-- sudah menghasilkan 0,42 -- lebih dekat daripada jarak masuk biasa
-- (ZOOM_MASUK 0,45), dan itu angka yang sempat tertulis di server. Satu angka yang dinaikkan tanpa sadar di sisi
-- server cukup untuk membawa kamera ke DALAM badan avatarnya, dan dari
-- sana yang terlihat cuma satu bidang warna.
local DENYUT_MIN = 0.30

-- Lama adegan yang sedang jalan, detik. Dibutuhkan busur untuk tahu
-- sudah sampai mana dia: sinemaSampai cuma menyimpan KAPAN berakhirnya,
-- dan tanpa lamanya tidak ada cara menghitung "baru 30% jalan".
local sinemaLama = 0

-- 0 = ayunan biasa, 1 = orbit penuh. Dipindah halus, tidak dijentikkan:
-- kamera yang mendadak merapat sembilan studs di satu frame terbaca
-- sebagai potongan, dan seluruh v2 dibangun tanpa satu pun potongan.
local sinemaMix = 0

-- Selisih sudut yang MENUMPUK selama orbit.
--
-- Ini bagian yang gampang salah. Ayunan biasa itu fungsi waktu:
-- sin(t) -- kalau orbit sekadar menimpanya, begitu orbitnya selesai
-- sudutnya harus meloncat kembali ke nilai sin(t) saat itu, dan
-- loncatan itu bisa sampai setengah lingkaran.
--
-- Jadi yang disimpan bukan sudutnya, tapi SELISIHNYA terhadap ayunan.
-- Selama orbit selisih ini tumbuh (orbit berputar lebih cepat daripada
-- ayunan), dan sesudahnya dia diluruhkan pelan ke nol. Tidak ada satu
-- pun frame yang meloncat, dan kameranya selalu pulang ke ayunan yang
-- sama seperti sebelum adegan.
local sudutBias = 0

-- Lama selisih itu diluruhkan, detik.
--
-- Dipakai dua hal sekaligus sekarang: pulang dari orbit, DAN pulang
-- dari pandangan lurus saat spawn (lihat SPAWN_LURUS di server). Dua-
-- duanya persoalan yang sama -- sudut yang digeser paksa harus kembali
-- ke ayunan alaminya tanpa satu pun frame yang meloncat.
local SINEMA_PULIH = 2.0

-- Sudut ayunan dan kecepatannya pada waktu t.
--
-- Dijadikan fungsi karena dua tempat membutuhkannya: gelung render
-- (tiap frame) dan penangan pesan kedatangan, yang harus tahu ayunannya
-- sedang di sudut berapa supaya bisa membatalkannya tepat sebanyak itu.
-- Dulu angkanya cuma hidup di dalam gelung, dan penangan pesan tidak
-- punya cara membacanya sama sekali.
local function ayunPada(t)
	local w   = (2 * math.pi) / math.max(CFG.sweepS or 9, 0.1)
	local amp = math.rad(CFG.sweepDeg or 20)
	return amp * math.sin(t * w), amp * w * math.cos(t * w)
end

-- Batalkan ayunan sekarang juga, lalu lepas pelan-pelan.
--
-- sudutBias disetel PERSIS berlawanan dengan ayunan saat ini, jadi
-- jumlah keduanya nol: kamera memandang lurus ke orang yang baru
-- datang. Sesudah itu bias-nya meluruh sendiri (SINEMA_PULIH) dan
-- ayunannya kembali seperti semula.
--
-- Tidak ada frame yang meloncat karena yang berubah cuma satu angka
-- yang memang sudah dijumlahkan ke sudutnya tiap frame -- mesin yang
-- sama yang dipakai orbit.
-- --- BUSUR DEPAN ---
--
-- Sudut kamera selama adegan berbayar, radian. 0 = tepat di depan
-- orangnya, positif = bergeser ke kanan.
--
-- CATATAN: di sini dulu ada GIANT_JALUR -- tiga sudut yang disinggahi
-- raksasa: serong kiri, serong kanan, lalu BELAKANG. Sudah dibuang, dan
-- ditulis supaya tidak dipasang lagi tanpa sadar.
--
-- Dari belakang yang terlihat cuma punggung: wajah, papan aura, dan
-- border semuanya menghadap ke arah lain, dan itu berlaku untuk semua
-- tier -- bukan cuma raksasa. Panggung ini ditonton dari depan.
--
-- Penggantinya satu sapuan sinus yang dikurung: kamera berangkat dari
-- depan, menyapu ke kanan, lewat depan lagi, ke kiri, lalu pulang ke
-- depan. Amplitudonya (arcDeg dari server) BATAS KERAS -- tidak ada
-- nilai u yang bisa membawanya lebih jauh dari itu.
local function busurSudut(u, amp, putaran)
	if not amp or amp <= 0 then return 0 end
	-- sin, bukan smoothstep antar titik: sin sudah melambat sendiri di
	-- kedua ujung sapuannya, dan yang penting di sini gerakan yang tidak
	-- pernah berhenti mendadak -- bukan perhentian yang terbaca seperti
	-- pada jalur tiga sudut dulu.
	--
	-- Selalu 0 di u=0. Di u=1 dia juga 0 untuk putaran yang kelipatan
	-- 0,5 (1,0 dan 1,5 yang dipakai sekarang), jadi adegannya berangkat
	-- dan pulang dari sudut yang sama: depan.
	return amp * math.sin(2 * math.pi * math.clamp(u, 0, 1) * (putaran or 1))
end

local function pandangLurus()
	if not CFG.spawnLurus then return end
	local ayun = ayunPada(os.clock())
	sudutBias = -ayun
end

-- ============ KAMERA ADEGAN NOVA (tier 4, Bouquet Flower) ============
--
-- Nova punya JALUR kamera sendiri, dan angkanya NOVA.KAMERA di server.
--
-- Ini pembalikan dari yang sempat tertulis di sini. Waktu nova baru
-- menggantikan dash, kameranya sengaja dibiarkan jadi kamera sorotan
-- biasa: nova terjadi di tempat orangnya berdiri, jadi kamera yang sudah
-- menghadap ke sana tidak perlu diganti. Itu benar sewaktu dia naik 13
-- stud. Pada 45 stud tidak lagi -- kamera yang diam di tanah memandang
-- orang setinggi sembilan badan cuma memperlihatkan telapak kakinya.
--
-- EMPAT bidikan berurutan, tiap satu menjawab pertanyaan yang berbeda:
--
--   NAIK    kamera RENDAH memandang ke atas sambil mengorbit 360 derajat
--           sekali penuh. Sudut rendah yang membuat dia menjulang;
--           orbitnya yang memperlihatkan dia dari segala sisi.
--   DIAM    meluncur ke DEPAN wajahnya dan berhenti selagi dia
--           menggantung. Satu-satunya detik tenang di seluruh adegan.
--   JATUH   meluncur ke ATAS kepalanya, jadi dia jatuh MENJAUH dari
--           lensa. Ini yang membuat 45 stud terbaca sebagai jarak.
--   LEDAKAN mundur ke shot lebar supaya shockwave dan barisan yang
--           berceceran muat dalam satu frame.
--
-- Kamera biasa TETAP dihitung di belakang layar selama adegan ini, jadi
-- pulangnya ke sorotan tarian yang sudah berjalan -- dan karena
-- pulangnya lewat Lerp yang turun dari 1 ke 0 (`lepas`), tidak ada satu
-- pun frame yang meloncat.
--
-- Dua hal lain masih dikemudikan modulnya lewat callback, dan tetap
-- MENUMPANG di atas apa pun yang dihasilkan jalur di atas:
--
--   FOV     menyempit pelan saat mengumpulkan tenaga, tajam saat
--           membanting, lalu melebar menghentak saat meledak
--   GETAR   goyangan waktu naik dan waktu menghantam tanah
--
-- Yang tidak pernah diserahkan ke modul: camera.CFrame dan
-- camera.FieldOfView itu sendiri. Kamera ini punya SATU penulis, gelung
-- render di bawah -- modul yang menulisnya sendiri akan dibatalkan
-- gelung itu di frame berikutnya.

-- Berapa derajat FOV sedang digeser dari FOV dasarnya, dan FOV dasar itu
-- berapa. novaFovDasar nil = tidak ada adegan yang sedang memegang FOV.
local novaFovDasar = nil
local novaFovNilai = nil   -- NumberValue: yang di-tween TweenService
local novaFovTween = nil

-- Getaran kamera: sisa waktu, kekuatan awal, dan pergeseran yang berlaku
-- di frame ini.
local novaGetarSampai = 0
local novaGetarLama   = 0
local novaGetarKuat   = 0
local novaGetarOffset = Vector3.zero

-- Geser FOV sejauh `delta` derajat dari FOV dasar adegan ini, dalam
-- `lama` detik. delta 0 = pulang ke FOV dasarnya.
--
-- Lewat NumberValue yang di-tween, bukan menghitung sendiri di gelung
-- render: yang diminta modulnya easing Roblox (Sine, Quint, Elastic) dan
-- menulis ulang ketiganya di sini berarti menyalin kurva yang sudah ada.
local function novaFov(delta, lama, style, dir)
	if not novaFovNilai then return end
	if novaFovTween then pcall(function() novaFovTween:Cancel() end) end
	local tujuan = tonumber(delta) or 0
	lama = math.max(tonumber(lama) or 0, 0)
	if lama <= 0 then
		novaFovNilai.Value = tujuan
		return
	end
	novaFovTween = TweenService:Create(novaFovNilai,
		TweenInfo.new(lama, style or Enum.EasingStyle.Quad,
			dir or Enum.EasingDirection.Out), { Value = tujuan })
	novaFovTween:Play()
end

-- Goyangkan kamera selama `lama` detik dengan kekuatan `kuat` stud.
-- lama <= 0 menghentikannya sekarang (dipakai waktu adegannya ditutup).
local function novaGetar(lama, kuat)
	lama = tonumber(lama) or 0
	kuat = tonumber(kuat) or 0
	if lama <= 0 or kuat <= 0 then
		novaGetarSampai, novaGetarOffset = 0, Vector3.zero
		return
	end
	novaGetarSampai = os.clock() + lama
	novaGetarLama   = lama
	novaGetarKuat   = kuat
end

-- Dipanggil gelung render tiap frame, SEBELUM camera.CFrame ditulis.
local function novaGetarFrame()
	if os.clock() >= novaGetarSampai then
		novaGetarOffset = Vector3.zero
		return
	end
	-- Meluruh ke nol supaya getarannya berhenti pelan, bukan dipotong.
	local sisa = (novaGetarSampai - os.clock()) / math.max(novaGetarLama, 1e-3)
	local k = novaGetarKuat * math.clamp(sisa, 0, 1)
	novaGetarOffset = Vector3.new(
		(math.random() - 0.5) * k,
		(math.random() - 0.5) * k,
		(math.random() - 0.5) * k)
end

-- Adegan yang sedang jalan. nil = tidak ada. Diisi jalankanNova,
-- dikosongkan gelung render sendiri begitu adegannya habis.
local novaKam = nil

local function haluskan(u)
	u = math.clamp(u, 0, 1)
	return u * u * (3 - 2 * u)
end

local function antara(a, b, u) return a + (b - a) * u end

-- CFrame kamera nova pada waktu t, dan seberapa kuat dia menimpa kamera
-- biasa (0..1). nil = adegannya habis.
--
-- "Depan" = sisi -Z. Bukan pilihan bebas: barisan tumbuh ke arah -Z
-- (getPosition di server) dan kamera panggung duduk di CAMERA_BACK yang
-- juga negatif, jadi -Z itu sisi tempat penonton berada -- dan avatarnya
-- menghadap ke sana. Kamera di sisi +Z memandang punggung.
local function kameraNova(s, t)
	local k     = s.k
	local j     = s.j
	local e     = t - s.mulai
	local atas  = Vector3.new(0, 1, 0)
	local depan = Vector3.new(0, 0, -1)

	-- Titik lantai yang dipakai SELURUH bidikan di bawah.
	--
	-- Dia bergeser kalau adegannya mendarat di tempat lain daripada
	-- tempat dia mulai (s.tanahAkhir, dari `tujuan` di server): badannya
	-- melintas ke sana selama fase ascend, dan orbit yang tetap
	-- melingkari titik asal akan menyeret dia keluar frame -- lalu
	-- ledakannya terjadi di luar layar.
	--
	-- Gesernya mengikuti fase yang sama dengan badannya, jadi begitu
	-- fase diam mulai keduanya sudah sama-sama sampai.
	local tanah = s.tanah
	if s.tanahAkhir then
		local u = 0
		if e >= j.ascend then
			u = haluskan((e - j.ascend) / math.max(j.freeze - j.ascend, 0.01))
		end
		tanah = s.tanah:Lerp(s.tanahAkhir, u)
	end
	local badan = s.badan or (tanah + atas * 3)

	local lepas = math.max(tonumber(k.lepas) or 1, 0.05)
	if e > j.selesai + lepas then return nil end

	-- --- NAIK: orbit rendah ---
	if e < j.freeze then
		local u = math.clamp(e / math.max(j.freeze, 0.01), 0, 1)
		local a = 2 * math.pi * u * (tonumber(k.naikPutaran) or 1)
		local r = tonumber(k.naikRadius) or 26
		-- a=0 menaruh kamera di (0, tinggi, -r) -- tepat di depan. Dan
		-- karena putarannya bilangan bulat, a=2pi mengembalikannya ke
		-- titik yang sama: fase berikutnya berangkat dari depan tanpa
		-- satu pun loncatan.
		-- Tingginya naik LEBIH CEPAT daripada orbitnya (naikCepat),
		-- supaya kamera sudah lewat di atas kepala barisan sebelum
		-- orbitnya membawa dia ke sisi belakang. Alasan lengkapnya di
		-- NOVA.KAMERA di server.
		local cepat  = math.max(tonumber(k.naikCepat) or 1, 0.01)
		local tinggi = antara(tonumber(k.naikBawah) or 2,
			tonumber(k.naikAtas) or 16, haluskan(math.min(u * cepat, 1)))
		local pos = tanah + Vector3.new(math.sin(a) * r, tinggi,
			-math.cos(a) * r)
		return CFrame.lookAt(pos, badan), 1
	end

	-- Posisi kamera di akhir orbit. Dihitung, bukan disimpan dari frame
	-- terakhir: frame terakhir belum tentu jatuh tepat di u=1, dan
	-- selisih sekecil apa pun di situ terlihat sebagai sentakan.
	local orbitAkhir = tanah + Vector3.new(0,
		tonumber(k.naikAtas) or 16, -(tonumber(k.naikRadius) or 26))

	-- Tinggi badannya DI PUNCAK. Dicatat sekali saat fase diam dimulai:
	-- sesudah dia menjatuhkan diri, `badan` sudah turun -- dan bidikan
	-- fase jatuh di bawah harus berangkat dari tempat kamera berada
	-- waktu dia masih menggantung, bukan dari tempat dia sekarang.
	if not s.puncak then s.puncak = badan end

	local posDepan = s.puncak + depan * (tonumber(k.diamRadius) or 20)
		- atas * (tonumber(k.diamTurun) or 3)

	-- --- DIAM DI PUNCAK: meluncur ke depan wajahnya ---
	if e < j.slam then
		local u = haluskan((e - j.freeze)
			/ math.max(j.slam - j.freeze, 0.01))
		return CFrame.lookAt(orbitAkhir:Lerp(posDepan, u), badan), 1
	end

	local posAtas = tanah + atas * (tonumber(k.atasNaik) or 52)
		+ depan * (tonumber(k.atasRadius) or 22)

	-- --- JATUH: meluncur ke atas kepalanya ---
	--
	-- Bidikannya tetap di badannya, yang sedang turun: jadi kamera naik
	-- dan orangnya turun di frame yang sama, dan 45 stud itu terbaca
	-- sebagai jarak yang ditempuh -- bukan sebagai angka.
	if e < j.mendarat then
		local u = haluskan((e - j.slam)
			/ math.max(j.mendarat - j.slam, 0.01))
		return CFrame.lookAt(posDepan:Lerp(posAtas, u), badan), 1
	end

	-- --- LEDAKAN: mundur ke shot lebar, lalu lepas ---
	local mundur = math.max(tonumber(k.lebarMundur) or 1.2, 0.05)
	local u = haluskan(math.min((e - j.mendarat) / mundur, 1))
	local posLebar = tanah + atas * (tonumber(k.lebarNaik) or 20)
		+ depan * (tonumber(k.lebarRadius) or 46)
	-- posAtas dihitung ulang di sini lewat nilai yang sama, bukan
	-- disimpan: fase ini berangkat dari tempat fase jatuh berakhir, dan
	-- dua rumus terpisah untuk satu titik yang sama akan berpisah
	-- diam-diam kalau salah satunya digeser.
	-- Dibidik SEDIKIT DI ATAS lantai, bukan ke badannya: yang dijual
	-- fase ini bukan orangnya lagi, tapi apa yang terjadi di sekitarnya.
	local cf = CFrame.lookAt(posAtas:Lerp(posLebar, u), tanah + atas * 4)

	local sisa = j.selesai - e
	if sisa < lepas then
		return cf, math.clamp(sisa / lepas, 0, 1)
	end
	return cf, 1
end

-- ============ KAMERA PANGGUNG ROSA ============
--
-- Jalur kamera Rosa, dari ROSA.JALUR di server: DARI BAWAH, KELILING dekat,
-- POTRET, lalu LEPAS. Diisi panggungRosa, dibaca gelung render, dan
-- dikosongkan gelung render sendiri begitu jalurnya habis.
--
-- "Depan" = -Z, sama dengan nova. Semua posisi dihitung dari titik
-- LANTAI tempat dia berdiri (tanah) dan tinggi badannya sendiri.
local rosaKam = nil

local function kameraRosa(s, t)
	local J = s.j
	local e = t - s.mulai
	local naik   = tonumber(J.naik) or 2.6
	local orbit  = tonumber(J.orbit) or 3.4
	local potret = tonumber(J.potret) or 2.6
	local lepas  = math.max(tonumber(J.lepas) or 1.4, 0.05)
	local mulaiLepas = naik + orbit + potret
	if e > mulaiLepas + lepas then return nil end

	local g, H = s.tanah, s.tinggi
	local atas = Vector3.new(0, 1, 0)
	local r = tonumber(J.radius) or 7
	local tOrbit = H * (tonumber(J.tinggiOrbit) or 0.55)
	local bOrbit = H * (tonumber(J.bidikOrbit) or 0.55)

	local pos, bidik
	if e < naik then
		-- DARI BAWAH. Ujung bidikan ini SAMA PERSIS dengan titik awal
		-- keliling di bawah (sudut 0), jadi pergantiannya tanpa loncatan.
		local u = haluskan(e / math.max(naik, 0.01))
		local jarak = antara(tonumber(J.naikJauh) or 10, r, u)
		pos   = g + Vector3.new(0,
			antara(tonumber(J.naikBawah) or 0.6, tOrbit, u), -jarak)
		bidik = g + atas * antara(H * (tonumber(J.naikBidik) or 0.3), bOrbit, u)
	elseif e < mulaiLepas - potret then
		-- KELILING. Sudutnya dihaluskan di kedua ujung, jadi putarannya
		-- berangkat dan berhenti pelan -- bukan langsung berputar penuh
		-- dari keadaan diam. Putarannya bulat: pulang ke depan.
		local u = (e - naik) / math.max(orbit, 0.01)
		local a = 2 * math.pi * (tonumber(J.putaran) or 1) * haluskan(u)
		local y = tOrbit + math.sin(math.pi * u) * (tonumber(J.orbitNaik) or 0)
		pos   = g + Vector3.new(math.sin(a) * r, y, -math.cos(a) * r)
		bidik = g + atas * bOrbit
	else
		-- POTRET: sepertiga pertama naik ke wajah sambil mundur sedikit
		-- (supaya papan auranya masuk frame), sisanya dorong masuk pelan.
		local u = math.clamp((e - naik - orbit) / math.max(potret, 0.01), 0, 1)
		local tP = H * (tonumber(J.potretTinggi) or 0.8)
		local bP = H + (tonumber(J.potretBidik) or 0.8)
		local jauhP  = tonumber(J.potretJauh) or 9
		local dekatP = tonumber(J.potretDekat) or 6.5
		local jarak, y, b
		if u < 0.35 then
			local v = haluskan(u / 0.35)
			jarak, y, b = antara(r, jauhP, v), antara(tOrbit, tP, v),
				antara(bOrbit, bP, v)
		else
			local v = haluskan((u - 0.35) / 0.65)
			jarak, y, b = antara(jauhP, dekatP, v), tP, bP
		end
		pos   = g + Vector3.new(0, y, -jarak)
		bidik = g + atas * b
	end

	local mix = 1
	local masuk = math.max(tonumber(J.masuk) or 0.4, 0.05)
	if e < masuk then mix = haluskan(e / masuk) end
	if e > mulaiLepas then
		mix = 1 - haluskan((e - mulaiLepas) / lepas)
	end
	return CFrame.lookAt(pos, bidik), mix
end

-- Ambil alih FOV untuk satu adegan, dan kembalikan fungsi pelepasnya.
--
-- FOV dasarnya dibaca SEKALI di sini. Kalau dibaca tiap panggilan novaFov,
-- adegan kedua yang datang selagi yang pertama masih menyempitkan FOV akan
-- mengunci angka yang sedang digeser sebagai "dasar" -- dan FOV-nya tidak
-- pernah pulang lagi.
local function novaAmbilFov(kam)
	if novaFovNilai then return nil end   -- sudah ada adegan yang memegang
	novaFovDasar = kam.FieldOfView
	novaFovNilai = Instance.new("NumberValue")
	novaFovNilai.Value = 0

	return function()
		if novaFovTween then pcall(function() novaFovTween:Cancel() end) end
		novaFovTween = nil
		if novaFovNilai then novaFovNilai:Destroy() end
		novaFovNilai = nil
		if novaFovDasar then kam.FieldOfView = novaFovDasar end
		novaFovDasar = nil
	end
end

-- ============ ZOOM MASUK LALU KELUAR ============
--
-- Tiap kedatangan baru, kamera mulai DEKAT lalu ditarik mundur ke jarak
-- biasa. Ini yang menggantikan ayunan lebar sebagai sumber gerakan:
-- ayunan menggerakkan seluruh gambar terus-menerus, zoom bergerak
-- sekali per kedatangan lalu berhenti.
--
-- Yang disimpan cuma KAPAN kedatangan terakhir; sisanya dihitung ulang
-- tiap frame dari selisih waktunya. Tidak ada tween yang harus
-- dibatalkan kalau ada yang datang di tengah jalan -- kedatangan
-- berikutnya cuma menulis ulang satu angka.
local zoomMulai = -1e9   -- jauh di masa lalu = sedang tidak zoom

-- Berapa lama menahan dekat sebelum mundur. Diisi ulang tiap kedatangan:
-- yang biasa memakai CFG.zoomTahan, yang BERBAYAR memakai lama
-- sorotannya sendiri -- jadi kamera menahan dekat di orang yang bayar
-- selama dia masih jadi sorotan, bukan cuma 1,6 detik pertama.
local zoomTahan = 0

-- Lama mundurnya untuk kedatangan ini, detik. Diisi dari pesan server
-- (tiap tier punya angkanya sendiri, lihat KAMERA_TIER di sana); kalau
-- pesannya tidak membawa angka, pakai setelan umum.
local zoomKeluar = CFG.zoomKeluar or 1.8

-- MERAPAT sampai sedekat apa, sebagai pecahan jarak penuh. Pasangan
-- zoomMaks di bawah: yang ini ujung dekatnya, yang itu ujung jauhnya.
--
-- Biasanya CFG.zoomMasuk untuk semua kedatangan. Yang mengisinya sendiri
-- cuma raksasa: badan 14x tidak muat di jarak sedekat itu, dan yang
-- terpotong kepalanya. Diisi ulang tiap kedatangan dengan alasan yang
-- sama seperti zoomMaks -- angka milik satu adegan tidak boleh diwarisi
-- kedatangan berikutnya.
local zoomMasuk = CFG.zoomMasuk or 0.45

-- Mundur sampai sejauh apa, sebagai pecahan jarak penuh. 1 = sejauh
-- biasa, 0,75 = berhenti di tiga perempat jalan.
--
-- Ini yang membuat adegan berbayar tetap terasa dekat tanpa kameranya
-- menempel. Cuma berlaku SELAMA adegannya (dikali sinemaMix di gelung),
-- jadi sesudahnya kamera pulang ke jarak penuh sendiri -- kalau tidak,
-- satu kedatangan tier 2 akan meninggalkan kamera terlalu dekat untuk
-- selamanya.
local zoomMaks = 1

-- Berapa frame gelung ini benar-benar jalan. Dipakai laporan di bawah:
-- "gelungnya tidak pernah jalan" dan "gelungnya jalan tapi hasilnya tidak
-- kelihatan" itu dua penyakit berbeda dengan obat berbeda.
local frame = 0

RunService.RenderStepped:Connect(function(dt)
	-- Dibaca ULANG tiap frame, bukan dipakai salinan dari awal script.
	--
	-- Ini bug yang bikin kamera diam total tanpa error: `camera` diisi
	-- sekali di awal dari workspace.CurrentCamera, dan di awal sesi
	-- nilainya masih bisa nil. Setelah itu satu-satunya yang memperbarui
	-- salinan lokal ini sinyal "CurrentCamera berubah" -- dan sinyal itu
	-- TIDAK menyala kalau kameranya sudah terpasang sejak sebelum script
	-- ini jalan. Jadi salinannya nil selamanya, gelung ini return di
	-- baris pertama tiap frame, dan tidak ada satu pun yang bisa
	-- dilihat di Output.
	--
	-- Membaca properti tiap frame itu murah; kehilangan kamera karena
	-- balapan yang tidak kelihatan tidak.
	camera = workspace.CurrentCamera
	if not camera then return end
	frame += 1

	-- Dipaksa tiap frame, bukan cuma lewat sinyal.
	--
	-- PlayerModule menyetel CameraType kembali ke Custom, dan sinyal
	-- GetPropertyChangedSignal kadang kalah cepat (atau tidak menyala
	-- kalau nilainya diset ke nilai yang sama dari sisi mesin). Menulis
	-- nilai yang sudah sama tidak memicu apa-apa, jadi ini gratis.
	if camera.CameraType ~= Enum.CameraType.Scriptable then
		camera.CameraType = Enum.CameraType.Scriptable
	end

	-- Penghalusan eksponensial: tidak bergantung frame rate, dan tidak
	-- perlu tahu kapan gerakannya "selesai" -- fokus baru boleh datang
	-- kapan saja di tengah jalan.
	local a = 1 - math.exp(-dt / math.max(CFG.moveS or 0.8, 0.05) * 3)
	fokusKini = fokusKini:Lerp(fokusTarget, math.clamp(a, 0, 1))

	local t = os.clock()

	-- Ayunan biasa, DAN kecepatan sudutnya (turunan dari sin). Yang
	-- kedua dipakai supaya orbit bisa mengambil alih sebagai selisih
	-- kecepatan, bukan sebagai posisi baru -- lihat sudutBias di atas.
	local ayun, ayunVel = ayunPada(t)

	-- Zoom: 0 = sedekat CFG.zoomMasuk, 1 = jarak penuh.
	local zoom = 1
	if CFG.zoom then
		local zt = t - zoomMulai - zoomTahan
		-- Batas bawah, bukan angka apa adanya: zoomKeluar 0 membuat
		-- pembagian di bawah jadi nan, dan kameranya lenyap ke tempat
		-- yang tidak ada.
		local keluar = math.max(zoomKeluar or CFG.zoomKeluar or 1.8, 0.05)
		if zt <= 0 then
			zoom = 0
		elseif zt < keluar then
			local u = zt / keluar
			-- Cubic out: mundurnya cepat di awal lalu melambat, jadi
			-- gerakannya berhenti dengan lembut dan bukan dengan rem.
			zoom = 1 - (1 - u) * (1 - u) * (1 - u)
		end
	end

	local aktif = CFG.sinema and t < sinemaSampai
	local tujuanMix = aktif and 1 or 0
	local m = 1 - math.exp(-dt / 0.9 * 3)
	sinemaMix = sinemaMix + (tujuanMix - sinemaMix) * math.clamp(m, 0, 1)

	-- Orbit hanya untuk adegan yang memang mengorbit. Tier 2 lewat sini
	-- dengan sinemaMix penuh tapi sinemaOrbit false: kameranya tetap
	-- mengayun seperti biasa, yang berubah cuma jaraknya.
	local orbitAktif = sinemaOrbit and sinemaMix > 0.001
	if orbitAktif then
		-- Orbit sedang TIDAK dipakai: main.py mengirim orbit=false untuk
		-- semua tier, jadi cabang ini tidak pernah jalan. Mesinnya
		-- dibiarkan utuh supaya orbit bisa dinyalakan lagi dari sana
		-- tanpa menyentuh file ini -- dan periodenya kembali ke setelan
		-- umum, bukan angka per kedatangan yang tidak lagi dikirim.
		local orbitVel = (2 * math.pi) / math.max(CFG.sinemaOrbitS or 14, 0.5)
		sudutBias += (orbitVel - ayunVel) * sinemaMix * dt
	end

	-- Kemajuan adegan yang sedang jalan, 0..1. Dipakai dua hal di bawah
	-- (busur menyamping dan gerakan naik-turun), jadi dihitung sekali.
	--
	-- Tetap dihitung selagi sinemaMix meluruh sesudah adegannya habis;
	-- di situ u sudah dijepit ke 1, dan kedua gerakan bernilai NOL di
	-- u=1 -- jadi kameranya pulang ke depan dan ke tinggi biasa sendiri.
	local adeganAktif = sinemaMix > 0.001 and sinemaLama > 0
	local u = 0
	if adeganAktif then
		u = math.clamp(1 - (sinemaSampai - t) / math.max(sinemaLama, 0.01), 0, 1)
	end

	-- Busur DEPAN. Menulis sudutBias LANGSUNG, bukan menambahnya seperti
	-- orbit di atas: yang dituju sudut tertentu, bukan kecepatan
	-- tertentu -- dan itu yang membuat batas +/-arcRad benar-benar batas.
	--
	-- Ayunan dikurangi supaya sudut akhirnya (ayun + sudutBias) benar-
	-- benar sama dengan sudut busurnya. Kalau tidak, ayunan kiri-kanan
	-- yang jalan terus-menerus ikut menggeser busurnya, dan simpangannya
	-- bisa melewati batas tergantung kebetulan ayunan sedang di fase
	-- mana.
	--
	-- Dikali sinemaMix supaya masuk dan keluarnya mulus: di awal adegan
	-- mix naik dari 0 (~0,9 detik), jadi kamera MELUNCUR ke busurnya
	-- alih-alih meloncat.
	local busurAktif = adeganAktif and arcRad > 0
	if busurAktif then
		sudutBias = (busurSudut(u, arcRad, arcPutar) - ayun) * sinemaMix
	end

	-- Dilipat ke [-pi, pi] supaya peluruhan di bawah mengambil jalan
	-- terdekat. Tanpa ini, orbit tiga putaran meninggalkan selisih 18
	-- radian dan kameranya "memutar balik" tiga kali sebelum tenang --
	-- padahal sudut 18 dan sudut 18-6pi itu tempat yang sama persis.
	if sudutBias > math.pi or sudutBias < -math.pi then
		sudutBias = (sudutBias + math.pi) % (2 * math.pi) - math.pi
	end

	-- Diluruhkan kapan pun orbit TIDAK sedang mengemudikannya.
	--
	-- Syaratnya dulu `sinemaMix < 0.02`, dan itu salah sejak sudutBias
	-- ikut dipakai pandangLurus. Sorotan tier 2 punya sinemaMix penuh
	-- tapi tidak mengorbit: bias-nya membeku di angka pembatal ayunan
	-- selama lima detik penuh, sementara ayunan yang dibatalkannya terus
	-- berjalan. Hasilnya sudut = ayun(sekarang) - ayun(saat datang),
	-- yang bisa mencapai DUA KALI lebar ayunan -- justru lebih menyerong
	-- daripada kalau tidak dibetulkan sama sekali.
	if not orbitAktif and not busurAktif and sudutBias ~= 0 then
		sudutBias = sudutBias * math.exp(-dt / SINEMA_PULIH)
		if math.abs(sudutBias) < 0.001 then sudutBias = 0 end
	end

	local sudut = ayun + sudutBias

	-- Jaraknya dicampur dulu (biasa -> sinematik), lalu zoom bekerja di
	-- atasnya. Zoom sengaja MENGALIKAN, bukan jadi lapis campuran
	-- ketiga: dengan begitu dia bekerja sama di jarak mana pun --
	-- termasuk di jarak raksasa yang berkali lipat -- tanpa satu pun
	-- angka tambahan.
	-- Jarak dan TINGGI diskalakan sendiri-sendiri. Lihat sinemaJauhY:
	-- satu pengali untuk keduanya menaruh kamera raksasa di atas kepala
	-- raksasanya sendiri.
	local sinemaKini = Vector3.new(offsetSinema.X * sinemaJauh,
		offsetSinema.Y * sinemaJauhY,
		offsetSinema.Z * sinemaJauh)
	local dasar = offsetDasar:Lerp(sinemaKini, sinemaMix)

	-- Batas mundur, dicampur mengikuti adegannya.
	--
	-- Dikali sinemaMix, bukan dipakai apa adanya: di luar adegan
	-- nilainya harus kembali 1 (jarak penuh). Tanpa pencampuran ini,
	-- zoomMaks 0,75 dari satu kedatangan tier 2 akan tetap berlaku
	-- untuk SEMUA kedatangan sesudahnya -- kamera diam-diam berhenti
	-- pernah mundur penuh lagi, dan barisan belakang tidak pernah
	-- terlihat lagi.
	local maksKini = 1 + ((zoomMaks or 1) - 1) * sinemaMix
	local skala = zoomMasuk + (maksKini - zoomMasuk) * zoom

	-- DENYUT: merapat sekali lagi di paruh akhir adegan.
	--
	-- Dikerjakan di sini, pada `skala`, dan bukan dengan menulis ulang
	-- zoomMulai: zoom dasarnya fungsi waktu-sejak-datang yang cuma tahu
	-- satu gerakan (masuk lalu mundur). Memaksanya berdenyut lewat
	-- zoomMulai berarti "kedatangan" yang palsu -- dan itu ikut
	-- mengulang penundaan `tahan` dan menyeret hal lain yang membaca
	-- angka yang sama.
	--
	-- abs(sin), bukan sin: untuk denyutUlang > 1 separuh gelombangnya
	-- negatif, dan yang negatif MENJAUHKAN kamera. Yang diminta rapatan
	-- yang berulang, bukan rapat-jauh-rapat-jauh.
	--
	-- Dikali sinemaMix dengan alasan yang sama seperti busur dan
	-- naik-turun: masuk dan keluar adegan harus meluncur.
	if adeganAktif and denyutDalam > 0 then
		local sisa = math.max(1 - denyutMulai, 0.001)
		local v    = math.clamp((u - denyutMulai) / sisa, 0, 1)
		local dalam = math.abs(math.sin(math.pi * v * (denyutUlang or 1)))
		skala = math.max(skala * (1 - denyutDalam * dalam * sinemaMix),
			DENYUT_MIN)
	end

	-- TINGGINYA tidak ikut dikalikan -- dia justru NAIK saat kameranya
	-- mundur.
	--
	-- Kalau tingginya ikut dikalikan seperti jaraknya, kamera yang
	-- mundur juga ikut turun mendekati lantai, dan dari sana barisan
	-- yang sejajar dan sama tinggi saling menutupi: yang terlihat cuma
	-- baris paling depan, sisanya bersembunyi persis di belakang badan
	-- mereka. Naik sedikit sambil mundur membuat kepala baris kedua dan
	-- ketiga muncul di atas bahu baris di depannya.
	--
	-- Kenaikannya DITAMBAHKAN, bukan menimpa: jadi mode sinematik yang
	-- punya tingginya sendiri (sinemaUp) tetap terpakai, dan yang ini
	-- cuma menumpang di atasnya.
	-- Tingginya IKUT diskalakan seperti jaraknya, LALU ditambah
	-- kenaikan yang cuma berlaku waktu mundur.
	--
	-- Skalanya tidak boleh dilewati. Kalau tinggi dibiarkan penuh
	-- sementara jaraknya dipangkas jadi 45%, sudut tunduk kamera
	-- melonjak dari 13 ke 27 derajat tepat di detik dia paling dekat --
	-- dan sudut tunduk itu yang memotong kaki. Persis masalah yang
	-- CAMERA_UP diturunkan untuk menyelesaikannya.
	--
	-- Jadi dua suku: yang pertama menjaga sudut pandangnya tetap sama
	-- di jarak berapa pun, yang kedua menaikkan kamera HANYA saat dia
	-- sudah mundur -- di situ yang penting kerumunannya, bukan satu
	-- badan yang utuh.
	local naik = ((upJauhKini or CFG.upJauh or CFG.up) - CFG.up) * zoom

	-- Naik-turun khusus adegan berbayar, stud.
	--
	-- Puncaknya di TENGAH adegan lalu pulang ke nol di akhir: sin(pi*u)
	-- bernilai 0 di u=0 dan u=1, jadi kameranya berangkat dan pulang
	-- dari tinggi yang sama dan tidak meninggalkan pergeseran apa pun
	-- untuk kedatangan berikutnya.
	--
	-- Ini pengganti gerakan yang dulu dikerjakan orbit. Untuk raksasa
	-- justru lebih tepat: badan setinggi empat orang dibaca dari kaki ke
	-- kepala, dan kamera yang naik-turun memperlihatkan itu -- sementara
	-- kamera yang memutar ke samping cuma memperlihatkan punggungnya.
	--
	-- Dikali sinemaMix dengan alasan yang sama seperti busurnya: masuk
	-- dan keluar adegan harus meluncur, bukan meloncat.
	local naikAdegan = 0
	if adeganAktif and naikAmp ~= 0 then
		-- naikPutar gundukan, bukan selalu satu. Dengan 2, paruh kedua
		-- gelombangnya NEGATIF -- kamera turun di bawah tinggi biasa,
		-- dan itu memang yang diminta: tier 3 bergerak ke atas DAN ke
		-- bawah, bukan cuma naik lalu pulang.
		--
		-- Tidak di-abs seperti denyut di atas: di sini yang negatif ada
		-- gunanya. Pulang ke nol di u=1 selama naikPutar bulat.
		naikAdegan = naikAmp
			* math.sin(math.pi * u * (naikPutar or 1)) * sinemaMix
	end

	dasar = Vector3.new(dasar.X * skala,
		dasar.Y * skala + naik + naikAdegan,
		dasar.Z * skala)

	local offset = CFrame.Angles(0, sudut, 0):VectorToWorldSpace(dasar)
	local cf = CFrame.new(fokusKini + offset, fokusKini)

	-- Jalur kamera nova MENIMPA semua gerakan di atas selama adegannya,
	-- lalu melepaskannya lewat mix yang turun ke 0. Lihat kameraNova.
	-- Jalur kamera Rosa, dengan cara yang sama persis seperti nova di
	-- bawah: menimpa kamera sorotan biasa lewat mix, lalu melepasnya.
	-- Nova dicampur SESUDAHNYA, jadi kalau keduanya pernah bertemu, nova
	-- yang menang.
	if rosaKam then
		local rcf, rmix = kameraRosa(rosaKam, t)
		if rcf then
			cf = cf:Lerp(rcf, math.clamp(rmix, 0, 1))
		else
			rosaKam = nil
		end
	end

	if novaKam then
		local ncf, mix = kameraNova(novaKam, t)
		if ncf then
			cf = cf:Lerp(ncf, math.clamp(mix, 0, 1))
		else
			novaKam = nil
		end
	end

	-- Getarannya MENAMBAH di atas apa pun hasilnya, jalur nova termasuk.
	--
	-- Digeser di ruang KAMERA (cf * CFrame.new(...)), bukan di sumbu
	-- dunia: goyangan yang selalu ke arah +X dunia terbaca berbeda-beda
	-- tergantung kamera sedang menghadap ke mana, dan di sudut tertentu
	-- dia berubah jadi zoom yang bergetar alih-alih guncangan.
	novaGetarFrame()
	if novaGetarOffset ~= Vector3.zero then
		cf = cf * CFrame.new(novaGetarOffset)
	end

	if novaFovNilai and novaFovDasar then
		camera.FieldOfView = math.clamp(novaFovDasar + novaFovNilai.Value,
			1, 120)
	end

	camera.CFrame = cf
end)

-- Laporan sekali, dua detik setelah mulai.
--
-- Ini yang membedakan tiga sebab "kamera diam" yang di layar kelihatan
-- sama persis:
--   frame = 0             -> gelungnya tidak jalan sama sekali
--   CameraType ~= Script  -> ada yang merebut kamera (KameraClient lama?)
--   posisi tidak berubah  -> gelungnya jalan tapi angkanya nol
task.delay(2, function()
	local p1 = camera and camera.CFrame.Position
	task.wait(1)
	local p2 = camera and camera.CFrame.Position

	print(("[diagnosa kamera] frame=%d  type=%s  geser 1 detik=%.2f studs")
		:format(frame,
			camera and tostring(camera.CameraType) or "tanpa kamera",
			(p1 and p2) and (p2 - p1).Magnitude or -1))
end)

-- ============ AURA DI TENGAH LAYAR ============

local gui = Instance.new("ScreenGui")
gui.Name           = "AuraGui"
gui.ResetOnSpawn   = false
gui.IgnoreGuiInset = true
gui.DisplayOrder   = 10
gui.Parent         = pemain:WaitForChild("PlayerGui")

-- Ukurannya pakai Scale, bukan Offset: layar HP penonton dan layar
-- Studio jauh berbeda, dan tulisan yang pas di satu layar hilang di
-- layar lain kalau dipatok pixel.
-- HUD diagnosa di pojok kiri atas.
--
-- Laporan yang sama seperti print di atas, tapi DI LAYAR dan hidup
-- terus. Sebabnya sederhana: kalau HUD-nya sendiri tidak kelihatan,
-- itu sudah jawaban -- LocalScript-nya memang tidak jalan, dan tidak
-- perlu ada yang membaca Output untuk tahu itu.
--
-- Matikan lewat DEBUG_HUD di AvatarQueueV2 kalau sudah beres.
local hud = nil
if CFG.debug then
	hud = Instance.new("TextLabel")
	hud.Size                   = UDim2.new(0, 420, 0, 22)
	hud.Position               = UDim2.new(0, 8, 0, 8)
	hud.BackgroundColor3       = Color3.fromRGB(0, 0, 0)
	hud.BackgroundTransparency = 0.4
	hud.Font                   = Enum.Font.Code
	hud.TextSize               = 14
	hud.TextColor3             = Color3.fromRGB(120, 255, 140)
	hud.TextXAlignment         = Enum.TextXAlignment.Left
	hud.Text                   = "kamera: menunggu frame pertama"
	hud.Parent                 = gui

	task.spawn(function()
		local lalu = nil
		while true do
			local cam = workspace.CurrentCamera
			local p   = cam and cam.CFrame.Position
			local gsr = (p and lalu) and (p - lalu).Magnitude or 0
			lalu = p

			hud.Text = ("frame=%d  %s  geser=%.2f  fokus=%s")
				:format(frame,
					cam and tostring(cam.CameraType):gsub("Enum.CameraType.", "")
						or "TANPA KAMERA",
					gsr,
					string.format("%.0f,%.0f,%.0f",
						fokusKini.X, fokusKini.Y, fokusKini.Z))
			task.wait(0.5)
		end
	end)
end

-- ============ GAYA TEKS (FONT, GRADIEN, GLOW) ============
--
-- Font bawaan Roblox (Gotham/Legacy) langsung terbaca "template": semua
-- game pakai itu. Yang dipakai di sini FontFace, bukan Enum.Font --
-- keluarga font yang sama dengan yang dipakai UI game modern, dengan
-- bobot huruf yang bisa dipilih sendiri.
--
--   Sarpanch ExtraBold  -> ANGKA. Huruf lebar, sudutnya tajam, terbaca
--                          dari jauh. Ini yang bikin angkanya terasa
--                          seperti skor, bukan teks biasa.
--   Montserrat Bold     -> NAMA. Geometris, bersih, tidak berebut
--                          perhatian dengan angkanya.
--
-- Tiga lapis yang bikin teksnya "hidup" tanpa jadi ramai:
--   1. UIGradient  -- warnanya bergerak dari atas ke bawah, bukan satu
--                     warna datar.
--   2. UIStroke    -- garis gelap tipis, tugasnya cuma memisahkan huruf
--                     dari langit/avatar di belakangnya.
--   3. label kembar di belakang -- huruf yang sama, warna neon, stroke
--                     tebal dan tembus. Roblox tidak punya blur untuk
--                     GUI, jadi glow-nya dipalsukan begini. Efeknya
--                     halus: yang dilihat penonton cuma "hurufnya
--                     bercahaya".
local FONT_ANGKA = Font.new("rbxasset://fonts/families/Sarpanch.json",
	Enum.FontWeight.ExtraBold)
local FONT_NAMA  = Font.new("rbxasset://fonts/families/Montserrat.json",
	Enum.FontWeight.Bold)
local FONT_KATA  = Font.new("rbxasset://fonts/families/Montserrat.json",
	Enum.FontWeight.SemiBold)

local function grad(...)
	local titik = {}
	for i, w in ipairs({ ... }) do
		table.insert(titik, ColorSequenceKeypoint.new(
			(i - 1) / (select("#", ...) - 1), w))
	end
	return ColorSequence.new(titik)
end

-- Nama: neon biru -> ungu. Dipakai untuk SEMUA nama, sengaja sama --
-- yang boleh berbeda antar avatar cuma angkanya.
-- Sengaja TERANG, bukan neon biru-ungu seperti sebelumnya.
--
-- Versi lama (125,226,255 -> 150,170,255 -> 196,130,255) itu biru ke
-- ungu, dan panggungnya berlatar biru: hurufnya punya warna yang
-- hampir sama dengan apa pun yang ada di belakangnya, jadi yang
-- membedakan tinggal stroke tipis di pinggirnya. Dari jarak kamera
-- penuh itu tidak cukup -- namanya terbaca sebagai bercak, bukan teks.
--
-- Yang menggantikannya tetap dingin (biar satu keluarga dengan
-- panggungnya) tapi jauh lebih terang: putih ke biru es. Terangnya
-- itu yang mengangkatnya dari latar, bukan warnanya.
local GRAD_NAMA = grad(Color3.fromRGB(255, 255, 255),
                       Color3.fromRGB(226, 243, 255),
                       Color3.fromRGB(168, 214, 255))
local GLOW_NAMA = Color3.fromRGB(150, 200, 255)

-- CATATAN: papan latar gelap di belakang tulisan sempat ada di sini dan
-- SUDAH DIBUANG atas permintaan.
--
-- Ditulis supaya tidak dipasang lagi tanpa sadar: papan itu membuat
-- kontras tidak bergantung pada latar, tapi bentuknya kotak melayang di
-- atas tiap kepala dan itu yang tidak diinginkan. Penggantinya warna
-- huruf yang jauh lebih terang plus stroke yang ditebalkan -- artinya
-- keterbacaannya memang kembali bergantung pada apa yang ada di
-- belakangnya. Kalau nanti masih ada sudut yang tulisannya tenggelam,
-- yang ditebalkan STROKE-nya, bukan papannya dipasang kembali.

-- Angka: warnanya IKUT nilainya. Penonton hafal polanya setelah
-- beberapa kedatangan, dan itu yang bikin angka 900 terasa berbeda dari
-- 200 sebelum angkanya sendiri terbaca.
local TIER = {
	-- Raksasa, dan cuma dia: 10.000% tidak bisa dicapai dengan cara
	-- lain (AURA_RAKSASA di server, tidak diundi). Ambangnya ditaruh
	-- jauh di bawah 10.000 supaya angkanya sudah berwarna emas selagi
	-- putarannya masih naik -- yang dijual justru putaran itu, dan
	-- warna yang baru berganti di frame terakhir tidak ikut menjualnya.
	--
	-- Putih ke emas, satu-satunya yang HANGAT di panggung sedingin ini.
	{ min = 5000, warna = grad(Color3.fromRGB(255, 255, 255),
	                           Color3.fromRGB(255, 226, 130),
	                           Color3.fromRGB(255, 168,  40)),
	              glow  = Color3.fromRGB(255, 200, 70) },
	{ min = 850, warna = grad(Color3.fromRGB(255, 236, 150),
	                          Color3.fromRGB(255, 150,  50),
	                          Color3.fromRGB(255,  72,  60)),
	             glow  = Color3.fromRGB(255, 120, 40) },
	{ min = 600, warna = grad(Color3.fromRGB(255, 170, 240),
	                          Color3.fromRGB(210, 120, 255),
	                          Color3.fromRGB(140, 110, 255)),
	             glow  = Color3.fromRGB(200, 110, 255) },
	{ min =   0, warna = grad(Color3.fromRGB(160, 255, 250),
	                          Color3.fromRGB(110, 190, 255),
	                          Color3.fromRGB(140, 130, 255)),
	             glow  = Color3.fromRGB(90, 170, 255) },
}

local function tier(persen)
	for _, t in ipairs(TIER) do
		if persen >= t.min then return t end
	end
	return TIER[#TIER]
end

-- Label kembar di belakang tiap teks. Disimpan di tabel, bukan sebagai
-- anak label aslinya: anak SELALU digambar di atas induknya (ZIndex
-- Sibling), jadi glow yang jadi anak malah menutupi hurufnya.
local glowOf = setmetatable({}, { __mode = "k" })

local function setTeks(t, txt)
	t.Text = txt
	local g = glowOf[t]
	if g then g.Text = txt end
end

local function warnai(t, warna, glow)
	local g = t:FindFirstChildOfClass("UIGradient")
	if g then g.Color = warna end

	local kembar = glowOf[t]
	if kembar then
		kembar.TextColor3 = glow
		local s = kembar:FindFirstChildOfClass("UIStroke")
		if s then s.Color = glow end
	end
end

-- Satu baris teks lengkap: gradien + stroke + glow.
--   induk   ScreenGui/BillboardGui/Frame tempat dia ditaruh
--   warna   ColorSequence gradiennya
--   glow    warna cahayanya (nil = tanpa glow)
--   tembus  transparansi teks aslinya
local function teksGaya(induk, nama, posY, tinggi, font, warna, glow,
                        tebalStroke, tembus, ukuranMax)
	local t = Instance.new("TextLabel")
	t.Name                   = nama
	t.Size                   = UDim2.new(1, 0, tinggi, 0)
	t.Position               = UDim2.new(0, 0, posY, 0)
	t.BackgroundTransparency = 1
	t.FontFace               = font
	t.TextColor3             = Color3.fromRGB(255, 255, 255)
	t.TextScaled             = true
	t.TextTransparency       = tembus or 0
	-- TextStroke lama dimatikan: dia menggandakan huruf jadi blok hitam
	-- bergerigi. UIStroke di bawah jauh lebih bersih (sudutnya bulat,
	-- tebalnya bisa pecahan).
	t.TextStrokeTransparency = 1
	t.Text                   = ""
	t.ZIndex                 = 2
	t.Parent                 = induk

	if ukuranMax then
		local batas = Instance.new("UITextSizeConstraint")
		batas.MaxTextSize = ukuranMax
		batas.Parent      = t
	end

	local g = Instance.new("UIGradient")
	g.Color    = warna
	g.Rotation = 90
	g.Parent   = t

	local s = Instance.new("UIStroke")
	s.Color           = Color3.fromRGB(10, 12, 24)
	s.Thickness       = tebalStroke
	s.Transparency    = 0.15
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.LineJoinMode    = Enum.LineJoinMode.Round
	s.Parent          = t

	t:SetAttribute("BaseT", tembus or 0)
	t:SetAttribute("BaseS", 0.15)

	if glow then
		-- Clone, bukan bikin dari nol: apa pun yang berubah di label
		-- aslinya (ukuran, posisi, batas ukuran huruf) ikut sendiri.
		local k = t:Clone()
		k.Name              = nama .. "Glow"
		k.ZIndex            = 1
		k.TextColor3        = glow
		k.TextTransparency  = 0.55
		local kg = k:FindFirstChildOfClass("UIGradient")
		if kg then kg:Destroy() end
		local ks = k:FindFirstChildOfClass("UIStroke")
		ks.Color        = glow
		ks.Thickness    = tebalStroke * 3.5
		ks.Transparency = 0.45
		k:SetAttribute("BaseT", 0.55)
		k:SetAttribute("BaseS", 0.45)
		k.Parent = induk
		glowOf[t] = k
	end

	return t
end

-- Label + glow-nya sebagai satu daftar, untuk di-tween bareng.
local function lapisan(daftar)
	local out = {}
	for _, t in ipairs(daftar) do
		table.insert(out, t)
		if glowOf[t] then table.insert(out, glowOf[t]) end
	end
	return out
end

-- Muncul/hilang. Tiap lapis kembali ke transparansi ASALNYA, bukan ke
-- nol: glow yang dipaksa ke nol berhenti jadi cahaya dan jadi huruf
-- kedua yang tebal.
local function pudar(daftar, waktu, keluar)
	for _, t in ipairs(lapisan(daftar)) do
		local s  = t:FindFirstChildOfClass("UIStroke")
		local tT = keluar and 1 or (t:GetAttribute("BaseT") or 0)
		local sT = keluar and 1 or (t:GetAttribute("BaseS") or 0)
		local info = TweenInfo.new(waktu)

		if not keluar then
			t.TextTransparency = 1
			if s then s.Transparency = 1 end
		end
		TweenService:Create(t, info, { TextTransparency = tT }):Play()
		if s then TweenService:Create(s, info, { Transparency = sT }):Play() end
	end
end

local kotak = Instance.new("Frame")
kotak.Size                   = UDim2.new(1, 0, CFG.auraH, 0)
kotak.Position               = UDim2.new(0, 0, CFG.auraY, 0)
kotak.BackgroundTransparency = 1
kotak.Visible                = false
kotak.Parent                 = gui

-- Aura di layar: ukuran hurufnya besar, jadi stroke dan glow-nya ikut
-- tebal. Angkanya yang paling menyala; nama dan kata AURA di bawahnya
-- lebih tenang supaya matanya tetap jatuh ke angka.
local lblNama = teksGaya(kotak, "Nama", 0.00, 0.22, FONT_NAMA,
	GRAD_NAMA, GLOW_NAMA, 2, 0, 70)
local lblPersen = teksGaya(kotak, "Persen", 0.22, 0.48, FONT_ANGKA,
	TIER[#TIER].warna, TIER[#TIER].glow, 3, 0, 200)
local lblAura = teksGaya(kotak, "Aura", 0.72, 0.26, FONT_KATA,
	grad(Color3.fromRGB(225, 232, 245), Color3.fromRGB(170, 182, 210)),
	nil, 1.5, 0.1, 90)
lblAura.TextXAlignment = Enum.TextXAlignment.Center

-- Nomor tayangan yang sedang jalan.
--
-- Kedatangan berikutnya bisa masuk sebelum yang sekarang selesai (poll
-- tiap 1 detik). Tanpa nomor ini, task lama yang bangun belakangan
-- menyembunyikan aura milik orang yang BARU muncul.
local auraGen = 0

local function tampilkanAura(d)
	auraGen += 1
	local gen = auraGen

	setTeks(lblNama,   d.nama or "?")
	setTeks(lblAura,   "A U R A")
	setTeks(lblPersen, "0%")
	-- Warna angkanya dipasang SEBELUM hitungannya jalan: kalau diganti
	-- di akhir, gradiennya berkedip pas angkanya berhenti.
	local jenjang = tier(d.persen or 0)
	warnai(lblPersen, jenjang.warna, jenjang.glow)
	kotak.Visible = true

	pudar({ lblNama, lblPersen, lblAura }, 0.18, false)

	task.spawn(function()
		-- Angkanya berhitung naik, tidak langsung ditulis: yang bikin
		-- angka acak terasa seperti "diundi" itu gerakannya, bukan
		-- besarnya.
		local target = d.persen or 0
		local roll   = math.max(d.roll or CFG.auraRoll or 0.6, 0.01)

		-- Ditunda sama seperti papan kepala, alasannya di sana. Versi
		-- layar sedang tidak dipakai (AURA_DI_LAYAR false), tapi
		-- dibiarkan berperilaku beda berarti menyalakannya nanti
		-- memunculkan bug yang sudah pernah diperbaiki.
		local tunda = math.max(tonumber(d.tunda) or 0, 0)
		if tunda > 0 then
			task.wait(tunda)
			if gen ~= auraGen then return end
		end

		local mulai = os.clock()

		while gen == auraGen do
			local t = (os.clock() - mulai) / roll
			if t >= 1 then break end
			-- Melambat di akhir, jadi angka terakhirnya sempat terbaca.
			local e = 1 - (1 - t) * (1 - t) * (1 - t)
			setTeks(lblPersen, ("%d%%"):format(math.floor(target * e)))
			RunService.RenderStepped:Wait()
		end

		if gen ~= auraGen then return end
		setTeks(lblPersen, ("%d%%"):format(target))

		-- Sentakan kecil di angka akhirnya. Ini penanda "sudah, ini
		-- angkanya" -- tanpa itu hitungannya cuma berhenti.
		for _, t in ipairs(lapisan({ lblPersen })) do
			t.Size = UDim2.new(1, 0, 0.54, 0)
			TweenService:Create(t,
				TweenInfo.new(0.25, Enum.EasingStyle.Back,
					Enum.EasingDirection.Out),
				{ Size = UDim2.new(1, 0, 0.48, 0) }):Play()
		end

		task.wait(math.max((d.lama or CFG.auraTime or 3.5) - roll, 0.2))
		if gen ~= auraGen then return end

		pudar({ lblNama, lblPersen, lblAura }, 0.3, true)
		task.wait(0.3)
		if gen == auraGen then kotak.Visible = false end
	end)
end

-- ============ AURA DI ATAS KEPALA ============
--
-- Versi dunia dari tulisan yang sama. Bedanya bukan cuma tempat:
-- yang di layar tampil satu per satu lalu hilang, yang ini MENETAP di
-- atas kepala pemiliknya sampai avatarnya dihapus. Jadi penonton bisa
-- membandingkan angka satu avatar dengan tetangganya -- dan itu yang
-- bikin angka acak jadi bahan omongan di kolom komentar.
--
-- Warna dan bobot huruf sengaja tidak rata. Versi sebelumnya putih
-- pekat + emas terang di tiga barisnya sekaligus: tiap baris berteriak
-- sama kerasnya, jadi tidak ada yang menonjol dan yang terbaca cuma
-- "ramai". Sekarang cuma ANGKA-nya yang bergradien dan bercahaya; nama
-- dan kata AURA lebih tenang, tugasnya memberi konteks.
-- Papan yang masih terpasang, beserta barisnya. Dipakai untuk melepas
-- papan baris belakang begitu ada yang membuka baris baru di depan.
local papanAura = {}

-- Lepaskan papan semua avatar yang barisnya DI BELAKANG baris ini.
local function lepasBarisBelakang(barisDepan)
	if not CFG.auraDepanSaja then return end

	for i = #papanAura, 1, -1 do
		local p = papanAura[i]

		if not p.gui.Parent then
			table.remove(papanAura, i)
		elseif p.baris < barisDepan then
			table.remove(papanAura, i)

			local gui = p.gui
			if (CFG.auraFadeOut or 0) > 0 then
				-- Yang dipudarkan ISI-nya, bukan GUI-nya: BillboardGui
				-- tidak punya properti transparansi sendiri, jadi yang
				-- bisa di-tween cuma label-labelnya.
				for _, anak in ipairs(gui:GetChildren()) do
					if anak:IsA("TextLabel") then
						local info = TweenInfo.new(CFG.auraFadeOut)
						TweenService:Create(anak, info, {
							TextTransparency = 1,
						}):Play()
						-- Stroke-nya benda sendiri, tidak ikut pudar
						-- kalau cuma teksnya yang di-tween: papan yang
						-- "hilang" akan meninggalkan garis huruf.
						local s = anak:FindFirstChildOfClass("UIStroke")
						if s then
							TweenService:Create(s, info,
								{ Transparency = 1 }):Play()
						end
					end
				end
				task.delay(CFG.auraFadeOut + 0.05, function()
					if gui then gui:Destroy() end
				end)
			else
				gui:Destroy()
			end
		end
	end
end

local function auraDiKepala(d)
	local model = d.model
	if not model then return end

	-- Modelnya sudah ada di client? Server men-spawn-nya beberapa
	-- milidetik sebelum mengirim pesan ini, tapi replikasinya tidak
	-- dijamin sudah sampai. WaitForChild dengan batas, bukan tanpa
	-- batas: kalau avatarnya keburu dihapus (reset panggung), menunggu
	-- selamanya berarti satu thread menggantung untuk tiap kedatangan.
	local head = model:FindFirstChild("Head") or model:WaitForChild("Head", 5)
	if not head then return end

	local lama = head:FindFirstChild("AuraPlate")
	if lama then lama:Destroy() end

	local gui = Instance.new("BillboardGui")
	gui.Name        = "AuraPlate"
	gui.Size        = UDim2.new(0, CFG.auraKepalaW, 0, CFG.auraKepalaH)
	gui.StudsOffset = Vector3.new(0, CFG.auraKepalaY, 0)
	-- AlwaysOnTop supaya papannya tidak tertutup badan avatar di
	-- depannya. Kerumunan berbaris ke arah kamera, jadi tanpa ini
	-- papan baris belakang hilang separuh-separuh.
	gui.AlwaysOnTop = true
	gui.MaxDistance = CFG.auraKepalaJauh
	gui.Parent      = head

	-- Papan kepala jauh lebih kecil dari aura di layar, jadi angkanya
	-- dikecilkan dari sisi lain: stroke tipis dan glow cuma di angka.
	-- Nama dan kata AURA tanpa glow sama sekali -- puluhan papan yang
	-- semuanya bercahaya bikin panggungnya jadi kabut.
	-- CATATAN: ada cabang `d.namaSaja` di sini yang membuat papan
	-- raksasa cuma berisi SATU BARIS NAMA -- tanpa angka, tanpa kata
	-- AURA. Server sudah tidak pernah mengirim penanda itu lagi, jadi
	-- cabangnya dibuang.
	--
	-- Alasannya di sisi server (lihat tampilkanAura di sana): raksasa
	-- sekarang dapat 10.000%, satu-satunya angka di panggung yang tidak
	-- bisa dicapai siapa pun dengan cara lain, dan menyembunyikan
	-- angkanya berarti yang bayar paling mahal adalah satu-satunya yang
	-- papannya tidak pernah berputar.
	--
	-- Ditulis di sini supaya tidak dipasang lagi tanpa sadar: yang
	-- dikhawatirkan dulu papan tiga baris di atas kepala setinggi
	-- belasan stud jadi papan reklame yang menyaingi badannya sendiri.
	-- Itu masih benar; yang berubah cuma penilaiannya -- angka sebesar
	-- itu memang pantas menyaingi badannya.

	local jenjang   = tier(d.persen or 0)
	-- Nama: stroke 1 -> 2 dan tembus 0,05 -> 0. Dua-duanya soal yang
	-- sama, yaitu nama yang tenggelam di latar biru -- dan yang paling
	-- rugi dari itu justru penonton yang namanya sedang dipajang.
	local lblNama   = teksGaya(gui, "Nama", 0.00, 0.26, FONT_NAMA,
		GRAD_NAMA, nil, 2, 0)
	local lblPersen = teksGaya(gui, "Persen", 0.26, 0.46, FONT_ANGKA,
		jenjang.warna, jenjang.glow, 1.5, 0)
	-- Kata "AURA" tetap yang paling tenang dari ketiganya -- dia sama di
	-- semua avatar, jadi tidak membawa satu pun informasi dan tugasnya
	-- cuma memberi nama pada angka di atasnya.
	--
	-- Tapi "tenang" dan "tidak terbaca" itu dua hal berbeda, dan yang
	-- sebelumnya jatuh ke yang kedua: abu-abu 196-150 dengan tembus 0,3
	-- di atas latar biru praktis lenyap. Sekarang warnanya diangkat ke
	-- hampir putih dan tembusnya 0,3 -> 0,12; urutan perhatiannya tetap
	-- terjaga lewat UKURAN dan glow, bukan lewat membuatnya nyaris
	-- hilang.
	local lblAura   = teksGaya(gui, "Aura", 0.72, 0.24, FONT_KATA,
		grad(Color3.fromRGB(238, 244, 255), Color3.fromRGB(190, 202, 226)),
		nil, 1.5, 0.12)

	setTeks(lblNama, d.nama or "?")
	setTeks(lblAura, "A U R A")

	-- Papan RAKSASA berdiri di luar aturan baris.
	--
	-- Dia tidak ikut didaftarkan dan tidak memicu pelepasan apa pun.
	-- Kalau dia ikut: nomor slotnya (SLOT_RAKSASA) di server jauh di
	-- luar barisan, jadi barisnya keluar sebagai angka raksasa juga --
	-- dan lepasBarisBelakang akan membaca SELURUH papan lain sebagai
	-- "di belakang dia" lalu melepas semuanya sekaligus.
	--
	-- Diamnya juga benar secara tampilan: raksasa berdiri paling jauh
	-- dari kamera dan menjulang di atas semua orang, jadi papannya
	-- tidak pernah menembus badan siapa pun -- masalah yang membuat
	-- aturan baris depan ada sejak awal.
	-- Yang dilewati HANYA pembukuan barisnya. Angka auranya di bawah
	-- tetap berputar seperti punya orang lain -- raksasa yang papannya
	-- diam di "0%" adalah bug yang paling kelihatan dari seluruh
	-- panggung, justru karena papannya paling besar.
	if not d.tetap then
		-- Dia sudah berdiri; kalau dia yang membuka baris baru,
		-- papan-papan di baris belakangnya lepas sekarang.
		table.insert(papanAura, { gui = gui, baris = d.baris or 0 })
		lepasBarisBelakang(d.baris or 0)
	end

	task.spawn(function()
		local target = d.persen or 0
		local roll   = math.max(d.roll or CFG.auraRoll or 0.6, 0.01)

		-- Ditahan dulu sebelum angkanya berputar.
		--
		-- Papannya sendiri sudah berdiri sejak tadi (berisi "0%"), yang
		-- ditunda cuma hitungannya. Selama kamera masih merapat papan
		-- ini di luar frame ATAS, jadi tanpa penundaan bagian yang
		-- paling ditonton -- angkanya naik lalu mendarat -- habis
		-- sebelum papannya kelihatan. Angkanya dari server per tier;
		-- lihat KAMERA_TIER di sana.
		local tunda = math.max(tonumber(d.tunda) or 0, 0)
		if tunda > 0 then
			task.wait(tunda)
			-- Avatarnya sudah dihapus selagi ditunggu? Berhenti di sini.
			-- Tanpa cek ini papan yang sudah dilepas tetap dihitung
			-- sampai selesai, dan setiap kedatangan meninggalkan satu
			-- gelung yang tidak ada gunanya.
			if not gui.Parent then return end
		end

		local mulai = os.clock()

		while gui.Parent do
			local t = (os.clock() - mulai) / roll
			if t >= 1 then break end
			local e = 1 - (1 - t) * (1 - t) * (1 - t)
			setTeks(lblPersen, ("%d%%"):format(math.floor(target * e)))
			RunService.RenderStepped:Wait()
		end

		if not gui.Parent then return end
		setTeks(lblPersen, ("%d%%"):format(target))

		-- Raksasa: sesudah angkanya mendarat dan sempat dibaca, papannya
		-- dirapikan jadi NAMA SAJA. Server yang menentukan siapa dan
		-- berapa lama (AURA_RAKSASA_NAMA_S); di sini cuma dijalankan.
		--
		-- Label nama yang sudah ada DIPERBESAR mengisi papan, bukan dibuat
		-- ulang: kembarannya (glow) menempel lewat glowOf, dan label baru
		-- berarti kembaran baru yang harus dirangkai lagi.
		local sesudah = tonumber(d.namaSesudah)
		if sesudah and sesudah >= 0 then
			task.wait(sesudah)
			if not gui.Parent then return end
			for _, lbl in ipairs({ lblPersen, lblAura }) do
				local kembar = glowOf[lbl]
				if kembar then kembar:Destroy() end
				glowOf[lbl] = nil
				lbl:Destroy()
			end
			-- Sepertiga tinggi, sama dengan papan nama-saja yang dulu:
			-- kalau tingginya dibiarkan, namanya melayang di sepertiga atas
			-- dan sisanya kotak kosong yang mendorong papan menjauh dari
			-- kepalanya.
			gui.Size = UDim2.new(0, CFG.auraKepalaW, 0, CFG.auraKepalaH * 0.34)
			for _, lbl in ipairs({ lblNama, glowOf[lblNama] }) do
				if lbl then
					lbl.Position = UDim2.new(0, 0, 0, 0)
					lbl.Size     = UDim2.new(1, 0, 1, 0)
				end
			end
		end
	end)
end

-- ============ JUDUL LAGU ============
--
-- Pojok bawah, kecil, sebentar. Penonton perlu tahu lagunya ganti
-- (tariannya ikut ganti); yang tidak boleh cuma dia merebut tempat dari
-- angka aura.
local lblLagu = Instance.new("TextLabel")
lblLagu.Size                   = UDim2.new(0.4, 0, 0.05, 0)
lblLagu.Position               = UDim2.new(0.03, 0, 0.88, 0)
lblLagu.BackgroundTransparency = 1
lblLagu.FontFace               = FONT_KATA
lblLagu.TextColor3             = Color3.fromRGB(255, 255, 255)
lblLagu.TextScaled             = true
lblLagu.TextXAlignment         = Enum.TextXAlignment.Left
lblLagu.TextStrokeTransparency = 1
lblLagu.TextTransparency       = 1
lblLagu.Text                   = ""
lblLagu.Parent                 = gui

local batasLagu = Instance.new("UITextSizeConstraint")
batasLagu.MaxTextSize = 34
batasLagu.Parent      = lblLagu

local gradLagu = Instance.new("UIGradient")
gradLagu.Color    = grad(Color3.fromRGB(210, 232, 255),
                         Color3.fromRGB(160, 175, 215))
gradLagu.Rotation = 90
gradLagu.Parent   = lblLagu

local strokeLagu = Instance.new("UIStroke")
strokeLagu.Color           = Color3.fromRGB(10, 12, 24)
strokeLagu.Thickness       = 1.5
strokeLagu.Transparency    = 1
strokeLagu.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
strokeLagu.LineJoinMode    = Enum.LineJoinMode.Round
strokeLagu.Parent          = lblLagu

local laguGen = 0

local function tampilkanLagu(d)
	laguGen += 1
	local gen = laguGen

	lblLagu.Text = "♪ " .. (d.nama or "")
	TweenService:Create(lblLagu, TweenInfo.new(0.3),
		{ TextTransparency = 0 }):Play()
	-- Stroke ikut, kalau tidak judulnya "hilang" tapi garis hurufnya
	-- tertinggal di pojok layar.
	TweenService:Create(strokeLagu, TweenInfo.new(0.3),
		{ Transparency = 0.25 }):Play()

	task.spawn(function()
		task.wait(5)
		if gen ~= laguGen then return end
		TweenService:Create(lblLagu, TweenInfo.new(0.5),
			{ TextTransparency = 1 }):Play()
		TweenService:Create(strokeLagu, TweenInfo.new(0.5),
			{ Transparency = 1 }):Play()
	end)
end

-- ============ PENYAMAAN TARIAN ============
--
-- AnimationTrack.TimePosition yang ditulis SERVER tidak direplikasi:
-- yang sampai ke client cuma "mainkan animasi ini sekarang", lalu client
-- memutarnya dari detik nol. Dua avatar yang datang berselang 4 detik
-- menari berselang 4 detik juga, dan karena Looped selisih itu bertahan
-- selamanya.
--
-- Jadi penyamaannya harus di sini: TimePosition yang ditulis client
-- langsung mengubah apa yang digambar di layar client itu. Master yang
-- berbeda antar penonton tidak masalah -- yang penting serempak di dalam
-- satu layar.
--
-- DUA HAL YANG DULU SALAH DI SINI, dan dua-duanya terlihat sebagai
-- "tariannya patah-patah":
--
-- 1. Yang dikumpulkan SEMUA animasi yang sedang jalan, apa pun itu.
--    Sejak ada raksasa (R15Wave, panjang ~2 detik) dan avatar melayang
--    (R15Fall), mereka ikut masuk kolam -- dan begitu salah satunya
--    kebetulan terpilih jadi master, SELURUH kerumunan dipaksa ke
--    TimePosition milik animasi lambaian tiap 0,6 detik. Tarian 10
--    detik yang terus-menerus dilempar balik ke detik 0-2 itu persis
--    yang terlihat sebagai patah-patah. Sekarang track dikelompokkan
--    per AnimationId dan yang disamakan cuma KELOMPOK TERBESAR --
--    kerumunan selalu mayoritas, raksasa dan si terbang cuma satu.
--
-- 2. Selisihnya dikoreksi dengan MENULIS TimePosition, dan itu selalu
--    meloncat. Selisih 0,05 detik pun jadi sentakan kecil yang terlihat
--    tiap 0,6 detik. Sekarang yang digeser KECEPATANNYA: yang
--    ketinggalan diputar sedikit lebih cepat sampai dia menyusul
--    sendiri, tanpa satu pun frame yang meloncat. TimePosition cuma
--    dipakai kalau selisihnya sudah terlalu besar untuk dikejar dengan
--    cara halus (syncSnap) -- di situ satu loncatan memang lebih baik
--    daripada menunggu belasan detik.
local function kumpulkanTarian()
	local daftar = {}
	for _, m in ipairs(workspace:GetChildren()) do
		-- Karakter penonton punya Humanoid juga, dan dia tidak sedang
		-- menari bersama antrian.
		if m:IsA("Model") and not Players:GetPlayerFromCharacter(m) then
			local hum = m:FindFirstChildOfClass("Humanoid")
			local animator = hum and hum:FindFirstChildOfClass("Animator")
			if animator then
				local main = animator:GetPlayingAnimationTracks()[1]
				if main then table.insert(daftar, main) end
			end
		end
	end
	return daftar
end

-- Kelompok terbesar yang memainkan animasi yang SAMA.
--
-- Dipilih dengan menghitung, bukan dengan bertanya ke server: client
-- yang join di tengah siaran tidak pernah menerima pesan "lagunya
-- sekarang ini", dan menebak dari jumlah selalu benar karena kerumunan
-- memang selalu lebih banyak daripada satu raksasa dan satu penerbang.
local function kelompokTerbesar(daftar)
    local per = {}
    for _, t in ipairs(daftar) do
        local anim = t.Animation
        local id   = anim and anim.AnimationId
        if id and id ~= "" then
            local g = per[id]
            if not g then g = {} per[id] = g end
            table.insert(g, t)
        end
    end

    local terbesar = nil
    for _, g in pairs(per) do
        if not terbesar or #g > #terbesar then terbesar = g end
    end
    return terbesar
end

-- Selisih waktu dua track, DILIPAT ke jarak terdekat pada lingkaran.
--
-- Tariannya Looped, jadi yang berada di detik 9,9 dari animasi 10 detik
-- sebenarnya cuma 0,1 detik DI DEPAN yang di detik 0 -- bukan 9,9 detik
-- di belakangnya. Tanpa lipatan ini, avatar yang kebetulan berada di
-- seberang titik ulang akan terus-menerus dianggap melenceng jauh dan
-- terus-menerus diloncatkan. Itu satu lagi sumber patah-patah, dan yang
-- paling sulit dilacak karena cuma muncul pada avatar tertentu di detik
-- tertentu.
--
-- Hasilnya selalu di rentang [-L/2, +L/2]. Positif = `kini` ketinggalan
-- dan harus dipercepat.
local function selisihLingkar(ref, kini, L)
	local d = ref - kini
	if not L or L <= 0 then return d end
	return (d + L / 2) % L - L / 2
end

task.spawn(function()
	if (CFG.resyncEvery or 0) <= 0 then return end

	-- Master dipegang lintas putaran. Kalau tiap putaran diambil "yang
	-- pertama ketemu", urutan GetChildren yang berubah bikin master
	-- berpindah -- dan tiap perpindahan menyeret semua yang lain ke fase
	-- baru, jadi seluruh panggung tersentak tiap beberapa detik.
	local master = nil

	while true do
		task.wait(CFG.resyncEvery)

		local grup = kelompokTerbesar(kumpulkanTarian())
		if grup and #grup > 1 then
			local masihAda = false
			if master then
				for _, t in ipairs(grup) do
					if t == master then masihAda = true break end
				end
			end
			if not masihAda then master = grup[1] end

			-- Master SELALU dikembalikan ke kecepatan normal.
			--
			-- Dia bisa saja track yang beberapa detik lalu masih jadi
			-- pengikut dan sempat dipercepat 9% untuk menyusul. Kalau
			-- kecepatan itu dibiarkan menempel setelah dia naik jadi
			-- master, SELURUH kerumunan mengejar acuan yang berlari 9%
			-- lebih cepat dari seharusnya -- dan mereka berhasil, jadi
			-- tidak ada satu pun yang terlihat salah. Yang terjadi cuma
			-- seluruh panggung menari lebih cepat daripada lagunya.
			master:AdjustSpeed(1)

			local ref = master.TimePosition
			local L   = master.Length or 0

			for _, t in ipairs(grup) do
				if t ~= master then
					local selisih = selisihLingkar(ref, t.TimePosition, L)
					local jauhnya = math.abs(selisih)
					if jauhnya > (CFG.syncSnap or 0.35) then
						-- Terlalu jauh untuk dikejar halus (biasanya
						-- avatar yang baru berdiri, atau yang baru
						-- mendarat dari adegan melayang). Satu
						-- loncatan, lalu kembali normal.
						t.TimePosition = ref
						t:AdjustSpeed(1)
					elseif jauhnya > (CFG.driftLimit or 0.04) then
						-- Yang ketinggalan diputar lebih cepat, yang
						-- kedahuluan diperlambat. Dibatasi supaya
						-- koreksinya tidak pernah terlihat sebagai
						-- gerakan yang dipercepat.
						t:AdjustSpeed(math.clamp(1 + (CFG.syncKp or 0.6) * selisih,
							1 - (CFG.syncSpeedMaks or 0.15),
							1 + (CFG.syncSpeedMaks or 0.15)))
					else
						-- Sudah serempak: kecepatannya dikembalikan ke
						-- normal. Tanpa baris ini koreksi terakhir
						-- menempel selamanya dan dia justru melewati
						-- targetnya, lalu dikoreksi ke arah sebaliknya
						-- -- berayun tanpa henti.
						t:AdjustSpeed(1)
					end
				end
			end
		else
			master = nil
		end
	end
end)

-- ============ BUNYI SAAT ANGKANYA BERPUTAR ============
--
-- Dibunyikan saat putaran mulai, lalu DIPOTONG tepat saat angkanya
-- mendarat -- bunyi dan angka berhenti bersamaan. Bunyi yang sekarang
-- lebih panjang dari AURA_ROLL, jadi yang terdengar cuma bagian
-- depannya; sisanya memang tidak pernah sampai.
--
-- auraSfxLoop (mati sekarang) untuk keadaan sebaliknya: bunyi yang
-- lebih PENDEK dari putaran. Tanpa diulang, dia habis di tengah jalan,
-- dan hening di tengah putaran terbaca sebagai "sudah selesai" padahal
-- angkanya masih naik.
--
-- Bunyinya ADA DUA, dan pergantian di antara keduanya yang sebenarnya
-- terdengar sebagai "mendarat": bunyi putaran dipotong dan bunyi
-- mendarat mulai, di frame yang sama.
--
-- Satu Sound dipakai berulang, bukan satu Sound baru tiap kedatangan.
-- Alasannya bukan hemat: kalau tiap kedatangan punya Sound sendiri,
-- dua orang yang datang berdekatan (poll tiap 1 detik) membunyikan dua
-- undian yang saling tumpang tindih -- terdengar seperti bunyi rusak,
-- bukan dua undian. Satu Sound yang diulang dari nol otomatis memotong
-- yang sebelumnya: yang terdengar selalu undian yang sedang berjalan.
--
-- Parent-nya SoundService, jadi dia tidak punya posisi di dunia: sama
-- kerasnya di mana pun kamera berada.
local function buatSfx(nama, id, volume)
	if not id or id == "" then return nil end

	local s = Instance.new("Sound")
	s.Name    = nama
	s.SoundId = id
	s.Volume  = volume
	s.Parent  = SoundService

	-- Dimuat di muka. Tanpa ini bunyi pertama datang terlambat --
	-- tepat pada kedatangan pertama, satu-satunya yang pasti ditonton
	-- orang dari awal.
	task.spawn(function()
		local ok, err = pcall(function()
			ContentProvider:PreloadAsync({ s })
		end)
		if not ok then warn(("Bunyi %s gagal dimuat: %s"):format(nama, err)) end
	end)

	return s
end

local sfxAura = buatSfx("AuraRollSfx", CFG.auraSfx, CFG.auraSfxVol or 0.7)

if sfxAura then
	-- Nadanya ikut naik bersama kecepatannya -- PlaybackSpeed
	-- menggeser tempo dan nada sekaligus.
	sfxAura.PlaybackSpeed = math.max(CFG.auraSfxSpeed or 1, 0.1)
	-- Looped hanya kalau ADA yang menghentikannya. Diulang tanpa
	-- auraSfxRoll berarti tidak satu pun Stop dipanggil: bunyinya
	-- berputar sampai sesi berakhir.
	sfxAura.Looped = (CFG.auraSfxLoop and CFG.auraSfxRoll) and true or false
end

-- Bunyi mendarat. Sengaja Sound yang TERPISAH, bukan SoundId yang
-- ditukar pada Sound di atas: keduanya harus bisa berbunyi di frame
-- yang sama -- yang satu dipotong, yang satu mulai -- dan satu Sound
-- cuma bisa memainkan satu di antaranya.
local sfxHit = buatSfx("AuraHitSfx", CFG.auraSfxHit, CFG.auraSfxHitVol or 0.8)

-- Bunyi mendarat untuk angka BESAR. Sound ketiga yang berdiri sendiri,
-- alasannya sama dengan yang di atas: dia dan sfxHit tidak pernah
-- berbunyi bersamaan, tapi yang menentukan mana yang dipakai baru
-- diketahui saat undiannya sudah jalan -- dan menukar SoundId di tengah
-- jalan pada Sound yang sedang dimuat kadang menghasilkan hening.
local sfxHitTinggi = buatSfx("AuraHitTinggiSfx", CFG.auraSfxHitTinggi,
	CFG.auraSfxHitTinggiVol or 0.9)

-- Bunyi mendarat KHUSUS RAKSASA. Sound keempat, berdiri sendiri seperti
-- dua di atasnya dan dengan alasan yang sama.
--
-- Dia MENGGANTI dua-duanya, tidak menambah. Raksasa selalu 10.000%
-- (AURA_RAKSASA di server), jadi tanpa dia yang berbunyi selalu
-- hentakan "angka besar" -- yang sama persis dengan milik penonton
-- gratisan yang kebetulan dapat 950, untuk angka yang sepuluh kali
-- lipat di atas apa pun yang bisa didapat orang lain.
--
-- Nadanya yang mengerjakan pekerjaannya: server mengirim 0,35, dan di
-- nada itu berkas mendarat bawaan Roblox turun satu setengah oktaf --
-- dia berhenti terdengar seperti orang mendarat dan jadi dentuman
-- rendah yang panjang.
local sfxHitRaksasa = buatSfx("AuraHitRaksasaSfx", CFG.auraSfxHitRaksasa,
	CFG.auraSfxHitRaksasaVol or 1.0)

-- Bunyi PUTARAN khusus raksasa: berkas yang sama dengan putaran biasa, nada
-- lebih rendah. Sound sendiri, bukan PlaybackSpeed yang ditukar pada
-- sfxAura: undian raksasa dan undian orang lain bisa menempel, dan menukar
-- nada Sound yang sedang berbunyi membuat putaran orang lain ikut berubah
-- nada di tengah jalan.
local sfxAuraRaksasa = buatSfx("AuraRollRaksasaSfx", CFG.auraSfx,
	CFG.auraSfxVol or 0.7)
if sfxAuraRaksasa then
	sfxAuraRaksasa.PlaybackSpeed = math.max(CFG.auraSfxSpeed or 1, 0.1)
		* math.max(tonumber(CFG.auraSfxRollRaksasaNada) or 1, 0.1)
	sfxAuraRaksasa.Looped = (CFG.auraSfxLoop and CFG.auraSfxRoll) and true or false
end
if sfxHitRaksasa then
	sfxHitRaksasa.PlaybackSpeed =
		math.max(tonumber(CFG.auraSfxHitRaksasaNada) or 1, 0.1)
end

-- --- BUNYI KEDATANGAN PER TIER ---
--
-- Satu Sound per tier, dibuat sekali di awal. Daftar kandidatnya dari
-- server (SFX_TIER); yang dipakai yang PERTAMA benar-benar berhasil
-- dimuat.
--
-- Kenapa harus dicoba satu per satu, bukan dipakai begitu saja: Sound
-- dengan SoundId yang tidak ada TIDAK melempar error. Dia cuma diam --
-- Play() jalan, tidak ada yang terdengar, tidak ada yang bisa dibaca di
-- Output. Satu-satunya cara tahu dia benar-benar ada memuatnya lalu
-- memeriksa IsLoaded.
local sfxTier = {}

local function muatSfxTier()
	local daftar = CFG.sfxTier
	if type(daftar) ~= "table" then return end

	for tier, setelan in pairs(daftar) do
		local kandidat = setelan and setelan.kandidat
		if type(kandidat) == "table" then
			local dipakai = nil

			for _, id in ipairs(kandidat) do
				local s = Instance.new("Sound")
				s.Name          = ("SfxTier%s"):format(tostring(tier))
				s.SoundId       = id
				s.Volume        = tonumber(setelan.vol) or 0.6
				s.PlaybackSpeed = math.max(tonumber(setelan.nada) or 1, 0.1)
				-- SoundService, jadi dia tidak punya posisi di dunia:
				-- sama kerasnya di mana pun kamera berada. Alasan
				-- lengkapnya sama dengan bunyi aura di atas.
				s.Parent        = SoundService

				local ok = pcall(function()
					ContentProvider:PreloadAsync({ s })
				end)

				-- IsLoaded, bukan cuma "PreloadAsync tidak error":
				-- preload yang selesai tanpa error masih bisa
				-- meninggalkan Sound kosong kalau asetnya memang tidak
				-- ada.
				if ok and s.IsLoaded then
					dipakai = id
					-- Dinormalkan ke ANGKA. Tabel yang lewat
					-- RemoteFunction tidak dijamin mempertahankan
					-- bentuk kuncinya, dan kunci "3" yang dicari dengan
					-- angka 3 tidak akan ketemu -- tanpa error, cuma
					-- hening. Disimpan sebagai angka di sini, dicari
					-- dua-duanya di bunyiTier.
					sfxTier[tonumber(tier) or tier] = s
					break
				end

				s:Destroy()
			end

			if dipakai then
				print(("[sfx] tier %s -- %s (volume %.2f, nada %.2f)")
					:format(tostring(tier), dipakai,
						tonumber(setelan.vol) or 0.6,
						tonumber(setelan.nada) or 1))
			else
				warn(("[sfx] tier %s TIDAK dapat bunyi -- %d kandidat " ..
					"dicoba, tidak satu pun berhasil dimuat.")
					:format(tostring(tier), #kandidat))
			end
		end
	end
end

task.spawn(muatSfxTier)

local function bunyiTier(tier)
	if not tier then return end
	-- Dicari sebagai angka DAN sebagai teks, alasannya di muatSfxTier.
	local s = sfxTier[tier] or sfxTier[tostring(tier)]
	if not s then return end
	-- Diulang dari nol, bukan dibiarkan menumpuk: dua kedatangan
	-- berbayar yang berdekatan harus terdengar sebagai dua kedatangan,
	-- bukan sebagai satu bunyi yang pecah.
	s.TimePosition = 0
	s:Play()
end

-- Nomor bunyi yang sedang jalan, sejajar dengan auraGen di atas: yang
-- menghentikan bunyi harus yang menyalakannya, bukan task lama yang
-- kebetulan bangun setelah undian berikutnya mulai.
local sfxGen = 0

-- Hentakan mendarat yang SUDAH dijanjikan tapi belum sempat berbunyi.
--
-- Ini yang dulu hilang. Undiannya tiga detik (AURA_ROLL) sementara
-- kedatangan baru bisa masuk tiap satu detik, jadi waktu panggungnya
-- ramai tiap undian selalu keburu diganti undian berikutnya -- dan
-- penjaga `gen` di task penundaannya membuang hentakannya diam-diam.
-- Akibatnya justru terbalik dari yang dimaui: makin ramai siarannya,
-- makin tidak pernah terdengar satu pun bunyi mendarat.
--
-- Sekarang tidak ada yang dibuang. Yang belum mendarat DITUNTASKAN
-- lebih dulu -- hentakannya berbunyi tepat sebelum putaran berikutnya
-- mulai, jadi urutan yang terdengar tetap "undian -> mendarat -> undian
-- berikutnya", cuma undian yang ketiban jadi lebih pendek dari tiga
-- detik penuh.
--
-- Isinya { gen = nomor undiannya, sfx = Sound mendarat yang dipilih }.
local hitTertunda = nil

local function tuntaskanHit(p)
	-- Sudah dituntaskan orang lain (atau ini sisa undian yang lebih
	-- lama lagi). Membunyikannya dua kali terdengar seperti gema.
	if hitTertunda ~= p then return end
	hitTertunda = nil

	-- Putarannya cuma dipotong kalau dia memang masih milik undian
	-- ini. Kalau undian berikutnya sudah mulai, Sound yang sama sedang
	-- memainkan putaran MILIK DIA -- memotongnya di sini berarti
	-- undian yang baru berbunyi sepersekian detik lalu hening.
	local putaran = p.roll or sfxAura
	if p.gen == sfxGen and putaran and CFG.auraSfxRoll and putaran.IsPlaying then
		putaran:Stop()
	end

	if p.sfx then
		p.sfx.TimePosition = 0
		p.sfx:Play()
	end
end

local function bunyiAura(roll, persen, tundaS, raksasa)
	-- Mana bunyi mendarat yang dipakai undian ini.
	--
	-- MENGGANTI, bukan menumpuk: kalau keduanya dibunyikan, yang
	-- terdengar cuma hentakan biasa yang kebetulan lebih ramai, dan
	-- angka 950 kehilangan satu-satunya penanda yang membedakannya dari
	-- 200. Kalau bunyi khususnya tidak ada (id kosong / gagal dimuat),
	-- jatuh kembali ke yang biasa -- lebih baik ada hentakan daripada
	-- angka besar yang mendarat tanpa suara.
	--
	-- Tiga tingkat, dibaca dari yang paling khusus: raksasa, lalu angka
	-- besar, lalu semua orang. Raksasa dikenali dari PENANDA yang
	-- dikirim server, bukan dari besarnya angka -- ambang angka di sini
	-- akan jadi jawaban kedua untuk "siapa yang raksasa", dan jawaban
	-- kedua itu yang diam-diam bisa tidak sepakat dengan yang pertama.
	local ambang = tonumber(CFG.auraTinggiMin) or 900
	local tinggi = sfxHitTinggi and (tonumber(persen) or 0) >= ambang
	local sfxMendarat = (raksasa and sfxHitRaksasa)
		or (tinggi and sfxHitTinggi)
		or sfxHit
	-- Putarannya juga punya versi raksasa. Jatuh ke yang biasa kalau
	-- Sound-nya tidak ada -- putaran tanpa bunyi lebih buruk daripada
	-- putaran dengan bunyi yang sama dengan orang lain.
	local sfxPutar = (raksasa and sfxAuraRaksasa) or sfxAura

	if not sfxPutar and not sfxMendarat then return end

	sfxGen += 1
	local gen = sfxGen

	-- Bunyinya ikut ditunda sepanjang penundaan angkanya.
	--
	-- Kalau tidak, bunyi putaran jalan selagi angkanya masih diam di
	-- "0%" dan hentakan mendaratnya jatuh sebelum angkanya bergerak
	-- sama sekali -- yang terdengar jadi bunyi milik kedatangan lain.
	--
	-- `gen` diambil SEBELUM penundaan, jadi undian yang datang di
	-- tengah penundaan membatalkan bunyi ini alih-alih menumpuknya.
	local tunda = math.max(tonumber(tundaS) or 0, 0)
	local function mulaiBunyi()
		if gen ~= sfxGen then return end

		-- Undian sebelumnya belum sempat mendarat -- bunyikan
		-- hentakannya SEKARANG, sebelum putaran yang baru mulai.
		-- Lihat hitTertunda: tanpa baris ini, panggung yang ramai
		-- tidak pernah terdengar mendarat sama sekali.
		if hitTertunda then tuntaskanHit(hitTertunda) end

		-- Putaran undian SEBELUMNYA dihentikan dulu. Dulu ini gratis:
		-- semua undian memakai satu Sound yang sama, dan Play() dari awal
		-- sekaligus memotong yang lama. Sekarang raksasa punya Sound
		-- sendiri, jadi putaran biasa yang masih jalan harus dipotong
		-- dengan tangan -- kalau tidak, dua putaran berbunyi bertumpuk.
		for _, lain in ipairs({ sfxAura, sfxAuraRaksasa }) do
			if lain and lain ~= sfxPutar and lain.IsPlaying then lain:Stop() end
		end

		if sfxPutar then
			sfxPutar.TimePosition = 0
			sfxPutar:Play()
		end

		-- Tidak ada yang perlu dikerjakan di akhir putaran: tidak ada
		-- bunyi mendarat, dan bunyi putarannya memang dibiarkan habis
		-- sendiri.
		if not sfxMendarat and not CFG.auraSfxRoll then return end

		-- Satu task untuk dua hal yang harus terjadi BERSAMAAN:
		-- putarannya dipotong dan bunyi mendaratnya mulai. Dipisah jadi
		-- dua task, dua penjadwalan yang berbeda bisa jatuh di frame
		-- yang berbeda -- dan celah sekecil itu pun terdengar sebagai
		-- bunyi yang tidak nyambung.
		--
		-- Batas bawahnya kecil saja -- undian sependek 0.05 detik memang
		-- tidak masuk akal, tapi 0 di sini berarti task ini jalan di
		-- frame yang sama dengan Play dan putarannya tidak sempat
		-- berbunyi.
		local tertunda = { gen = gen, sfx = sfxMendarat, roll = sfxPutar }
		hitTertunda = tertunda

		task.delay(math.max(roll or 0.6, 0.05), function()
			-- TIDAK lagi dibatalkan kalau sudah ada undian baru.
			--
			-- Dulu baris di sini `if gen ~= sfxGen then return end`,
			-- dan itu sumber bug-nya: undian berikutnya datang sebelum
			-- tiga detik lewat, jadi hentakan mendaratnya dibuang. Yang
			-- perlu dijaga bukan "siapa yang paling baru", tapi jangan
			-- sampai satu hentakan berbunyi dua kali dan jangan sampai
			-- putaran orang lain ikut dipotong -- dua-duanya diurus
			-- tuntaskanHit lewat perbandingan hitTertunda dan p.gen.
			tuntaskanHit(tertunda)
		end)
	end

	if tunda > 0 then
		task.delay(tunda, mulaiBunyi)
	else
		mulaiBunyi()
	end
end


-- ============ MUTU VISUAL PER PERANGKAT ============
--
-- Pencahayaan dan efeknya dipasang server (AvatarQueueV2, bagian
-- VISUAL) dan direplikasi ke semua orang. Yang tidak bisa dilakukan
-- server: tahu penontonnya menonton dari PC atau dari HP tahun 2019.
--
-- Jadi yang di sini cuma menurunkan, tidak pernah menaikkan. Efek yang
-- dimatikan dimatikan SECARA LOKAL -- penonton lain tidak ikut kena,
-- karena perubahan properti di client tidak balik ke server.
--
-- Urutannya dari yang paling mahal:
--   1. DepthOfField -- buram = layar digambar dua kali lalu dicampur
--   2. SunRays      -- ikut menghitung berkas tiap frame
--   3. Bloom        -- paling murah, cuma dikecilkan, tidak dimatikan
local function turunkanMutu(alasan)
	for _, nama in ipairs({ "VisualDOF", "VisualSunRays" }) do
		local e = Lighting:FindFirstChild(nama)
		if e then e.Enabled = false end
	end

	local pendar = Lighting:FindFirstChild("VisualBloom")
	if pendar then
		pendar.Intensity = (CFG.visualBloom or 0.45) * 0.5
	end

	print(("[visual] mutu diturunkan (%s) -- dof & sunrays mati")
		:format(alasan))
end

-- Sudah boleh mengerjakan hal berat di client?
--
-- Selama pengukuran FPS di bawah masih berjalan, jawabannya TIDAK -- dan
-- itu bukan kehati-hatian berlebihan, itu memperbaiki bug yang sudah
-- terjadi.
--
-- Pengukurannya menentukan mutu visual untuk SELURUH sesi, sekali, dan
-- tidak bisa dibatalkan. ContentProvider:PreloadAsync yang dipanggil
-- siapkanAvatar tiap kedatangan membuat frame tersendat -- kalau dia
-- jalan tepat di jendela pengukuran, angka yang terbaca bukan kemampuan
-- perangkatnya, tapi kesibukan yang KITA sendiri bikin. Hasilnya
-- DepthOfField dan SunRays dimatikan, Bloom dipotong separuh, dan
-- panggungnya terlihat jauh lebih datar sepanjang siaran.
--
-- Jadi selama jendela itu avatar muncul apa adanya (bertahap, seperti
-- sebelum ada siapkanAvatar). Delapan detik popping di awal jauh lebih
-- murah daripada kehilangan DOF dan bloom selama satu jam.
local bolehBerat = not CFG.visualAuto

if CFG.visualAuto then
	task.spawn(function()
		-- Layar sentuh tanpa keyboard = HP/tablet. Tidak diukur dulu:
		-- HP kelas atas memang sanggup 60 FPS, tapi dia mencapainya
		-- sambil panas, dan sesudah beberapa menit siaran frame-nya
		-- turun sendiri. Yang dijaga di sini siaran satu jam, bukan
		-- screenshot menit pertama.
		local UserInputService = game:GetService("UserInputService")
		if UserInputService.TouchEnabled
			and not UserInputService.KeyboardEnabled then
			turunkanMutu("layar sentuh")
			-- Keputusannya sudah jatuh tanpa mengukur, jadi tidak ada
			-- jendela yang perlu dilindungi lagi.
			bolehBerat = true
			return
		end

		-- Di Studio, JANGAN diukur.
		--
		-- Play di Studio menjalankan server dan client dalam satu
		-- proses, di atas editor yang juga sedang menggambar Explorer
		-- dan viewport-nya sendiri. Angka yang keluar (15 fps di mesin
		-- yang sama sekali tidak lemot) tidak mewakili apa pun tentang
		-- game yang sudah di-publish -- dan menurunkan mutu berdasarkan
		-- angka itu berarti kamu tidak pernah melihat tampilan yang
		-- sebenarnya akan dilihat penonton.
		if RunService:IsStudio() then
			print("[visual] Studio -- pengukuran FPS dilewati, mutu penuh")
			bolehBerat = true
			return
		end

		-- Selain itu: ukur SEKALI, lalu putuskan dan selesai.
		--
		-- Ditunggu 6 detik dulu. Detik-detik pertama habis untuk memuat
		-- avatar dan lagu; FPS di situ jelek untuk semua orang, dan
		-- mengukur di situ berarti menghukum PC yang sebenarnya kuat.
		task.wait(6)

		local frame = 0
		local sambung = RunService.RenderStepped:Connect(function()
			frame += 1
		end)
		local mulai = os.clock()
		task.wait(2)
		local lama = os.clock() - mulai
		sambung:Disconnect()

		-- Dibuka SEBELUM keputusannya, bukan sesudah: angkanya sudah
		-- terkumpul di baris di atas, jadi apa pun yang terjadi sekarang
		-- tidak bisa lagi mempengaruhinya.
		bolehBerat = true

		local fps = frame / math.max(lama, 0.01)
		print(("[visual] FPS terukur %.0f (ambang %.0f)")
			:format(fps, CFG.visualFpsMin or 32))
		if fps < (CFG.visualFpsMin or 32) then
			turunkanMutu(("%.0f fps"):format(fps))
		end
	end)
end

-- ============ MUNCUL UTUH, BUKAN BERTAHAP ============
--
-- Avatar datang POLOS dulu, beberapa detik kemudian rambutnya muncul,
-- lalu bajunya. Sebabnya bukan di kode server: rig-nya memang dibuat
-- seketika, tapi isinya cuma RUJUKAN (MeshId rambut, TextureId baju) --
-- dan file-nya baru diunduh dari CDN Roblox oleh TIAP PENONTON, saat
-- modelnya sudah kelihatan di layar mereka.
--
-- Karena unduhannya terjadi di sini, obatnya juga di sini: avatar yang
-- baru datang disembunyikan, asetnya ditunggu, lalu dimunculkan utuh.
--
-- Yang disembunyikan lewat LocalTransparencyModifier, BUKAN Transparency:
-- properti itu milik client dan tidak direplikasi, jadi menyetelnya
-- tidak menyentuh apa yang dilihat penonton lain. Transparency akan
-- dikirim balik ke server dan mengubah avatar untuk semua orang.
local disembunyikan = setmetatable({}, { __mode = "k" })

-- Yang punya properti Enabled dan HARUS ikut dimatikan selama badannya
-- belum kelihatan.
--
-- Bukan cuma badan yang perlu disembunyikan: server memasang border,
-- papan nama, dan aura VFX SESUDAH modelnya masuk workspace. Kalau
-- ketiganya dibiarkan menyala, yang terlihat selama gerbangnya tertutup
-- justru partikel dan garis yang mengambang tanpa orangnya -- lebih
-- aneh daripada popping yang mau dihilangkan.
local KELAS_MATIKAN = {
	BillboardGui = true, SurfaceGui = true,
	ParticleEmitter = true, Fire = true, Smoke = true, Sparkles = true,
	PointLight = true, SpotLight = true, SurfaceLight = true,
	Highlight = true, Beam = true, Trail = true,
}

local function siapkanAvatar(m)
	if not CFG.spawnSiap then return end
	-- Jendela pengukuran FPS masih jalan -- lihat bolehBerat. Avatarnya
	-- muncul apa adanya dulu; mutu visual seluruh sesi lebih mahal
	-- daripada popping beberapa detik pertama.
	if not bolehBerat then return end
	local maks = math.max(tonumber(CFG.spawnSiapMaks) or 0.6, 0)
	if maks <= 0 then return end

	local sudah = false

	local function sembunyikanSatu(d)
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		elseif KELAS_MATIKAN[d.ClassName] and d.Enabled then
			-- Dicatat mana yang KITA matikan, supaya yang memang sudah
			-- mati sejak awal tidak ikut dinyalakan waktu dibuka.
			d.Enabled = false
			disembunyikan[d] = true
		end
	end

	for _, d in ipairs(m:GetDescendants()) do sembunyikanSatu(d) end

	-- Yang datang BELAKANGAN (aksesori, rambut) ikut disembunyikan
	-- sampai gerbangnya dibuka. Tanpa ini justru merekalah yang muncul
	-- satu per satu -- persis yang mau dihilangkan.
	local sambung = m.DescendantAdded:Connect(function(d)
		if not sudah then sembunyikanSatu(d) end
	end)

	local function munculkan()
		if sudah then return end
		sudah = true
		sambung:Disconnect()

		local bagian = {}
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				table.insert(bagian, d)
			elseif disembunyikan[d] then
				d.Enabled = true
				disembunyikan[d] = nil
			end
		end

		local fade = math.max(tonumber(CFG.spawnSiapFade) or 0.12, 0)
		if fade <= 0 then
			for _, d in ipairs(bagian) do d.LocalTransparencyModifier = 0 end
			return
		end

		-- Ditulis tangan, bukan TweenService: LocalTransparencyModifier
		-- properti client yang tidak direplikasi, dan tween terhadapnya
		-- tidak bisa diandalkan.
		task.spawn(function()
			local t0 = os.clock()
			while m.Parent do
				local u = (os.clock() - t0) / fade
				if u >= 1 then break end
				for _, d in ipairs(bagian) do
					if d.Parent then d.LocalTransparencyModifier = 1 - u end
				end
				RunService.RenderStepped:Wait()
			end
			for _, d in ipairs(bagian) do
				if d.Parent then d.LocalTransparencyModifier = 0 end
			end
		end)
	end

	-- Batas keras, dipasang SEBELUM PreloadAsync dan bukan sesudah.
	--
	-- PreloadAsync memblokir sampai selesai, dan aset yang gagal diunduh
	-- bisa menahannya lama. Kalau batas ini dipasang setelahnya, dia
	-- tidak pernah sempat jalan -- dan avatarnya tidak pernah muncul.
	-- Yang lewat batas tetap dimunculkan, apa adanya.
	task.delay(maks, munculkan)

	task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync({ m }) end)
		munculkan()
	end)
end

-- Cakram lantai milik border di-parent ke workspace, BUKAN ke modelnya
-- (supaya dia tidak ikut terbawa bounding box avatarnya), jadi dia lolos
-- dari penyembunyian di atas -- dan yang terlihat jadi lingkaran cahaya
-- menyala di lantai tanpa siapa pun berdiri di atasnya.
--
-- Ditunda dengan timer sendiri, bukan disambungkan ke avatar tertentu:
-- keduanya dibuat dalam satu panggilan spawnAvatar yang sama, jadi
-- timernya berangkat pada saat yang praktis sama. Kalau badannya
-- kebetulan siap lebih cepat, yang terjadi cuma cakramnya menyusul
-- sebentar kemudian di bawah avatar yang sudah berdiri -- dan itu tidak
-- mengganggu sama sekali.
local function siapkanCakram(p)
	if not CFG.spawnSiap then return end
	-- Ikut menunggu jendela yang sama seperti siapkanAvatar: kalau cuma
	-- salah satunya ditahan, cakramnya disembunyikan tapi avatarnya
	-- tidak -- dan yang terlihat justru orang berdiri tanpa lingkaran
	-- cahaya yang seharusnya menyertainya.
	if not bolehBerat then return end
	local maks = math.max(tonumber(CFG.spawnSiapMaks) or 0.6, 0)
	if maks <= 0 then return end

	p.LocalTransparencyModifier = 1
	for _, d in ipairs(p:GetDescendants()) do
		if KELAS_MATIKAN[d.ClassName] and d.Enabled then
			d.Enabled = false
			disembunyikan[d] = true
		end
	end

	task.delay(maks, function()
		if not p.Parent then return end
		-- 0 = tanpa perubahan lokal, jadi Transparency milik cakramnya
		-- sendiri (BORDER_CAKRAM_ALPHA) yang kembali berlaku. Tidak ada
		-- yang perlu disimpan dan dikembalikan.
		p.LocalTransparencyModifier = 0
		for _, d in ipairs(p:GetDescendants()) do
			if disembunyikan[d] then
				d.Enabled = true
				disembunyikan[d] = nil
			end
		end
	end)
end

-- ============ KARAKTER PENONTON DISEMBUNYIKAN ============
--
-- Siaran ini direkam dengan MASUK ke room-nya lalu meng-capture layar,
-- dan begitu masuk Roblox men-spawn avatar penontonnya di panggung --
-- ikut terekam, berdiri di tengah kerumunan dengan nama di atas
-- kepalanya, dan tidak pernah menari.
--
-- Sampai sekarang karakter penonton sengaja DILEWATI di mana-mana
-- (lihat penjaga GetPlayerFromCharacter di ChildAdded), supaya dia tidak
-- ikut disembunyikan gerbang "muncul utuh" lalu penontonnya memandang
-- dirinya sendiri lenyap tiap respawn. Yang di sini kebalikannya, dan
-- disengaja: dia disembunyikan SELAMANYA, bukan sebentar.
--
-- SEMUANYA LOKAL. LocalTransparencyModifier tidak direplikasi, jadi
-- tidak ada satu pun baris di sini yang mengubah apa yang dilihat orang
-- lain -- kalau nanti ada dua orang yang masuk, masing-masing cuma
-- menyembunyikan dirinya sendiri.
local function sembunyikanPenonton(karakter)
	if not CFG.sembunyiPenonton then return end
	if not karakter then return end

	local function sembunyi(d)
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
			-- BAYANGANNYA ikut dimatikan, dan ini yang paling gampang
			-- terlewat: part yang ditembuskan secara lokal TETAP
			-- menjatuhkan bayangan. Bayangan orang yang tidak ada,
			-- bergerak di lantai panggung, justru lebih aneh daripada
			-- orangnya sendiri -- dan jauh lebih sulit ditebak asalnya.
			d.CastShadow = false
		elseif KELAS_MATIKAN[d.ClassName] and d.Enabled then
			-- Topi berpartikel dan aksesori bercahaya: badannya hilang
			-- tapi partikelnya tetap mengambang di udara.
			d.Enabled = false
		end
	end

	for _, d in ipairs(karakter:GetDescendants()) do sembunyi(d) end
	-- Aksesori diunduh belakangan (rambut, topi) -- lihat catatan
	-- panjang di siapkanAvatar soal kenapa. Tanpa baris ini merekalah
	-- yang muncul satu per satu di panggung, tanpa badan.
	karakter.DescendantAdded:Connect(sembunyi)

	local hum = karakter:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType   = Enum.HumanoidHealthDisplayType.AlwaysOff
	end

	-- Badannya diparkir. URUTANNYA PENTING: anchor DULU, baru
	-- CanCollide dimatikan.
	--
	-- Dibalik, dia jatuh menembus lantai sampai FallenPartsDestroyHeight,
	-- Roblox men-spawn-nya lagi, dan begitu terus -- gelung respawn yang
	-- tidak terlihat sama sekali karena badannya memang sudah tembus
	-- pandang. Yang terlihat cuma FPS yang turun pelan-pelan.
	local akar = karakter:FindFirstChild("HumanoidRootPart")
	if akar then
		akar.Anchored = true
		for _, d in ipairs(karakter:GetDescendants()) do
			if d:IsA("BasePart") then d.CanCollide = false end
		end
	end
end

sembunyikanPenonton(pemain.Character)
pemain.CharacterAdded:Connect(sembunyikanPenonton)

-- ============ NOVA TIER 3 ============
--
-- Server cuma mengirim "nova": model, seed, palet, dan setelan. Yang
-- terjadi di sini:
--
--   1. avatar ASLI ditahan tersembunyi (sejak ChildAdded, lewat atribut
--      TierNova yang dipasang server sebelum model masuk workspace)
--   2. asetnya ditunggu, sama batasnya dengan siapkanAvatar
--   3. SALINAN lokalnya memainkan seluruh adegan lewat TierNova, mulai
--      dari slot avatar aslinya
--   4. salinannya dihapus dan yang asli dimunculkan di titik salinan
--      itu MENDARAT (d.tujuan) -- server memindahkan avatar aslinya ke
--      sana di detik hantaman, jadi keduanya berdiri di titik yang sama
--
-- Kenapa salinan, bukan avatar aslinya yang digerakkan: posisi yang asli
-- milik server dan dipegang BodyPosition. CFrame yang ditulis client ke
-- badan itu ditimpa lagi oleh replikasi tiap frame -- dan kalaupun tidak,
-- dia cuma melayang di layar ini sambil ditarik pegas balik ke slotnya.
-- Salinan lokal tidak punya satu pun dari keduanya.
--
-- Nova juga BERPINDAH -- dia mendarat di slot 1, barisan yang baru saja
-- dikosongkan hantamannya sendiri. Pergantian salinan-ke-asli tetap
-- tidak bisa terlihat, dan syaratnya dua: salinannya sudah kembali
-- menyentuh tanah (dijamin fase IMPACT, 3,2 detik sesudah mendarat), dan
-- titik mendaratnya dihitung SATU tempat saja -- server, lewat `tujuan`,
-- yang dipakai bersama oleh bantingan salinan di sini dan pemindahan
-- avatar aslinya di sana.
--
-- Salinannya diparent ke folder, bukan langsung ke workspace: kalau
-- langsung, ChildAdded di bawah menangkapnya sebagai avatar baru, dan
-- penyamaan tarian ikut menghitungnya sebagai anggota kerumunan.
local NOVA_FOLDER       = "NovaSalinan"

-- Berapa lama avatar bertanda TierNova boleh ditahan tanpa pesan "nova"
-- datang. Jaring pengaman, bukan setelan: pesannya hampir selalu tiba di
-- frame yang sama dengan modelnya. Yang ditangkap angka ini kasus pesan
-- yang hilang -- tanpa dia, avatarnya tersembunyi selamanya.
local NOVA_TAHAN_MAKS_S = 4

-- Berapa lama pesan nova boleh menunggu modelnya datang lewat
-- ChildAdded. Lihat novaCariModel.
local NOVA_TUNGGU_MODEL_S = 2

-- Model bertanda TierNova yang sedang ditahan, dicari lewat nomor
-- adegannya (NovaId). Nilainya lemah: model yang dihapus panggung tidak
-- ditahan hidup oleh tabel ini.
local novaModel = setmetatable({}, { __mode = "v" })

local tierNovaModul = nil
local tierNovaGagal = false

local function muatTierNova()
	if tierNovaModul or tierNovaGagal then return tierNovaModul end

	local skrip = ReplicatedStorage:WaitForChild("TierNova", 5)
	if not skrip then
		tierNovaGagal = true
		warn("[nova] ModuleScript 'TierNova' tidak ada di ReplicatedStorage " ..
			"-- nova (Bouquet Flower) muncul tanpa efek. Buat ModuleScript bernama TierNova " ..
			"di sana (atau `make rojo` lalu Connect).")
		return nil
	end

	local ok, modul = pcall(require, skrip)
	if not ok then
		tierNovaGagal = true
		warn("[nova] TierNova gagal di-require -- nova muncul tanpa efek:",
			modul)
		return nil
	end

	tierNovaModul = modul
	return modul
end

local novaTahan = setmetatable({}, { __mode = "k" })

-- Sembunyikan avatar asli sampai adegannya selesai. Mengembalikan catatan
-- yang punya `buka()`. Dipanggil dua kali untuk model yang sama (dari
-- ChildAdded DAN dari pesan nova) aman: yang kedua mendapat catatan yang
-- sama.
local function tahanUntukNova(m)
	if novaTahan[m] then return novaTahan[m] end

	local rec = { dimatikan = {}, dibuka = false, mulai = false }

	local function sembunyi(d)
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
		elseif KELAS_MATIKAN[d.ClassName] and d.Enabled then
			d.Enabled = false
			rec.dimatikan[d] = true
		end
	end

	for _, d in ipairs(m:GetDescendants()) do sembunyi(d) end
	rec.sambung = m.DescendantAdded:Connect(function(d)
		if not rec.dibuka then sembunyi(d) end
	end)

	function rec.buka()
		if rec.dibuka then return end
		rec.dibuka = true
		rec.sambung:Disconnect()
		novaTahan[m] = nil
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0
			elseif rec.dimatikan[d] then
				d.Enabled = true
			end
		end
	end

	novaTahan[m] = rec
	task.delay(NOVA_TAHAN_MAKS_S, function()
		if not rec.mulai then rec.buka() end
	end)
	return rec
end

-- Model untuk sebuah pesan "nova".
--
-- Jalur normalnya d.model, dan itu yang hampir selalu terjadi. Yang
-- ditangani di sini satu kegagalan yang tidak memunculkan satu pun
-- error: argumen Instance di dalam pesan remote sampai sebagai NIL
-- kalau modelnya belum selesai direplikasi ke client ini. Yang terlihat
-- waktu itu terjadi: kamera menjalankan adegannya di atas panggung
-- kosong -- pesan `fokus` tidak membawa Instance apa pun, jadi dia
-- tetap sampai utuh, sementara avatarnya tinggal tersembunyi sampai
-- NOVA_TAHAN_MAKS_S dan baru muncul sesudah semuanya lewat.
--
-- NovaId dipasang server SEBELUM modelnya masuk workspace, jadi atribut
-- itu ikut di dalam replikasi modelnya sendiri dan tidak bisa datang
-- terpisah darinya. Menunggu nomornya = menunggu modelnya.
local function novaCariModel(d)
	if d.model and d.model.Parent then return d.model end

	local id = d.novaId
	if not id then return nil end

	local t0 = os.clock()
	repeat
		local m = novaModel[id]
		if m and m.Parent then
			warn(("[nova] model adegan %d telat %.2f detik -- ditemukan " ..
				"lewat NovaId, adegannya tetap jalan")
				:format(id, os.clock() - t0))
			return m
		end
		RunService.Heartbeat:Wait()
	until os.clock() - t0 > NOVA_TUNGGU_MODEL_S

	warn(("[nova] model adegan %d tidak pernah sampai ke client ini -- " ..
		"kameranya bergerak tapi tidak ada yang melayang"):format(id))
	return nil
end

-- --- LAYAR SINEMATIK SELAMA SOROTAN (Rosa) ---
--
-- Versi ringan dari layar nova: letterbox, dan sesuai pilihannya warna
-- yang lebih hangat serta sekejap abu-abu + buram. Pilihannya dikirim
-- server lewat pesan `fokus` (LAYAR di AvatarQueueV2); di sini cuma
-- dijalankan.
--
-- Nama benda-bendanya SENDIRI (awalan "Rosa"), bukan milik nova: kalau
-- keduanya pernah bertemu, satu tidak boleh menghapus milik yang lain.
--
-- Satu adegan layar pada satu waktu. Yang baru membersihkan yang lama
-- SEKETIKA -- dua letterbox bertumpuk jadi bilah setebal dua kali.
local layarGen = 0
local layarBenda = {}

local function layarBersihkan()
	for _, b in ipairs(layarBenda) do
		pcall(function() b:Destroy() end)
	end
	layarBenda = {}
end

local function layarSinema(opsi, lama, model, kilatDi, warnaLayar)
	if type(opsi) ~= "table" then return end
	lama = tonumber(lama) or 0
	if lama <= 0 then return end

	layarGen += 1
	local gen = layarGen
	layarBersihkan()

	local masuk  = math.max(tonumber(opsi.masuk) or 0.5, 0.05)
	local keluar = math.max(tonumber(opsi.keluar) or 0.5, 0.05)
	local tebal  = math.clamp(tonumber(opsi.letterbox) or 0, 0, 0.3)
	-- Kapan mulai keluar. Dijepit supaya adegan yang lebih pendek dari
	-- masuk + keluar tetap sempat keluar sebelum sorotannya habis.
	local mulaiKeluar = math.max(lama - keluar, masuk)

	local function tw(obj, detik, props)
		local t = TweenService:Create(obj, TweenInfo.new(detik,
			Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
		t:Play()
		return t
	end

	-- --- letterbox ---
	local induk = pemain and pemain:FindFirstChildOfClass("PlayerGui")
	local bilah = {}
	if tebal > 0 and induk then
		local gui = Instance.new("ScreenGui")
		gui.Name = "RosaLetterbox"
		gui.IgnoreGuiInset, gui.ResetOnSpawn = true, false
		-- Di bawah letterbox nova (50): kalau keduanya sempat bertemu,
		-- yang lebih besar tetap di depan.
		gui.DisplayOrder = 49
		for i, jangkar in ipairs({ 0, 1 }) do
			local f = Instance.new("Frame")
			f.BackgroundColor3, f.BorderSizePixel = Color3.new(0, 0, 0), 0
			f.AnchorPoint = Vector2.new(0, jangkar)
			f.Position = UDim2.fromScale(0, jangkar)
			f.Size = UDim2.fromScale(1, 0)
			f.Parent = gui
			bilah[i] = f
		end
		gui.Parent = induk
		table.insert(layarBenda, gui)
		for _, b in ipairs(bilah) do
			tw(b, masuk, { Size = UDim2.fromScale(1, tebal) })
		end
	end

	-- --- warna ---
	local cc, bloom
	if opsi.warna then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "RosaColorCorrection"
		cc.Parent = Lighting
		bloom = Instance.new("BloomEffect")
		bloom.Name = "RosaBloom"
		bloom.Intensity, bloom.Size, bloom.Threshold = 0, 24, 0.95
		bloom.Parent = Lighting
		table.insert(layarBenda, cc)
		table.insert(layarBenda, bloom)
		-- Warna tema Rosa kalau server mengirimnya (ROSA.TEMA), kalau
		-- tidak hangat seperti sebelumnya.
		local tint = Color3.fromRGB(255, 238, 220)
		if type(warnaLayar) == "table" and warnaLayar[1] then
			tint = Color3.fromRGB(warnaLayar[1], warnaLayar[2], warnaLayar[3])
		end
		tw(cc, masuk, { TintColor = tint, Contrast = 0.1, Saturation = 0.2 })
		tw(bloom, masuk, { Intensity = 0.5 })
	end

	-- --- sekejap abu-abu + buram di tengah ---
	if opsi.beku then
		local blur = Instance.new("BlurEffect")
		blur.Name = "RosaBlur"
		blur.Size = 0
		blur.Parent = Lighting
		table.insert(layarBenda, blur)
		local cBeku = cc
		if not cBeku then
			cBeku = Instance.new("ColorCorrectionEffect")
			cBeku.Name = "RosaColorCorrection"
			cBeku.Parent = Lighting
			table.insert(layarBenda, cBeku)
		end
		-- Mulai di sepertiga sorotan, sesudah kamera berhenti merapat:
		-- abu-abu di detik kedatangan menutupi wajah orangnya persis
		-- di detik yang paling perlu terlihat.
		local mulai = lama * 0.33
		task.delay(mulai, function()
			if gen ~= layarGen then return end
			tw(cBeku, 0.3, { Saturation = -1, Contrast = 0.3 })
			tw(blur, 0.3, { Size = 6 })
			task.delay(0.9, function()
				if gen ~= layarGen then return end
				tw(cBeku, 0.4, { Saturation = opsi.warna and 0.2 or 0,
					Contrast = opsi.warna and 0.1 or 0 })
				tw(blur, 0.4, { Size = 0 })
			end)
		end)
	end

	-- --- kilatan saat angka auranya mendarat ---
	--
	-- Bloom dan terang disentak naik lalu dilepas pelan, di detik yang
	-- sama dengan hentakan mendarat. Tanpa bloom `warna`, dibuat sendiri.
	kilatDi = tonumber(kilatDi)
	if opsi.kilat and kilatDi and kilatDi > 0 and kilatDi < lama then
		local bKilat = bloom
		if not bKilat then
			bKilat = Instance.new("BloomEffect")
			bKilat.Name = "RosaBloom"
			bKilat.Intensity, bKilat.Size, bKilat.Threshold = 0, 24, 0.95
			bKilat.Parent = Lighting
			table.insert(layarBenda, bKilat)
		end
		local cKilat = cc
		if not cKilat then
			cKilat = Instance.new("ColorCorrectionEffect")
			cKilat.Name = "RosaColorCorrection"
			cKilat.Parent = Lighting
			table.insert(layarBenda, cKilat)
		end
		task.delay(kilatDi, function()
			if gen ~= layarGen then return end
			local dasarB = opsi.warna and 0.5 or 0
			tw(bKilat, 0.08, { Intensity = 1.6 })
			tw(cKilat, 0.08, { Brightness = 0.18 })
			task.delay(0.1, function()
				if gen ~= layarGen then return end
				tw(bKilat, 0.7, { Intensity = dasarB })
				tw(cKilat, 0.7, { Brightness = 0 })
			end)
		end)
	end

	-- --- garis tepi yang berdenyut ---
	--
	-- Highlight milik server (BorderTier), diubah LOKAL: tidak ada yang
	-- terkirim balik, dan server tidak menulis transparansinya selama
	-- sorotan. Nilai aslinya dicatat dulu dan dikembalikan di akhir --
	-- tanpa itu garisnya tertinggal di fase denyut terakhirnya.
	--
	-- Highlight tidak bisa di-tween, jadi ditulis per frame.
	if opsi.garis and model then
		local h = model:FindFirstChild("BorderTier")
		if h and h:IsA("Highlight") then
			local asliGaris, asliIsi = h.OutlineTransparency, h.FillTransparency
			task.spawn(function()
				local t0 = os.clock()
				while gen == layarGen and h.Parent do
					local e = os.clock() - t0
					if e >= mulaiKeluar then break end
					-- 0..1..0 sekitar 1,2 kali per detik.
					local u = (1 - math.cos(e * math.pi * 2.4)) / 2
					h.OutlineTransparency = asliGaris + (0.6 - asliGaris) * u
					h.FillTransparency = asliIsi - (asliIsi - 0.7) * (1 - u)
					RunService.RenderStepped:Wait()
				end
				if h.Parent then
					h.OutlineTransparency = asliGaris
					h.FillTransparency = asliIsi
				end
			end)
		end
	end

	-- --- keluar, lalu bersih ---
	task.delay(mulaiKeluar, function()
		if gen ~= layarGen then return end
		for _, b in ipairs(bilah) do
			if b.Parent then tw(b, keluar, { Size = UDim2.fromScale(1, 0) }) end
		end
		if cc and cc.Parent then
			tw(cc, keluar, { TintColor = Color3.new(1, 1, 1),
				Contrast = 0, Saturation = 0 })
		end
		if bloom and bloom.Parent then tw(bloom, keluar, { Intensity = 0 }) end
		task.delay(keluar + 0.05, function()
			-- Dicek lagi: adegan berikutnya bisa sudah mulai dan
			-- memasang benda-bendanya sendiri di daftar yang sama.
			if gen == layarGen then layarBersihkan() end
		end)
	end)
end

-- --- PANGGUNG ROSA: latar sinematik + tetangga disembunyikan ---
--
-- Memasang jalur kameranya (rosaKam), lalu selama adegannya:
--   - panggung diredupkan (ExposureCompensation), orangnya disiram lampu
--     sorot dari atas dan cahaya dari belakang
--   - partikel cahaya melayang di sekitarnya
--   - avatar tetangga dan cakramnya dalam radius `sepi` disembunyikan
--
-- SEMUANYA LOKAL: LocalTransparencyModifier, Enabled, dan Lighting yang
-- ditulis client tidak terkirim ke server atau ke penonton lain.
--
-- Tetangga yang datang SELAGI adegannya jalan ikut disembunyikan: slot
-- berikutnya persis di sebelahnya, dan kamera keliling lewat di sana.
--
-- Transparansinya DITULIS TIAP FRAME selama adegan, bukan sekali. Gerbang
-- "muncul utuh" (siapkanAvatar) juga menulis properti yang sama untuk
-- kedatangan baru, dan tanpa penulisan tiap frame gerbang itu yang menang
-- -- tetangga yang baru datang muncul di tengah putaran kamera.
local panggungGen = 0

-- Terang panggung SEBELUM panggung Rosa mana pun meredupkannya. Dibaca
-- sekali dan dipakai semua panggung yang menumpuk: kalau tiap panggung
-- membaca Lighting sendiri, yang kedua membaca angka yang SUDAH
-- diredupkan yang pertama -- dan itu yang dia kembalikan di akhir,
-- jadi panggungnya tertinggal gelap sampai server di-restart.
local exposDasar = nil

local function panggungRosa(d)
	local model = d.model
	local J = d.jalur
	if type(J) ~= "table" or not model or not model.Parent then return end
	local lama = tonumber(d.lama) or 0
	if lama <= 0 then return end

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then return end

	panggungGen += 1
	local gen = panggungGen

	-- Titik lantai dan tinggi badannya, dicatat SEKALI di awal: dia
	-- sedang menari, dan kamera yang mengikuti goyangan tiap frame
	-- terbaca sebagai kamera yang gemetar.
	local hum = model:FindFirstChildOfClass("Humanoid")
	local kaki = 3
	if hum then
		local okH, h = pcall(function() return hum.HipHeight + root.Size.Y / 2 end)
		if okH and h and h > 0 then kaki = h end
	end
	local p = root.Position
	local tanah = Vector3.new(p.X, p.Y - kaki, p.Z)
	local tinggi = 5.5
	local kepala = model:FindFirstChild("Head")
	if kepala and kepala:IsA("BasePart") then
		tinggi = math.max(kepala.Position.Y + kepala.Size.Y / 2 - tanah.Y, 2)
	end

	rosaKam = { j = J, mulai = os.clock(), tanah = tanah, tinggi = tinggi }

	local naik   = tonumber(J.naik) or 2.6
	local orbit  = tonumber(J.orbit) or 3.4
	local potret = tonumber(J.potret) or 2.6
	local lepas  = math.max(tonumber(J.lepas) or 1.4, 0.05)
	local mulaiLepas = naik + orbit + potret
	local total = mulaiLepas + lepas

	local tema = type(d.tema) == "table" and d.tema or {}
	local function warna(tr, cadangan)
		if type(tr) == "table" and tr[1] then
			return Color3.fromRGB(tr[1], tr[2], tr[3])
		end
		return cadangan
	end

	local function tw(obj, detik, props)
		local t = TweenService:Create(obj, TweenInfo.new(detik,
			Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props)
		t:Play()
		return t
	end

	local benda = {}
	local function bagianTakKasatMata(cf)
		local b = Instance.new("Part")
		b.Anchored, b.CanCollide, b.CanQuery, b.CanTouch = true, false, false, false
		b.Transparency, b.CastShadow = 1, false
		b.Size = Vector3.one
		b.CFrame = cf
		b.Name = "RosaPanggung"
		b.Parent = workspace
		table.insert(benda, b)
		return b
	end

	-- --- lampu sorot dari atas ---
	local atasPart = bagianTakKasatMata(CFrame.new(tanah + Vector3.new(0, tinggi + 9, 0)))
	local sorot = Instance.new("SpotLight")
	sorot.Face, sorot.Angle, sorot.Range = Enum.NormalId.Bottom, 40, 26
	sorot.Brightness, sorot.Shadows = 0, true
	sorot.Color = warna(tema.sorot, Color3.fromRGB(255, 225, 180))
	sorot.Parent = atasPart
	tw(sorot, 0.6, { Brightness = 6 })

	-- --- cahaya dari belakang: memisahkan siluetnya dari latar gelap ---
	local belakangPart = bagianTakKasatMata(CFrame.new(
		tanah + Vector3.new(0, tinggi * 0.6, 3)))
	local belakang = Instance.new("PointLight")
	belakang.Range, belakang.Brightness = 11, 0
	belakang.Color = warna(tema.belakang, Color3.fromRGB(120, 170, 255))
	belakang.Parent = belakangPart
	tw(belakang, 0.6, { Brightness = 2.5 })

	-- --- partikel cahaya yang melayang ---
	local partikelPart = bagianTakKasatMata(CFrame.new(
		tanah + Vector3.new(0, tinggi * 0.5, 0)))
	partikelPart.Size = Vector3.new(7, tinggi, 7)
	local debu = Instance.new("ParticleEmitter")
	debu.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	debu.Color = ColorSequence.new(warna(tema.partikel, Color3.new(1, 1, 1)))
	debu.LightEmission = 1
	debu.Rate = 14
	debu.Lifetime = NumberRange.new(2, 3.2)
	debu.Speed = NumberRange.new(0.3, 1.2)
	debu.SpreadAngle = Vector2.new(180, 180)
	debu.Acceleration = Vector3.new(0, 0.6, 0)
	debu.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.28),
		NumberSequenceKeypoint.new(1, 0),
	})
	debu.Transparency = NumberSequence.new(0.2, 1)
	debu.Parent = partikelPart

	-- --- panggung diredupkan ---
	if exposDasar == nil then exposDasar = Lighting.ExposureCompensation end
	local exposAsli = exposDasar
	tw(Lighting, 0.6, { ExposureCompensation = exposAsli - (tonumber(J.redup) or 0.7) })

	-- --- tetangga disembunyikan ---
	local radius = tonumber(J.sepi) or 14
	local datar = Vector3.new(tanah.X, 0, tanah.Z)
	local dilacak = {}   -- BasePart -> true
	local dimatikan = {} -- benda ber-Enabled yang KITA matikan -> true
	local modelDilacak = {} -- Model tetangga -> true

	local function dekat(pos)
		return (Vector3.new(pos.X, 0, pos.Z) - datar).Magnitude <= radius
	end

	-- Dipanggil ulang tiap SAPU_ULANG_S, bukan cuma sekali di awal.
	-- Tetangga yang BARU datang di tengah adegan belum lengkap waktu
	-- pertama dilacak: server memasang papan nama, border, dan aura VFX
	-- sesudah modelnya masuk workspace, dan siapkanAvatar menyalakan
	-- kembali semua yang dia matikan begitu asetnya siap. Tanpa sapuan
	-- ulang, yang terlihat selama sorotan Rosa justru papan nama dan
	-- partikel mengambang tanpa badan di sebelahnya.
	local function sapuModel(m)
		for _, x in ipairs(m:GetDescendants()) do
			if x:IsA("BasePart") then
				dilacak[x] = true
			elseif KELAS_MATIKAN[x.ClassName] and x.Enabled then
				x.Enabled = false
				dimatikan[x] = true
			end
		end
	end

	local function lacak(m)
		if gen ~= panggungGen then return end
		if m:IsA("BasePart") and m.Name == "CakramTier" then
			-- Cakram MILIKNYA sendiri tetap menyala.
			if dekat(m.Position)
				and (Vector3.new(m.Position.X, 0, m.Position.Z) - datar).Magnitude > 1 then
				dilacak[m] = true
				for _, x in ipairs(m:GetDescendants()) do
					if x:IsA("Light") and x.Enabled then
						x.Enabled = false
						dimatikan[x] = true
					end
				end
			end
			return
		end
		if m == model or not m:IsA("Model") then return end
		if Players:GetPlayerFromCharacter(m) then return end
		-- Avatar asli nova sedang ditahan tahanUntukNova. Kalau ikut
		-- dilacak, tutup() di bawah memunculkannya di tengah adegannya.
		if novaTahan[m] then return end
		if not m:FindFirstChildOfClass("Humanoid") then return end
		local okP, pv = pcall(function() return m:GetPivot().Position end)
		if not okP or not dekat(pv) then return end
		modelDilacak[m] = true
		sapuModel(m)
	end

	for _, m in ipairs(workspace:GetChildren()) do lacak(m) end
	-- Ditunda satu langkah: bagian-bagian model yang baru datang belum
	-- tentu sudah lengkap di frame ChildAdded.
	local sambungBaru = workspace.ChildAdded:Connect(function(m)
		task.defer(lacak, m)
	end)

	local selesai = false
	local function tutup()
		if selesai then return end
		selesai = true
		sambungBaru:Disconnect()
		for part in pairs(dilacak) do
			if part.Parent then part.LocalTransparencyModifier = 0 end
		end
		for x in pairs(dimatikan) do
			if x.Parent then x.Enabled = true end
		end
		Lighting.ExposureCompensation = exposAsli
		if gen == panggungGen then exposDasar = nil end
		for _, b in ipairs(benda) do pcall(function() b:Destroy() end) end
	end

	local t0 = os.clock()
	local lepasMulai = false
	local SAPU_ULANG_S = 0.25
	local sapuBerikut = SAPU_ULANG_S
	local kon
	kon = RunService.RenderStepped:Connect(function()
		-- Panggung Rosa berikutnya sudah mulai: yang ini pergi SEKARANG,
		-- termasuk mengembalikan terang panggung -- kalau tidak, dua
		-- peredupan bertumpuk dan panggungnya tertinggal gelap.
		if gen ~= panggungGen then
			kon:Disconnect()
			tutup()
			return
		end
		local e = os.clock() - t0

		-- Berhenti begitu tetangganya mulai dimunculkan kembali.
		if e >= sapuBerikut and e < mulaiLepas then
			sapuBerikut = e + SAPU_ULANG_S
			for m in pairs(modelDilacak) do
				if m.Parent and not novaTahan[m] then sapuModel(m) end
			end
		end

		local a
		if e < 0.5 then
			a = e / 0.5
		elseif e < mulaiLepas then
			a = 1
		else
			a = 1 - math.clamp((e - mulaiLepas) / lepas, 0, 1)
		end
		for part in pairs(dilacak) do
			if part.Parent then part.LocalTransparencyModifier = a end
		end

		if not lepasMulai and e >= mulaiLepas then
			lepasMulai = true
			tw(sorot, lepas, { Brightness = 0 })
			tw(belakang, lepas, { Brightness = 0 })
			debu.Rate = 0
			tw(Lighting, lepas, { ExposureCompensation = exposAsli })
		end

		if e >= total then
			kon:Disconnect()
			tutup()
		end
	end)

	print(("[rosa] panggung %s -- tema %s, %d bagian tetangga disembunyikan")
		:format(model.Name, tostring(tema.nama or "?"), (function()
			local n = 0
			for _ in pairs(dilacak) do n += 1 end
			return n
		end)()))
end

-- Tiap jalan keluar dari jalankanNova yang membuat avatarnya berdiri
-- TANPA adegan dicatat lewat sini.
--
-- Dulu empat dari jalan itu diam total, dan keempatnya menghasilkan gejala
-- yang sama persis di layar: avatarnya muncul, efeknya tidak ada, Output
-- bersih. "Kadang nova tidak muncul" tanpa satu baris pun untuk dibaca
-- tidak bisa dibedakan antara bug, modul yang belum ditempel, dan
-- koneksi. Sekarang tiap jalan menyebut alasannya sendiri.
local function novaGagal(asli, alasan)
	warn(("[nova] %s muncul TANPA efek -- %s")
		:format(asli and asli.Name or "?", alasan))
end

local function jalankanNova(d)
	if not d then return end
	local asli = novaCariModel(d)
	if not asli then return end   -- novaCariModel sudah mencetak alasannya
	if not asli.Parent then
		novaGagal(asli, "avatarnya sudah tidak ada di workspace client ini " ..
			"waktu pesan novanya tiba")
		return
	end

	local rec = tahanUntukNova(asli)
	rec.mulai = true

	local modul = muatTierNova()
	if not modul then
		-- muatTierNova cuma mencetak alasannya SEKALI (hasilnya di-cache),
		-- jadi tanpa baris ini nova kedua dan seterusnya diam.
		novaGagal(asli, "ModuleScript TierNova tidak termuat (lihat pesan " ..
			"[nova] pertama di Output)")
		rec.buka()
		return
	end

	-- Tunggu asetnya, dengan batas yang sama dengan siapkanAvatar. Salinan
	-- yang dibuat sebelum rambut dan bajunya siap melayang POLOS selama
	-- sepuluh detik, dan itu tepat sepuluh detik yang paling ditonton.
	local maks = math.max(tonumber(CFG.spawnSiapMaks) or 0.6, 0)
	if bolehBerat and maks > 0 then
		local siap = false
		task.spawn(function()
			pcall(function() ContentProvider:PreloadAsync({ asli }) end)
			siap = true
		end)
		local t0 = os.clock()
		while not siap and os.clock() - t0 < maks do
			RunService.Heartbeat:Wait()
		end
	end
	if not asli.Parent then
		novaGagal(asli, "avatarnya dicabut dari workspace client selagi " ..
			"asetnya ditunggu (StreamingEnabled menyala?)")
		rec.buka()
		return
	end

	local folder = workspace:FindFirstChild(NOVA_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = NOVA_FOLDER
		folder.Parent = workspace
	end

	local arsip = asli.Archivable
	asli.Archivable = true
	local ok, salinan = pcall(function() return asli:Clone() end)
	asli.Archivable = arsip
	if not ok or not salinan then
		novaGagal(asli, "salinan avatarnya gagal dibuat: " ..
			tostring(ok and "Clone() mengembalikan nil" or salinan))
		rec.buka()
		return
	end

	-- Salinan tanpa root part tidak bisa melayang sama sekali, dan TierNova
	-- akan berhenti di frame pertamanya. Paling sering terjadi kalau
	-- avatarnya baru terkirim SEBAGIAN ke client ini -- StreamingEnabled
	-- mengirim model sepotong-sepotong kecuali modelnya Persistent.
	if not salinan:FindFirstChild("HumanoidRootPart") then
		novaGagal(asli, ("avatarnya baru sebagian sampai di client ini " ..
			"(%d part, tanpa HumanoidRootPart) -- StreamingEnabled menyala?")
			:format(#salinan:GetDescendants()))
		salinan:Destroy()
		rec.buka()
		return
	end

	-- Pengunci posisi server (BodyPosition/BodyGyro) HARUS dibuang: dia
	-- ikut tersalin dan akan menarik salinannya balik ke lantai di setiap
	-- frame dia melayang. Papan, border, dan efek juga -- salinan ini cuma
	-- badan, dan outline putihnya dipasang TierNova sendiri.
	for _, x in ipairs(salinan:GetDescendants()) do
		if x:IsA("BodyMover") or x:IsA("LuaSourceContainer")
			or KELAS_MATIKAN[x.ClassName] then
			x:Destroy()
		elseif x:IsA("BasePart") then
			x.LocalTransparencyModifier = 0
			x.CanCollide = false
			x.CanQuery   = false
			x.CanTouch   = false
		end
	end
	salinan.Name = asli.Name .. "_nova"

	-- Ditaruh persis di tempat avatar aslinya berdiri, sebelum dia masuk
	-- folder: satu frame di titik lain berarti satu frame avatarnya
	-- meloncat.
	pcall(function() salinan:PivotTo(asli:GetPivot()) end)
	salinan.Parent = folder

	local kam = workspace.CurrentCamera
	local lepasFov = kam and novaAmbilFov(kam) or nil

	local config = {}
	if type(d.config) == "table" then
		for k, v in pairs(d.config) do config[k] = v end
	end
	config.seed  = d.seed
	config.palet = d.palet
	-- Bunyi per fase (NOVA.SFX). Diteruskan apa adanya: modulnya yang
	-- memainkannya, karena cuma dia yang tahu kapan tiap fase benar-benar
	-- mulai -- bunyi yang dijadwalkan dari sini meleset sebanyak tunggu
	-- aset avatarnya.
	config.sfx   = d.sfx
	-- Di mana dia membanting diri. Server yang menghitungnya (slot 1,
	-- yang dikosongkan gempa di detik yang sama) supaya bantingan
	-- salinan di sini dan pemindahan avatar aslinya di server jatuh di
	-- satu titik yang sama persis.
	config.tujuan = d.tujuan
	-- Letterbox butuh tempat menggantung. Diambil di sini, bukan di dalam
	-- modul: modul itu tidak tahu (dan tidak boleh tahu) siapa pemain
	-- lokalnya.
	config.induk = pemain and pemain:FindFirstChildOfClass("PlayerGui")

	-- Ketiga callback kamera. Lihat catatan panjang di atas novaFov soal
	-- kenapa kamera tidak diserahkan begitu saja ke modulnya.
	config.fov   = novaFov
	config.getar = novaGetar
	config.pandang = function(pos)
		-- Disimpan, bukan dipakai langsung: yang membidik keempat
		-- bidikan di kameraNova, dan mereka butuh tahu badannya di mana
		-- SEKARANG -- bukan diseret pelan-pelan seperti fokusTarget.
		--
		-- fokusTarget sengaja TIDAK disentuh sama sekali. Dia masih
		-- berisi titik slot yang dikirim server, dan di situlah kamera
		-- biasa sudah menunggu waktu jalur nova melepaskannya -- jadi
		-- pergantiannya jatuh ke sorotan tarian yang sudah benar.
		if novaKam then novaKam.badan = pos end
	end

	-- Jalur kamera adegannya. Dipasang SEBELUM Play supaya frame
	-- pertamanya sudah dikemudikan jalur ini -- kalau sesudah,
	-- kedip pertama masih memakai kamera sorotan biasa.
	--
	-- Titik berdirinya diturunkan ke LANTAI: seluruh angka di
	-- NOVA.KAMERA diukur dari lantai (naikBawah 2 = dua stud di atas
	-- tanah), dan pivot avatar ada sekitar tiga stud di atasnya.
	if kam and type(d.kamera) == "table" then
		local pivot = salinan:GetPivot().Position
		local kaki  = 3
		local hum   = salinan:FindFirstChildOfClass("Humanoid")
		local root  = salinan:FindFirstChild("HumanoidRootPart")
		if hum and root then
			local okH, h = pcall(function()
				return hum.HipHeight + root.Size.Y / 2
			end)
			if okH and h and h > 0 then kaki = h end
		end

		local tujuanPos = typeof(d.tujuan) == "CFrame" and d.tujuan.Position
			or (typeof(d.tujuan) == "Vector3" and d.tujuan or nil)

		novaKam = {
			k     = d.kamera,
			j     = modul.Jadwal and modul.Jadwal(config) or nil,
			mulai = os.clock(),
			tanah = Vector3.new(pivot.X, pivot.Y - kaki, pivot.Z),
			-- nil kalau dia mendarat di tempat dia mulai: kameraNova
			-- melewati seluruh perhitungan gesernya kalau begitu.
			tanahAkhir = tujuanPos
				and Vector3.new(tujuanPos.X, tujuanPos.Y - kaki, tujuanPos.Z)
				or nil,
			badan = pivot,
		}
		-- Modul versi lama tidak punya Jadwal: tanpa jadwalnya tidak ada
		-- fase yang bisa dibedakan, jadi adegannya jalan tanpa jalur
		-- kamera alih-alih dengan jalur yang salah.
		if not novaKam.j then
			novaKam = nil
			warn("[nova] ModuleScript TierNova versi lama (tidak ada " ..
				"Jadwal) -- sinkron ulang lewat Rojo. Adegannya " ..
				"jalan tanpa jalur kamera.")
		end
	end

	local janji = modul.Play(salinan, config)
	print(("[nova] %s mulai (seed %s, palet %s)")
		:format(asli.Name, tostring(d.seed),
			type(d.palet) == "table" and tostring(d.palet.nama) or "?"))

	-- Adegan yang BATAL melepas jalur kameranya SEKARANG.
	--
	-- Jalur kamera dipasang sebelum Play dan punya jadwal sepuluh detiknya
	-- sendiri. Dulu dia jalan terus walaupun adegannya berhenti di detik
	-- pertama -- yang terlihat persis "kameranya bergerak, VFX dan SFX-nya
	-- tidak ada": kamera mengorbit, naik, dan menukik di atas panggung yang
	-- tidak berisi apa pun.
	--
	-- Dicek ke `jalurIni`, bukan asal dikosongkan: kalau nova berikutnya
	-- sudah memasang jalurnya sendiri, yang itu tidak boleh ikut hilang.
	local jalurIni = novaKam
	local function lepasJalur(berhasil)
		if not berhasil and novaKam and novaKam == jalurIni then
			novaKam = nil
		end
	end
	janji.Completed:Connect(lepasJalur)
	-- Play menjalankan adegannya lewat task.spawn, yang jalan SEKETIKA sampai
	-- yield pertama. Error sebelum yield itu menyalakan Completed di dalam
	-- Play sendiri -- sebelum baris Connect di atas sempat ada.
	if janji.Done then lepasJalur(janji.Success) end

	-- Bunyi kedatangannya saat dia MEMBANTING DIRI ke tanah, bukan
	-- sekarang: sekarang dia baru mulai mengumpulkan tenaga, dan bunyi
	-- jatuh di detik itu tidak menjelaskan apa pun.
	local tierNova = tonumber(d.tier)
	if tierNova then
		local jadwal = modul.Jadwal and modul.Jadwal(config) or nil
		local tunda  = jadwal and jadwal.slam or 0
		task.delay(tunda, function()
			if not janji.Done then bunyiTier(tierNova) end
		end)
	end

	-- Panggung di-reset di tengah adegan: yang asli dihapus server, jadi
	-- salinan dan seluruh VFX-nya harus ikut pergi SEKARANG, bukan
	-- meledak di atas slot yang sudah kosong.
	local dicabut = false
	local putus = asli.AncestryChanged:Connect(function()
		if not asli:IsDescendantOf(workspace) then
			dicabut = true
			janji:Cancel()
		end
	end)

	local berhasil = janji:Await()
	putus:Disconnect()
	-- Batal di tengah jalan. Error di dalam modulnya sudah dicetak sendiri
	-- ([TierNova] berhenti: ...), jadi yang dicatat di sini cuma pembatalan
	-- yang tidak membawa alasan apa pun.
	if not berhasil and dicabut then
		novaGagal(asli, "avatar aslinya dicabut dari workspace client di " ..
			"tengah adegan (dihapus server, atau StreamingEnabled)")
	elseif not berhasil then
		novaGagal(asli, "adegannya berhenti di tengah jalan -- alasannya di " ..
			"baris [TierNova] berhenti tepat di atas ini")
	else
		print(("[nova] %s selesai"):format(asli.Name))
	end
	if lepasFov then lepasFov() end
	novaGetar(0, 0)
	-- Jalur kameranya sengaja TIDAK dilepas di sini. Dia punya fase
	-- lepasnya sendiri (NOVA.KAMERA.lepas) yang meluncur balik ke kamera
	-- sorotan biasa, dan gelung render yang mengosongkan novaKam begitu
	-- fase itu habis. Memotongnya sekarang berarti satu frame yang
	-- meloncat -- tepat di frame avatar aslinya muncul kembali.
	salinan:Destroy()
	rec.buka()
end

-- --- PRA-MUAT AVATAR ---
--
-- Server menaruh tiap avatar di ReplicatedStorage.AvatarPramuat selama
-- SPAWN_PRAMUAT_S sebelum memindahkannya ke panggung. Di sini asetnya
-- mulai diunduh selagi dia masih tersembunyi, jadi waktu dia masuk
-- panggung, siapkanAvatar mendapati semuanya sudah siap -- tanpa kaki
-- yang bolong dan tanpa rambut yang menyusul belakangan.
--
-- WaitForChild tanpa batas di task sendiri: server versi lama tidak
-- membuat foldernya, dan menunggu selamanya di task terpisah tidak
-- menahan apa pun.
--
-- Begitu unduhannya selesai, server diberi tahu lewat AvatarPramuatSiap:
-- dia menahan avatarnya sampai semua pemain melapor (paling lama
-- SPAWN_PRAMUAT_S), jadi yang koneksinya bagus tidak menunggu sia-sia
-- dan yang lambat tidak disodori avatar bolong. Dilapor juga kalau
-- PreloadAsync gagal -- aset yang rusak tidak akan siap berapa lama pun
-- ditunggu.
task.spawn(function()
	local folder = ReplicatedStorage:WaitForChild("AvatarPramuat")
	local siap   = ReplicatedStorage:WaitForChild("AvatarPramuatSiap")
	local function pramuat(m)
		task.spawn(function()
			pcall(function() ContentProvider:PreloadAsync({ m }) end)
			if m.Parent == folder then siap:FireServer(m) end
		end)
	end
	for _, m in ipairs(folder:GetChildren()) do pramuat(m) end
	folder.ChildAdded:Connect(pramuat)
end)

workspace.ChildAdded:Connect(function(anak)
	if anak:IsA("BasePart") and anak.Name == "CakramTier" then
		siapkanCakram(anak)
		return
	end
	if not anak:IsA("Model") then return end

	-- Karakter PENONTON punya Humanoid juga, dan menyembunyikannya
	-- berarti dia memandang dirinya sendiri lenyap setengah detik tiap
	-- kali respawn.
	--
	-- Dua penjaga, bukan satu: GetPlayerFromCharacter belum tentu sudah
	-- tersambung tepat di frame ChildAdded, dan karakter pemain selalu
	-- bernama sama dengan pemainnya -- jadi yang kedua menangkap kasus
	-- yang lolos dari yang pertama.
	if Players:GetPlayerFromCharacter(anak) then return end
	if Players:FindFirstChild(anak.Name) then return end

	-- Avatar nova tidak lewat gerbang "muncul utuh": dia ditahan
	-- tersembunyi sampai adegan novanya selesai, dan jalankanNova yang
	-- memunculkannya kembali di slotnya.
	if anak:GetAttribute("TierNova") then
		tahanUntukNova(anak)
		-- Dicatat supaya pesan novanya tetap bisa menemukan modelnya
		-- kalau referensi Instance di dalam pesan itu sampai nil. Lihat
		-- novaCariModel.
		local id = anak:GetAttribute("NovaId")
		if id then novaModel[id] = anak end
		return
	end

	siapkanAvatar(anak)
end)

-- ============ SAMBUNGAN ============

V2Event.OnClientEvent:Connect(function(jenis, d)
	if jenis == "fokus" then
		-- Tinggi mundur penuh ikut tiap pesan, bukan cuma pesan
		-- berbayar: yang mengubahnya bukan tier yang datang, tapi ada
		-- atau tidaknya raksasa di panggung -- dan raksasa berdiri
		-- melewati kedatangan gratisan berikutnya.
		upJauhKini = tonumber(d.upJauh) or CFG.upJauh or CFG.up

		if d.sinema and d.lama and d.lama > 0 then
			-- Adegan berbayar. Selalu merebut kamera, termasuk dari
			-- adegan lain yang belum habis -- yang baru bayar yang
			-- menang.
			--
			-- Batas waktunya dihitung dari SEKARANG, bukan dari cap
			-- waktu server: jam client dan jam server tidak pernah
			-- sama, dan selisih satu detik di sini berarti kamera
			-- pulang ke ayunan sedetik sebelum orangnya mendarat.
			fokusTarget  = d.pos or fokusTarget
			-- Letterbox dan kawan-kawannya, kalau tier ini punya (Rosa).
			-- Tier tanpa `layar` tidak menyentuh apa pun -- termasuk
			-- tidak membersihkan milik adegan sebelumnya, yang punya
			-- jadwal keluarnya sendiri.
			if d.layar then
				layarSinema(d.layar, d.lama, d.model, d.layarKilat,
					type(d.tema) == "table" and d.tema.layar or nil)
			end
			-- Jalur kamera sendiri + latar sinematik (Rosa).
			if d.jalur then panggungRosa(d) end
			sinemaSampai = os.clock() + d.lama
			sinemaLama   = d.lama
			sinemaOrbit  = (d.orbit == true)
			sinemaJauh   = tonumber(d.jauh) or 1
			-- Jatuh ke sinemaJauh, BUKAN ke 1: tier selain raksasa tidak
			-- mengirim jauhY sama sekali, dan untuk mereka tingginya
			-- memang harus ikut jaraknya seperti sebelumnya.
			sinemaJauhY  = tonumber(d.jauhY) or sinemaJauh
			zoomMulai    = os.clock()
			zoomKeluar   = tonumber(d.zoomKeluar) or CFG.zoomKeluar or 1.8
			zoomMasuk    = tonumber(d.zoomMasuk) or CFG.zoomMasuk or 0.45
			zoomMaks     = tonumber(d.zoomMaks) or 1
			-- Busur depan. Derajat di server, radian di sini -- diubah
			-- di satu tempat saja supaya sisa file tidak perlu tahu
			-- satuannya.
			arcRad       = math.rad(tonumber(d.arcDeg) or 0)
			arcPutar     = tonumber(d.arcPutar) or 1
			naikAmp      = tonumber(d.naikAmp) or 0
			naikPutar    = tonumber(d.naikPutar) or 1
			-- Denyut zoom. Server mengirim ketiganya cuma untuk tier
			-- yang memang berdenyut; yang lain jatuh ke 0 di sini, dan
			-- 0 berarti bagian denyut di gelung render dilewati sama
			-- sekali.
			denyutDalam  = tonumber(d.denyutDalam) or 0
			denyutMulai  = math.clamp(tonumber(d.denyutMulai) or 0.5, 0, 0.95)
			denyutUlang  = math.max(tonumber(d.denyutUlang) or 1, 1)

			-- Dibunyikan di sini, di cabang BERBAYAR saja.
			--
			-- Cabang gratisan di bawah tidak memanggilnya, dan itu
			-- disengaja: tier 1 datang tiap detik saat live ramai, dan
			-- bunyi kedatangan untuk tiap satu dari mereka akan jadi
			-- derau yang terus-menerus -- lalu yang berbayar kehilangan
			-- satu-satunya penanda telinganya.
			--
			-- bunyiNanti: nova membunyikannya sendiri saat dia membanting
			-- diri ke tanah (jalankanNova). Di detik ini dia baru mulai
			-- mengumpulkan tenaga.
			if not d.bunyiNanti then bunyiTier(tonumber(d.tier)) end
			-- Adegan berbayar juga dimulai dari depan, dan busurnya
			-- memang berangkat dari 0 (depan) -- jadi keduanya sepakat.
			--
			-- Tetap dipanggil walau busurnya menimpa sudutBias tiap
			-- frame: kalau arcDeg-nya 0 (tier yang tidak menyapu), ini
			-- satu-satunya yang meluruskan pandangan ke orangnya.
			pandangLurus()
			-- Ditahan sama lamanya dengan kedatangan gratisan.
			--
			-- Dulu yang bayar ditahan dekat SELAMA SOROTANNYA (5-6
			-- detik), dan itu justru merugikan dia: papan auranya
			-- berada di luar frame atas selama kamera masih merapat,
			-- jadi undian angkanya -- tiga detik yang paling ditonton
			-- orang -- lewat tanpa terlihat sama sekali. Yang dia dapat
			-- dari sorotan tetap utuh (kamera tidak bisa direbut
			-- kedatangan lain), yang berubah cuma kameranya tidak lagi
			-- menempel terlalu dekat terlalu lama.
			zoomTahan    = tonumber(d.zoomTahan) or CFG.zoomTahan or 1.0

		elseif os.clock() >= sinemaSampai then
			fokusTarget = d.pos or fokusTarget
			sinemaJauh  = 1
			sinemaJauhY = 1
			zoomMulai   = os.clock()
			zoomKeluar  = tonumber(d.zoomKeluar) or CFG.zoomKeluar or 1.8
			zoomTahan   = tonumber(d.zoomTahan) or CFG.zoomTahan or 1.6
			-- Dikembalikan ke nilai diamnya, bukan dibiarkan: semuanya
			-- milik adegan yang sudah selesai.
			--
			-- zoomMaks yang tertinggal membuat kamera berhenti mundur
			-- penuh, dan busur yang tertinggal membuat kedatangan
			-- gratisan berikutnya ikut menyapu dengan lebar milik tier
			-- berbayar -- tier 1 seharusnya cuma dapat ayunan panggung
			-- yang biasa.
			zoomMaks    = tonumber(d.zoomMaks) or 1
			zoomMasuk   = tonumber(d.zoomMasuk) or CFG.zoomMasuk or 0.45
			arcRad      = math.rad(tonumber(d.arcDeg) or 0)
			arcPutar    = tonumber(d.arcPutar) or 1
			naikAmp     = tonumber(d.naikAmp) or 0
			naikPutar   = tonumber(d.naikPutar) or 1
			-- Ikut dikembalikan ke nilai diamnya, alasannya sama dengan
			-- zoomMaks dan arcRad di atas: denyut milik tier 3 yang
			-- tertinggal akan membuat kedatangan GRATISAN berikutnya
			-- ikut merapat di tengah jalan -- gerakan yang cuma boleh
			-- dipunyai orang yang membayar 10 koin.
			denyutDalam = tonumber(d.denyutDalam) or 0
			denyutMulai = math.clamp(tonumber(d.denyutMulai) or 0.5, 0, 0.95)
			denyutUlang = math.max(tonumber(d.denyutUlang) or 1, 1)
			pandangLurus()

		-- else: kedatangan biasa DI TENGAH adegan berbayar -- diabaikan.
		--
		-- Ini penjaga yang di v1 bernama spotlightBusy, dan tanpa dia
		-- seluruh sorotan tier 2 percuma. Panggung cuma berhenti untuk
		-- tier 3 (lihat BEKU_MIN_TIER di server), jadi selama lima
		-- detik sorotan tier 2, komentar gratisan tetap berdatangan --
		-- dan tiap satu dari mereka akan menyeret kamera pergi dari
		-- orang yang barusan bayar. Avatarnya tetap muncul; yang tidak
		-- dia dapat cuma kameranya.
		end
	elseif jenis == "ikut" then
		-- Titik pandang yang mengejar badan yang sedang melayang.
		-- Sengaja terpisah dari "fokus": pesan ini datang tujuh kali
		-- per detik dan tidak boleh menyentuh sinemaSampai sama sekali
		-- -- kalau dia ikut memperbarui batas waktunya, adegan yang
		-- seharusnya tujuh detik tidak akan pernah berakhir.
		--
		-- Juga tidak lewat penjaga "sedang ada adegan": pesan ini
		-- DATANG dari adegan itu sendiri.
		fokusTarget = d.pos or fokusTarget

	elseif jenis == "aura" then
		-- Dibunyikan di sini, bukan di dalam auraDiKepala/tampilkanAura:
		-- kalau dua-duanya dinyalakan, satu kedatangan memanggil dua
		-- fungsi -- dan bunyinya akan diulang dari nol dua kali dalam
		-- satu frame.
		if CFG.auraKepala or CFG.auraLayar then
			bunyiAura(d.roll or CFG.auraRoll, d.persen, d.tunda, d.raksasa)
		end
		if CFG.auraKepala then auraDiKepala(d) end
		if CFG.auraLayar  then tampilkanAura(d) end
	elseif jenis == "nova" then
		-- task.spawn: jalankanNova menunggu aset dan animasinya sendiri,
		-- dan handler ini tidak boleh tertahan -- pesan "fokus" dan "aura"
		-- berikutnya harus tetap diproses selama adegannya berjalan.
		task.spawn(jalankanNova, d)
	elseif jenis == "musik" then
		tampilkanLagu(d)
	end
end)

-- Bingkai pertama, sebelum ada satu pun kedatangan. Tanpa ini penonton
-- yang join di tengah siaran memandang avatarnya sendiri sampai orang
-- berikutnya datang -- dan kalau pollingnya sepi, itu bisa berpuluh
-- detik.
if camera then
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.new(fokusKini + offsetDasar, fokusKini)
end
 