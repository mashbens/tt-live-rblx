# Perintah-perintah tt-rblx. Jalankan `make` untuk daftar lengkapnya.
#
# Server antrian jalan terus di VM (`make deploy`, container tt-rblx), jadi
# saat live cukup SATU terminal di laptop:
#     make listener
#
# `make listener` memilih sumbernya sendiri: TikFinity Desktop kalau
# aplikasinya jalan, kalau tidak baru lewat EulerStream. Paksa salah satu
# dengan `make listener ARGS=--source=tikfinity` atau `ARGS=--source=euler`.
#
# Cadangan kalau VM bermasalah: `make server` + `make tunnel` di laptop (lihat
# README, "Cadangan: server di laptop lewat tunnel"). `make up` menjalankan
# jalur cadangan itu sekaligus di satu terminal.

PY            := ./.venv/bin/python
PORT          ?= 8000

# Tunnel ke VM sendiri, pengganti ngrok:
#   Roblox -> Cloudflare -> nginx (docker, VM) -> 172.17.0.1:9000 -> ssh -R -> laptop:8000
# Tunnel sengaja diikat ke IP docker0 (172.17.0.1), bukan 0.0.0.0, supaya port
# 9000 tidak terbuka ke internet -- cuma container nginx yang bisa menjangkaunya.
# Config sisi VM: /root/nignx/config/conf.d/rblx.conf dan
# /etc/ssh/sshd_config.d/10-tt-rblx-tunnel.conf (GatewayPorts clientspecified).
# Login SSH ke VM dibaca dari .env (TUNNEL_SSH=user@ip) -- repo ini publik,
# alamat VM tidak ditulis di sini.
TUNNEL_SSH    ?= $(shell grep -E '^TUNNEL_SSH=' .env 2>/dev/null | cut -d= -f2- | tr -d '"'"'"' ')
TUNNEL_BIND   ?= 172.17.0.1:9000
PUBLIC_URL    ?= https://rblx.buanaglobalcipta.com

# autossh menyambung ulang sendiri kalau wifi putus di tengah live.
# ExitOnForwardFailure: kalau port 9000 masih dipegang sesi lama yang basi,
# ssh keluar dan autossh mencoba lagi, bukannya jalan tanpa tunnel.
TUNNEL_CMD := AUTOSSH_GATETIME=0 autossh -M 0 -N \
	-o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
	-o ExitOnForwardFailure=yes -o BatchMode=yes \
	-R $(TUNNEL_BIND):127.0.0.1:$(PORT) $(TUNNEL_SSH)

# http://127.0.0.1:8000/docs#/default/push_api_push_post

# Username TikTok yang mau didengarkan. Urutan pencarian:
#   1. `make listener TIKTOK=namaakun`
#   2. baris TIKTOK_USERNAME= di .env
#
# Sengaja BUKAN variabel bernama USER: shell sudah punya $USER (nama login),
# dan make mewarisinya -- targetnya bakal diam-diam mencoba connect ke akun
# TikTok bernama "bens".
TIKTOK ?= $(shell grep -E '^TIKTOK_USERNAME=' .env 2>/dev/null | cut -d= -f2- | tr -d '"'"'"' ')

# Server antrian yang dipakai peek/clear/status. Kalau .env berisi PUSH_URL
# (server di VM), ke sana; kalau tidak, ke `make server` di laptop.
PUSH_URL_ENV := $(shell grep -E '^PUSH_URL=' .env 2>/dev/null | cut -d= -f2- | tr -d '"'"'"' ')
BASE_URL     ?= $(if $(PUSH_URL_ENV),$(PUSH_URL_ENV:/api/push=),http://127.0.0.1:$(PORT))
API_TOKEN    ?= $(shell grep -E '^API_TOKEN=' .env 2>/dev/null | cut -d= -f2- | tr -d '"'"'"' ')

# Server di VM (`make deploy`). Login SSH-nya sama dengan tunnel.
VM_SSH ?= $(TUNNEL_SSH)
VM_DIR ?= /root/tt-rblx
# Kunci .env yang dibaca main.py. Cuma ini yang dikirim ke VM -- kunci
# EulerStream, login VM, dan setelan listener tetap di laptop.
VM_ENV_KEYS := ^(TIER[0-9]_(SCALE|KOIN)|SPOTLIGHT_[A-Z0-9_]+|QUEUE_MAX|API_TOKEN)=

# Rojo dipasang lewat Aftman (aftman.toml). Pakai shim-nya langsung supaya
# jalan juga di shell yang belum memuat ~/.aftman/env.
ROJO      ?= $(HOME)/.aftman/bin/rojo

.PHONY: help install server dev tunnel listener listener-tf watch watch-tf up mock mock-tier3 mock-tier4 mock-tier5 selftest test test-tier test-sync lint rojo rojo-build peek clear status clean deploy vm-logs

help:
	@echo ""
	@echo "  tt-rblx -- komentar TikTok Live -> antrian -> Roblox Studio"
	@echo ""
	@echo "  PERSIAPAN"
	@echo "    make install     pasang dependency ke .venv"
	@echo ""
	@echo "  JALAN (tiga terminal)"
	@echo "    make server      server antrian di port $(PORT)"
	@echo "    make tunnel      tunnel SSH ke $(PUBLIC_URL)"
	@echo "    make listener    baca komentar live  (TIKTOK=namaakun)"
	@echo "                     sumber otomatis: TikFinity kalau jalan,"
	@echo "                     kalau tidak jatuh ke EulerStream"
	@echo ""
	@echo "  JALAN (satu terminal)"
	@echo "    make up          ketiganya sekaligus, Ctrl+C mematikan semua"
	@echo ""
	@echo "  TES"
	@echo "    make mock        19 skenario pasti (5 tier, combo, gift tak menumpuk, tap)"
	@echo "                     lalu campuran acak mirip live"
	@echo "    make mock-tier3  banjir Rose, menguji adegan sinematik tier 3"
	@echo "    make mock-tier4  banjir Rosa, menguji nova tier 4"
	@echo "    make mock-tier5  banjir Doughnut, menguji raksasa tier 5"
	@echo "    make selftest    uji saringan dengan beberapa komentar contoh"
	@echo "    make test-tier   uji lantai aura + jatah border di AvatarQueueV2"
	@echo "    make test-sync   uji penyamaan tarian di KameraClientV2"
	@echo "    make lint        cari nil global di ketiga file Lua"
	@echo "    make test        lint + ketiga uji sekaligus"
	@echo "    make watch       listener + tampilkan semua komentar, tanpa isi antrian"
	@echo "    make watch-tf    sama, tapi paksa lewat TikFinity"
	@echo ""
	@echo "  STUDIO (Rojo)"
	@echo "    make rojo        sinkron ketiga file Lua ke Studio (plugin Rojo > Connect)"
	@echo "    make rojo-build  bikin tt-rblx.rbxlx berisi ketiga script"
	@echo ""
	@echo "  ANTRIAN"
	@echo "    make peek        lihat isi antrian"
	@echo "    make clear       kosongkan antrian"
	@echo "    make status      cek server, tunnel dari luar, dan isi antrian"
	@echo ""
	@echo "  VM"
	@echo "    make deploy      kirim server + setelan .env ke VM, build, jalankan"
	@echo "    make vm-logs     log server antrian di VM (Ctrl+C keluar)"
	@echo ""
	@echo "  LAIN"
	@echo "    make dev         server + auto-reload (JANGAN dipakai saat live)"
	@echo "    make clean       hapus __pycache__"
	@echo ""

install:
	test -d .venv || python3 -m venv .venv
	$(PY) -m pip install -q --upgrade pip
	$(PY) -m pip install -q -r requirements.txt
	@echo "Selesai. Lanjut: make server"

# ------------------------------------------------------------------ menjalankan

server:
	$(PY) -m uvicorn main:app --port $(PORT)

# Auto-reload menyimpan ulang modul tiap ada file berubah, dan antrian cuma ada
# di memori -- jadi tiap kamu menyentuh file apa pun di folder ini saat live,
# seluruh antrian hilang. Makanya dipisah dari `make server`.
dev:
	@echo ">> auto-reload aktif: antrian akan TERHAPUS tiap file berubah."
	$(PY) -m uvicorn main:app --reload --port $(PORT)

tunnel:
	@echo ">> $(PUBLIC_URL) -> localhost:$(PORT). Ctrl+C memutus."
	$(TUNNEL_CMD)

listener: check-tiktok
	$(PY) tiktok_listener.py $(TIKTOK) $(ARGS)

# Jalur cadangan: event dibaca dari TikFinity Desktop, tidak lewat EulerStream.
# Tidak perlu $(TIKTOK) — live yang dibaca ditentukan dari aplikasi TikFinity.
# Aplikasinya harus jalan di PC ini dulu.
listener-tf:
	$(PY) tiktok_listener.py --source tikfinity $(ARGS)

# Versi TikFinity dari `make watch`: lihat semua komentar, tanpa push antrian.
watch-tf:
	$(PY) tiktok_listener.py --source tikfinity --show-comments --dry-run

# Numpang live orang lain buat lihat komentarnya lewat tanpa mengotori antrian.
watch: check-tiktok
	$(PY) tiktok_listener.py $(TIKTOK) --show-comments --dry-run

up: check-tiktok
	@echo ">> server + tunnel + listener jadi satu. Ctrl+C mematikan ketiganya."
	@trap 'kill 0' EXIT INT TERM; \
	$(PY) -m uvicorn main:app --port $(PORT) & \
	sleep 2; \
	$(TUNNEL_CMD) & \
	sleep 2; \
	$(PY) tiktok_listener.py $(TIKTOK) $(ARGS); \
	wait

# ------------------------------------------------------------------------ tes

# Dibuka dengan 19 skenario pasti yang masing-masing diperiksa hasilnya,
# TERMASUK urutan spawn-nya: kelima tier, Doughnut lalu Rose yang harus jadi
# raksasa DULU baru Rose (bukan raksasa dua kali), Bouquet dua kali yang
# harus tetap nova, combo (Rose x25 = 2 Rosa + 5 Rose, Doughnut x3 = 3
# raksasa, dua combo Rose x5 yang TIDAK jadi Rosa), gift tak dikenal
# yang jatuh ke harganya, tap dulu / username dulu, boost hangus, dan nama
# ngawur yang harus ditolak. Sesudah itu campuran acak mirip live.
# Baris terakhirnya mencetak rincian per tier dan skenario yang gagal.
# Lewati pembukanya dengan `make mock ARGS=--tanpa-pembuka`.
mock:
	$(PY) mock_comments.py $(ARGS)

# Rose saja (tier 3: adegan sinematik + aura VFX acak). Lajunya menyesuaikan
# sendiri ke jeda sorotan tier itu milik server (dibaca lewat /api/settings),
# jadi tiap kedatangan benar-benar kebagian tampil dan tidak menumpuk.
mock-tier3:
	$(PY) mock_comments.py --tier3 $(ARGS)

# Rosa saja (tier 4: adegan nova). Butuh ModuleScript TierNova di
# ReplicatedStorage; tanpa itu Output client mencetak [nova] dan avatarnya
# langsung berdiri tanpa adegan.
mock-tier4:
	$(PY) mock_comments.py --tier4 $(ARGS)

# Doughnut saja (tier 5: raksasa).
mock-tier5:
	$(PY) mock_comments.py --tier5 $(ARGS)

selftest:
	$(PY) tiktok_listener.py --self-test "builderman" "halo bang mantap" "@Roblox" "ngasal_bukan_akun"

# Menjalankan fungsi tier V2 dari AvatarQueueV2 di Lua sungguhan.
# Yang diuji dua bug yang tidak pernah memunculkan error waktu live:
# lantai aura untuk yang bayar, dan jatah Highlight (Roblox diam-diam
# berhenti menggambar border setelah sekitar 31 sekaligus).
test-tier:
	$(PY) test_tier.py

# Menjalankan fungsi penyamaan tarian dari KameraClientV2 di Lua
# sungguhan. Yang diuji dua sebab "tariannya patah-patah" yang tidak
# pernah memunculkan satu pun baris di Output: raksasa/avatar melayang
# ikut menyeret kerumunan ke animasinya sendiri, dan selisih waktu yang
# tidak dilipat di titik ulang animasi.
test-sync:
	$(PY) test_sync.py

# Nama konstanta yang dipakai tapi tidak pernah dideklarasikan.
#
# Lua tidak menganggap itu kesalahan -- nilainya nil dan dia diam, jadi
# kompilasi lolos mulus. Yang terjadi di Studio: script berhenti di
# pemakaian pertama, dan karena itu terjadi di chunk utama, gelung
# pollingnya tidak pernah jalan. Panggung mati total gara-gara satu
# titik yang tertulis sebagai garis bawah.
lint:
	$(PY) lint_lua.py

# Semuanya sekaligus. Lint duluan: dia yang paling cepat dan paling
# sering menangkap sesuatu.
test: lint test-tier test-sync
	@echo ""
	@echo "Semua pemeriksaan lolos."

# --------------------------------------------------------------------- rojo

# Folder src/ meniru Explorer di Studio (peta lengkapnya di default.project.json):
#   src/ServerScriptService/AvatarQueueV2.server.luau                 -> Script
#   src/StarterPlayer/StarterPlayerScripts/KameraClientV2.client.luau -> LocalScript
#   src/ReplicatedStorage/TierNova.luau                               -> ModuleScript
# Akhiran .server / .client yang menentukan jenis script-nya. Isi lain di
# service yang sama (yang tidak ada di src/) dibiarkan Rojo, tidak dihapus.
#
# Studio jalan di Windows, Rojo di WSL. Plugin menyambung ke localhost:34872
# dan WSL2 meneruskannya; kalau tidak nyambung, coba `make rojo ARGS="--address 0.0.0.0"`.
rojo:
	$(ROJO) serve $(ARGS)

rojo-build:
	$(ROJO) build -o tt-rblx.rbxlx

# ------------------------------------------------------------------- antrian

peek:
	@curl -s $(BASE_URL)/api/peek || echo "server antrian tidak menyahut -- sudah `make server`?"
	@echo ""

clear:
	@curl -s -X DELETE -H "X-Token: $(API_TOKEN)" $(BASE_URL)/api/clear || echo "server antrian tidak menyahut"
	@echo ""

status:
	@printf 'server antrian  : '; curl -s -m 2 $(BASE_URL)/ >/dev/null 2>&1 \
		&& echo "hidup di $(BASE_URL)" || echo "MATI"
	@printf 'tunnel          : '; code=$$(curl -s -m 5 -o /dev/null -w '%{http_code}' $(PUBLIC_URL)/); \
		case $$code in 2*|3*|404) echo "hidup di $(PUBLIC_URL)";; \
		502|504) echo "MATI -- VM menyahut ($$code), tapi tunnel/server laptop tidak";; \
		*) echo "MATI ($$code)";; esac
	@printf 'antrian         : '; curl -s -m 2 $(BASE_URL)/api/peek 2>/dev/null \
		| $(PY) -c "import json,sys; print(json.load(sys.stdin)['size'], 'nama menunggu')" 2>/dev/null \
		|| echo "-"

# ------------------------------------------------------------------------- vm

# Server antrian di VM: Roblox -> Cloudflare -> nginx -> container tt-rblx.
# Tidak butuh laptop menyala; listener di laptop mengirim ke PUSH_URL.
#
# .env VM ditulis ulang tiap deploy dari .env laptop (disaring VM_ENV_KEYS),
# jadi mengubah setelan tier/sorotan = ubah .env di sini lalu `make deploy`.
# Antrian ikut kosong tiap deploy (dia cuma di memori) -- jangan saat live.
deploy:
	@test -n "$(VM_SSH)" || { echo "TUNNEL_SSH belum diisi di .env"; exit 1; }
	@test -n "$(API_TOKEN)" || { echo "API_TOKEN belum diisi di .env -- server di VM terbuka ke internet"; exit 1; }
	ssh $(VM_SSH) 'mkdir -p $(VM_DIR)/deploy'
	grep -E '$(VM_ENV_KEYS)' .env | ssh $(VM_SSH) 'umask 077; cat > $(VM_DIR)/.env'
	tar czf - Dockerfile .dockerignore main.py roblox_ssl.py deploy/docker-compose.yml \
		| ssh $(VM_SSH) 'tar xzf - -C $(VM_DIR) && cd $(VM_DIR) && docker compose -f deploy/docker-compose.yml up -d --build'
	@echo ""
	@# Container baru butuh beberapa detik, dan nginx menyimpan IP container
	@# lama sampai 10 detik -- cek sekali langsung selalu 502.
	@for i in 1 2 3 4 5 6 7 8 9 10; do \
		code=$$(curl -s -m 5 -o /dev/null -w '%{http_code}' $(PUBLIC_URL)/); \
		[ "$$code" = 200 ] && break; sleep 2; \
	done; echo "$(PUBLIC_URL) -> $$code"

vm-logs:
	ssh -t $(VM_SSH) 'docker logs -f --tail 100 tt-rblx'

# ------------------------------------------------------------------------ lain

clean:
	rm -rf __pycache__ .pytest_cache
	@echo "Bersih."

check-tiktok:
	@test -n "$(TIKTOK)" || { \
		echo "Username TikTok belum diisi."; \
		echo ""; \
		echo "  make listener TIKTOK=namaakun"; \
		echo ""; \
		echo "atau tulis sekali saja di .env:"; \
		echo ""; \
		echo "  TIKTOK_USERNAME=namaakun"; \
		echo ""; \
		exit 1; }
# make listener TIKTOK=kyra.void5.