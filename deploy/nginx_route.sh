#!/usr/bin/env bash
# Dijalankan DI VM oleh `make deploy` dari repo pembeli (INSTANCE=<nama>):
#     ssh vm 'bash -s' -- <nama> < deploy/nginx_route.sh
#
# Membuka https://rblx.buanaglobalcipta.com/<nama>/ -> container tt-rblx-<nama>.
#
# Nginx di VM juga melayani situs lain, jadi tiap perubahan diuji `nginx -t`
# dulu dan dibatalkan kalau gagal -- reload dengan config rusak mematikan
# SEMUA situs, bukan cuma ini.
#
# rblx.conf cuma diedit SEKALI: ditambah satu baris include ke rblx.d/.
# Sesudah itu tiap pembeli = satu file rblx.d/<nama>.conf, dan menghapus
# pembeli cukup menghapus filenya.
set -euo pipefail

NAMA="$1"
CONF=/root/nignx/config/conf.d
D="$CONF/rblx.d"
FILE="$D/$NAMA.conf"
INCLUDE="include /etc/nginx/conf.d/rblx.d/*.conf;"

[[ "$NAMA" =~ ^[A-Za-z0-9_-]+$ ]] || { echo "nama tidak sah: $NAMA"; exit 1; }
mkdir -p "$D"

cadangan=""
if ! grep -qF "$INCLUDE" "$CONF/rblx.conf"; then
    cadangan="/root/nignx/rblx.conf.sebelum-rblx.d.bak"
    cp "$CONF/rblx.conf" "$cadangan"
    # Disisipkan di blok 443, tepat sesudah ssl_certificate_key -- blok 80
    # cuma redirect ke https.
    python3 - "$CONF/rblx.conf" "$INCLUDE" <<'EOF'
import sys
p, inc = sys.argv[1], sys.argv[2]
baris = open(p).read().split("\n")
for i, b in enumerate(baris):
    if b.strip().startswith("ssl_certificate_key"):
        baris.insert(i + 1, "\n    # Satu file per pembeli, ditulis deploy/nginx_route.sh.\n    " + inc)
        break
else:
    sys.exit("ssl_certificate_key tidak ketemu di " + p)
open(p, "w").write("\n".join(baris))
EOF
    echo "rblx.conf: include rblx.d ditambahkan (cadangan: $cadangan)"
fi

# Nama variabel nginx tidak boleh mengandung '-'.
VAR="ttrblx_${NAMA//-/_}"
BARU="$(cat <<EOF
# tt-rblx pembeli $NAMA: /$NAMA/... -> container tt-rblx-$NAMA (/root/tt-rblx-$NAMA).
location /$NAMA/ {
    resolver 127.0.0.11 valid=10s;
    set \$$VAR http://tt-rblx-$NAMA:8000;
    rewrite ^/$NAMA/(.*)\$ /\$1 break;
    proxy_pass \$$VAR;
    proxy_http_version 1.1;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_connect_timeout 5s;
}
EOF
)"

if [ -z "$cadangan" ] && [ -f "$FILE" ] && [ "$(cat "$FILE")" = "$BARU" ]; then
    echo "route /$NAMA/ sudah ada"
    exit 0
fi

lama=""
[ -f "$FILE" ] && lama="$(cat "$FILE")"
printf '%s\n' "$BARU" > "$FILE"

if ! docker exec nginx nginx -t >/dev/null 2>&1; then
    docker exec nginx nginx -t || true
    if [ -n "$lama" ]; then printf '%s\n' "$lama" > "$FILE"; else rm -f "$FILE"; fi
    [ -n "$cadangan" ] && cp "$cadangan" "$CONF/rblx.conf"
    echo "nginx -t GAGAL -- dikembalikan, nginx tidak di-reload."
    exit 1
fi
docker exec nginx nginx -s reload
echo "route /$NAMA/ aktif"
