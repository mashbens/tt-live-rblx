--[[
    LatarSolo  --  latar panggung solo + efek per tier

    Di Studio: ReplicatedStorage.LatarSolo (ModuleScript). Disinkron Rojo.
    Dipakai KameraClientV2 kalau AvatarQueueV2 menyalakan SOLO.AKTIF:

        pasang(cfg)  sekali, membangun latarnya (cfg = V2Config.solo)
        datang(d)    tiap kedatangan (pesan "fokus"): warna + efek tier
        getar()      guncangan frame ini, ditambahkan ke kamera

    Semuanya dibangun CLIENT, di workspace lokal: tidak ada yang
    direplikasi, jadi animasinya (cincin berputar, pilar berdenyut,
    kembang api) tidak membebani server, dan kameranya memang cuma satu
    titik -- tidak ada yang perlu sama persis antar penonton.

    Ukurannya dihitung untuk kamera solo (9 stud di depan, setinggi
    pinggang) dan layar HP TEGAK: di jarak dinding cuma sekitar 8 stud ke
    kiri-kanan yang kelihatan, jadi semua yang penting ada di tengah.
--]]

local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local LatarSolo = {}

-- ============ SETELAN ============

-- Bentuk latarnya:
--   "ruangan"  kamar sederhana yang gelap: dinding, lantai kayu, plafon,
--              rak, strip LED berwarna tier di bawah plafon
--   "halloween" kamar santai Halloween (bangunHalloween): jendela bulan
--              purnama, perapian api hijau, sofa ungu, labu, kuali, hantu
--   "angkasa"  latar lama: langit, sinar, cincin, pilar cahaya
-- Efek partikel (debu, konfeti, kembang api) dan getar ada di semuanya.
local GAYA = "halloween"

-- Ukuran kamar, stud dari titik kaki avatar. Dinding belakang dekat
-- (BELAKANG_Z) supaya avatarnya terasa berdiri DI DALAM kamar, bukan di
-- depan layar jauh: di layar HP tegak, kamera 9 stud di depan kaki
-- melihat dinding ini selebar sekitar 12 stud, plafonnya ikut masuk
-- frame di atas kepala.
local RUANG_BELAKANG_Z = 6
local RUANG_DEPAN_Z    = -16
local RUANG_LEBAR      = 22
local RUANG_TINGGI     = 12

-- Dinding latar: sejauh ini di belakang kaki avatar, seukuran ini.
local DINDING_Z      = 14
local DINDING_LEBAR  = 90
local DINDING_TINGGI = 50
-- Pusat dinding di atas lantai. Tepi atasnya = DINDING_Y + TINGGI/2.
local DINDING_Y      = 8
-- Resolusi gambar dinding.
local PIKSEL_STUD    = 6
-- Titik di dinding yang segaris dengan kepala avatar dari kamera: pusat
-- pendar dan sinar.
local PUSAT_Y        = 8

-- Pilar cahaya di belakang avatar, X-nya (dicerminkan kiri-kanan).
local PILAR_X  = { 5.5, 9 }
local PILAR_Z  = 11

local PUTIH = Color3.new(1, 1, 1)

-- Warna per tier, sama dengan KartuProfil supaya satu kedatangan satu
-- warna di semua tempat.
local TEMA = {
	[1] = { a = Color3.fromRGB(110, 140, 255), b = Color3.fromRGB(60, 50, 140) },
	[2] = { a = Color3.fromRGB(90, 180, 255), b = Color3.fromRGB(50, 90, 255) },
	[3] = { a = Color3.fromRGB(0, 230, 255), b = Color3.fromRGB(170, 80, 255) },
	[4] = { a = Color3.fromRGB(255, 215, 90), b = Color3.fromRGB(255, 70, 190) },
	[5] = { a = Color3.fromRGB(255, 170, 40), b = Color3.fromRGB(255, 40, 90) },
}

-- Seberapa ramai latarnya per tier.
--   putar   derajat/detik cincin dan sinar
--   pilar   transparansi dasar pilar (0 = paling terang)
--   sinar   transparansi sinar di belakang kepala (1 = tidak ada)
--   debu    partikel cahaya per detik
--   kembang jeda antar kembang api, detik (0 = tidak ada)
--   konfeti hujan konfeti selama tampil
--   getar   kuat guncangan kamera saat datang, stud
local EFEK = {
	[1] = { putar = 10, pilar = 0.55, sinar = 1,    debu = 3,  kembang = 0,   konfeti = false, getar = 0 },
	[2] = { putar = 18, pilar = 0.4,  sinar = 0.9,  debu = 8,  kembang = 0,   konfeti = false, getar = 0 },
	[3] = { putar = 30, pilar = 0.25, sinar = 0.75, debu = 16, kembang = 0,   konfeti = false, getar = 0.08 },
	[4] = { putar = 40, pilar = 0.15, sinar = 0.65, debu = 24, kembang = 0,   konfeti = true,  getar = 0.15 },
	[5] = { putar = 55, pilar = 0,    sinar = 0.45, debu = 34, kembang = 0.7, konfeti = true,  getar = 0.35 },
}

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

-- ============ KEADAAN ============

local L = nil          -- semua benda latar, diisi pasang()
local efekKini = EFEK[1]
local gen = 0          -- naik tiap kedatangan; efek lama berhenti sendiri
local getarSampai, getarMulai, getarKuat = 0, 0, 0

-- ============ ALAT ============

local function baru(kelas, sifat, induk)
	local o = Instance.new(kelas)
	for k, v in pairs(sifat) do o[k] = v end
	if induk then o.Parent = induk end
	return o
end

local function gerak(o, detik, sifat, gaya)
	local t = TweenService:Create(o, TweenInfo.new(detik,
		gaya or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), sifat)
	t:Play()
	return t
end

local function balok(induk, sifat)
	sifat.Anchored    = true
	sifat.CanCollide  = false
	sifat.CanQuery    = false
	sifat.CanTouch    = false
	sifat.CastShadow  = false
	-- Part dari Instance.new() bawaannya Studs di atas, Inlet di bawah;
	-- di place ini keduanya dirender abu-abu pucat apa pun warnanya
	-- (labu kelihatan seperti kotak abu-abu, silinder tegak abu-abu
	-- di badannya karena sisi atasnya ikut berputar ke samping).
	sifat.TopSurface    = Enum.SurfaceType.Smooth
	sifat.BottomSurface = Enum.SurfaceType.Smooth
	return baru("Part", sifat, induk)
end

local function bulat(induk, d, x, y, warna, alpha, z)
	local f = baru("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(d, d),
		BackgroundColor3 = warna, BackgroundTransparency = alpha,
		BorderSizePixel = 0, ZIndex = z or 1,
	}, induk)
	baru("UICorner", { CornerRadius = UDim.new(1, 0) }, f)
	return f
end

local function urutanAlpha(titik)
	local kp = {}
	for _, p in ipairs(titik) do
		table.insert(kp, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(kp)
end

-- ============ MEMBANGUN ============

-- Lampu depan: wajah avatar tetap terang apa pun warna latarnya.
local function lampuDepan(folder, kaki)
	local depan = balok(folder, {
		Name = "LampuDepan", Size = Vector3.new(1, 1, 1), Transparency = 1,
		CFrame = CFrame.lookAt(kaki + Vector3.new(0, 7, -7), kaki + Vector3.new(0, 3, 0)),
	})
	baru("SpotLight", { Face = Enum.NormalId.Front, Range = 22, Angle = 50,
		Brightness = 1.6, Color = Color3.fromRGB(255, 244, 235), Shadows = true }, depan)
end

local function bangunDinding(folder, kaki)
	local dinding = balok(folder, {
		Name     = "Dinding",
		Size     = Vector3.new(DINDING_LEBAR, DINDING_TINGGI, 1),
		CFrame   = CFrame.new(kaki + Vector3.new(0, DINDING_Y, DINDING_Z)),
		Color    = Color3.fromRGB(8, 8, 14),
		Material = Enum.Material.SmoothPlastic,
	})
	-- Front = sisi -Z = sisi yang menghadap kamera.
	local sg = baru("SurfaceGui", {
		Face          = Enum.NormalId.Front,
		SizingMode    = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = PIKSEL_STUD,
		LightInfluence = 0,
	}, dinding)

	local W = DINDING_LEBAR * PIKSEL_STUD
	local atas = DINDING_Y + DINDING_TINGGI / 2
	local function py(y) return (atas - y) * PIKSEL_STUD end
	local cx, cy = W / 2, py(PUSAT_Y)

	-- Langit: warna tier, digelapkan ke bawah oleh gradien (gradien
	-- MENGALIKAN warna, jadi cukup BackgroundColor3 yang di-tween).
	local langit = baru("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = TEMA[1].b,
		BorderSizePixel = 0,
	}, sg)
	baru("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.new(0.5, 0.5, 0.55)),
			ColorSequenceKeypoint.new(0.6, Color3.new(0.16, 0.16, 0.2)),
			ColorSequenceKeypoint.new(1, Color3.new(0.04, 0.04, 0.06)),
		}),
	}, langit)

	-- Bintang kecil yang berkelip.
	local bintang = {}
	local acak = Random.new(7)
	for i = 1, 46 do
		local b = bulat(sg, acak:NextInteger(2, 4),
			acak:NextInteger(0, W), acak:NextInteger(0, math.floor(py(10))),
			PUTIH, 0.5, 2)
		bintang[i] = { f = b, fase = acak:NextNumber(0, 6.28),
			laju = acak:NextNumber(1, 3) }
	end

	-- Pita cahaya di garis cakrawala, tepat di atas lantai.
	local cakrawala = baru("Frame", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromOffset(0, py(0)), Size = UDim2.new(1, 0, 0, 70),
		BackgroundColor3 = TEMA[1].a, BorderSizePixel = 0, ZIndex = 2,
	}, sg)
	baru("UIGradient", { Rotation = 90,
		Transparency = urutanAlpha({ { 0, 1 }, { 1, 0.35 } }) }, cakrawala)

	-- Pendar bulat berlapis di belakang kepala (UIGradient tidak bisa
	-- radial, jadi lingkaran bertumpuk makin kecil makin pekat).
	local pendar = {}
	for i, ukur in ipairs({ 300, 220, 150, 96 }) do
		pendar[i] = bulat(sg, ukur, cx, cy, TEMA[1].a,
			0.93 - i * 0.07, 3)
	end

	-- Sinar. Tiap sinar = bingkai seukuran penuh yang berpusat di titik
	-- pendar, isinya cuma separuh atas: GuiObject berputar di PUSATNYA
	-- sendiri, bukan di AnchorPoint, jadi begini caranya supaya semua
	-- sinar berporos di satu titik.
	local poros = baru("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(560, 560),
		BackgroundTransparency = 1, ZIndex = 4,
	}, sg)
	local sinar = {}
	for i = 1, 16 do
		local wadah = baru("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(0, (i % 2 == 0) and 10 or 5, 1, 0),
			Rotation = i * 22.5, BackgroundTransparency = 1, ZIndex = 4,
		}, poros)
		local s = baru("Frame", {
			Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = TEMA[1].a,
			BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 4,
		}, wadah)
		baru("UIGradient", { Rotation = 90,
			Transparency = urutanAlpha({ { 0, 1 }, { 0.6, 0.6 }, { 1, 0.2 } }) }, s)
		sinar[i] = s
	end

	-- Dua cincin dengan busur yang menyapu (gradien transparansi pada
	-- garis tepinya yang diputar), berlawanan arah.
	local cincin = {}
	for i, ukur in ipairs({ 250, 196 }) do
		local c = baru("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(ukur, ukur),
			BackgroundTransparency = 1, ZIndex = 5,
		}, sg)
		baru("UICorner", { CornerRadius = UDim.new(1, 0) }, c)
		local garis = baru("UIStroke", { Thickness = (i == 1) and 4 or 2,
			Color = TEMA[1].a }, c)
		local g = baru("UIGradient", {
			Transparency = urutanAlpha({ { 0, 0 }, { 0.22, 0 }, { 0.3, 1 },
				{ 0.7, 1 }, { 0.78, 0 }, { 1, 0 } }),
		}, garis)
		cincin[i] = { garis = garis, g = g, arah = (i == 1) and 1 or -1 }
	end

	return {
		dinding = dinding, langit = langit, cakrawala = cakrawala,
		pendar = pendar, poros = poros, sinar = sinar, cincin = cincin,
		bintang = bintang,
	}
end

local function bangunPanggung(folder, kaki)
	-- Lantai gelap mengkilap menutupi baseplate dari kamera sampai dinding.
	balok(folder, {
		Name = "Lantai", Size = Vector3.new(120, 0.2, 60),
		-- Permukaannya 0,05 di atas lantai asli, bukan pas: dua permukaan
		-- serapat itu saling tembus di dekat kamera, dan garis grid
		-- Baseplate muncul sebagai bingkai kotak di sekitar kaki.
		CFrame = CFrame.new(kaki + Vector3.new(0, -0.05, 2)),
		-- Pantulan kecil saja: di sudut kamera serendah pinggang, lantai
		-- yang memantul memantulkan LANGIT, dan lantai gelapnya jadi biru.
		Color = Color3.fromRGB(14, 14, 20), Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.03,
	})

	-- Lingkaran panggung di kaki: gambar bulat di sisi atas part yang
	-- tidak terlihat. Bukan silinder: silinder setipis ini digambar
	-- Roblox dengan sisi lurus, dan dari kamera serendah pinggang dia
	-- terbaca sebagai bingkai KOTAK di sekitar kaki.
	local alas = balok(folder, {
		Name = "Panggung", Size = Vector3.new(8, 0.1, 8), Transparency = 1,
		CFrame = CFrame.new(kaki + Vector3.new(0, 0.08, 0)),
	})
	local sg = baru("SurfaceGui", {
		Face = Enum.NormalId.Top, SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40, LightInfluence = 0,
	}, alas)
	local piring = bulat(sg, 300, 160, 160, Color3.fromRGB(16, 16, 26), 0.1, 1)
	local tepi = baru("UIStroke", { Thickness = 9, Color = TEMA[1].a }, piring)
	-- Cincin tipis kedua di dalam, sedikit pudar.
	local dalam = bulat(sg, 230, 160, 160, PUTIH, 1, 2)
	baru("UIStroke", { Thickness = 3, Color = PUTIH, Transparency = 0.6 }, dalam)

	-- Pilar cahaya di belakang, kiri-kanan, dengan lampu yang memberi
	-- garis cahaya di tepi badan avatar.
	local pilar = {}
	for _, x in ipairs(PILAR_X) do
		for _, sisi in ipairs({ -1, 1 }) do
			local p = balok(folder, {
				Name = "Pilar", Size = Vector3.new(0.5, 34, 0.5),
				CFrame = CFrame.new(kaki + Vector3.new(x * sisi, 17, PILAR_Z)),
				Color = TEMA[1].a, Material = Enum.Material.Neon,
				Transparency = EFEK[1].pilar,
			})
			local lampu = baru("PointLight", { Range = 14, Brightness = 1.2,
				Color = TEMA[1].a, Shadows = false }, p)
			table.insert(pilar, { p = p, lampu = lampu, fase = #pilar * 0.9 })
		end
	end

	lampuDepan(folder, kaki)

	return { tepi = tepi, pilar = pilar }
end

-- Kamarnya GELAP: dinding, lantai, dan plafon nyaris hitam, supaya
-- kartu profil tanpa kotak (KartuProfil, TEMBUS = 1) menyatu dengan
-- latarnya dan teks putihnya terbaca tanpa panel. Yang terang cuma
-- avatarnya (lampu depan) dan strip LED warna tier.
--
-- Concrete, bukan Plaster: di place ini Plaster ditimpa MaterialVariant
-- bermotif bunga.
local function bangunRuangan(folder, kaki)
	local bz, lebar, tinggi = RUANG_BELAKANG_Z, RUANG_LEBAR, RUANG_TINGGI
	local dalam = bz - RUANG_DEPAN_Z
	local tengahZ = (bz + RUANG_DEPAN_Z) / 2
	local function di(x, y, z) return CFrame.new(kaki + Vector3.new(x, y, z)) end
	local PUTIH_RAK = Color3.fromRGB(58, 58, 66)

	-- Lantai kayu. Permukaannya 0,05 di atas lantai asli, alasannya sama
	-- dengan lantai angkasa: grid Baseplate tembus di dekat kamera.
	balok(folder, {
		Name = "Lantai", Size = Vector3.new(lebar, 0.2, dalam),
		CFrame = di(0, -0.05, tengahZ),
		Color = Color3.fromRGB(48, 34, 26), Material = Enum.Material.WoodPlanks,
	})
	balok(folder, {
		Name = "DindingBelakang", Size = Vector3.new(lebar, tinggi, 1),
		CFrame = di(0, tinggi / 2, bz + 0.5),
		Color = Color3.fromRGB(30, 30, 36), Material = Enum.Material.Concrete,
	})
	for _, sisi in ipairs({ -1, 1 }) do
		balok(folder, {
			Name = "DindingSamping", Size = Vector3.new(1, tinggi, dalam),
			CFrame = di(sisi * (lebar / 2 + 0.5), tinggi / 2, tengahZ),
			Color = Color3.fromRGB(24, 24, 30), Material = Enum.Material.Concrete,
		})
	end
	balok(folder, {
		Name = "Plafon", Size = Vector3.new(lebar + 2, 1, dalam),
		CFrame = di(0, tinggi + 0.5, tengahZ),
		Color = Color3.fromRGB(18, 18, 22), Material = Enum.Material.Concrete,
	})
	-- List putih di kaki dinding: tanpa ini sambungan dinding-lantai
	-- dari kamera serendah pinggang terbaca seperti dinding melayang.
	balok(folder, {
		Name = "List", Size = Vector3.new(lebar, 0.5, 0.2),
		CFrame = di(0, 0.25, bz - 0.1), Color = PUTIH_RAK,
		Material = Enum.Material.SmoothPlastic,
	})

	-- Rak putih menempel di dinding, kiri avatar. Sengaja terpotong tepi
	-- layar HP: memberi kedalaman tanpa merebut perhatian dari avatarnya.
	local rx, rz, rl, rt, rd = -4.6, bz - 0.75, 2.6, 6, 1.4
	for _, sisi in ipairs({ -1, 1 }) do
		balok(folder, {
			Name = "Rak", Size = Vector3.new(0.15, rt, rd),
			CFrame = di(rx + sisi * rl / 2, rt / 2, rz),
			Color = PUTIH_RAK, Material = Enum.Material.SmoothPlastic,
		})
	end
	for i = 0, 4 do
		balok(folder, {
			Name = "Rak", Size = Vector3.new(rl, 0.15, rd),
			CFrame = di(rx, 0.075 + i * (rt - 0.15) / 4, rz),
			Color = PUTIH_RAK, Material = Enum.Material.SmoothPlastic,
		})
	end
	-- Beberapa kotak di raknya, supaya rak itu terbaca sebagai rak.
	-- { geser X, papan ke berapa (0 = paling bawah), ukuran, warna }
	local jarakPapan = (rt - 0.15) / 4
	for _, b in ipairs({
		{ -0.6, 0, Vector3.new(0.9, 1, 0.9), Color3.fromRGB(60, 60, 66) },
		{ 0.5, 1, Vector3.new(0.7, 0.9, 1), Color3.fromRGB(200, 170, 130) },
		{ -0.3, 2, Vector3.new(1.2, 0.6, 0.8), Color3.fromRGB(90, 110, 150) },
	}) do
		balok(folder, {
			Name = "Barang", Size = b[3],
			CFrame = di(rx + b[1], 0.15 + b[2] * jarakPapan + b[3].Y / 2, rz),
			Color = b[4], Material = Enum.Material.SmoothPlastic,
		})
	end

	-- Strip LED di bawah plafon, satu-satunya yang ikut warna tier.
	local led = balok(folder, {
		Name = "LED", Size = Vector3.new(lebar, 0.18, 0.18),
		CFrame = di(0, tinggi - 0.25, bz - 0.1),
		Color = TEMA[1].a, Material = Enum.Material.Neon,
	})
	local cahayaLed = baru("PointLight", { Range = 14, Brightness = 2,
		Color = TEMA[1].a, Shadows = false }, led)

	-- Lampu plafon hangat di atas avatar. Shadows = bayangan badannya
	-- jatuh di lantai dan dinding, itu yang menempelkan dia ke kamar.
	local plafon = balok(folder, {
		Name = "LampuPlafon", Size = Vector3.new(1.6, 0.1, 1.6),
		CFrame = di(0, tinggi - 0.05, 0),
		Color = Color3.fromRGB(255, 244, 225), Material = Enum.Material.Neon,
	})
	baru("PointLight", { Range = 20, Brightness = 0.6,
		Color = Color3.fromRGB(255, 236, 210), Shadows = true }, plafon)

	lampuDepan(folder, kaki)

	return { led = led, cahayaLed = cahayaLed,
		pilar = {}, pendar = {}, sinar = {}, cincin = {}, bintang = {} }
end

local function pemancar(induk, sifat)
	sifat.Texture = sifat.Texture or SPARKLE
	sifat.LightEmission = sifat.LightEmission or 1
	return baru("ParticleEmitter", sifat, induk)
end

-- atas = tinggi pemancar konfeti, kembang = titik ledak kembang api,
-- keduanya relatif ke kaki. Di ruangan dua-duanya harus di BAWAH plafon
-- dan di DEPAN dinding, kalau tidak partikelnya tertutup.
local function bangunPartikel(folder, kaki, atas, titikKembang)
	-- Debu cahaya yang naik pelan di belakang avatar.
	local kotakDebu = balok(folder, {
		Name = "Debu", Size = Vector3.new(16, 1, 4), Transparency = 1,
		CFrame = CFrame.new(kaki + Vector3.new(0, 0.5, 5)),
	})
	local debu = pemancar(kotakDebu, {
		Rate = EFEK[1].debu, Lifetime = NumberRange.new(4, 7),
		Speed = NumberRange.new(1, 2.5), SpreadAngle = Vector2.new(20, 20),
		EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.2, 0.35), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new(0.2),
		Color = ColorSequence.new(TEMA[1].a),
	})

	-- Konfeti dari atas frame: tiga pemancar, satu warna masing-masing
	-- (ColorSequence partikel berubah sepanjang UMUR, bukan diacak per
	-- partikel).
	local kotakKonfeti = balok(folder, {
		Name = "Konfeti", Size = Vector3.new(14, 1, 6), Transparency = 1,
		CFrame = CFrame.new(kaki + Vector3.new(0, atas, 1)),
	})
	local konfeti = {}
	for i = 1, 3 do
		konfeti[i] = pemancar(kotakKonfeti, {
			Enabled = false, Rate = 18, Lifetime = NumberRange.new(3, 4.5),
			Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(30, 30),
			EmissionDirection = Enum.NormalId.Bottom,
			Acceleration = Vector3.new(0, -3, 0), Drag = 0.6,
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-260, 260),
			Size = NumberSequence.new(0.28), LightEmission = 0.4,
			Texture = "rbxasset://textures/particles/fire_main.dds",
			Color = ColorSequence.new(PUTIH),
		})
	end

	-- Titik ledak kembang api di depan dinding, di atas kepala avatar.
	local kotakKembang = balok(folder, {
		Name = "Kembang", Size = Vector3.new(1, 1, 1), Transparency = 1,
		CFrame = CFrame.new(kaki + titikKembang),
	})
	local kembang = pemancar(kotakKembang, {
		Enabled = false, Lifetime = NumberRange.new(0.9, 1.5),
		Speed = NumberRange.new(10, 16), SpreadAngle = Vector2.new(180, 180),
		Drag = 3, Acceleration = Vector3.new(0, -5, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7),
			NumberSequenceKeypoint.new(1, 0) }),
		Color = ColorSequence.new(PUTIH),
	})

	return { debu = debu, konfeti = konfeti, kotakKembang = kotakKembang,
		kembang = kembang, kembangDasar = kaki + titikKembang }
end

-- ============ HALLOWEEN ============

local ASAP = "rbxasset://textures/particles/smoke_main.dds"

local HW = {
	dinding = Color3.fromRGB(62, 36, 88),
	plafon  = Color3.fromRGB(34, 20, 48),
	kayu    = Color3.fromRGB(44, 24, 40),
	ubin    = Color3.fromRGB(200, 88, 22),
	hitam   = Color3.fromRGB(22, 16, 28),
	oranye  = Color3.fromRGB(255, 122, 20),
	alur    = Color3.fromRGB(222, 92, 12),
	ungu    = Color3.fromRGB(150, 60, 255),
	hijau   = Color3.fromRGB(70, 255, 120),
	lilin   = Color3.fromRGB(245, 234, 205),
	nyala   = Color3.fromRGB(255, 176, 70),
	siluet  = Color3.fromRGB(18, 10, 28),
	beludru = Color3.fromRGB(80, 32, 124),
	putih   = Color3.fromRGB(245, 245, 255),
}

-- Part bentuk Ball selalu bulat sempurna; labu, hantu, dan kuali butuh
-- elips, jadi pakai SpecialMesh Sphere yang ikut Size part-nya.
local function lonjong(induk, sifat)
	local p = balok(induk, sifat)
	baru("SpecialMesh", { MeshType = Enum.MeshType.Sphere }, p)
	return p
end

-- Silinder Roblox memanjang di sumbu X; diputar supaya tegak. cf =
-- pusat silindernya.
local TEGAK = CFrame.Angles(0, 0, math.pi / 2)
local function tabung(induk, cf, tinggi, d, sifat)
	sifat.Shape  = Enum.PartType.Cylinder
	sifat.Size   = Vector3.new(tinggi, d, d)
	sifat.CFrame = cf * TEGAK
	return balok(induk, sifat)
end

-- Garis lurus di SurfaceGui dari titik a ke b (piksel). GuiObject
-- berputar di pusatnya, jadi bingkainya diletakkan di titik tengah.
local function garis(induk, a, b, tebal, warna, alpha, z)
	local d = b - a
	return baru("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2),
		Size = UDim2.fromOffset(d.Magnitude + tebal * 0.5, tebal),
		Rotation = math.deg(math.atan2(d.Y, d.X)),
		BackgroundColor3 = warna, BackgroundTransparency = alpha or 0,
		BorderSizePixel = 0, ZIndex = z or 1,
	}, induk)
end

-- Jaring laba-laba: jari-jari dari pusat, lalu benang melingkar.
local function jaring(induk, pusat, r, sudut0, sudut1, jari, warna, alpha, z)
	local arah = {}
	for i = 0, jari do
		local a = math.rad(sudut0 + (sudut1 - sudut0) * i / jari)
		arah[i] = Vector2.new(math.cos(a), math.sin(a))
		garis(induk, pusat, pusat + arah[i] * r, 2, warna, alpha, z)
	end
	for _, f in ipairs({ 0.3, 0.55, 0.8 }) do
		for i = 0, jari - 1 do
			garis(induk, pusat + arah[i] * r * f, pusat + arah[i + 1] * r * f,
				1.5, warna, alpha, z)
		end
	end
end

-- Labu berdiri di cf (titik bawah, sisi depan = -Z lokal), lebar d.
-- Alur kulitnya: elips yang lebih ramping diputar di sumbu tegak, ujungnya
-- menyembul sedikit dari bola utama. Diputar 30 derajat supaya tidak ada
-- alur yang tepat di depan: di sana dia menutupi wajah ukirannya.
local function labu(induk, cf, d, wajah)
	local t = d * 0.78
	local pusat = cf * CFrame.new(0, t / 2, 0)
	local badan = lonjong(induk, { Name = "Labu", Size = Vector3.new(d, t, d),
		CFrame = pusat, Color = HW.oranye, Material = Enum.Material.SmoothPlastic })
	for i = 0, 2 do
		lonjong(induk, { Name = "Alur", Size = Vector3.new(d * 0.5, t * 0.98, d * 1.04),
			CFrame = pusat * CFrame.Angles(0, math.pi / 6 + i * math.pi / 3, 0),
			Color = HW.alur, Material = Enum.Material.SmoothPlastic })
	end
	tabung(induk, pusat * CFrame.new(0, t / 2 + d * 0.05, 0), d * 0.18, d * 0.12,
		{ Name = "Tangkai", Color = Color3.fromRGB(86, 112, 40), Material = Enum.Material.Wood })
	if wajah then
		-- Kedalaman permukaan elips di titik mata/mulut, dihitung supaya
		-- ukirannya menyembul tipis, tidak tenggelam di dalam labu.
		local muka = Color3.fromRGB(255, 214, 90)
		local function ukir(ukuran, x, y, z, putar)
			balok(induk, { Name = "Ukiran", Size = ukuran,
				CFrame = pusat * CFrame.new(x, y, z) * CFrame.Angles(0, 0, putar),
				Color = muka, Material = Enum.Material.Neon })
		end
		for _, s in ipairs({ -1, 1 }) do
			ukir(Vector3.new(d * 0.14, d * 0.14, d * 0.08), s * d * 0.17, t * 0.1, -d * 0.46, math.rad(45))
			ukir(Vector3.new(d * 0.13, d * 0.07, d * 0.08), s * d * 0.17, -t * 0.1, -d * 0.45, s * math.rad(-30))
		end
		ukir(Vector3.new(d * 0.24, d * 0.07, d * 0.08), 0, -t * 0.16, -d * 0.47, 0)
	end
	return badan, t
end

-- Model 3D dari ReplicatedStorage.AsetHalloween. Folder itu diisi lewat
-- Studio (model Creator Store, script-nya sudah dibuang) dan TIDAK ada di
-- repo: Rojo membiarkannya karena $ignoreUnknownInstances, jadi dia ikut
-- tersimpan di file place. Tidak ada = benda itu dilewati, latar tetap jadi.
--
-- ukuran = panjang sisi terpanjang, atau tinggi kalau tinggi = true. cf =
-- titik BAWAH-TENGAH kotak pembatasnya; sisi depan model = -Z cf, putar =
-- koreksi kalau depan model aslinya bukan -Z.
local asetHilang = {}
local function aset(nama, induk, cf, ukuran, tinggi, putar)
	local gudang = game:GetService("ReplicatedStorage"):FindFirstChild("AsetHalloween")
	local asli = gudang and gudang:FindFirstChild(nama)
	if not asli then
		if not asetHilang[nama] then
			asetHilang[nama] = true
			warn("[latar] ReplicatedStorage.AsetHalloween." .. nama .. " tidak ada, dilewati")
		end
		return nil
	end
	local m = asli:Clone()
	if not m:IsA("Model") then
		local w = Instance.new("Model")
		w.Name = nama
		m.Parent = w
		m = w
	end
	local _, s = m:GetBoundingBox()
	m:ScaleTo(m:GetScale() * ukuran / (tinggi and s.Y or math.max(s.X, s.Y, s.Z)))
	-- Sumbu kotak pembatas (= orientasi pivot model) disejajarkan dengan
	-- cf. Pivot model Creator Store sering miring sembarang (di sini
	-- sampai 33 derajat); kalau orientasinya dibawa, semuanya serong.
	local bb, s2 = m:GetBoundingBox()
	local bawah = bb * CFrame.new(0, -s2.Y / 2, 0)
	m:PivotTo(cf * CFrame.Angles(0, putar or 0, 0) * bawah:ToObjectSpace(m:GetPivot()))
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
			d.CastShadow = d.Material ~= Enum.Material.Neon and d.Transparency < 0.5
		elseif d:IsA("Light") then
			-- Lampu bawaan model dibatasi: bola kristalnya membawa
			-- PointLight Brightness 100 yang membakar separuh kamar jadi putih.
			d.Brightness = math.min(d.Brightness, 1.5)
		elseif d:IsA("ClickDetector") or d:IsA("ProximityPrompt") or d:IsA("Seat") then
			d:Destroy()
		end
	end
	m.Parent = induk
	return m
end

-- Kotak pembatas model di dunia: pusat, ukuran.
local function batas(m)
	local cf, s = m:GetBoundingBox()
	return cf.Position, s
end

-- Kamar santai Halloween, semuanya benda 3D: dinding papan ungu, lantai
-- catur, jendela gothic yang BENAR-BENAR berlubang (di luarnya langit
-- malam, bulan purnama, pohon mati -- bergeser sesuai sudut kamera, tidak
-- seperti gambar tempel), perapian batu api hijau, sofa L beludru ungu,
-- meja labu, kuali berasap, rak ramuan, bola kristal, hantu berlentera,
-- kucing tidur, kelelawar, lilin melayang.
--
-- Semua x di sini = kanan LAYAR. Kamera menghadap +Z, jadi kanan layar
-- adalah -X dunia; tanpa pembalik ini tata letaknya tercermin. Di layar
-- HP tegak cuma sekitar x = -6..6 di dinding belakang yang kelihatan,
-- makin dekat kamera makin sempit (sekitar 3,5 di garis kaki avatar).
local function bangunHalloween(folder, kaki, kameraPos)
	local bz, lebar, tinggi = RUANG_BELAKANG_Z, RUANG_LEBAR, RUANG_TINGGI
	local dalam = bz - RUANG_DEPAN_Z
	local tengahZ = (bz + RUANG_DEPAN_Z) / 2
	local function v(x, y, z) return kaki + Vector3.new(-x, y, z) end
	-- Tanpa putaran: -Z-nya sudah -Z dunia, lurus ke kamera. Cocok untuk
	-- benda yang menempel di dinding belakang.
	local function di(x, y, z) return CFrame.new(v(x, y, z)) end
	-- Menghadap kamera (mendatar): sisi depan benda = -Z lokal.
	local function hadap(x, y, z)
		local p = v(x, y, z)
		return CFrame.lookAt(p, Vector3.new(kameraPos.X, p.Y, kameraPos.Z))
	end

	local goyang, kelip, hias = {}, {}, {}
	-- Benda melayang naik-turun: semua part di f digeser bersama.
	local function goyangkan(f, amp, laju, fase)
		local bagian = {}
		for _, p in ipairs(f:GetDescendants()) do
			if p:IsA("BasePart") then table.insert(bagian, { p = p, cf = p.CFrame }) end
		end
		table.insert(goyang, { bagian = bagian, amp = amp, laju = laju, fase = fase })
	end
	local function lampu(induk, sifat, berkedip)
		if sifat.Shadows == nil then sifat.Shadows = false end
		local l = baru("PointLight", sifat, induk)
		if berkedip then
			table.insert(kelip, { lampu = l, dasar = l.Brightness, fase = #kelip * 7.3 })
		end
		return l
	end
	local function titikLampu(nama, cf)
		return balok(folder, { Name = nama, Size = Vector3.one * 0.2, Transparency = 1, CFrame = cf })
	end
	local function lilin(induk, cf, t, d, terang)
		tabung(induk, cf * CFrame.new(0, t / 2, 0), t, d,
			{ Name = "Lilin", Color = HW.lilin, Material = Enum.Material.SmoothPlastic })
		for i = 1, 3 do
			local a, h = i * 2.1, t * (0.12 + 0.1 * i)
			balok(induk, { Name = "Leleh", Size = Vector3.new(d * 0.22, h, d * 0.22),
				CFrame = cf * CFrame.new(math.cos(a) * d * 0.48, t - h / 2 + 0.02, math.sin(a) * d * 0.48),
				Color = HW.lilin, Material = Enum.Material.SmoothPlastic })
		end
		local api = lonjong(induk, { Name = "Api", Size = Vector3.new(d * 0.45, d * 0.9, d * 0.45),
			CFrame = cf * CFrame.new(0, t + d * 0.5, 0), Color = HW.nyala, Material = Enum.Material.Neon })
		if terang then lampu(api, { Range = 7, Brightness = 0.9, Color = HW.nyala }, true) end
	end

	-- ============ CANGKANG RUANGAN ============

	-- Lantai catur. Ubin tengah tepat di bawah kaki avatar. Permukaannya
	-- 0,05 di atas lantai asli, alasannya sama dengan gaya lain. Sedikit
	-- mengkilap: pantulan api dan neon terlihat di lantai. (Marble
	-- oranye malah terbaca seperti lava.)
	local UBIN = 2
	for i = 0, math.ceil(lebar / UBIN) - 1 do
		for j = 0, math.ceil(dalam / UBIN) - 1 do
			balok(folder, { Name = "Ubin", Size = Vector3.new(UBIN, 0.2, UBIN),
				CFrame = di(-lebar / 2 + UBIN * (i + 0.5), -0.05, RUANG_DEPAN_Z + UBIN * (j + 0.5)),
				Color = ((i + j) % 2 == 0) and HW.hitam or HW.ubin,
				Material = Enum.Material.SmoothPlastic, Reflectance = 0.08 })
		end
	end

	-- Dinding belakang = empat potong di sekeliling lubang jendela.
	local JL, JB, JA = 4.6, 3.9, 10.2      -- lebar lubang, tepi bawah, tepi atas
	local jx = JL / 2
	local function dinding(nama, x0, x1, y0, y1)
		return balok(folder, { Name = nama, Size = Vector3.new(x1 - x0, y1 - y0, 1),
			CFrame = di((x0 + x1) / 2, (y0 + y1) / 2, bz + 0.5),
			Color = HW.dinding, Material = Enum.Material.WoodPlanks })
	end
	local kiri = dinding("DindingBelakang", -lebar / 2, -jx, 0, tinggi)
	local kanan = dinding("DindingBelakang", jx, lebar / 2, 0, tinggi)
	dinding("DindingBelakang", -jx, jx, 0, JB)
	dinding("DindingBelakang", -jx, jx, JA, tinggi)
	-- Kusen dalam: tebal dinding terlihat di sisi lubang, bukan tepi tipis.
	for _, k in ipairs({ { -jx - 0.1, JB, JA }, { jx + 0.1, JB, JA } }) do
		balok(folder, { Name = "Kusen", Size = Vector3.new(0.2, k[3] - k[2], 1.1),
			CFrame = di(k[1], (k[2] + k[3]) / 2, bz + 0.5), Color = HW.kayu, Material = Enum.Material.Wood })
	end
	balok(folder, { Name = "AmbangJendela", Size = Vector3.new(JL + 0.8, 0.22, 1.5),
		CFrame = di(0, JB - 0.11, bz + 0.25), Color = HW.kayu, Material = Enum.Material.Wood })
	-- Dua jendela lancet gothic berdampingan (modelnya sempit, 1:3).
	-- Kacanya dibuang: kaca patrinya lebih lebar dari bingkai dan
	-- menutupi bulan.
	for _, x in ipairs({ -1.2, 1.2 }) do
		local j = aset("Jendela", folder, di(x, JB - 0.3, bz - 0.05), JA - JB + 1.2, true)
		if j then
			for _, d in ipairs(j:GetDescendants()) do
				if d:IsA("BasePart") and d.Material == Enum.Material.Glass then d:Destroy() end
			end
		end
	end

	for _, sisi in ipairs({ -1, 1 }) do
		balok(folder, {
			Name = "DindingSamping", Size = Vector3.new(1, tinggi, dalam),
			CFrame = di(sisi * (lebar / 2 + 0.5), tinggi / 2, tengahZ),
			Color = HW.dinding, Material = Enum.Material.WoodPlanks,
		})
	end
	balok(folder, {
		Name = "Plafon", Size = Vector3.new(lebar + 2, 1, dalam),
		CFrame = di(0, tinggi + 0.5, tengahZ), Color = HW.plafon, Material = Enum.Material.WoodPlanks,
	})
	-- Balok plafon melintang: memberi kedalaman di bagian atas frame.
	for i = 0, 3 do
		balok(folder, { Name = "BalokPlafon", Size = Vector3.new(lebar, 0.5, 0.5),
			CFrame = di(0, tinggi - 0.25, bz - 1 - i * 4), Color = HW.kayu, Material = Enum.Material.Wood })
	end

	-- Strip LED di tepi plafon: ungu + oranye di dinding belakang, oranye
	-- di samping. cahayaLed = kilat saat kedatangan (lihat datang()), tapi
	-- warnanya tetap ungu: L.led sengaja tidak diisi supaya warnai() tidak
	-- mengecatnya dengan warna tier.
	local ledUngu = balok(folder, { Name = "LED", Size = Vector3.new(lebar, 0.16, 0.16),
		CFrame = di(0, tinggi - 0.6, bz - 0.1), Color = HW.ungu, Material = Enum.Material.Neon })
	balok(folder, { Name = "LED", Size = Vector3.new(lebar, 0.16, 0.16),
		CFrame = di(0, tinggi - 0.82, bz - 0.1), Color = HW.oranye, Material = Enum.Material.Neon })
	for _, sisi in ipairs({ -1, 1 }) do
		balok(folder, { Name = "LED", Size = Vector3.new(0.16, 0.16, dalam),
			CFrame = di(sisi * (lebar / 2 - 0.1), tinggi - 0.6, tengahZ),
			Color = HW.oranye, Material = Enum.Material.Neon })
	end
	local cahayaLed = baru("PointLight", { Range = 14, Brightness = 2,
		Color = HW.ungu, Shadows = false }, ledUngu)

	-- Jaring laba-laba di sudut atas yang masih masuk frame.
	local benang = Color3.fromRGB(225, 220, 240)
	for _, k in ipairs({ { kiri, -6.3, 0, 90 }, { kanan, 6.3, 90, 180 } }) do
		local p = k[1]
		local PPS = 24
		local sg = baru("SurfaceGui", { Face = Enum.NormalId.Front,
			SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = PPS, LightInfluence = 0.3 }, p)
		-- Front part ini = sisi -Z = menghadap kamera; kiri GUI = kiri layar.
		local x0 = -(p.Position.X - kaki.X) - p.Size.X / 2
		jaring(sg, Vector2.new((k[2] - x0) * PPS, 0), 2.2 * PPS, k[3], k[4], 5, benang, 0.45, 2)
	end

	-- ============ DI LUAR JENDELA ============
	-- Pemandangan malam sungguhan di balik lubang jendela. Bergeser sedikit
	-- saat kamera bergoyang/mundur, itu yang membuatnya terasa 3D.
	local luarZ = bz + 1
	balok(folder, { Name = "TanahLuar", Size = Vector3.new(90, 1, 60),
		CFrame = di(0, -0.6, luarZ + 30), Color = Color3.fromRGB(16, 14, 24), Material = Enum.Material.Ground })
	-- Pemandangan luar dikurung rapat: atap, sisi, dan dinding depan di
	-- sekeliling kamar. Place ini siang (Lighting.ClockTime dari server);
	-- tanpa kurungan, cahaya langit masuk lewat jendela dan Unified
	-- Lighting memantulkannya ke seluruh kamar -- semuanya putih terbakar.
	-- Langitnya SurfaceGui tanpa pengaruh cahaya, jadi tetap terlihat.
	local GELAP = Color3.fromRGB(6, 5, 12)
	for _, k in ipairs({
		{ "AtapLuar", Vector3.new(92, 1, 48), 0, 60.5, luarZ + 23 },
		{ "SisiLuar", Vector3.new(1, 64, 48), -45.5, 28, luarZ + 23 },
		{ "SisiLuar", Vector3.new(1, 64, 48), 45.5, 28, luarZ + 23 },
		{ "DepanLuar", Vector3.new(92, 47.5, 1), 0, tinggi + 1 + 47.5 / 2, luarZ - 0.5 },
		{ "DepanLuar", Vector3.new(34, tinggi + 3, 1), -(lebar / 2 + 1 + 17), (tinggi + 1) / 2, luarZ - 0.5 },
		{ "DepanLuar", Vector3.new(34, tinggi + 3, 1), lebar / 2 + 1 + 17, (tinggi + 1) / 2, luarZ - 0.5 },
	}) do
		balok(folder, { Name = k[1], Size = k[2], CFrame = di(k[3], k[4], k[5]), Color = GELAP,
			Material = Enum.Material.SmoothPlastic }).CastShadow = true
	end
	local langit = balok(folder, { Name = "Langit", Size = Vector3.new(120, 70, 1),
		CFrame = di(0, 25, luarZ + 45), Color = Color3.fromRGB(20, 14, 46), Material = Enum.Material.SmoothPlastic })
	local sgL = baru("SurfaceGui", { Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 4, LightInfluence = 0 }, langit)
	local latar = baru("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = PUTIH, BorderSizePixel = 0 }, sgL)
	baru("UIGradient", { Rotation = 90, Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(8, 6, 26)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(42, 26, 90)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(120, 80, 160)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(60, 40, 90)),
	}) }, latar)
	local acak = Random.new(7)
	for _ = 1, 140 do
		bulat(sgL, acak:NextInteger(1, 3), acak:NextInteger(0, 480), acak:NextInteger(0, 170),
			PUTIH, acak:NextNumber(0.1, 0.6), 2)
	end
	-- Bulan: bola neon + dua lapis pendar tembus pandang.
	local bulanPos = di(1.6, 15.5, luarZ + 26)
	balok(folder, { Name = "Bulan", Shape = Enum.PartType.Ball, Size = Vector3.one * 5,
		CFrame = bulanPos, Color = Color3.fromRGB(255, 244, 210), Material = Enum.Material.Neon })
	for i, k in ipairs({ { 7, 0.85 }, { 10, 0.93 } }) do
		balok(folder, { Name = "PendarBulan" .. i, Shape = Enum.PartType.Ball, Size = Vector3.one * k[1],
			CFrame = bulanPos, Color = Color3.fromRGB(255, 225, 170), Material = Enum.Material.Neon,
			Transparency = k[2] })
	end
	-- Cahaya bulan yang masuk lewat jendela: garis cahaya kebiruan di
	-- rambut/bahu avatar dari belakang, dan bayangan kusen di lantai.
	local sinarBulan = balok(folder, { Name = "SinarBulan", Size = Vector3.one * 0.2, Transparency = 1,
		CFrame = CFrame.lookAt(v(0.8, 9.5, luarZ + 3), v(0, 1, 0)) })
	baru("SpotLight", { Face = Enum.NormalId.Front, Range = 22, Angle = 40, Brightness = 2.2,
		Color = Color3.fromRGB(160, 170, 255), Shadows = true }, sinarBulan)
	-- Pohon mati: siluet gelap (warnanya diganti; matahari place ini
	-- siang, pohon berwarna aslinya akan tampak terang di malam hari).
	-- Di kiri-kanan saja, dan tidak terlalu tinggi: modelnya selebar
	-- 1,4x tingginya, rantingnya menutupi bulan kalau dekat tengah.
	for _, k in ipairs({ { -9, 12, 8, 0.3 }, { 9.5, 18, 9, 2.4 }, { -12, 26, 10, 4 } }) do
		local pohon = aset("Pohon", folder, di(k[1], -0.1, luarZ + k[2]) * CFrame.Angles(0, k[4], 0), k[3], true)
		if pohon then
			for _, d in ipairs(pohon:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Color, d.Material, d.CastShadow = Color3.fromRGB(14, 10, 20), Enum.Material.SmoothPlastic, false
					if d:IsA("MeshPart") then d.TextureID = "" end
				elseif d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture") then
					d:Destroy()
				end
			end
		end
	end
	local kabutLuar = balok(folder, { Name = "KabutLuar", Size = Vector3.new(40, 0.5, 20), Transparency = 1,
		CFrame = di(0, 0.5, luarZ + 14) })
	pemancar(kabutLuar, { Texture = ASAP, LightEmission = 0.3, Rate = 6,
		Lifetime = NumberRange.new(10, 14), Speed = NumberRange.new(0.2, 0.5),
		SpreadAngle = Vector2.new(80, 80), EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new(8, 12), Rotation = NumberRange.new(0, 360),
		Transparency = urutanAlpha({ { 0, 1 }, { 0.3, 0.75 }, { 0.7, 0.8 }, { 1, 1 } }),
		Color = ColorSequence.new(Color3.fromRGB(170, 140, 220)) })
	-- Kelelawar terbang di depan bulan.
	for i, k in ipairs({ { 0.2, 13.5, 18, 1.4 }, { 2.6, 12.2, 15, 1.1 }, { -1.6, 11.2, 11, 0.9 } }) do
		local f = baru("Folder", { Name = "KelelawarLuar" }, folder)
		if aset("Kelelawar", f, hadap(k[1], k[2], luarZ + k[3]), k[4]) then
			goyangkan(f, 0.6, 1.6 + i * 0.3, i * 2)
		end
	end

	-- ============ PERAPIAN (kiri) ============
	-- Muka model perapian ini di +X kotaknya; +90 derajat memutarnya ke
	-- kamera.
	local fx = -4.9
	local perapian = aset("Perapian", folder, di(fx, 0, bz - 0.1), 8.5, true, math.pi / 2)
	local ukP = Vector3.new(3, 8.5, 3)
	if perapian then
		_, ukP = batas(perapian)
		-- Cerobongnya disambung batu sampai plafon: model setinggi kamar
		-- terlalu lebar untuk layar HP, yang pendek berhenti di udara.
		local lebarC, dalamC = math.max(ukP.X, ukP.Z) * 0.62, math.min(ukP.X, ukP.Z) * 0.7
		balok(folder, { Name = "Cerobong", Size = Vector3.new(lebarC, tinggi - ukP.Y + 0.1, dalamC),
			CFrame = di(fx, (ukP.Y + tinggi) / 2, bz - dalamC / 2),
			Color = Color3.fromRGB(120, 124, 140), Material = Enum.Material.Cobblestone })
		-- Api asli model (kalau ada) diganti api hijau.
		for _, d in ipairs(perapian:GetDescendants()) do
			if d:IsA("Fire") or d:IsA("ParticleEmitter") or d:IsA("Light") then d:Destroy() end
		end
	end
	local depanP = bz - math.min(ukP.Z, ukP.X)       -- muka perapian
	local tungku = balok(folder, { Name = "ApiHijau", Size = Vector3.new(1.2, 0.4, 0.4), Transparency = 1,
		CFrame = di(fx, 0.7, depanP + 0.6) })
	baru("Fire", { Color = HW.hijau, SecondaryColor = Color3.fromRGB(20, 140, 60),
		Size = 3, Heat = 5 }, tungku)
	lampu(tungku, { Range = 16, Brightness = 2.6, Color = HW.hijau, Shadows = true }, true)
	-- Lilin dan tengkorak di rak perapian. Tingginya ditebak dari model
	-- (rak di sekitar sepertiga tinggi); lantai kalau tidak ada model.
	local rakY = perapian and 3.3 or 0
	aset("Lilin", folder, hadap(fx - 0.9, rakY, depanP + 0.35), 1.1, true)
	aset("Tengkorak", folder, hadap(fx + 0.8, rakY, depanP + 0.35), 0.6, true)
	aset("Lilin", folder, hadap(fx + 2.1, 0.05, depanP - 0.4), 0.9, true, 1)

	-- Papan neon BOO! di cerobong perapian (dinding antara perapian dan
	-- jendela terlalu sempit). Papan akrilik gelap berdiri sedikit di
	-- depan cerobong, tulisannya yang menyala.
	local booZ = perapian and (depanP - 0.15) or (bz - 0.2)
	local papan = balok(folder, { Name = "PapanBoo", Size = Vector3.new(2.6, 1.2, 0.08),
		CFrame = di(fx, 7.4, booZ) * CFrame.Angles(0, 0, math.rad(-6)),
		Color = Color3.fromRGB(20, 10, 30), Material = Enum.Material.Glass, Transparency = 0.35 })
	local sgB = baru("SurfaceGui", { Face = Enum.NormalId.Front,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 60, LightInfluence = 0 }, papan)
	local teks = baru("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
		Text = "BOO!", Font = Enum.Font.FredokaOne, TextScaled = true,
		TextColor3 = Color3.fromRGB(255, 190, 245) }, sgB)
	baru("UIStroke", { Color = Color3.fromRGB(200, 70, 255), Thickness = 5 }, teks)
	lampu(papan, { Range = 8, Brightness = 1.6, Color = Color3.fromRGB(255, 110, 230) })

	-- ============ KUALI (kiri depan) ============
	-- Agak ke tengah: di depan perapian dia menutupi apinya.
	local kuali = aset("Kuali", folder, hadap(-2.3, 0, 0.2), 1.7)
	if kuali then
		-- Cairan ungu bawaan model jadi hijau.
		for _, d in ipairs(kuali:GetDescendants()) do
			if d:IsA("BasePart") and (d.Material == Enum.Material.Neon
				or (d.Color.B > d.Color.G * 1.5 and d.Color.B > 0.3)) then
				d.Color, d.Material = HW.hijau, Enum.Material.Neon
			elseif d:IsA("ParticleEmitter") or d:IsA("Light") then
				d:Destroy()
			end
		end
		local pk, uk = batas(kuali)
		local mulut = balok(folder, { Name = "UapKuali", Size = Vector3.new(uk.X * 0.5, 0.1, uk.Z * 0.5),
			Transparency = 1, CFrame = CFrame.new(pk + Vector3.new(0, uk.Y / 2 - 0.1, 0)) })
		lampu(mulut, { Range = 10, Brightness = 1.8, Color = HW.hijau, Shadows = true }, true)
		pemancar(mulut, { Texture = ASAP, LightEmission = 0.4, Rate = 10,
			Lifetime = NumberRange.new(3, 4.5), Speed = NumberRange.new(0.8, 1.2),
			SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, -0.9, 0), Drag = 0.5,
			Size = NumberSequence.new(0.6, 2.4), Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-20, 20),
			Transparency = urutanAlpha({ { 0, 0.5 }, { 1, 1 } }),
			Color = ColorSequence.new(Color3.fromRGB(120, 255, 150)) })
		pemancar(mulut, { Rate = 6, Lifetime = NumberRange.new(0.6, 1),
			Speed = NumberRange.new(0.5, 1), EmissionDirection = Enum.NormalId.Top,
			Size = NumberSequence.new(0.15), Color = ColorSequence.new(HW.hijau) })
	end

	-- ============ SOFA, MEJA LABU, RAK (kanan) ============
	local sofa = aset("Sofa", folder, di(4.6, 0, bz - 0.05), 5.4)
	if sofa then
		-- Beludru ungu: bantalan (bagian yang lebih terang) ungu, rangka
		-- ungu tua.
		for _, d in ipairs(sofa:GetDescendants()) do
			if d:IsA("BasePart") then
				local _, _, terang = d.Color:ToHSV()
				d.Color = terang > 0.3 and HW.beludru or Color3.fromRGB(46, 18, 72)
				d.Material = Enum.Material.Fabric
				if d:IsA("MeshPart") then d.TextureID = "" end
			elseif d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture") then
				d:Destroy()
			end
		end
	end
	local meja = hadap(2.7, 0, 2.4)
	local labuMeja = aset("LabuLucu", folder, meja, 1.5)
	if labuMeja then
		local _, uk = batas(labuMeja)
		local atas = meja * CFrame.new(0, uk.Y + 0.04, 0)
		tabung(folder, atas, 0.08, 1.3, { Name = "PapanMeja", Color = HW.kayu,
			Material = Enum.Material.Glass, Transparency = 0.4 })
		local atasMeja = atas * CFrame.new(0, 0.04, 0)
		tabung(folder, atasMeja * CFrame.new(0.3, 0.09, 0.15), 0.18, 0.55,
			{ Name = "Mangkuk", Color = Color3.fromRGB(120, 50, 170), Material = Enum.Material.Glass })
		local PERMEN = { Color3.fromRGB(255, 80, 120), Color3.fromRGB(80, 220, 255), Color3.fromRGB(255, 230, 60),
			Color3.fromRGB(120, 255, 120), Color3.fromRGB(255, 140, 40) }
		for i = 1, 8 do
			local a, r = i * 2.4, 0.06 + (i % 3) * 0.06
			balok(folder, { Name = "Permen", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.12,
				CFrame = atasMeja * CFrame.new(0.3 + math.cos(a) * r, 0.22 + (i % 2) * 0.05, 0.15 + math.sin(a) * r),
				Color = PERMEN[i % #PERMEN + 1], Material = Enum.Material.SmoothPlastic })
		end
		local cangkir = atasMeja * CFrame.new(-0.35, 0, -0.15)
		lonjong(folder, { Name = "Cangkir", Size = Vector3.new(0.28, 0.26, 0.28),
			CFrame = cangkir * CFrame.new(0, 0.12, 0), Color = Color3.fromRGB(30, 28, 36), Material = Enum.Material.Metal })
		tabung(folder, cangkir * CFrame.new(0, 0.22, 0), 0.03, 0.2,
			{ Name = "Cokelat", Color = Color3.fromRGB(110, 60, 35), Material = Enum.Material.SmoothPlastic })
		local uap = balok(folder, { Name = "Uap", Size = Vector3.new(0.15, 0.1, 0.15), Transparency = 1,
			CFrame = CFrame.new((cangkir * CFrame.new(0, 0.26, 0)).Position) })
		pemancar(uap, { Texture = ASAP, LightEmission = 0.2, Rate = 4,
			Lifetime = NumberRange.new(1.5, 2.2), Speed = NumberRange.new(0.4, 0.7),
			SpreadAngle = Vector2.new(12, 12), EmissionDirection = Enum.NormalId.Top,
			Size = NumberSequence.new(0.12, 0.45),
			Transparency = urutanAlpha({ { 0, 0.6 }, { 1, 1 } }), Color = ColorSequence.new(PUTIH) })
		balok(folder, { Name = "BukuMantra", Size = Vector3.new(0.4, 0.08, 0.3),
			CFrame = atasMeja * CFrame.new(-0.15, 0.04, 0.35) * CFrame.Angles(0, 0.4, 0),
			Color = Color3.fromRGB(90, 40, 120), Material = Enum.Material.Leather })
	else
		labu(folder, meja, 1.5, true)
	end
	aset("RakRamuan", folder, di(4.4, 4.2, bz - 0.05), 2.8, true, math.pi / 2)
	aset("BolaKristal", folder, hadap(3.6, 0, 0.4), 1.9, true)

	-- ============ TUMPUKAN LABU ============
	local function labuNyata(x, y, z, d, putar)
		local m = aset("LabuLucu", folder, hadap(x, y, z) * CFrame.Angles(0, putar or 0, 0), d)
		if not m then labu(folder, hadap(x, y, z), d, true) end
		return m
	end
	-- Di antara perapian dan jendela, bukan di depan api.
	labuNyata(-1.9, 0, 4.7, 1.1)
	labuNyata(-1.9, 0.85, 4.7, 0.75, 0.6)
	labuNyata(-2.6, 0, 3.6, 0.7, -0.4)
	labuNyata(1.9, 0, 4.6, 0.8, 0.3)

	-- ============ KARPET + KUCING (kiri depan, dekat kamera) ============
	local karpet = balok(folder, { Name = "Karpet", Size = Vector3.new(2.2, 0.05, 2.2), Transparency = 1,
		CFrame = di(-1.4, 0.08, -2.2) })
	local sgK = baru("SurfaceGui", { Face = Enum.NormalId.Top,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud, PixelsPerStud = 60, LightInfluence = 1 }, karpet)
	bulat(sgK, 130, 66, 66, Color3.fromRGB(60, 40, 82), 0, 1)
	jaring(sgK, Vector2.new(66, 66), 62, 0, 360, 8, Color3.fromRGB(200, 190, 225), 0, 2)
	local kucing = aset("Kucing", folder, hadap(-1.4, 0.1, -2.2), 1.3)
	if kucing then
		local pk, uk = batas(kucing)
		local titik = balok(folder, { Name = "Zz", Size = Vector3.one * 0.2, Transparency = 1,
			CFrame = CFrame.new(pk + Vector3.new(0, uk.Y / 2 + 0.4, 0)) })
		local zz = baru("BillboardGui", { Size = UDim2.new(0.7, 0, 0.45, 0), LightInfluence = 0 }, titik)
		baru("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "z Z",
			Font = Enum.Font.FredokaOne, TextScaled = true,
			TextColor3 = Color3.fromRGB(220, 200, 255) }, zz)
	end

	-- ============ HANTU BERLENTERA (kanan atas) ============
	local fHantu = baru("Folder", { Name = "Hantu" }, folder)
	local h = hadap(4.2, 7.3, 3.4)
	if aset("Hantu", fHantu, h, 1.9, true) then
		local lentera = h * CFrame.new(0.85, 0.6, -0.3)
		local logam = Color3.fromRGB(40, 34, 44)
		for _, y in ipairs({ 0.22, -0.22 }) do
			balok(fHantu, { Name = "Lentera", Size = Vector3.new(0.3, 0.06, 0.3),
				CFrame = lentera * CFrame.new(0, y, 0), Color = logam, Material = Enum.Material.Metal })
		end
		for _, k in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
			balok(fHantu, { Name = "Lentera", Size = Vector3.new(0.04, 0.4, 0.04),
				CFrame = lentera * CFrame.new(k[1] * 0.13, 0, k[2] * 0.13), Color = logam, Material = Enum.Material.Metal })
		end
		balok(fHantu, { Name = "Lentera", Size = Vector3.new(0.04, 0.2, 0.04),
			CFrame = lentera * CFrame.new(0, 0.34, 0), Color = logam, Material = Enum.Material.Metal })
		local inti = balok(fHantu, { Name = "NyalaLentera", Size = Vector3.new(0.2, 0.34, 0.2),
			CFrame = lentera, Color = HW.nyala, Material = Enum.Material.Neon })
		lampu(inti, { Range = 9, Brightness = 1.6, Color = HW.nyala, Shadows = true }, true)
		goyangkan(fHantu, 0.25, 1.3, 0)
	end

	-- ============ KELELAWAR GANTUNG, UNTAIAN, LILIN MELAYANG ============
	for i, k in ipairs({ { -2.9, 9.8, 3.5, 0.9 }, { 2.4, 10.3, 2.5, 0.8 }, { -5.3, 8.9, 4.6, 0.7 },
		{ 5.3, 10, 4.4, 0.9 } }) do
		local f = baru("Folder", { Name = "Kelelawar" }, folder)
		if aset("Kelelawar", f, hadap(k[1], k[2], k[3]) * CFrame.Angles(0, (i - 2.5) * 0.3, 0), k[4]) then
			goyangkan(f, 0.2, 1 + i * 0.25, i * 1.3)
		end
	end
	-- Untaian daun kering + lampu tumbler di atas jendela. (Model untaian
	-- lampu labu di AsetHalloween menggantung miring diagonal, tidak bisa
	-- dibentangkan mendatar.)
	do
		local DAUN = { Color3.fromRGB(150, 70, 25), Color3.fromRGB(205, 112, 30), Color3.fromRGB(125, 40, 30) }
		for _, ruas in ipairs({ { -6.5, -jx - 0.3 }, { jx + 0.3, 6.5 } }) do
			for i = 0, 10 do
				local f = i / 10
				local x = ruas[1] + (ruas[2] - ruas[1]) * f
				local y = tinggi - 1.1 - 0.6 * math.sin(f * math.pi)
				balok(folder, { Name = "Daun", Size = Vector3.new(0.32, 0.2, 0.04),
					CFrame = di(x, y - 0.1, bz - 0.12) * CFrame.Angles(0, 0, acak:NextNumber(-1.2, 1.2)),
					Color = DAUN[acak:NextInteger(1, 3)], Material = Enum.Material.Fabric })
				if i % 2 == 0 then
					local bola = balok(folder, { Name = "LampuHias", Shape = Enum.PartType.Ball,
						Size = Vector3.one * 0.2, CFrame = di(x, y - 0.25, bz - 0.22),
						Color = (i % 4 == 0) and HW.oranye or HW.ungu, Material = Enum.Material.Neon })
					table.insert(hias, { p = bola, fase = acak:NextNumber(0, 6.28) })
				end
			end
		end
	end
	for i, k in ipairs({ { -3.4, 9.2, 2.5 }, { -1.6, 10.1, 1.5 }, { 1.5, 9.6, 1.2 },
		{ 3.0, 10.4, 3.0 }, { -0.4, 10.8, 3.8 } }) do
		local f = baru("Folder", { Name = "LilinMelayang" }, folder)
		lilin(f, di(k[1], k[2], k[3]), 0.6, 0.2, i % 2 == 1)
		goyangkan(f, 0.15, 0.8 + 0.1 * i, i * 1.7)
	end

	-- Kabut ungu tipis menempel di lantai. Tidak sampai ke depan kamera:
	-- gumpalan sebesar ini di dekat lensa menutupi separuh layar.
	local kabut = balok(folder, { Name = "Kabut", Size = Vector3.new(18, 0.2, 8), Transparency = 1,
		CFrame = di(0, 0.15, 2) })
	pemancar(kabut, { Texture = ASAP, LightEmission = 0.15, Rate = 5,
		Lifetime = NumberRange.new(7, 10), Speed = NumberRange.new(0.1, 0.3),
		SpreadAngle = Vector2.new(80, 80), EmissionDirection = Enum.NormalId.Top,
		Size = NumberSequence.new(3, 5), Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-8, 8),
		Transparency = urutanAlpha({ { 0, 1 }, { 0.3, 0.88 }, { 0.7, 0.9 }, { 1, 1 } }),
		Color = ColorSequence.new(Color3.fromRGB(170, 140, 220)) })

	-- Lampu isi hangat redup dari depan-atas: tanpa ini benda di sudut
	-- yang jauh dari api/lilin hitam pekat.
	lampu(titikLampu("LampuIsi", di(0, 9, -3)), { Range = 24, Brightness = 0.5,
		Color = Color3.fromRGB(255, 200, 160) })
	lampuDepan(folder, kaki)

	-- balok() mematikan bayangan (gaya lain sengaja datar). Di sini semua
	-- benda padat berbayang: itu yang membuat ruangannya terasa 3D, dan
	-- dinding/plafon tanpa bayangan membiarkan cahaya siang menembus.
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.5 and d.Material ~= Enum.Material.Neon then
			d.CastShadow = true
		end
	end

	return { cahayaLed = cahayaLed, goyang = goyang, kelip = kelip, hias = hias,
		pilar = {}, pendar = {}, sinar = {}, cincin = {}, bintang = {} }
end


-- ============ ANIMASI TERUS-MENERUS ============

local function denyut(dt)
	if not L then return end
	local t = os.clock()
	local e = efekKini
	if L.poros then
		L.poros.Rotation = (L.poros.Rotation + e.putar * 0.35 * dt) % 360
	end
	for _, c in ipairs(L.cincin) do
		c.g.Rotation = (c.g.Rotation + e.putar * c.arah * dt) % 360
	end
	for _, p in ipairs(L.pilar) do
		p.p.Transparency = math.clamp(e.pilar
			+ 0.18 * (0.5 + 0.5 * math.sin(t * 2.2 + p.fase)), 0, 0.95)
	end
	for _, b in ipairs(L.bintang) do
		b.f.BackgroundTransparency = 0.35
			+ 0.55 * (0.5 + 0.5 * math.sin(t * b.laju + b.fase))
	end
	-- Halloween: hantu dan lilin melayang, api/lilin berkedip, lampu
	-- tumbler berkelip.
	for _, g in ipairs(L.goyang) do
		local naik = Vector3.new(0, g.amp * math.sin(t * g.laju + g.fase), 0)
		for _, b in ipairs(g.bagian) do b.p.CFrame = b.cf + naik end
	end
	for _, k in ipairs(L.kelip) do
		k.lampu.Brightness = k.dasar * (0.8 + 0.6 * math.noise(t * 5, k.fase))
	end
	for _, h in ipairs(L.hias) do
		h.p.Transparency = 0.1 + 0.5 * (0.5 + 0.5 * math.sin(t * 2 + h.fase))
	end
end

-- ============ API ============

function LatarSolo.pasang(cfg)
	if L then return end
	local kaki = cfg.kaki or Vector3.zero

	local lama = workspace:FindFirstChild("LatarSolo")
	if lama then lama:Destroy() end
	local folder = baru("Folder", { Name = "LatarSolo" }, workspace)

	-- SpawnLocation template berdiri tepat di titik panggung dan
	-- setebal 1 stud: tanpa ini kaki avatarnya terbenam di dalamnya.
	-- Disembunyikan LOKAL saja; tabrakannya tidak dipakai siapa pun
	-- (avatar ditahan BodyPosition, karakter penonton disembunyikan).
	--
	-- Juga yang datang BELAKANGAN: dengan StreamingEnabled, SpawnLocation
	-- baru sampai di client sesudah modul ini jalan, dan gelung sekali
	-- jalan melewatkannya begitu saja.
	local function sembunyikan(b)
		if not b:IsA("SpawnLocation") then return end
		local function tembus(d)
			if d:IsA("Decal") or d:IsA("Texture") then d.Transparency = 1 end
		end
		b.Transparency = 1
		b.CastShadow = false
		for _, d in ipairs(b:GetDescendants()) do tembus(d) end
		b.DescendantAdded:Connect(tembus)
	end
	for _, b in ipairs(workspace:GetDescendants()) do sembunyikan(b) end
	-- Grid Baseplate juga, untuk jaga-jaga di sudut yang masih tembus.
	local dasar = workspace:FindFirstChild("Baseplate")
	if dasar then
		for _, d in ipairs(dasar:GetChildren()) do
			if d:IsA("Texture") or d:IsA("Decal") then d.Transparency = 1 end
		end
	end
	workspace.DescendantAdded:Connect(sembunyikan)

	L = {}
	local atas, titikKembang
	if GAYA == "ruangan" or GAYA == "halloween" then
		local kamera = typeof(cfg.kamera) == "CFrame" and cfg.kamera.Position
			or kaki + Vector3.new(0, 2.6, -9)
		local isi = (GAYA == "halloween") and bangunHalloween(folder, kaki, kamera)
			or bangunRuangan(folder, kaki)
		for k, v in pairs(isi) do L[k] = v end
		atas = RUANG_TINGGI - 0.6
		titikKembang = Vector3.new(0, 8, RUANG_BELAKANG_Z - 1.5)
	else
		for k, v in pairs(bangunDinding(folder, kaki)) do L[k] = v end
		for k, v in pairs(bangunPanggung(folder, kaki)) do L[k] = v end
		atas = 15
		titikKembang = Vector3.new(0, 11, 9)
	end
	for k, v in pairs(bangunPartikel(folder, kaki, atas, titikKembang)) do L[k] = v end
	-- Cuma gaya halloween yang punya benda bergerak; gaya lain kosong.
	L.goyang, L.kelip, L.hias = L.goyang or {}, L.kelip or {}, L.hias or {}
	L.tahan = tonumber(cfg.tahan) or 4

	RunService.Heartbeat:Connect(denyut)
end

-- Yang tidak ada di gaya latar ini (nil, atau tabel kosong) dilewati.
local function warnai(tema, detik)
	if L.langit then gerak(L.langit, detik, { BackgroundColor3 = tema.b }) end
	if L.cakrawala then gerak(L.cakrawala, detik, { BackgroundColor3 = tema.a }) end
	if L.tepi then gerak(L.tepi, detik, { Color = tema.a }) end
	if L.led then
		gerak(L.led, detik, { Color = tema.a })
		gerak(L.cahayaLed, detik, { Color = tema.a })
	end
	for _, f in ipairs(L.pendar) do
		gerak(f, detik, { BackgroundColor3 = tema.a })
	end
	for _, s in ipairs(L.sinar) do
		gerak(s, detik, { BackgroundColor3 = tema.a })
	end
	for _, c in ipairs(L.cincin) do
		gerak(c.garis, detik, { Color = tema.a })
	end
	for _, p in ipairs(L.pilar) do
		gerak(p.p, detik, { Color = (p.fase % 2 < 1) and tema.a or tema.b })
		gerak(p.lampu, detik, { Color = tema.a })
	end
	L.debu.Color = ColorSequence.new(tema.a, tema.b)
	local warna = { tema.a, tema.b, PUTIH }
	for i, k in ipairs(L.konfeti) do k.Color = ColorSequence.new(warna[i]) end
end

-- Satu ledakan kembang api di titik acak di atas kepala.
local function ledak(tema)
	local x = math.random(-60, 60) / 10
	local y = math.random(0, 40) / 10
	L.kotakKembang.CFrame = CFrame.new(L.kembangDasar + Vector3.new(x, y, 0))
	local pilihan = { tema.a, tema.b, PUTIH }
	L.kembang.Color = ColorSequence.new(pilihan[math.random(1, 3)],
		pilihan[math.random(1, 3)])
	L.kembang:Emit(70)
	getarSampai, getarMulai, getarKuat = os.clock() + 0.25, os.clock(), 0.05
end

function LatarSolo.datang(d)
	if not L or type(d) ~= "table" then return end
	local tier = math.clamp(math.floor(tonumber(d.tier) or 1), 1, 5)
	local tema, e = TEMA[tier], EFEK[tier]
	gen += 1
	local saya = gen
	efekKini = e

	warnai(tema, 0.5)
	L.debu.Rate = e.debu

	-- Kilat: pendar dan pilar menyala penuh sesaat, lalu turun.
	for i, f in ipairs(L.pendar) do
		f.BackgroundTransparency = 0.3
		gerak(f, 0.9, { BackgroundTransparency = 0.93 - i * 0.07 })
	end
	for _, s in ipairs(L.sinar) do
		s.BackgroundTransparency = math.min(e.sinar, 0.3)
		gerak(s, 1.2, { BackgroundTransparency = e.sinar })
	end
	if L.cahayaLed then
		L.cahayaLed.Brightness = 6
		gerak(L.cahayaLed, 1, { Brightness = 2 })
	end

	if e.getar > 0 then
		getarSampai, getarMulai, getarKuat = os.clock() + 0.7, os.clock(), e.getar
	end

	local lama = tonumber(d.lama) or 0
	if lama <= 0 then lama = L.tahan end

	for _, k in ipairs(L.konfeti) do k.Enabled = e.konfeti end

	if e.kembang > 0 then
		task.spawn(function()
			local sampai = os.clock() + lama - 0.5
			while gen == saya and os.clock() < sampai do
				ledak(tema)
				task.wait(e.kembang * (0.6 + math.random() * 0.8))
			end
		end)
	end

	-- Sesudah tampilnya habis, yang ramai berhenti sendiri -- kecuali
	-- kedatangan berikutnya sudah mengambil alih.
	task.delay(lama, function()
		if gen ~= saya then return end
		for _, k in ipairs(L.konfeti) do k.Enabled = false end
	end)
end

function LatarSolo.getar()
	local t = os.clock()
	if t >= getarSampai then return Vector3.zero end
	local sisa = (getarSampai - t) / math.max(getarSampai - getarMulai, 0.01)
	local k = getarKuat * sisa
	return Vector3.new((math.random() - 0.5) * 2 * k,
		(math.random() - 0.5) * 2 * k, 0)
end

return LatarSolo
