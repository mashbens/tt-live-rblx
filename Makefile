# Perintah-perintah tt-rblx. Jalankan `make` untuk daftar lengkapnya.
#
# Alur normal butuh TIGA terminal, satu perintah masing-masing:
#     make server      (terminal 1)
#     make tunnel      (terminal 2)
#     make listener    (terminal 3)
#
# `make up` menjalankan ketiganya sekaligus di satu terminal -- praktis, tapi
# log ketiganya bercampur. Buat live beneran, tiga terminal lebih enak dibaca.

PY            := ./.venv/bin/python
PORT          ?= 8000
NGROK_DOMAIN  ?= deluxe-sash-retired.ngrok-free.dev

# http://127.0.0.1:8000/docs#/default/push_api_push_post

# Username TikTok yang mau didengarkan. Urutan pencarian:
#   1. `make listener TIKTOK=namaakun`
#   2. baris TIKTOK_USERNAME= di .env
#
# Sengaja BUKAN variabel bernama USER: shell sudah punya $USER (nama login),
# dan make mewarisinya -- targetnya bakal diam-diam mencoba connect ke akun
# TikTok bernama "bens".
TIKTOK ?= $(shell grep -E '^TIKTOK_USERNAME=' .env 2>/dev/null | cut -d= -f2- | tr -d '"'"'"' ')

BASE_URL := http://127.0.0.1:$(PORT)

.PHONY: help install server dev tunnel listener watch up mock mock-tier2 mock-tier3 selftest test test-podium test-tier test-sync lint peek clear status clean

help:
	@echo ""
	@echo "  tt-rblx -- komentar TikTok Live -> antrian -> Roblox Studio"
	@echo ""
	@echo "  PERSIAPAN"
	@echo "    make install     pasang dependency ke .venv"
	@echo ""
	@echo "  JALAN (tiga terminal)"
	@echo "    make server      server antrian di port $(PORT)"
	@echo "    make tunnel      ngrok ke $(NGROK_DOMAIN)"
	@echo "    make listener    baca komentar live  (TIKTOK=namaakun)"
	@echo ""
	@echo "  JALAN (satu terminal)"
	@echo "    make up          ketiganya sekaligus, Ctrl+C mematikan semua"
	@echo ""
	@echo "  TES"
	@echo "    make mock        simulasi komentar live -- menyentuh ketiga tier"
	@echo "    make mock-tier2  tier 1 + sedikit tier 2, tanpa sorotan"
	@echo "    make mock-tier3  banjir 10 koin, menguji raksasa tier 3"
	@echo "    make selftest    uji saringan dengan beberapa komentar contoh"
	@echo "    make test-podium uji pembukuan slot podium di my_sscript_lua"
	@echo "    make test-tier   uji lantai aura + jatah border di my_scrip_lua_v2"
	@echo "    make test-sync   uji penyamaan tarian di kamera_client_lua_v2"
	@echo "    make lint        cari nil global di kedua file Lua"
	@echo "    make test        lint + ketiga uji sekaligus"
	@echo "    make watch       listener + tampilkan semua komentar, tanpa isi antrian"
	@echo ""
	@echo "  ANTRIAN"
	@echo "    make peek        lihat isi antrian"
	@echo "    make clear       kosongkan antrian"
	@echo "    make status      cek server, tunnel, dan kuota inspector ngrok"
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
	ngrok http --url=$(NGROK_DOMAIN) $(PORT)

listener: check-tiktok
	$(PY) tiktok_listener.py $(TIKTOK) $(ARGS)

# Numpang live orang lain buat lihat komentarnya lewat tanpa mengotori antrian.
watch: check-tiktok
	$(PY) tiktok_listener.py $(TIKTOK) --show-comments --dry-run

up: check-tiktok
	@echo ">> server + tunnel + listener jadi satu. Ctrl+C mematikan ketiganya."
	@trap 'kill 0' EXIT INT TERM; \
	$(PY) -m uvicorn main:app --port $(PORT) & \
	sleep 2; \
	ngrok http --url=$(NGROK_DOMAIN) $(PORT) --log=stdout > /dev/null 2>&1 & \
	sleep 2; \
	$(PY) tiktok_listener.py $(TIKTOK) $(ARGS); \
	wait

# ------------------------------------------------------------------------ tes

# Campuran harian: mayoritas komentar biasa, sisanya gift rose (1 koin)
# dan rosa (10 koin) -- jadi ketiga tier ikut lewat. Baris terakhirnya
# mencetak rincian per tier, dan memperingatkan kalau ada tier yang sama
# sekali tidak tersentuh.
mock:
	$(PY) mock_comments.py $(ARGS)

# Panggung sehari-hari: mayoritas tier 1, sesekali ada yang menonjol.
# Tidak pernah memicu sorotan, jadi enak buat menilai jarak dan susunan.
mock-tier2:
	$(PY) mock_comments.py --tier2 $(ARGS)

# Rosa saja (10 koin = raksasa). Lajunya menyesuaikan sendiri ke jeda
# sorotan tier 3 milik server (dibaca lewat /api/settings), jadi tiap
# raksasa benar-benar kebagian tampil dan tidak menumpuk di antrian.
mock-tier3:
	$(PY) mock_comments.py --tier3 $(ARGS)

selftest:
	$(PY) tiktok_listener.py --self-test "builderman" "halo bang mantap" "@Roblox" "ngasal_bukan_akun"

# Menjalankan fungsi slot podium dari my_sscript_lua di Lua sungguhan.
# Yang diuji: satu orang = satu podium, dan avatar lamanya benar-benar
# dihapus saat dia kirim gift lagi -- dulu dua badan menumpuk di sana.
test-podium:
	$(PY) test_podium.py

# Menjalankan fungsi tier V2 dari my_scrip_lua_v2 di Lua sungguhan.
# Yang diuji dua bug yang tidak pernah memunculkan error waktu live:
# lantai aura untuk yang bayar, dan jatah Highlight (Roblox diam-diam
# berhenti menggambar border setelah sekitar 31 sekaligus).
test-tier:
	$(PY) test_tier.py

# Menjalankan fungsi penyamaan tarian dari kamera_client_lua_v2 di Lua
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
test: lint test-tier test-sync test-podium
	@echo ""
	@echo "Semua pemeriksaan lolos."

# ------------------------------------------------------------------- antrian

peek:
	@curl -s $(BASE_URL)/api/peek || echo "server antrian tidak menyahut -- sudah `make server`?"
	@echo ""

clear:
	@curl -s -X DELETE $(BASE_URL)/api/clear || echo "server antrian tidak menyahut"
	@echo ""

status:
	@printf 'server antrian  : '; curl -s -m 2 $(BASE_URL)/ >/dev/null 2>&1 \
		&& echo "hidup di $(BASE_URL)" || echo "MATI"
	@printf 'tunnel ngrok    : '; curl -s -m 2 http://127.0.0.1:4040/api/tunnels >/dev/null 2>&1 \
		&& echo "hidup -- inspector di http://127.0.0.1:4040" || echo "MATI"
	@printf 'antrian         : '; curl -s -m 2 $(BASE_URL)/api/peek 2>/dev/null \
		| $(PY) -c "import json,sys; print(json.load(sys.stdin)['size'], 'nama menunggu')" 2>/dev/null \
		|| echo "-"

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