"""
Pemutar lagu untuk live: lagunya bunyi di laptop, tariannya di Roblox.

Jalankan:
    make player
lalu buka http://127.0.0.1:8765 di browser (atau jadikan Browser Source di
OBS) dan tekan Mulai.

Lagu diambil dari folder asset/, urut nama file. File ke-N berpasangan dengan
baris ke-N PLAYLIST di AvatarQueueV2 -- lagu1.mp3 = baris 1, dan seterusnya.

Cara sinkronnya: sebelum lagu dimulai, halaman melapor ke server antrian
(/api/music) "lagu N mulai JEDA_MS lagi", baru menunggu JEDA_MS itu dan
memutar lagunya. Roblox polling tiap POLL_MUSIK dan menjadwalkan ganti tarian
ke detik yang sama. Jeda itu yang menghapus telat satu polling.

Lapornya lewat server kecil ini, bukan langsung dari browser, supaya
API_TOKEN tidak pernah sampai ke halaman.
"""

import json
import os
import sys
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

FOLDER = Path(__file__).parent / "asset"
PORT = int(os.environ.get("PLAYER_PORT", "8765"))
EKSTENSI = {".mp3": "audio/mpeg", ".ogg": "audio/ogg", ".wav": "audio/wav",
            ".m4a": "audio/mp4"}

# Server antrian yang sama dengan listener: PUSH_URL di .env kalau ada (VM),
# kalau tidak `make server` di laptop.
_push = os.environ.get("PUSH_URL", "").strip()
BASE_URL = (_push.removesuffix("/api/push") if _push
            else "http://127.0.0.1:8000")
API_TOKEN = os.environ.get("API_TOKEN", "")


def daftar_lagu() -> list[str]:
    return sorted(p.name for p in FOLDER.iterdir()
                  if p.suffix.lower() in EKSTENSI)


def lapor(body: bytes) -> tuple[int, bytes]:
    req = urllib.request.Request(
        BASE_URL + "/api/music", data=body, method="POST",
        headers={"Content-Type": "application/json", "X-Token": API_TOKEN})
    try:
        with urllib.request.urlopen(req, timeout=5) as res:
            return res.status, res.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()
    except OSError as e:
        return 502, json.dumps({"error": str(e)}).encode()


class Handler(BaseHTTPRequestHandler):
    def kirim(self, code: int, body: bytes, tipe: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", tipe)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/":
            self.kirim(200, HALAMAN.encode(), "text/html; charset=utf-8")
        elif self.path == "/lagu":
            self.kirim(200, json.dumps(daftar_lagu()).encode(),
                       "application/json")
        elif self.path.startswith("/asset/"):
            nama = urllib.request.url2pathname(self.path[len("/asset/"):])
            # Cuma nama yang ada di daftar -- tidak bisa dipakai membaca
            # file lain lewat "../".
            if nama not in daftar_lagu():
                self.kirim(404, b"tidak ada", "text/plain")
                return
            p = FOLDER / nama
            self.kirim(200, p.read_bytes(), EKSTENSI[p.suffix.lower()])
        else:
            self.kirim(404, b"tidak ada", "text/plain")

    def do_POST(self):
        if self.path != "/lapor":
            self.kirim(404, b"tidak ada", "text/plain")
            return
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        code, isi = lapor(body)
        self.kirim(code, isi, "application/json")

    def log_message(self, fmt, *args):
        if self.command == "POST":
            sys.stderr.write("[lapor] %s\n" % (fmt % args))


HALAMAN = r"""<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8">
<title>Pemutar Lagu</title>
<style>
  body { font: 15px system-ui, sans-serif; background: #111; color: #eee;
         max-width: 520px; margin: 24px auto; padding: 0 16px; }
  button { font: inherit; padding: 8px 16px; margin-right: 6px; }
  ol { padding-left: 22px; }
  li.aktif { color: #6f6; font-weight: 600; }
  .ket { color: #999; font-size: 13px; }
  #status { margin: 12px 0; min-height: 1.4em; }
  .salah { color: #f77; }
</style>
</head>
<body>
<h2>Pemutar Lagu</h2>
<button id="mulai">Mulai</button>
<button id="lewati" disabled>Lewati</button>
<button id="berhenti" disabled>Berhenti</button>
<div id="status"></div>
<ol id="daftar"></ol>
<label>Geser suara <input id="geser" type="number" step="10" value="0"
  style="width:80px"> ms</label>
<div class="ket">Positif = lagu dibunyikan lebih lambat. Naikkan kalau
tarian terlihat telat dari lagunya, turunkan kalau tarian mendahului.</div>

<script>
// Jeda antara melapor dan membunyikan lagu. Harus lebih lama dari
// POLL_MUSIK di AvatarQueueV2 (0,5 dtk) plus waktu tempuh ke VM dan Roblox.
const JEDA_MS = 2000;

const audio = new Audio();
const el = id => document.getElementById(id);
let lagu = [], nomor = -1, timer = null, jalan = false;

try { el("geser").value = localStorage.getItem("geser") || 0; } catch (e) {}
el("geser").onchange = () => {
  try { localStorage.setItem("geser", el("geser").value); } catch (e) {}
};

function tulis(pesan, salah) {
  el("status").textContent = pesan;
  el("status").className = salah ? "salah" : "";
}

function gambar() {
  el("daftar").innerHTML = "";
  lagu.forEach((nama, i) => {
    const li = document.createElement("li");
    li.textContent = nama;
    if (i === nomor) li.className = "aktif";
    el("daftar").appendChild(li);
  });
}

async function putar(i) {
  clearTimeout(timer);
  audio.pause();
  nomor = i % lagu.length;
  gambar();
  audio.src = "/asset/" + encodeURIComponent(lagu[nomor]);
  audio.load();

  const dikirim = performance.now();
  try {
    const res = await fetch("/lapor", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ index: nomor + 1, nama: lagu[nomor],
                             mulai_dalam_ms: JEDA_MS }),
    });
    if (!res.ok) throw new Error("HTTP " + res.status + " " + await res.text());
    tulis("Lagu " + (nomor + 1) + " mulai sebentar lagi...");
  } catch (e) {
    // Lagunya tetap diputar: live tidak boleh senyap cuma karena server
    // antrian sedang bermasalah. Tariannya saja yang tidak ikut ganti.
    tulis("Gagal lapor ke server, tarian tidak ikut ganti: " + e.message, true);
  }

  // Dihitung dari saat laporan DIKIRIM, bukan saat balasannya datang:
  // server mulai menghitung JEDA_MS begitu laporannya tiba.
  const tunggu = JEDA_MS + Number(el("geser").value || 0)
               - (performance.now() - dikirim);
  timer = setTimeout(() => {
    if (!jalan) return;
    audio.play().catch(e => tulis("Browser menolak memutar: " + e.message, true));
    tulis("Sedang diputar: " + lagu[nomor]);
  }, Math.max(0, tunggu));
}

audio.onended = () => { if (jalan) putar(nomor + 1); };
audio.onerror = () => {
  tulis("File rusak / tidak bisa diputar: " + lagu[nomor] + " -- dilewati", true);
  if (jalan) setTimeout(() => putar(nomor + 1), 1000);
};

el("mulai").onclick = async () => {
  lagu = await (await fetch("/lagu")).json();
  if (!lagu.length) { tulis("Folder asset/ kosong.", true); return; }
  jalan = true;
  el("mulai").disabled = true;
  el("lewati").disabled = el("berhenti").disabled = false;
  putar(0);
};
el("lewati").onclick = () => putar(nomor + 1);
el("berhenti").onclick = () => {
  jalan = false;
  clearTimeout(timer);
  audio.pause();
  nomor = -1;
  gambar();
  tulis("Berhenti.");
  el("mulai").disabled = false;
  el("lewati").disabled = el("berhenti").disabled = true;
};

fetch("/lagu").then(r => r.json()).then(d => { lagu = d; gambar(); });
</script>
</body>
</html>
"""


if __name__ == "__main__":
    lagu = daftar_lagu()
    print(f"Lagu di {FOLDER}:")
    for i, nama in enumerate(lagu, 1):
        print(f"  {i}. {nama}  -> baris {i} PLAYLIST")
    print(f"Lapor ke {BASE_URL}/api/music"
          + ("" if API_TOKEN else "  (API_TOKEN kosong!)"))
    print(f"Buka http://127.0.0.1:{PORT} lalu tekan Mulai.  Ctrl+C berhenti.")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
