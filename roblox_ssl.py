"""Cara memanggil API Roblox tanpa request-nya menggantung.

Isi file ini dipindahkan dari `server.py` (proxy CORS untuk viewer 3D
berbasis browser) waktu viewer itu dihapus. Yang dipindah cuma bagian yang
masih dipakai: alamat API pencarian username, dan konteks SSL-nya.

Kenapa dipisah jadi file sendiri, bukan ditempel ke salah satu pemakainya:
`main.py` dan `tiktok_listener.py` DUA-DUANYA memanggil users.roblox.com,
dan kalau akal-akalan di bawah ini cuma ada di salah satunya, yang satu lagi
diam-diam kembali menggantung.
"""

import ssl

USERS_API = "https://users.roblox.com/v1/usernames/users"

# Roblox kadang menolak request tanpa User-Agent, jadi selalu kirim satu.
ROBLOX_HEADERS = {
    "User-Agent": "tt-rblx/0.1",
    "Accept": "application/json",
}


class _NoALPNContext(ssl.SSLContext):
    """SSLContext yang mengabaikan permintaan set_alpn_protocols().

    KENAPA INI PERLU (jangan dihapus, ini bukan cargo cult):
    edge server roblox.com menggantung -- koneksi TLS sukses, request
    terkirim, tapi response TIDAK PERNAH datang sampai timeout -- kalau
    ALPN menegosiasikan "http/1.1" secara eksplisit. Diverifikasi lewat
    raw socket TLS:

        ALPN ["http/1.1"]        -> hang sampai timeout
        ALPN ["h2","http/1.1"]   -> OK (ini yang dipakai curl)
        tanpa ekstensi ALPN      -> OK, HTTP/1.1 biasa

    Masalahnya httpcore SELALU memanggil ctx.set_alpn_protocols() pada
    context yang kita berikan (["http/1.1"], atau ["http/1.1","h2"] kalau
    http2=True -- urutannya bikin server tetap memilih http/1.1), jadi
    `verify=<context>` biasa tidak cukup: override-nya harus di level
    class. Efeknya request kita jadi mirip urllib/requests-tanpa-ALPN,
    yang memang jalan normal ke Roblox.
    """

    def set_alpn_protocols(self, protocols):  # noqa: D102 - sengaja no-op
        pass


def _make_ssl_context() -> ssl.SSLContext:
    ctx = _NoALPNContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = True
    ctx.verify_mode = ssl.CERT_REQUIRED
    ctx.load_default_certs(ssl.Purpose.SERVER_AUTH)
    return ctx
