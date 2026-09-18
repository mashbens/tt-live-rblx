--[[
	TierNova  --  efek kedatangan nova (tier 4, Bouquet Flower): PRISMATIC STARFALL
	Di Studio: ReplicatedStorage.TierNova (ModuleScript). Disinkron Rojo dari
	file ini -- `make rojo`. NAMA-nya harus persis "TierNova".

	Yang memakainya KameraClientV2 (LocalScript). Server tidak pernah
	me-require modul ini: server cuma mengirim V2Event "nova" berisi model,
	seed, palet, dan setelan -- lihat NOVA di AvatarQueueV2.

	Modul ini menggantikan TierDash. Nomor tier-nya sengaja TIDAK ada di
	nama: tier mana yang memakai nova diputuskan NOVA.TIER di server, bukan
	nama modul ini. Alasannya sudah pernah terbukti mahal di file ini --
	lihat adalahRaksasa di AvatarQueueV2.

	TIMELINE (10 detik, tiap fase bisa ditimpa lewat config)

	  0,0 - 4,0   CHARGING      letterbox masuk, FOV menyempit pelan, badan
	                            melayang naik 7 stud, orb mengorbit + beam,
	                            rune berputar di lantai, partikel naik
	  4,0 - 5,5   ASCENSION     naik ke 13 stud, orb jadi mahkota di atas
	                            kepala, lingkaran rune melebar dan cepat,
	                            dan badannya melintas ke titik tempat dia
	                            akan mendarat (config.tujuan)
	  5,5 - 6,5   TIME FREEZE   orb tersedot ke dada, kilatan membesar,
	                            layar jadi abu-abu dan buram (slow-mo)
	  6,5 - 6,8   STARFALL      banting ke tanah di config.tujuan, FOV
	                            menyempit tajam
	  6,8 - 10,0  IMPACT        shell, tiga shockwave, pilar cahaya, petir,
	                            kristal melayang lalu jatuh, aftershock
	                            kedua, warna pulih, letterbox keluar

	KAMERA DAN LAYAR BUKAN MILIK MODUL INI

	Aslinya efek ini menulis camera.FieldOfView dan humanoid.CameraOffset
	langsung. Keduanya tidak bisa dipakai di panggung ini:

	  - kameranya dipegang penuh gelung render KameraClientV2, dan
	    dua penulis untuk satu kamera berarti yang satu membatalkan yang
	    lain di frame berikutnya
	  - CameraOffset cuma berlaku untuk Humanoid milik pemain lokal. Avatar
	    di panggung ini NPC, jadi baris itu tidak melakukan apa pun

	Jadi keduanya jadi CALLBACK yang diisi client: cfg.fov, cfg.getar, dan
	cfg.pandang. Yang tidak diisi dilewati diam-diam -- modulnya tetap
	jalan (tanpa gerak kamera) kalau dipanggil dari tempat lain.

	PEMAKAIAN

		local TierNova = require(ReplicatedStorage.TierNova)
		local janji = TierNova.Play(salinan, {
			seed  = 12345,      -- sama di semua client = pola sama
			palet = { nama = "prisma", warna = { {255,120,220}, ... } },
		})
		local berhasil = janji:Await()   -- memblokir sampai efeknya habis

	Bentuk nilai kembaliannya sama persis dengan TierDash dulu, supaya
	pemanggil di KameraClientV2 tidak perlu tahu modul mana yang
	sedang dipakai:
		janji:Await()     -> true kalau selesai normal, false kalau batal
		janji:Cancel()    -> hentikan sekarang, bersihkan semuanya
		janji.Completed   -> RBXScriptSignal, menyala sekali dengan (berhasil)
		janji.Done        -> boolean
--]]

local TierNova = {}

-- `game` tidak ada waktu file ini dimuat test_tier.py (Lua biasa, di luar
-- Roblox). Yang diuji di sana cuma fungsi murni -- Total dan Jadwal --
-- jadi service-nya boleh nil selama Play tidak dipanggil.
local TweenService, RunService, Debris, Lighting, SoundService
if game then
	TweenService = game:GetService("TweenService")
	RunService   = game:GetService("RunService")
	Debris       = game:GetService("Debris")
	Lighting     = game:GetService("Lighting")
	SoundService = game:GetService("SoundService")
end

-- ============ SETELAN BAWAAN ============
--
-- Semua bisa ditimpa lewat argumen `config` di Play. Lima yang pertama
-- LAMA TIAP FASE dalam detik, dan jumlahnya = lama seluruh adegan. Server
-- mengirim kelimanya apa adanya (NOVA.CONFIG) supaya "berapa lama nova
-- berlangsung" cuma punya SATU jawaban: yang di server, yang sama yang
-- dipakai menghitung auraMulai dan lama sorotan.
TierNova.DEFAULTS = {
	charge = 4.0,   -- mengisi tenaga, melayang naik pelan
	ascend = 1.5,   -- naik lebih tinggi, orb jadi mahkota
	freeze = 1.0,   -- orb tersedot, layar membeku
	slam   = 0.3,   -- banting ke tanah
	impact = 3.2,   -- ledakan slow-mo sampai warnanya pulih

	-- Berapa tinggi badannya melayang di tiap fase, stud.
	naikCharge = 7,
	naikAscend = 13,

	-- Di mana dia MENDARAT: CFrame (atau Vector3) titik pivot badannya
	-- waktu dia menyentuh tanah lagi. nil = di tempat dia mulai.
	--
	-- Dipakai panggung ini untuk memindahkannya ke barisan paling depan:
	-- hantamannya menyapu seluruh barisan, jadi sesudah itu dia yang
	-- berdiri di slot 1. Perpindahan mendatarnya terjadi selama ASCEND
	-- -- di ketinggian, jauh dari kepala orang lain -- lalu SLAM
	-- menjatuhkannya lurus ke bawah di titik yang baru.
	--
	-- Yang TIDAK ikut pindah: partikel lantai fase charge. Dia penanda
	-- tempat upacaranya dimulai, dan hantamannya toh menyapu panggung.
	tujuan = nil,

	orbCount   = 6,
	runeCount  = 32,
	shardCount = 20,
	boltCount  = 8,

	-- Efek SELURUH LAYAR: letterbox hitam atas-bawah, layar abu-abu waktu
	-- time-freeze, bloom, blur. Dia yang membuat fase freeze terbaca
	-- sebagai waktu berhenti dan bukan cuma sebagai orb yang hilang.
	--
	-- Satu saklar untuk keempatnya: mereka satu gagasan (ini adegan
	-- sinema, bukan kedatangan biasa), dan menyalakan separuhnya
	-- menghasilkan layar yang setengah berkomitmen.
	layar = true,

	-- Tinggi tiap bilah letterbox, pecahan tinggi layar.
	letterbox = 0.12,

	-- Seberapa jauh FOV ditarik di tiap fase, derajat. Relatif terhadap
	-- FOV yang sedang berlaku waktu adegannya mulai -- angka mutlak akan
	-- menabrak zoom kamera panggung yang punya FOV-nya sendiri.
	fovCharge =  -12,
	fovSlam   =  -20,
	fovImpact =  20,
}

-- --- PALET ---
--
-- Diundi satu dari tiga tiap kedatangan, SERVER yang mengundi (lihat
-- NOVA.PALET di AvatarQueueV2) dan hasilnya dikirim ke semua client --
-- jadi satu orang tampil dengan warna yang sama di tiap layar.
--
-- Alasannya sama dengan AURA_VFX_IDS: dua orang yang sama-sama kirim 10
-- koin harus tampil berbeda, kalau tidak efeknya berhenti diperhatikan
-- sesudah beberapa kedatangan. Warna yang selalu sama jadi latar.
--
-- Bentuknya TRIPLET RGB biasa, bukan Color3: tabel ini menyeberangi
-- RemoteEvent dan ikut dibaca test_tier.py di Lua biasa, dan keduanya
-- lebih murah kalau isinya angka. Color3-nya dibuat di sini, sekali.
TierNova.PALET_BAWAAN = {
	{ 255, 120, 220 }, { 120, 200, 255 }, { 180, 120, 255 },
	{ 255, 220, 130 }, { 130, 255, 200 },
}

local TEX = {
	spark = "rbxasset://textures/particles/sparkles_main.dds",
	fire  = "rbxasset://textures/particles/fire_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}

-- Nama efek Lighting yang dibuat adegan ini. Diberi awalan supaya tidak
-- pernah tertukar dengan VisualBloom/VisualDOF milik setelan panggung --
-- yang itu hidup selama sesi, yang ini mati waktu adegannya habis.
local NAMA_CC    = "NovaColorCorrection"
local NAMA_BLOOM = "NovaBloom"
local NAMA_BLUR  = "NovaBlur"
local NAMA_GUI   = "NovaLetterbox"

-- ============ FUNGSI MURNI (diuji di test_tier.py) ============

local function gabung(config)
	local hasil = {}
	for k, v in pairs(TierNova.DEFAULTS) do hasil[k] = v end
	if type(config) == "table" then
		for k, v in pairs(config) do hasil[k] = v end
	end
	return hasil
end

-- Lama SELURUH adegan, detik.
--
-- Dipakai tiga tempat yang harus sepakat: penjadwalan di server
-- (auraMulai dan lama sorotan), batas tahan di client, dan test_tier.py.
-- Satu fungsi supaya penjumlahan yang sama tidak ditulis tiga kali.
function TierNova.Total(config)
	local c = gabung(config)
	return c.charge + c.ascend + c.freeze + c.slam + c.impact
end

-- Kapan tiap fase MULAI, detik sejak adegannya mulai.
--
-- Yang paling penting `mendarat`: di detik itu badannya menyentuh tanah
-- lagi, dan itu satu-satunya momen yang dibaca dari luar modul ini --
-- bunyi kedatangannya dibunyikan di sana.
function TierNova.Jadwal(config)
	local c = gabung(config)
	local j = {}
	j.charge   = 0
	j.ascend   = j.charge + c.charge
	j.freeze   = j.ascend + c.ascend
	j.slam     = j.freeze + c.freeze
	j.mendarat = j.slam + c.slam
	j.selesai  = j.mendarat + c.impact
	return j
end

-- Park-Miller. Sama persis dengan yang dipakai TierDash dulu, dan
-- alasannya juga sama: Random milik Roblox tidak ada di test_tier.py yang
-- jalan di Lua biasa, dan 48271 x (2^31 - 1) masih di bawah 2^53 -- jadi
-- perkaliannya tepat tanpa pembulatan yang bisa berbeda antar mesin.
local function buatAcak(seed)
	local s = math.floor(math.abs(tonumber(seed) or 1)) % 2147483647
	if s == 0 then s = 1 end

	local acak = {}
	function acak.angka()
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
	-- Pemanasan: angka pertama Park-Miller hampir sebanding lurus dengan
	-- seed-nya, jadi seed kecil selalu menghasilkan angka kecil.
	for _ = 1, 6 do acak.angka() end
	function acak.antara(a, b) return a + (b - a) * acak.angka() end
	return acak
end

-- ============ HELPER ROBLOX ============

local function kp(t, v) return NumberSequenceKeypoint.new(t, v) end
local function lerp(a, b, t) return a + (b - a) * t end

local function warnaDari(triplet)
	return Color3.fromRGB(triplet[1], triplet[2], triplet[3])
end

local function cariRoot(model)
	return model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
		or model:FindFirstChildWhichIsA("BasePart")
end

-- ============ PLAY ============

function TierNova.Play(model, config)
	local cfg = gabung(config)

	local selesaiEvent = Instance.new("BindableEvent")
	local janji = { Done = false, Success = nil, Completed = selesaiEvent.Event }

	local tertutup = false
	local conn     = nil
	local folder   = nil
	local gui      = nil
	local efek     = {}   -- ColorCorrection/Bloom/Blur yang dibuat adegan ini
	local suara    = {}   -- semua Sound yang dibuat adegan ini
	local gelung   = {}   -- yang looped, dihentikan waktu fasenya habis
	local tweens   = {}   -- semua tween yang masih boleh dibatalkan
	local poseAsli = {}   -- Motor6D -> C0 semula
	local root, hum
	local anchoredAsli, platformAsli

	local function tween(obj, lama, props, style, dir)
		if tertutup then return nil end
		local tw = TweenService:Create(obj, TweenInfo.new(lama,
			style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
			props)
		tweens[#tweens + 1] = tw
		tw:Play()
		return tw
	end

	local function tutup(berhasil, alasan)
		if tertutup then return end
		tertutup = true

		if conn then conn:Disconnect() end
		for _, tw in ipairs(tweens) do pcall(function() tw:Cancel() end) end

		-- Pose dikembalikan LANGSUNG, bukan di-tween: kalau adegannya
		-- batal (panggung di-reset), salinannya dihapus di baris
		-- berikutnya juga -- dan tween ke part yang sudah tidak ada
		-- meninggalkan peringatan di output tiap kali.
		for m, c0 in pairs(poseAsli) do
			if m.Parent then m.C0 = c0 end
		end
		if root and root.Parent and anchoredAsli ~= nil then
			root.Anchored = anchoredAsli
		end
		if hum and hum.Parent and platformAsli ~= nil then
			hum.PlatformStand = platformAsli
		end

		-- Layar HARUS pulih walau adegannya batal di tengah. Ini bagian
		-- yang paling tidak boleh gagal diam-diam: letterbox atau layar
		-- abu-abu yang tertinggal tidak menempel di satu avatar, dia
		-- menempel di SELURUH siaran sampai client-nya restart.
		if gui then pcall(function() gui:Destroy() end) end
		for _, e in ipairs(efek) do pcall(function() e:Destroy() end) end

		-- Bunyinya HARUS ikut mati, dan ini yang paling tidak boleh
		-- gagal diam-diam: isyarat charge itu Looped. Satu adegan yang
		-- dibatalkan tanpa baris ini meninggalkan dengungan yang
		-- berputar sampai client-nya restart -- di TIAP layar penonton,
		-- dan tidak ada apa pun di layar yang menjelaskan asalnya.
		for _, sn in ipairs(suara) do
			pcall(function() sn:Stop() end)
			pcall(function() sn:Destroy() end)
		end
		if cfg.fov then pcall(cfg.fov, 0, berhasil and 0.4 or 0) end
		if cfg.getar then pcall(cfg.getar, 0, 0) end

		-- Yang selesai NORMAL meninggalkan VFX-nya memudar sendiri --
		-- kristal masih jatuh dan asap masih mengembang di detik
		-- avatarnya muncul kembali. Yang BATAL membawa semuanya pergi
		-- sekarang: panggung di-reset, dan ledakan yang mengambang di
		-- atas slot kosong tidak menjelaskan apa pun.
		if folder then
			if berhasil then
				Debris:AddItem(folder, 4)
			else
				pcall(function() folder:Destroy() end)
			end
		end

		if alasan and not berhasil then
			warn("[TierNova] berhenti: " .. tostring(alasan))
		end

		janji.Done = true
		janji.Success = berhasil and true or false
		selesaiEvent:Fire(janji.Success)
		task.defer(function() selesaiEvent:Destroy() end)
	end

	function janji:Await()
		if not self.Done then selesaiEvent.Event:Wait() end
		return self.Success
	end

	function janji:Cancel() tutup(false, nil) end

	root = model and cariRoot(model)
	if not root then
		task.defer(tutup, false, "model tanpa root part")
		return janji
	end
	hum = model:FindFirstChildOfClass("Humanoid")

	-- Warna adegan ini. Server mengirim palet yang sudah diundi; kalau
	-- pesannya tidak membawa apa-apa, palet bawaan dipakai -- efeknya
	-- tetap jalan, cuma tidak ikut berganti warna.
	local triplet = (type(cfg.palet) == "table" and cfg.palet.warna)
		or TierNova.PALET_BAWAAN
	local P = {}
	for i, t in ipairs(triplet) do P[i] = warnaDari(t) end
	if #P == 0 then
		for i, t in ipairs(TierNova.PALET_BAWAAN) do P[i] = warnaDari(t) end
	end
	local function warna(i) return P[((i - 1) % #P) + 1] end

	local PELANGI = ColorSequence.new({
		ColorSequenceKeypoint.new(0.00, warna(1)),
		ColorSequenceKeypoint.new(0.25, warna(2)),
		ColorSequenceKeypoint.new(0.50, warna(3)),
		ColorSequenceKeypoint.new(0.75, warna(4)),
		ColorSequenceKeypoint.new(1.00, warna(5)),
	})

	local acak = buatAcak(cfg.seed)

	-- Model yang dihapus di tengah adegan (panggung di-reset) membawa
	-- adegannya pergi. Tanpa ini, gelung RenderStepped di bawah terus
	-- membaca root yang sudah tidak punya induk.
	local putus = model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(workspace) then tutup(false) end
	end)

	local function newPart(props, induk)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		for k, v in pairs(props) do p[k] = v end
		p.Parent = induk
		return p
	end

	local function emitter(induk, props)
		local e = Instance.new("ParticleEmitter")
		e.Rate = 0
		e.LightEmission = 1
		for k, v in pairs(props) do e[k] = v end
		e.Parent = induk
		return e
	end

	-- Petir: rantai segmen lurus yang digoyang acak di tiap sambungan.
	-- Goyangannya dari `acak`, bukan math.random, supaya sambaran yang
	-- sama muncul di semua layar.
	local function petir(dari, ke, c, induk, pudar)
		local segmen, prev = 9, dari
		for i = 1, segmen do
			local pt = dari:Lerp(ke, i / segmen)
			if i < segmen then
				pt = pt + Vector3.new(acak.angka() - 0.5, acak.angka() - 0.5,
					acak.angka() - 0.5) * 3
			end
			local panjang = (pt - prev).Magnitude
			local seg = newPart({
				Size = Vector3.new(0.3, 0.3, panjang),
				CFrame = CFrame.lookAt(prev, pt) * CFrame.new(0, 0, -panjang / 2),
				Color = c,
			}, induk)
			tween(seg, pudar, { Transparency = 1, Size = Vector3.new(0, 0, panjang) })
			prev = pt
		end
	end

	-- Getar kamera lewat callback client. Tanpa callback (dipanggil dari
	-- luar panggung ini) baris ini tidak melakukan apa-apa, dan itu
	-- memang benar: tidak ada kamera yang boleh digetarkan modul ini.
	local function getar(lama, kuat)
		if cfg.getar then pcall(cfg.getar, lama, kuat) end
	end

	local function fov(delta, lama, style, dir)
		if cfg.fov then pcall(cfg.fov, delta, lama, style, dir) end
	end

	-- --- BUNYI PER FASE ---
	--
	-- Dimainkan DARI SINI, bukan dijadwalkan pemanggilnya: modul ini
	-- satu-satunya yang tahu kapan tiap fase benar-benar mulai. Bunyi
	-- yang dijadwalkan dari luar meleset sebanyak tunggu aset avatarnya
	-- (SPAWN_SIAP_MAKS), dan setengah detik pada dentuman ledakan
	-- terdengar seperti bunyi milik kejadian lain.
	local function mainkanFase(nama, lama)
		-- Isyarat looped milik fase SEBELUMNYA dihentikan di sini.
		-- Dipudarkan, bukan dipotong: dengungan yang berhenti mendadak
		-- terdengar seperti bunyi yang putus, bukan seperti bunyi yang
		-- selesai.
		for _, sn in ipairs(gelung) do
			if sn.Parent then
				tween(sn, 0.15, { Volume = 0 })
				local pergi = sn
				task.delay(0.2, function()
					pcall(function() pergi:Stop() end)
				end)
			end
		end
		gelung = {}

		local daftar = cfg.sfx
		if type(daftar) ~= "table" then return end

		for _, c in ipairs(daftar) do
			if c.fase == nama and c.id and c.id ~= "" then
				local tunda = math.max(tonumber(c.tunda) or 0, 0)
				local function bunyikan()
					if tertutup then return end
					local sn = Instance.new("Sound")
					sn.Name          = "Nova_" .. nama
					sn.SoundId       = c.id
					sn.Volume        = tonumber(c.vol) or 0.6
					sn.PlaybackSpeed = math.max(tonumber(c.nada) or 1, 0.05)
					sn.Looped        = c.ulang and true or false
					-- SoundService, jadi dia tidak punya posisi di dunia:
					-- sama kerasnya di mana pun kamera berada. Alasannya
					-- sama dengan bunyi aura di KameraClientV2 --
					-- dan di sini lebih penting lagi, karena kameranya
					-- berpindah jauh empat kali selama adegan ini.
					sn.Parent        = SoundService
					suara[#suara + 1] = sn
					if sn.Looped then gelung[#gelung + 1] = sn end
					sn:Play()

					-- Nada yang MELUNCUR sepanjang fasenya. Ini yang
					-- membuat dengungan charge terbaca sebagai tenaga
					-- yang dikumpulkan, bukan sebagai nada yang diam.
					local akhir = tonumber(c.nadaAkhir)
					if akhir and lama and lama > 0 then
						tween(sn, lama, { PlaybackSpeed = akhir },
							Enum.EasingStyle.Linear)
					end
				end

				if tunda > 0 then
					task.delay(tunda, bunyikan)
				else
					bunyikan()
				end
			end
		end
	end

	local function pose(pengali, lama)
		local ARM = {
			["Right Shoulder"] = CFrame.Angles(0, 0, math.rad(70)),
			["Left Shoulder"]  = CFrame.Angles(0, 0, math.rad(-70)),
			["RightShoulder"]  = CFrame.Angles(0, 0, math.rad(70)),
			["LeftShoulder"]   = CFrame.Angles(0, 0, math.rad(-70)),
		}
		for nama, rot in pairs(ARM) do
			local m = model:FindFirstChild(nama, true)
			if m and m:IsA("Motor6D") then
				-- C0 semula dicatat SEKALI. pose() dipanggil dua kali
				-- (charge lalu ascend), dan mencatat ulang di panggilan
				-- kedua akan menyimpan pose yang sudah terangkat sebagai
				-- "asli" -- lengannya tidak pernah turun lagi.
				if poseAsli[m] == nil then poseAsli[m] = m.C0 end
				local rx, ry, rz = rot:ToOrientation()
				tween(m, lama, { C0 = m.C0 * CFrame.fromOrientation(
					rx * pengali, ry * pengali, rz * pengali) },
					Enum.EasingStyle.Back)
			end
		end
	end

	-- Menunggu yang IKUT BATAL. task.wait biasa tetap kembali sesudah
	-- waktunya habis walau adegannya sudah ditutup di tengah, dan
	-- sisa fungsinya lanjut membangun VFX di atas model yang sudah pergi.
	local function tunggu(detik)
		local t0 = os.clock()
		while os.clock() - t0 < detik do
			if tertutup then return false end
			RunService.Heartbeat:Wait()
		end
		return not tertutup
	end

	-- Animasi angka manual (memblokir). fn menerima alpha 0..1.
	local function animasi(lama, fn, style, dir)
		local t0 = os.clock()
		while true do
			if tertutup then return false end
			local a = math.min((os.clock() - t0) / lama, 1)
			fn(TweenService:GetValue(a, style or Enum.EasingStyle.Sine,
				dir or Enum.EasingDirection.InOut))
			if a >= 1 then break end
			RunService.Heartbeat:Wait()
		end
		return true
	end

	local function jalankan()
		folder = Instance.new("Folder")
		folder.Name = "NovaVFX"
		folder.Parent = workspace

		local asalCF = root.CFrame

		-- Titik mendaratnya. Tanpa cfg.tujuan dia kembali ke tempat dia
		-- mulai -- perilaku modul ini sebelum panggung memindahkannya,
		-- dan yang masih benar kalau modul ini dipanggil dari tempat
		-- lain.
		local tujuanCF = asalCF
		if typeof(cfg.tujuan) == "CFrame" then
			tujuanCF = cfg.tujuan
		elseif typeof(cfg.tujuan) == "Vector3" then
			tujuanCF = CFrame.new(cfg.tujuan)
		end

		local kakiY  = 0
		if hum then
			local ok, h = pcall(function()
				return hum.HipHeight + root.Size.Y / 2
			end)
			if ok and h then kakiY = h end
		end
		-- DUA titik lantai, dan bedanya penting: yang pertama tempat
		-- upacaranya dimulai (partikel naik dari sana), yang kedua
		-- tempat seluruh ledakannya terjadi.
		local tanahAsal = asalCF.Position - Vector3.new(0, kakiY, 0)
		local tanah     = tujuanCF.Position - Vector3.new(0, kakiY, 0)

		-- --- LAYAR: letterbox, warna, bloom, blur ---
		--
		-- Dibuat di awal dan dibersihkan tutup(), termasuk kalau
		-- adegannya batal. Lihat catatan di tutup().
		local cc, bloom, blur
		if cfg.layar then
			cc = Instance.new("ColorCorrectionEffect")
			cc.Name = NAMA_CC
			cc.Parent = Lighting
			bloom = Instance.new("BloomEffect")
			bloom.Name = NAMA_BLOOM
			bloom.Intensity, bloom.Size, bloom.Threshold = 0, 24, 0.95
			bloom.Parent = Lighting
			blur = Instance.new("BlurEffect")
			blur.Name = NAMA_BLUR
			blur.Size = 0
			blur.Parent = Lighting
			efek = { cc, bloom, blur }

			if cfg.induk then
				gui = Instance.new("ScreenGui")
				gui.Name = NAMA_GUI
				gui.IgnoreGuiInset, gui.ResetOnSpawn = true, false
				gui.DisplayOrder = 50
				local bilah = {}
				for i, jangkar in ipairs({ 0, 1 }) do
					local f = Instance.new("Frame")
					f.BackgroundColor3, f.BorderSizePixel = Color3.new(0, 0, 0), 0
					f.AnchorPoint = Vector2.new(0, jangkar)
					f.Position = UDim2.fromScale(0, jangkar)
					f.Size = UDim2.fromScale(1, 0)
					f.Parent = gui
					bilah[i] = f
				end
				gui.Parent = cfg.induk
				for _, b in ipairs(bilah) do
					tween(b, 0.8, { Size = UDim2.fromScale(1, cfg.letterbox) })
				end
				-- Ditutup lebih cepat daripada dibuka: adegannya sudah
				-- selesai, dan bilah hitam yang berlama-lama sesudah itu
				-- terbaca sebagai layar yang nyangkut.
				task.delay(TierNova.Total(cfg) - 0.6, function()
					if tertutup then return end
					for _, b in ipairs(bilah) do
						tween(b, 0.6, { Size = UDim2.fromScale(1, 0) })
					end
				end)
			end

			tween(cc, cfg.charge, { TintColor = Color3.fromRGB(220, 205, 255),
				Contrast = 0.15, Saturation = 0.35 })
			tween(bloom, cfg.charge, { Intensity = 0.6 })
		end
		fov(cfg.fovCharge, cfg.charge, Enum.EasingStyle.Sine)

		-- ================= FASE 1: CHARGING =================
		mainkanFase("charge", cfg.charge)
		pose(1, 0.8)
		anchoredAsli = root.Anchored
		root.Anchored = true
		if hum then
			platformAsli = hum.PlatformStand
			hum.PlatformStand = true
		end
		tween(root, cfg.charge,
			{ CFrame = asalCF + Vector3.new(0, cfg.naikCharge, 0) },
			Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)

		local inti = Instance.new("Attachment")
		inti.Parent = root

		-- Outline supaya avatarnya tetap terbaca di tengah efek. Tanpa
		-- ini badannya hilang di dalam cahayanya sendiri, dan yang
		-- ditonton jadi partikelnya -- bukan orang yang membayar.
		local sorot = Instance.new("Highlight")
		sorot.FillColor, sorot.FillTransparency = Color3.new(1, 1, 1), 1
		sorot.OutlineColor, sorot.OutlineTransparency = Color3.new(1, 1, 1), 1
		sorot.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		sorot.Parent = model
		tween(sorot, 0.8, { OutlineTransparency = 0.1, FillTransparency = 0.9 })

		-- "Cangkang" tak terlihat: partikelnya lahir DI SEKITAR badan,
		-- bukan di dalamnya.
		local cangkang = newPart({
			Anchored = false, Massless = true, Transparency = 1,
			Size = Vector3.new(7, 8, 7), CFrame = root.CFrame,
		}, folder)
		local las = Instance.new("WeldConstraint")
		las.Part0, las.Part1 = root, cangkang
		las.Parent = cangkang

		local aura = emitter(cangkang, {
			Texture = TEX.spark, Color = PELANGI, Rate = 20,
			Shape = Enum.ParticleEmitterShape.Sphere,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward,
			Size = NumberSequence.new({ kp(0, 0.8), kp(1, 0) }),
			Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(1, 3),
			Drag = 2,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-180, 180),
		})
		local api = emitter(cangkang, {
			Texture = TEX.fire, Rate = 12,
			Shape = Enum.ParticleEmitterShape.Cylinder,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
			ZOffset = -3,   -- digambar DI BELAKANG badan
			Color = ColorSequence.new(warna(3), warna(2)),
			Size = NumberSequence.new({ kp(0, 2), kp(1, 0) }),
			Transparency = NumberSequence.new({ kp(0, 0.6), kp(1, 1) }),
			Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(1, 3),
			Acceleration = Vector3.new(0, 10, 0),
		})

		local lampu = Instance.new("PointLight")
		lampu.Color, lampu.Brightness, lampu.Range = warna(3), 1.5, 0
		lampu.Parent = root
		tween(lampu, cfg.charge, { Range = 16 })

		-- Partikel naik dari tanah.
		local lantai = newPart({ Size = Vector3.new(14, 0.2, 14),
			Transparency = 1, CFrame = CFrame.new(tanahAsal) }, folder)
		local naik = emitter(lantai, {
			Texture = TEX.spark, Color = PELANGI, Rate = 0,
			Size = NumberSequence.new({ kp(0, 0), kp(0.3, 0.8), kp(1, 0) }),
			Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(4, 9),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(10, 10),
		})
		tween(naik, 2, { Rate = 60 })

		local rune = {}
		for i = 1, cfg.runeCount do
			local r = newPart({ Size = Vector3.new(0.3, 0.15, 1.6),
				Color = warna(i + 1), Transparency = 1 }, folder)
			tween(r, 1.5, { Transparency = 0.1 })
			rune[i] = r
		end

		local orb = {}
		for i = 1, cfg.orbCount do
			local c = warna(i)
			local o = newPart({ Shape = Enum.PartType.Ball,
				Size = Vector3.zero, Color = c, CFrame = root.CFrame }, folder)
			task.delay(i * 0.25, function()
				if not tertutup then
					tween(o, 0.5, { Size = Vector3.one * 1.2 },
						Enum.EasingStyle.Back)
				end
			end)

			local atas   = Instance.new("Attachment")
			local bawah  = Instance.new("Attachment")
			local tengah = Instance.new("Attachment")
			atas.Position, bawah.Position = Vector3.new(0, 0.5, 0),
				Vector3.new(0, -0.5, 0)
			atas.Parent, bawah.Parent, tengah.Parent = o, o, o

			local jejak = Instance.new("Trail")
			jejak.Attachment0, jejak.Attachment1 = atas, bawah
			jejak.Lifetime, jejak.LightEmission, jejak.FaceCamera = 0.5, 1, true
			jejak.Color = ColorSequence.new(c, Color3.new(1, 1, 1))
			jejak.Transparency = NumberSequence.new(0, 1)
			jejak.WidthScale = NumberSequence.new(1, 0)
			jejak.Parent = o

			local sinar = Instance.new("Beam")
			sinar.Attachment0, sinar.Attachment1 = inti, tengah
			sinar.Color = ColorSequence.new(Color3.new(1, 1, 1), c)
			sinar.Transparency = NumberSequence.new(0.2, 0.8)
			sinar.LightEmission, sinar.FaceCamera = 1, true
			sinar.Width0, sinar.Width1 = 0.25, 0.05
			sinar.CurveSize0 = (i % 2 == 0) and 3 or -3
			sinar.Parent = o

			orb[i] = { part = o, geser = (i / cfg.orbCount) * math.pi * 2 }
		end

		-- Keadaan yang diubah tiap fase; gelung di bawah cuma membacanya.
		local S = { radius = 6, putar = 1.5, orbY = 0, ayun = 1.5,
			runeR = 5, runePutar = 1 }
		local sudutRune, sudutOrb = 0, 0
		conn = RunService.RenderStepped:Connect(function(dt)
			if tertutup or not root.Parent then return end
			sudutOrb  = sudutOrb + dt * S.putar
			sudutRune = sudutRune - dt * S.runePutar
			local t = os.clock()
			local c = root.Position
			for _, o in ipairs(orb) do
				local a = o.geser + sudutOrb
				local y = S.orbY + math.sin(t * 3 + o.geser) * S.ayun
				o.part.Position = c + Vector3.new(math.cos(a) * S.radius, y,
					math.sin(a) * S.radius)
			end
			local pusat = c - Vector3.new(0, 3.2, 0)
			for i, r in ipairs(rune) do
				local a = (i / #rune) * math.pi * 2 + sudutRune
				local p = pusat + Vector3.new(math.cos(a) * S.runeR, 0,
					math.sin(a) * S.runeR)
				r.CFrame = CFrame.lookAt(p, pusat)
			end

			-- Kamera diberi tahu badannya sedang di mana. Tanpa ini dia
			-- tetap membidik slot di lantai selagi orangnya melayang 13
			-- stud di atas frame.
			if cfg.pandang then cfg.pandang(c) end
		end)

		-- Charge makin intens.
		task.spawn(function()
			for _ = 1, 40 do
				if tertutup then return end
				S.putar = S.putar + 0.08
				aura.Rate = aura.Rate + 1.5
				api.Rate  = api.Rate + 0.6
				task.wait(cfg.charge / 40)
			end
		end)

		if not tunggu(cfg.charge) then return end

		-- ================= FASE 2: ASCENSION =================
		mainkanFase("ascend", cfg.ascend)
		pose(0.6, 0.5)
		-- tujuanCF, bukan asalCF: satu tween yang sama menaikkan DAN
		-- memindahkannya mendatar. Dipisah jadi dua tween yang jalan
		-- bersamaan, yang kedua akan menimpa yang pertama -- keduanya
		-- menulis properti yang sama.
		tween(root, cfg.ascend,
			{ CFrame = tujuanCF + Vector3.new(0, cfg.naikAscend, 0) },
			Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		if bloom then tween(bloom, cfg.ascend, { Intensity = 0.9 }) end
		getar(cfg.ascend, 0.25)

		if not animasi(cfg.ascend, function(a)
			S.radius    = lerp(6, 2.5, a)
			S.orbY      = lerp(0, 4, a)
			S.ayun      = lerp(1.5, 0.3, a)
			S.putar     = lerp(4.7, 9, a)
			S.runeR     = lerp(5, 10, a)
			S.runePutar = lerp(1, 4, a)
		end) then return end

		-- ================= FASE 3: TIME FREEZE =================
		mainkanFase("freeze", cfg.freeze)
		aura.Rate, api.Rate, naik.Rate = 0, 0, 0

		-- Orb tersedot ke dada.
		if not animasi(math.min(0.3, cfg.freeze), function(a)
			S.radius = lerp(2.5, 0, a)
			S.orbY   = lerp(4, 0, a)
			S.putar  = lerp(9, 20, a)
		end, Enum.EasingStyle.Quad, Enum.EasingDirection.In) then return end
		for _, o in ipairs(orb) do o.part.Transparency = 1 end

		-- Kilatan berbahan ForceField: tembus pandang di tengah, jadi
		-- avatarnya tetap terlihat di dalamnya.
		local kilat = newPart({ Shape = Enum.PartType.Ball,
			Size = Vector3.one, Material = Enum.Material.ForceField,
			Color = Color3.new(1, 1, 1), CFrame = root.CFrame }, folder)
		local sisaFreeze = math.max(cfg.freeze - 0.3, 0.05)
		tween(kilat, sisaFreeze, { Size = Vector3.one * 9, Transparency = 0.4 },
			Enum.EasingStyle.Sine)
		if cc then
			tween(cc, 0.3, { Saturation = -1, Brightness = 0.2, Contrast = 0.4 })
		end
		if blur then tween(blur, 0.3, { Size = 6 }) end
		S.runePutar = 0.2   -- rune hampir berhenti = waktu berhenti
		if not tunggu(sisaFreeze) then return end

		-- ================= FASE 4: STARFALL =================
		--
		-- TIDAK ada mainkanFase("slam") di sini, dan itu disengaja:
		-- bunyi jatuhnya sudah dibunyikan pemanggil lewat bunyiTier
		-- (SFX_TIER[3], desis angin) tepat di detik ini. Menambah
		-- isyarat kedua berarti dua bunyi jatuh yang bertumpuk.
		--
		-- Yang menghentikan denting freeze tetap jalan: mainkanFase
		-- berikutnya (impact) yang mematikan gelung fase sebelumnya.
		tween(root, cfg.slam, { CFrame = tujuanCF },
			Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		tween(kilat, cfg.slam, { CFrame = tujuanCF, Size = Vector3.one * 3,
			Transparency = 0.8 }, Enum.EasingStyle.Quint,
			Enum.EasingDirection.In)
		fov(cfg.fovSlam, cfg.slam, Enum.EasingStyle.Quint,
			Enum.EasingDirection.In)
		if not tunggu(cfg.slam) then return end

		-- root TETAP di-anchor sampai adegannya selesai (tutup() yang
		-- mengembalikannya). Aslinya baris ini melepasnya supaya
		-- karakternya berdiri normal lagi -- tapi itu ditulis untuk
		-- karakter PEMAIN, yang punya lantai untuk dipijak.
		--
		-- Yang dipakai di sini salinan, dan seluruh part-nya sudah
		-- di-CanCollide-false oleh pemanggilnya (kalau tidak, dia
		-- menabrak avatar asli yang berdiri di slot yang sama). Melepas
		-- anchor-nya berarti dia JATUH MENEMBUS LANTAI selama 3,2 detik
		-- fase impact -- persis detik-detik dia paling ditonton.
		for m, c0 in pairs(poseAsli) do
			if m.Parent then tween(m, 0.4, { C0 = c0 }) end
		end
		tween(kilat, 0.4, { Transparency = 1 })
		for _, r in ipairs(rune) do tween(r, 0.3, { Transparency = 1 }) end

		-- ================= FASE 5: IMPACT =================
		--
		-- Dibunyikan di baris PERTAMA fase ini, sebelum satu pun part
		-- ledakan dibuat: membuat shell, tiga cincin, pilar, delapan
		-- petir, dan dua puluh kristal makan beberapa milidetik, dan
		-- dentuman yang menyusul sesudahnya terdengar terlambat.
		--
		-- Isyarat gempa dan aftershock ikut terjadwal dari sini lewat
		-- `tunda` masing-masing (0,3 dan 1,4 detik) -- lihat NOVA.SFX.
		mainkanFase("impact", cfg.impact)

		local hantam = CFrame.new(tanah)

		if cc then
			tween(cc, 0.15, { Saturation = 0.7, Brightness = 0.12,
				TintColor = Color3.fromRGB(255, 225, 255) })
		end
		if blur then tween(blur, 0.15, { Size = 0 }) end
		if bloom then tween(bloom, 0.15, { Intensity = 1.5 }) end
		fov(cfg.fovImpact, 0.1)
		task.delay(0.1, function()
			if not tertutup then fov(0, 1.6, Enum.EasingStyle.Elastic) end
		end)
		getar(1.2, 1.4)

		local kulit = newPart({ Shape = Enum.PartType.Ball,
			Material = Enum.Material.ForceField, Color = warna(3),
			Size = Vector3.one * 2, CFrame = hantam }, folder)
		tween(kulit, 2.6, { Size = Vector3.one * 65, Transparency = 1 },
			Enum.EasingStyle.Quint)

		local function cincin(c, tunda, maks, lama)
			task.delay(tunda, function()
				if tertutup then return end
				local r = newPart({ Shape = Enum.PartType.Cylinder, Color = c,
					Size = Vector3.new(0.3, 4, 4),
					CFrame = hantam * CFrame.new(0, 0.2, 0)
						* CFrame.Angles(0, 0, math.rad(90)) }, folder)
				tween(r, lama, { Size = Vector3.new(0.05, maks, maks),
					Transparency = 1 }, Enum.EasingStyle.Quint)
			end)
		end
		cincin(Color3.new(1, 1, 1), 0,    85, 2.2)
		cincin(warna(1),            0.15, 75, 2.2)
		cincin(warna(2),            0.3,  65, 2.2)

		local pilar = newPart({ Shape = Enum.PartType.Cylinder,
			Color = warna(2), Transparency = 0.1,
			Size = Vector3.new(300, 9, 9),
			CFrame = hantam * CFrame.new(0, 150, 0)
				* CFrame.Angles(0, 0, math.rad(90)) }, folder)
		tween(pilar, 2.8, { Size = Vector3.new(300, 0.2, 0.2), Transparency = 1 },
			Enum.EasingStyle.Quint)

		for i = 1, cfg.boltCount do
			local a = (i / cfg.boltCount) * math.pi * 2 + acak.angka()
			local ke = tanah + Vector3.new(math.cos(a) * 26,
				acak.antara(0, 8), math.sin(a) * 26)
			petir(tanah + Vector3.new(0, 1, 0), ke, warna(i + 1), folder, 1)
		end

		local letup = newPart({ Size = Vector3.one, Transparency = 1,
			CFrame = hantam }, folder)
		local sambung = Instance.new("Attachment")
		sambung.Parent = letup
		local percik = emitter(sambung, {
			Texture = TEX.spark, Color = PELANGI,
			Size = NumberSequence.new({ kp(0, 2.2), kp(1, 0) }),
			Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(40, 80),
			SpreadAngle = Vector2.new(180, 180), Drag = 5,
			Acceleration = Vector3.new(0, -3, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-90, 90),
		})
		percik:Emit(250)
		local asap = emitter(sambung, {
			Texture = TEX.smoke, LightEmission = 0.3,
			Color = ColorSequence.new(Color3.fromRGB(230, 210, 255)),
			Size = NumberSequence.new({ kp(0, 6), kp(1, 20) }),
			Transparency = NumberSequence.new({ kp(0, 0.4), kp(1, 1) }),
			Lifetime = NumberRange.new(2.2, 3), Speed = NumberRange.new(15, 30),
			SpreadAngle = Vector2.new(180, 180), Drag = 3,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-30, 30),
		})
		asap:Emit(50)

		-- Kristal melayang pelan lalu jatuh.
		for i = 1, cfg.shardCount do
			local a = (i / cfg.shardCount) * math.pi * 2
			local arah = Vector3.new(math.cos(a), 0, math.sin(a))
			local awal = hantam * CFrame.new(arah * 2 + Vector3.new(0, 1, 0))
			local pecah = newPart({ Material = Enum.Material.Glass,
				Color = warna(i + 1), Transparency = 0.15,
				Size = Vector3.new(0.7, acak.antara(1.5, 3.2), 0.7),
				CFrame = awal }, folder)
			local tujuan = CFrame.new(awal.Position
				+ arah * acak.antara(10, 18)
				+ Vector3.new(0, acak.antara(6, 12), 0))
				* CFrame.Angles(acak.antara(0, 6), acak.antara(0, 6),
					acak.antara(0, 6))
			tween(pecah, 1.3, { CFrame = tujuan }, Enum.EasingStyle.Quint)
			task.delay(1.3, function()
				if tertutup or not pecah.Parent then return end
				pecah.Anchored, pecah.CanCollide = false, true
				pecah.AssemblyLinearVelocity = arah * 8
				pecah.AssemblyAngularVelocity = Vector3.new(
					acak.antara(-8, 8), acak.antara(-8, 8), acak.antara(-8, 8))
				task.delay(1.2, function()
					if not tertutup and pecah.Parent then
						tween(pecah, 0.6,
							{ Transparency = 1, Size = Vector3.zero })
					end
				end)
			end)
		end

		-- Aftershock kedua.
		task.delay(1.4, function()
			if tertutup then return end
			cincin(warna(4), 0,   55, 1.4)
			cincin(warna(5), 0.1, 45, 1.4)
			percik:Emit(90)
			getar(0.6, 0.6)
			for _ = 1, 4 do
				local a = acak.angka() * math.pi * 2
				petir(tanah + Vector3.new(0, 1, 0),
					tanah + Vector3.new(math.cos(a) * 16, acak.antara(2, 10),
						math.sin(a) * 16), warna(4), folder, 0.6)
			end
		end)

		-- Warna kembali normal pelan.
		task.delay(0.4, function()
			if tertutup then return end
			if cc then
				tween(cc, 2.4, { Saturation = 0, Brightness = 0, Contrast = 0,
					TintColor = Color3.new(1, 1, 1) })
			end
			if bloom then tween(bloom, 2.4, { Intensity = 0 }) end
			tween(lampu, 2.4, { Range = 0 })
		end)

		if not tunggu(cfg.impact) then return end
		tutup(true)
	end

	task.spawn(function()
		local ok, err = pcall(jalankan)
		putus:Disconnect()
		if not ok then tutup(false, err) end
	end)

	return janji
end

return TierNova
