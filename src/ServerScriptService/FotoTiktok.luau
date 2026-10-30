--[[
    FotoTiktok  --  foto profil TikTok untuk kartu profil

    Di Studio: ServerScriptService.FotoTiktok (ModuleScript). Disinkron
    Rojo. Dipakai AvatarQueueV2.

    Roblox tidak bisa memuat gambar dari URL luar -- ImageLabel cuma
    menerima aset Roblox. main.py yang mengunduh foto TikTok-nya dan
    menyajikannya sebagai RGBA mentah (base64) di /api/foto/<kunci>. Di
    sini base64 itu dipecah jadi buffer, lalu dikirim ke client bersama
    pesan "profil"; KartuProfil menggambarnya dengan EditableImage.

        siapkan(url, kunci)  mulai mengunduh di belakang, saat avatar datang
        ambil(kunci, tunggu) { w, h, piksel = buffer } atau nil

    Modul sendiri, bukan fungsi di AvatarQueueV2: chunk utama script itu
    sudah menempel di batas 200 local.
--]]

local HttpService = game:GetService("HttpService")

local FotoTiktok = {}

-- Yang sudah jadi: kunci -> { w, h, piksel } atau false (gagal). Dibatasi
-- supaya live berjam-jam tidak menumpuk ratusan foto di memori server.
local cache = {}
local urutan = {}
local MAKS = 60
-- Kunci yang sedang diunduh: tidak diunduh dua kali (combo gift).
local sedang = {}

-- ============ BASE64 ============

local NILAI = {}
do
	local abjad = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	for i = 1, #abjad do NILAI[string.byte(abjad, i)] = i - 1 end
end

-- base64 -> buffer. Ditulis tangan: Luau tidak punya pemecah base64, dan
-- teks 80x80x4 piksel cuma ~34 KB -- sekali jalan di bawah satu milidetik.
local function pecah(s)
	local n = #s
	while n > 0 and string.byte(s, n) == 61 do n -= 1 end   -- buang "="
	local keluar = buffer.create(math.floor(n * 3 / 4))
	local j = 0
	for i = 1, n, 4 do
		local a = NILAI[string.byte(s, i)] or 0
		local b = NILAI[string.byte(s, i + 1) or 65] or 0
		local c = NILAI[string.byte(s, i + 2) or 65] or 0
		local d = NILAI[string.byte(s, i + 3) or 65] or 0
		local v = a * 262144 + b * 4096 + c * 64 + d
		buffer.writeu8(keluar, j, bit32.rshift(v, 16))
		if i + 2 <= n then buffer.writeu8(keluar, j + 1, bit32.band(bit32.rshift(v, 8), 255)) end
		if i + 3 <= n then buffer.writeu8(keluar, j + 2, bit32.band(v, 255)) end
		j += 3
	end
	return keluar
end

-- ============ API ============

local function simpan(kunci, isi)
	if cache[kunci] == nil then table.insert(urutan, kunci) end
	cache[kunci] = isi
	while #urutan > MAKS do
		cache[table.remove(urutan, 1)] = nil
	end
end

function FotoTiktok.siapkan(url, kunci)
	if type(kunci) ~= "string" or kunci == "" then return end
	if cache[kunci] ~= nil or sedang[kunci] then return end
	sedang[kunci] = true
	task.spawn(function()
		local ok, res = pcall(HttpService.RequestAsync, HttpService, {
			Url = url .. "/api/foto/" .. kunci, Method = "GET",
		})
		local isi = false
		if ok and res.StatusCode == 200 then
			local okJson, data = pcall(HttpService.JSONDecode, HttpService, res.Body)
			local w = okJson and tonumber(data.w)
			local h = okJson and tonumber(data.h)
			if w and h and type(data.rgba) == "string" then
				local piksel = pecah(data.rgba)
				-- Ukuran yang tidak cocok = data rusak. EditableImage
				-- menolaknya dengan error, lebih baik tanpa foto.
				if buffer.len(piksel) == w * h * 4 then
					isi = { w = w, h = h, piksel = piksel }
				end
			end
		elseif ok and res.StatusCode ~= 404 then
			warn("[foto] HTTP", res.StatusCode, kunci)
		elseif not ok then
			warn("[foto] gagal:", res)
		end
		simpan(kunci, isi)
		sedang[kunci] = nil
	end)
end

-- Foto yang sudah jadi. Kalau masih diunduh, ditunggu paling lama
-- `tunggu` detik -- kartu yang terlambat lebih buruk daripada kartu
-- dengan foto Roblox.
function FotoTiktok.ambil(kunci, tunggu)
	if type(kunci) ~= "string" then return nil end
	local sampai = os.clock() + (tunggu or 0)
	while sedang[kunci] and os.clock() < sampai do task.wait(0.1) end
	return cache[kunci] or nil
end

return FotoTiktok
