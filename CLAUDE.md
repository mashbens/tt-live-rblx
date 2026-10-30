# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Gambaran

Komentar & gift TikTok Live → antrian HTTP → avatar Roblox menari di panggung. Tiga bagian:

- `tiktok_listener.py` (laptop) — baca komentar/gift (TikFinity Desktop kalau jalan, kalau tidak EulerStream), saring username Roblox, tentukan tier dari **nama gift** (`GIFT_TIER`, fallback ke harga koin), `POST /api/push` ke `PUSH_URL` dengan header `X-Token`.
- `main.py` (FastAPI, container Docker di VM) — antrian **di memori saja**, sorotan/jeda per tier, lookup displayName Roblox, sinkron lagu (`/api/music`). Endpoint tulis dikunci `API_TOKEN`; `/api/next`, `/api/settings` sengaja terbuka karena Roblox cuma membaca.
- `src/*.luau` (Roblox, disinkron Rojo) — `AvatarQueueV2` (Script server: polling `/api/next`, spawn avatar, tier, PLAYLIST lagu+dance), `KameraClientV2` (LocalScript: kamera, penyamaan tarian, sembunyikan pemain asli), `TierNova` (ModuleScript: adegan nova tier 4), `KartuProfil` (ModuleScript: kartu profil TikTok + Roblox per kedatangan, lihat README "Kartu profil"). Peta folder → Explorer di `default.project.json`; akhiran `.server`/`.client` menentukan jenis script.

`mock_comments.py` **mengimpor** pipeline dari `tiktok_listener.py` (bukan salinan), jadi perubahan saringan/tier di listener langsung teruji lewat mock. `roblox_ssl.py` wajib dipakai untuk semua panggilan ke API Roblox — tanpa `_NoALPNContext` httpx menggantung sampai timeout (lihat README "Catatan teknis").

`dashboard.py` = halaman lokal (port 8765) berisi tombol make, log, pemutar lagu, spawn manual. File lagu ke-N di `asset/` (urut nama) berpasangan dengan baris ke-N `PLAYLIST` di `AvatarQueueV2`. `tt_rblx.py` + `tt_rblx.spec` + `build_exe.sh` membungkus dashboard/listener/mock jadi satu .exe Windows untuk pembeli (mode pembeli: tanpa `make`).

## Repo pembeli (repo ini)

Repo ini worktree `pembeli/kyra` dari repo utama `../tt-rblx` (branch `main`). `INSTANCE=kyra` di `.env` membuat Makefile mengarah ke container `tt-rblx-kyra`, folder VM `/root/tt-rblx-kyra`, dan URL `https://rblx.buanaglobalcipta.com/kyra` (juga `URL` di atas `AvatarQueueV2`). Perbaikan umum dibuat di `main` lalu `git merge main` di sini; kustomisasi khusus pembeli (Lua, lagu, setelan tier di `.env`) tetap di branch ini.

Di `main.py`, satu **Kanal** = satu antrian + sorotan + lagu. Kanal dipilih dari `X-Token` (listener/dashboard) atau `?owner=<PrivateServerOwnerId>` (Roblox); pasangannya di `buyers.json` (tidak di-commit, dibaca ulang tanpa restart). Studio tanpa owner memakai kanal `API_TOKEN`.

## Perintah

Semua lewat `make` (`make` saja = daftar lengkap). Python dari `./.venv` (symlink ke venv repo utama).

```bash
make test         # lint + test-tier + test-sync — jalankan setelah mengubah src/
make lint         # lint_lua.py: KONSTANTA yang dipakai tapi tak dideklarasikan (nil global = script mati diam-diam)
make test-tier    # test_tier.py
make test-sync    # test_sync.py
make selftest     # saringan listener dengan contoh komentar
make mock         # 19 skenario pasti + campuran acak ke server antrian (ARGS=--tanpa-pembuka, --dry-run, --seed N)
make mock-tier3 / mock-tier4 / mock-tier5
make server       # server antrian lokal port 8000 (jangan pakai `make dev`/--reload saat live: antrian hilang)
make rojo         # rojo serve -> Studio Plugins > Rojo > Connect
make peek / clear / status
make deploy       # kirim main.py + Dockerfile + .env tersaring ke VM; ANTRIAN KOSONG tiap deploy
make vm-logs
make exe          # .exe + zip untuk pembeli (C:\tt-rblx-build\)
```

Tidak ada pytest: `test_tier.py`/`test_sync.py` adalah skrip yang mengambil fungsi `local function <nama>` **apa adanya** dari file `.luau` (sampai `end` di kolom 0) lalu menjalankannya di Lua sungguhan lewat `lupa`. Konsekuensinya: fungsi yang diuji harus tetap top-level, diawali `local function nama(` dan ditutup `end` tanpa indentasi; konstanta dibaca dengan regex `^local NAMA = angka`. Satu-satunya transformasi adalah `a += b` → `a = a + b`, jadi hindari sintaks khusus Luau lain di fungsi-fungsi itu.

## Aturan kerja

- Script Roblox diedit **hanya di `src/`**; Rojo yang menyinkronkan ke Studio. MCP Roblox_Studio dipakai untuk tes (play, console output, screenshot), bukan untuk mengedit script — Rojo menimpa perubahan di Studio.
- Setelan server yang dikirim ke VM cuma yang cocok `VM_ENV_KEYS` di Makefile (`TIER*_SCALE|KOIN`, `SPOTLIGHT_*`, `QUEUE_MAX`, `API_TOKEN`, `KANAL_PUBLIK`); setelan listener (`GIFT_TIER`, `TIER3_KOIN`, `USER_COOLDOWN_S`, dst.) hanya dibaca di laptop.
- Repo publik: `.env`, `buyers.json`, `paket_pembeli/`, `asset/` jangan di-commit; alamat VM dibaca dari `TUNNEL_SSH` di `.env`, jangan ditulis di kode.
- Kode, komentar, log, dan pesan commit berbahasa Indonesia; komentar menjelaskan *kenapa* (sering bug yang tidak memunculkan error di Output Studio). Ikuti gaya itu.
- README berisi detail perilaku tier/sorotan/podium; sebagian tabel podium menggambarkan skrip v13 lama, yang aktif adalah pasangan V2 di `src/`.
