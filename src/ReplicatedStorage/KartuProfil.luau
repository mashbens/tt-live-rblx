--[[
    KartuProfil  --  kartu profil TikTok + Roblox saat avatar datang

    Di Studio: ReplicatedStorage.KartuProfil (ModuleScript). Disinkron
    Rojo dari file ini. Dipanggil KameraClientV2 tiap pesan "profil" dari
    AvatarQueueV2 -- yang ini cuma menggambar.

    Dua bentuk:
      tier 2+  dua kartu di atas layar (TikTok kiri, Roblox kanan),
               permata tier di tengah, pita gift di bawahnya, semuanya
               muncul bersamaan.
      tier 1   dua kartu yang sama, tanpa permata dan pita. Atau pil
               kecil satu baris kalau PIL_TIER1 = true: pil baru
               menggantikan yang lama, dan kalau kartu penuh sedang
               tampil pilnya turun ke bawah kartu itu.

    Keduanya tidak punya timer: pergi saat avatarnya pergi dari
    panggung (KartuProfil.tutup, pesan "profilTutup" dari server).

    Kartu TikTok memakai foto profil TikTok ASLI kalau ada (d.fotoTiktok,
    piksel mentah dari FotoTiktok di server, digambar lewat
    EditableImage -- ImageLabel tidak bisa memuat URL luar). Tanpa itu,
    dan di kartu Roblox, fotonya foto avatar Roblox.

    Baris yang datanya kosong (TikTok kadang tidak mengirim jumlah
    follower, API Roblox kadang kena 429) tidak ditampilkan sama sekali
    -- "0 Pengikut" untuk orang yang pengikutnya ribuan lebih buruk
    daripada tidak menulis apa-apa.
--]]

local AssetService = game:GetService("AssetService")
local Players      = game:GetService("Players")
local RunService   = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local KartuProfil = {}

-- ============ SETELAN ============

-- Tepi atas kartu, pecahan tinggi layar. Tepat di bawah letterbox
-- nova (0,12), supaya tidak tertutup bilah hitamnya.
local POS_Y      = 0.135
-- Lebar rombongan dua kartu, pecahan lebar layar, dan batasnya dalam
-- pixel untuk layar lebar (Studio) -- siarannya layar HP tegak.
local LEBAR      = 0.96
local LEBAR_MAKS = 900
-- Lebar : tinggi rombongan. Tiap kartu 0,47 lebarnya, jadi satu kartu
-- kira-kira 2,2 : 1.
local ASPEK      = 4.7
-- Tembus pandang latar kartu: 0 = pekat, 1 = TANPA KOTAK sama sekali
-- (tanpa latar, tanpa tepi, pita tanpa pil) -- cuma foto dan teks yang
-- menyatu dengan ruangan gelap LatarSolo. Di bawah 1, latarnya hitam
-- ala aplikasi TikTok di kartu kiri dan banner abu di kartu Roblox.
-- Teksnya diberi garis tepi gelap supaya tetap terbaca di atas apa pun.
local TEMBUS     = 1
-- Komentar biasa (tier 1): false = dua kartu TikTok + Roblox seperti
-- gift, tanpa permata dan pita. true = pil kecil satu baris (nama Roblox
-- + @TikTok) -- lebih ringkas kalau komentarnya datang tiap detik.
local PIL_TIER1  = false

local GELAP = Color3.fromRGB(12, 12, 20)
local PUTIH = Color3.new(1, 1, 1)
local ABU   = Color3.fromRGB(170, 175, 195)

-- a/b = dua warna gradien tier, nama = tulisan di pita, ikon = isi
-- permata di tengah. Ikonnya emoji: simbol seperti ✦ dan ♛ tidak ada
-- di font Gotham dan tampil sebagai kotak kosong, emoji punya font
-- cadangannya sendiri.
local TEMA = {
	[1] = { a = Color3.fromRGB(150, 160, 190), b = Color3.fromRGB(90, 100, 130) },
	[2] = { a = Color3.fromRGB(90, 180, 255), b = Color3.fromRGB(50, 90, 255),
		nama = "SOROTAN", ikon = "⭐" },
	[3] = { a = Color3.fromRGB(0, 230, 255), b = Color3.fromRGB(170, 80, 255),
		nama = "SINEMATIK", ikon = "⭐" },
	[4] = { a = Color3.fromRGB(255, 215, 90), b = Color3.fromRGB(255, 70, 190),
		nama = "NOVA", ikon = "✨" },
	[5] = { a = Color3.fromRGB(255, 140, 40), b = Color3.fromRGB(255, 40, 90),
		nama = "MEGAH", ikon = "👑" },
}

-- Warna chip platform, bukan warna kartunya: kartu ikut tier.
local CHIP_TIKTOK = { Color3.fromRGB(37, 244, 238), Color3.fromRGB(254, 44, 85) }
local CHIP_ROBLOX = { Color3.fromRGB(235, 240, 255), Color3.fromRGB(130, 140, 170) }

-- Logo platform, lencana di pojok kiri atas foto tiap kartu. Diunggah
-- lewat Studio ke akun pemilik place (PNG 256x256, pojok membulat).
-- "" = tanpa lencana.
local LOGO_TIKTOK = "rbxassetid://90584901489664"
local LOGO_ROBLOX = "rbxassetid://71761855081013"

-- Percikan saat kartu bertabrakan, per tier. 0 = tanpa percikan.
local PERCIKAN = { [1] = 0, [2] = 0, [3] = 10, [4] = 20, [5] = 26 }

-- ============ ALAT ============

local function baru(kelas, sifat, induk)
	local o = Instance.new(kelas)
	for k, v in pairs(sifat) do o[k] = v end
	if induk then o.Parent = induk end
	return o
end

local function gerak(o, detik, sifat, gaya, arah)
	local t = TweenService:Create(o, TweenInfo.new(detik,
		gaya or Enum.EasingStyle.Quint, arah or Enum.EasingDirection.Out), sifat)
	t:Play()
	return t
end

-- Untuk teks yang masuk RichText: nama penonton bebas berisi < dan &.
local function aman(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

-- Dipotong per huruf, bukan per byte: nickname TikTok penuh emoji, dan
-- emoji yang terbelah di tengah jadi kotak rusak.
local function potong(s, n)
	s = tostring(s or "")
	local len = utf8.len(s)
	if not len then return s:sub(1, n) end
	if len <= n then return s end
	return s:sub(1, utf8.offset(s, n) - 1) .. "…"
end

local function desimal(x, akhiran)
	local s = ("%.1f"):format(x)
	s = (s:gsub("%.0$", ""))
	s = (s:gsub("%.", ","))
	return s .. akhiran
end

local function ringkas(n)
	if n >= 1e6 then return desimal(n / 1e6, "M") end
	if n >= 1e3 then return desimal(n / 1e3, "K") end
	return tostring(math.floor(n))
end

local function angka(v)
	v = tonumber(v)
	return (v and v > 0) and v or nil
end

-- Baris statistik, misalnya "**3,4K** Pengikut   **210** Mengikuti".
-- `p` 0..1 untuk animasi hitung naik. nil = tidak ada yang bisa ditulis.
local function barisAngka(isi, p)
	local bagian = {}
	for _, pasang in ipairs(isi) do
		local n = pasang[1]
		if n then
			table.insert(bagian, ("<b>%s</b> %s"):format(
				ringkas(n * p), pasang[2]))
		end
	end
	if #bagian == 0 then return nil end
	return table.concat(bagian, "   ")
end

local function label(induk, teks, x, y, w, h, opsi)
	opsi = opsi or {}
	local l = baru("TextLabel", {
		BackgroundTransparency = 1,
		Position       = UDim2.fromScale(x, y),
		Size           = UDim2.fromScale(w, h),
		Text           = teks,
		TextScaled     = true,
		RichText       = opsi.rich or false,
		TextColor3     = opsi.warna or PUTIH,
		Font           = opsi.font or Enum.Font.GothamMedium,
		TextXAlignment = opsi.rata or Enum.TextXAlignment.Left,
		ZIndex         = 3,
	}, induk)
	baru("UITextSizeConstraint", { MaxTextSize = opsi.maks or 40 }, l)
	return l
end

-- Garis tepi gelap tipis di semua teks kartu. Latarnya tembus pandang
-- (TEMBUS), jadi yang ada di belakang teks bisa saja lampu panggung
-- putih -- tanpa garis ini tulisan ABU di atasnya hilang.
local function tepiTeks(panel)
	if TEMBUS <= 0 then return end
	for _, d in ipairs(panel:GetDescendants()) do
		if d:IsA("TextLabel") then
			d.TextStrokeColor3       = GELAP
			d.TextStrokeTransparency = TEMBUS >= 1 and 0.35 or 0.6
		end
	end
end

local function gradien(induk, a, b, rotasi)
	return baru("UIGradient", {
		Color = ColorSequence.new(a, b), Rotation = rotasi or 0,
	}, induk)
end

-- Satu Heartbeat untuk semua cincin foto yang berputar.
local putar = {}
RunService.Heartbeat:Connect(function(dt)
	for g, laju in pairs(putar) do
		if g.Parent then
			g.Rotation = (g.Rotation + laju * dt) % 360
		else
			putar[g] = nil
		end
	end
end)

local function gui(pemain)
	local pg = pemain:WaitForChild("PlayerGui")
	local g = pg:FindFirstChild("KartuProfilGui")
	if g then return g end
	return baru("ScreenGui", {
		Name           = "KartuProfilGui",
		ResetOnSpawn   = false,
		IgnoreGuiInset = true,
		-- Di atas letterbox nova (50): kartu tidak boleh tertutup layar
		-- abu-abu sesaatnya.
		DisplayOrder   = 60,
	}, pg)
end

-- Foto TikTok asli dari piksel mentah ({ w, h, piksel = buffer }, dari
-- FotoTiktok di server). ImageLabel tidak bisa memuat URL TikTok, jadi
-- digambar sendiri lewat EditableImage. false = tidak bisa (data rusak,
-- atau EditableImage tidak diizinkan di game ini) -- pemanggilnya jatuh
-- ke foto Roblox.
local function pasangPiksel(gbr, f)
	if type(f) ~= "table" or typeof(f.piksel) ~= "buffer" then return false end
	local ok, ed = pcall(function()
		local ukuran = Vector2.new(f.w, f.h)
		local e = AssetService:CreateEditableImage({ Size = ukuran })
		e:WritePixelsBuffer(Vector2.zero, ukuran, f.piksel)
		gbr.ImageContent = Content.fromObject(e)
		return e
	end)
	if not ok then
		warn("[profil] foto TikTok tidak bisa digambar:", ed)
		return false
	end
	-- EditableImage memakan anggaran memori sampai di-Destroy sendiri;
	-- ikut pergi bersama kartunya.
	gbr.Destroying:Connect(function() ed:Destroy() end)
	return true
end

-- Foto bulat dengan cincin gradien berputar. Fotonya diunduh di
-- belakang: kartu tampil langsung dengan inisial, foto menyusul.
-- `piksel` = foto TikTok asli; kalau ada dan bisa digambar, foto Roblox
-- tidak diunduh sama sekali.
local function foto(induk, d, tema, jenis, x, rataX, piksel)
	local cincin = baru("Frame", {
		AnchorPoint      = Vector2.new(rataX, 0.5),
		Position         = UDim2.fromScale(x, 0.5),
		Size             = UDim2.fromScale(1, 0.72),
		BackgroundColor3 = PUTIH,
		ZIndex           = 2,
	}, induk)
	baru("UIAspectRatioConstraint", {
		AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, cincin)
	baru("UICorner", { CornerRadius = UDim.new(1, 0) }, cincin)
	local g = baru("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, tema.a),
			ColorSequenceKeypoint.new(0.5, tema.b),
			ColorSequenceKeypoint.new(1, tema.a),
		}),
	}, cincin)
	putar[g] = 90

	local gbr = baru("ImageLabel", {
		AnchorPoint      = Vector2.new(0.5, 0.5),
		Position         = UDim2.fromScale(0.5, 0.5),
		Size             = UDim2.fromScale(0.88, 0.88),
		BackgroundColor3 = Color3.fromRGB(30, 32, 48),
		ZIndex           = 2,
	}, cincin)
	baru("UICorner", { CornerRadius = UDim.new(1, 0) }, gbr)
	local inisial = label(gbr, potong(d.displayName or d.username or "?", 1),
		0.2, 0.2, 0.6, 0.6, { font = Enum.Font.GothamBlack,
			rata = Enum.TextXAlignment.Center, warna = tema.a })

	if piksel and pasangPiksel(gbr, piksel) then
		inisial:Destroy()
		return cincin
	end

	local id = tonumber(d.userId)
	if id and id > 0 then
		task.spawn(function()
			local ok, url = pcall(Players.GetUserThumbnailAsync, Players, id,
				jenis, Enum.ThumbnailSize.Size150x150)
			if ok and url and gbr.Parent then
				gbr.Image = url
				inisial:Destroy()
			end
		end)
	end
	return cincin
end

-- Lencana logo di pojok kiri atas cincin foto (titik hijau "online"
-- kartu TikTok di kanan bawah, jadi tidak bertabrakan).
local function lencana(cincin, gambar)
	if gambar == "" then return end
	local l = baru("ImageLabel", {
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.13, 0.13),
		Size                   = UDim2.fromScale(0.36, 0.36),
		BackgroundTransparency = 1,
		Image                  = gambar,
		ZIndex                 = 4,
	}, cincin)
	baru("UICorner", { CornerRadius = UDim.new(0.22, 0) }, l)
	baru("UIStroke", { Thickness = 1.5, Color = GELAP }, l)
end

local function chip(induk, teks, warna, x, y, w)
	local c = baru("TextLabel", {
		Position         = UDim2.fromScale(x, y),
		Size             = UDim2.fromScale(w, 0.15),
		BackgroundColor3 = PUTIH,
		Text             = teks,
		TextScaled       = true,
		TextColor3       = GELAP,
		Font             = Enum.Font.GothamBlack,
		ZIndex           = 3,
	}, induk)
	baru("UICorner", { CornerRadius = UDim.new(1, 0) }, c)
	baru("UIPadding", { PaddingTop = UDim.new(0.18, 0),
		PaddingBottom = UDim.new(0.14, 0) }, c)
	gradien(c, warna[1], warna[2])
	return c
end

-- ============ KARTU PENUH ============

-- isi = { nama, handle, centang, fan, chip, chipWarna, angka = {{n, kata}},
--         bawah = teks | {{n, kata}}, foto = Enum.ThumbnailType, logo }
local function kartu(induk, d, tema, isi, kiri)
	local akar = baru("CanvasGroup", {
		Position               = UDim2.fromScale(kiri and 0 or 0.53, 0),
		Size                   = UDim2.fromScale(0.47, 1),
		BackgroundTransparency = 1,
		GroupTransparency      = 1,
	}, induk)

	-- Panel disisipkan 2 px: CanvasGroup memotong apa pun di luar
	-- batasnya, termasuk garis tepi UIStroke.
	local panel = baru("Frame", {
		Position               = UDim2.new(0, 2, 0, 2),
		Size                   = UDim2.new(1, -4, 1, -4),
		BackgroundColor3       = PUTIH,
		BackgroundTransparency = TEMBUS,
	}, akar)
	baru("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
	if TEMBUS < 1 then
		-- Latar: banner warna platformnya, digelapkan supaya teks putih
		-- tetap menonjol, dengan tepi warna tier.
		gradien(panel, isi.chipWarna[1]:Lerp(GELAP, 0.55),
			isi.chipWarna[2]:Lerp(GELAP, 0.6), kiri and 0 or 180)
		local tepi = baru("UIStroke", { Thickness = 2, Color = PUTIH }, panel)
		gradien(tepi, tema.a, tema.b, kiri and 0 or 180)
	end

	lencana(foto(panel, d, tema, isi.foto, kiri and 0.04 or 0.96, kiri and 0 or 1),
		isi.logo or "")

	local x = kiri and 0.36 or 0.05
	local w = 0.59

	chip(panel, isi.chip, isi.chipWarna, x, 0.09, 0.27)
	if isi.fan then
		chip(panel, "FOLLOWER", { tema.a, tema.b }, x + 0.29, 0.09, 0.3)
	end

	local nama = aman(potong(isi.nama, 18))
	if isi.centang then
		nama = nama .. ' <font color="#5BC8FF">✓</font>'
	end
	label(panel, nama, x, 0.27, w, 0.22,
		{ font = Enum.Font.GothamBlack, rich = true, maks = 32 })
	label(panel, "@" .. potong(isi.handle, 24), x, 0.49, w, 0.13,
		{ warna = ABU, maks = 20 })

	local baris = label(panel, "", x, 0.65, w, 0.14,
		{ rich = true, maks = 20 })
	local bawah
	if type(isi.bawah) == "string" and isi.bawah ~= "" then
		bawah = label(panel, aman(potong(isi.bawah, 34)), x, 0.81, w, 0.12,
			{ warna = ABU, font = Enum.Font.GothamMedium, maks = 16 })
	elseif type(isi.bawah) == "table" then
		bawah = label(panel, "", x, 0.81, w, 0.12,
			{ warna = ABU, rich = true, maks = 16 })
	end

	-- Hitung naik dari nol begitu kartunya mendarat.
	local function isiAngka(p)
		baris.Text = barisAngka(isi.angka, p) or ""
		if bawah and type(isi.bawah) == "table" then
			bawah.Text = barisAngka(isi.bawah, p) or ""
		end
	end
	isiAngka(0)
	tepiTeks(panel)

	return { akar = akar, isiAngka = isiAngka }
end

-- ============ KARTU TIKTOK ============

-- Meniru kepala halaman profil aplikasi TikTok: latar hitam, nama besar
-- tebal, @handle abu, angka tebal dengan keterangannya di bawah, foto
-- bulat di kanan dengan titik hijau. Fotonya tetap foto Roblox (lihat
-- catatan di atas). Jumlah Likes profil tidak ikut: event live TikTok
-- tidak mengirimnya, dan kolom kosong lebih buruk daripada tidak ada.
local ABU_TT   = Color3.fromRGB(150, 150, 158)
local HIJAU_TT = Color3.fromRGB(32, 213, 96)

local function kartuTiktok(induk, d, tema, tt)
	local akar = baru("CanvasGroup", {
		Size                   = UDim2.fromScale(0.47, 1),
		BackgroundTransparency = 1,
		GroupTransparency      = 1,
	}, induk)
	local panel = baru("Frame", {
		Position               = UDim2.new(0, 2, 0, 2),
		Size                   = UDim2.new(1, -4, 1, -4),
		BackgroundColor3       = Color3.new(0, 0, 0),
		BackgroundTransparency = TEMBUS,
	}, akar)
	baru("UICorner", { CornerRadius = UDim.new(0, 16) }, panel)
	if TEMBUS < 1 then
		-- Tepi warna tier: satu kedatangan satu warna, sama dengan kartu
		-- Roblox di sebelahnya.
		local tepi = baru("UIStroke", { Thickness = 2, Color = PUTIH }, panel)
		gradien(tepi, tema.a, tema.b)
	end

	local cincin = foto(panel, d, tema, Enum.ThumbnailType.HeadShot, 0.96, 1,
		d.fotoTiktok)
	local titik = baru("Frame", {
		AnchorPoint      = Vector2.new(0.5, 0.5),
		Position         = UDim2.fromScale(0.85, 0.85),
		Size             = UDim2.fromScale(0.2, 0.2),
		BackgroundColor3 = HIJAU_TT,
		ZIndex           = 4,
	}, cincin)
	baru("UICorner", { CornerRadius = UDim.new(1, 0) }, titik)
	baru("UIStroke", { Thickness = 2, Color = Color3.new(0, 0, 0) }, titik)
	lencana(cincin, LOGO_TIKTOK)

	local nama = aman(potong((tt.nickname ~= "" and tt.nickname)
		or tt.handle or "TikTok", 16))
	if tt.verified == true then
		nama = nama .. ' <font color="#20D5EC">✓</font>'
	end
	label(panel, nama, 0.05, 0.1, 0.55, 0.27,
		{ font = Enum.Font.GothamBlack, rich = true, maks = 36 })
	label(panel, "@" .. potong(tt.handle or "", 22), 0.05, 0.37, 0.55, 0.13,
		{ warna = ABU_TT, maks = 20 })

	-- Kolom angka, urutannya sama dengan aplikasinya. Yang datanya kosong
	-- tidak dibuat sama sekali, kolom sesudahnya bergeser ke kiri.
	local kolom = {}
	for _, k in ipairs({ { angka(tt.following), "Following" },
		{ angka(tt.followers), "Followers" } }) do
		if k[1] then
			local x = 0.05 + #kolom * 0.18
			k.l = label(panel, "0", x, 0.53, 0.17, 0.19,
				{ font = Enum.Font.GothamBlack, maks = 28 })
			label(panel, k[2], x, 0.72, 0.17, 0.11, { warna = ABU_TT, maks = 16 })
			table.insert(kolom, k)
		end
	end
	if tt.fan == true then
		-- Lebar 0,17: foto di kanan mulai sekitar 0,63, chip tidak boleh
		-- menabraknya meski dua kolom angka terisi.
		chip(panel, "FOLLOWER", { tema.a, tema.b }, 0.05 + #kolom * 0.18, 0.56, 0.17)
	end

	local function isiAngka(p)
		for _, k in ipairs(kolom) do k.l.Text = ringkas(k[1] * p) end
	end
	isiAngka(0)
	tepiTeks(panel)

	return { akar = akar, isiAngka = isiAngka }
end

local function permata(induk, tema)
	local wadah = baru("CanvasGroup", {
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.fromScale(1, 0.62),
		BackgroundTransparency = 1,
		ZIndex                 = 6,
	}, induk)
	baru("UIAspectRatioConstraint", {
		AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, wadah)
	local skala = baru("UIScale", { Scale = 0 }, wadah)

	-- 0,68: belah ketupat yang diputar 45 derajat masih muat di wadahnya
	-- (diagonalnya ~0,96), jadi sudutnya tidak terpotong CanvasGroup.
	local ketupat = baru("Frame", {
		AnchorPoint      = Vector2.new(0.5, 0.5),
		Position         = UDim2.fromScale(0.5, 0.5),
		Size             = UDim2.fromScale(0.68, 0.68),
		Rotation         = 45,
		BackgroundColor3 = PUTIH,
	}, wadah)
	baru("UICorner", { CornerRadius = UDim.new(0.18, 0) }, ketupat)
	gradien(ketupat, tema.a, tema.b, 90)
	baru("UIStroke", { Thickness = 2, Color = PUTIH, Transparency = 0.2 }, ketupat)
	local ikon = label(ketupat, tema.ikon or "", 0.15, 0.15, 0.7, 0.7,
		{ font = Enum.Font.GothamBlack, rata = Enum.TextXAlignment.Center,
			maks = 48 })
	ikon.Rotation = -45
	return wadah, skala
end

local function pita(induk, d, tema)
	local teks = tema.nama
	if type(d.gift) == "string" and d.gift ~= "" then
		teks = potong(d.gift, 18):upper() .. "  ·  " .. teks
	end
	local p = baru("CanvasGroup", {
		AnchorPoint            = Vector2.new(0.5, 0),
		Position               = UDim2.new(0.5, 0, 1, 6),
		Size                   = UDim2.fromScale(0.46, 0.24),
		BackgroundColor3       = PUTIH,
		BackgroundTransparency = TEMBUS < 1 and 0 or 1,
		GroupTransparency      = 1,
	}, induk)
	local l = label(p, teks, 0.05, 0.16, 0.9, 0.7,
		{ font = Enum.Font.GothamBlack, rata = Enum.TextXAlignment.Center,
			maks = 26 })
	baru("UIStroke", { Thickness = 1.5, Color = GELAP, Transparency = 0.5 }, l)
	if TEMBUS < 1 then
		baru("UICorner", { CornerRadius = UDim.new(1, 0) }, p)
		gradien(p, tema.a, tema.b)
	else
		-- Tanpa pil: gradien warna tier pindah ke hurufnya sendiri.
		gradien(l, tema.a, tema.b)
	end
	return p
end

local function percikan(layar, dari, tema, jumlah)
	local pusat = dari.AbsolutePosition + dari.AbsoluteSize / 2
	for i = 1, jumlah do
		local sudut = math.rad(i * 360 / jumlah + math.random(-12, 12))
		local jauh  = math.random(90, 230)
		-- Kepingan belah ketupat, bukan teks ✦: simbol itu tidak ada di
		-- font Roblox.
		local s = baru("Frame", {
			AnchorPoint      = Vector2.new(0.5, 0.5),
			Position         = UDim2.fromOffset(pusat.X, pusat.Y),
			Size             = UDim2.fromOffset(14, 14),
			Rotation         = 45,
			BackgroundColor3 = (i % 2 == 0) and tema.a or tema.b,
			ZIndex           = 8,
		}, layar)
		local lama = 0.7 + math.random() * 0.4
		gerak(s, lama, {
			Position = UDim2.fromOffset(pusat.X + math.cos(sudut) * jauh,
				pusat.Y + math.sin(sudut) * jauh * 0.6),
			Rotation = math.random(-180, 180),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(4, 4),
		})
		task.delay(lama, s.Destroy, s)
	end
end

-- ============ PENGATUR ============

local penuh = nil   -- { wadah, sampai } kartu penuh yang sedang tampil
local mini  = nil   -- pil tier 1 yang sedang tampil

local function tutupPenuh(p, cepat)
	if not p or p.tutup then return end
	p.tutup = true
	local lama = cepat and 0.18 or 0.4
	for _, k in ipairs(p.kartu) do
		gerak(k.akar, lama, { GroupTransparency = 1 },
			Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
	if p.pita then gerak(p.pita, lama, { GroupTransparency = 1 }) end
	if p.permata then gerak(p.permata, lama, { GroupTransparency = 1 }) end
	task.delay(lama + 0.05, function() p.wadah:Destroy() end)
	if penuh == p then penuh = nil end
end

local function tutupMini(m, cepat)
	if not m or m.tutup then return end
	m.tutup = true
	local lama = cepat and 0.15 or 0.35
	gerak(m.akar, lama, { GroupTransparency = 1 })
	task.delay(lama + 0.05, function() m.akar:Destroy() end)
	if mini == m then mini = nil end
end

local function tampilPenuh(layar, d, tema)
	tutupPenuh(penuh, true)

	local wadah = baru("Frame", {
		AnchorPoint            = Vector2.new(0.5, 0),
		Position               = UDim2.fromScale(0.5, POS_Y),
		Size                   = UDim2.fromScale(LEBAR, 1),
		BackgroundTransparency = 1,
	}, layar)
	baru("UIAspectRatioConstraint", {
		AspectRatio = ASPEK, DominantAxis = Enum.DominantAxis.Width }, wadah)
	baru("UISizeConstraint", {
		MaxSize = Vector2.new(LEBAR_MAKS, LEBAR_MAKS / ASPEK) }, wadah)

	local tt  = type(d.tiktok) == "table" and d.tiktok or {}
	local rbx = type(d.roblox) == "table" and d.roblox or {}

	local kiri = kartuTiktok(wadah, d, tema, tt)
	local kanan = kartu(wadah, d, tema, {
		nama      = d.displayName or d.username,
		handle    = d.username or "",
		centang   = rbx.verified == true,
		chip      = "ROBLOX",
		chipWarna = CHIP_ROBLOX,
		angka     = { { angka(rbx.followers), "Pengikut" },
			{ angka(rbx.following), "Mengikuti" } },
		bawah     = { { angka(rbx.friends), "Teman" } },
		foto      = Enum.ThumbnailType.AvatarBust,
		logo      = LOGO_ROBLOX,
	}, false)

	-- Permata dan pita cuma untuk gift (tema bernama). Komentar biasa
	-- dapat dua kartunya saja.
	local gem, skalaGem, pt
	if tema.nama then
		gem, skalaGem = permata(wadah, tema)
		pt = pita(wadah, d, tema)
	end

	local p = { wadah = wadah, kartu = { kiri, kanan }, permata = gem, pita = pt,
		id = d.id }
	penuh = p

	-- Masuk: semuanya BERSAMAAN, di tempatnya -- TikTok, Roblox,
	-- permata, dan pita muncul pada saat yang sama, bukan meluncur satu
	-- per satu. Server sudah memilih saatnya (sesudah adegan sinematik
	-- atau nova, kalau ada).
	for _, k in ipairs(p.kartu) do
		gerak(k.akar, 0.35, { GroupTransparency = 0 })
	end
	if gem then
		gerak(skalaGem, 0.45, { Scale = 1 }, Enum.EasingStyle.Back)
		gerak(pt, 0.35, { GroupTransparency = 0 })
		local tier = tonumber(d.tier) or 1
		percikan(layar, gem, tema, PERCIKAN[tier] or 0)
	end

	-- Angka berhitung naik.
	local mulai = os.clock()
	while not p.tutup do
		local t = math.min((os.clock() - mulai) / 0.9, 1)
		local p01 = 1 - (1 - t) ^ 3
		for _, k in ipairs(p.kartu) do k.isiAngka(p01) end
		if t >= 1 then break end
		RunService.Heartbeat:Wait()
	end
	-- Tidak ada timer tutup: kartunya pergi bersama avatarnya
	-- (KartuProfil.tutup, dipanggil saat server mengirim "profilTutup"),
	-- atau digantikan kartu kedatangan berikutnya.
end

local function tampilMini(layar, d, tema)
	tutupMini(mini, true)

	-- Di bawah kartu penuh kalau sedang ada, supaya dua-duanya terbaca.
	local turun = 0
	if penuh and not penuh.tutup then
		turun = penuh.wadah.AbsoluteSize.Y * 1.45
	end

	local akar = baru("CanvasGroup", {
		AnchorPoint            = Vector2.new(0.5, 0),
		Position               = UDim2.new(0.5, 0, POS_Y, turun - 20),
		Size                   = UDim2.fromScale(0.56, 1),
		BackgroundTransparency = 1,
		GroupTransparency      = 1,
	}, layar)
	baru("UIAspectRatioConstraint", {
		AspectRatio = 5.6, DominantAxis = Enum.DominantAxis.Width }, akar)
	baru("UISizeConstraint", { MaxSize = Vector2.new(420, 75) }, akar)

	local panel = baru("Frame", {
		Position = UDim2.new(0, 2, 0, 2), Size = UDim2.new(1, -4, 1, -4),
		BackgroundColor3 = PUTIH, BackgroundTransparency = TEMBUS,
	}, akar)
	baru("UICorner", { CornerRadius = UDim.new(1, 0) }, panel)
	if TEMBUS < 1 then
		gradien(panel, CHIP_TIKTOK[1]:Lerp(GELAP, 0.55), CHIP_TIKTOK[2]:Lerp(GELAP, 0.6))
		local tepi = baru("UIStroke", { Thickness = 2, Color = PUTIH }, panel)
		gradien(tepi, CHIP_TIKTOK[1], CHIP_TIKTOK[2])
	end

	lencana(foto(panel, d, TEMA[3], Enum.ThumbnailType.HeadShot, 0.02, 0, d.fotoTiktok),
		LOGO_TIKTOK)

	local tt = type(d.tiktok) == "table" and d.tiktok or {}
	local nama = aman(potong(d.displayName or d.username, 20))
	if type(d.roblox) == "table" and d.roblox.verified == true then
		nama = nama .. ' <font color="#5BC8FF">✓</font>'
	end
	label(panel, nama, 0.22, 0.14, 0.72, 0.42,
		{ font = Enum.Font.GothamBlack, rich = true, maks = 26 })
	local sub = "dari @" .. aman(potong(tt.handle or "?", 22))
	local n = angka(tt.followers)
	if n then sub = sub .. "  ·  <b>" .. ringkas(n) .. "</b> pengikut" end
	label(panel, sub, 0.22, 0.56, 0.72, 0.3,
		{ warna = ABU, rich = true, maks = 18 })
	tepiTeks(panel)

	local m = { akar = akar, id = d.id }
	mini = m
	gerak(akar, 0.35, { GroupTransparency = 0,
		Position = UDim2.new(0.5, 0, POS_Y, turun) }, Enum.EasingStyle.Back)
end

-- Avatarnya pergi dari panggung: kartunya ikut pergi, saat itu juga.
-- Dicocokkan lewat id: di panggung barisan avatar lama bisa dihapus
-- sementara kartu orang yang lebih baru sedang tampil.
function KartuProfil.tutup(id)
	if penuh and penuh.id == id then tutupPenuh(penuh) end
	if mini and mini.id == id then tutupMini(mini) end
end

function KartuProfil.tampil(pemain, d)
	if type(d) ~= "table" then return end
	local tier = math.clamp(math.floor(tonumber(d.tier) or 1), 1, 5)
	local layar = gui(pemain)
	if tier >= 2 or not PIL_TIER1 then
		tampilPenuh(layar, d, TEMA[tier])
	else
		tampilMini(layar, d, TEMA[1])
	end
end

return KartuProfil
