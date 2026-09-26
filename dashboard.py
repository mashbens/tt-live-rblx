"""
Dashboard live: tombol make, log, putar lagu, dan spawn manual di satu halaman.

Jalankan:
    make dashboard
lalu buka http://127.0.0.1:8765 di browser. Ctrl+C mematikan dashboard DAN
semua proses yang dinyalakan dari sana (listener, rojo, dst.).

Isinya:
- Tombol make. Cuma target di PERINTAH yang bisa dijalankan -- halaman ini
  tidak bisa dipakai menjalankan perintah sembarang.
- Log tiap perintah, termasuk output `make listener` secara langsung.
- Putar lagu. Lagu diambil dari folder asset/, urut nama file. File ke-N
  berpasangan dengan baris ke-N PLAYLIST di AvatarQueueV2 -- lagu1.mp3 =
  baris 1, dan seterusnya.
- Spawn manual: username + tier langsung ke /api/push.

Cara sinkron lagunya: sebelum lagu dimulai, halaman melapor ke server antrian
(/api/music) "lagu N mulai JEDA_MS lagi". Server membalas sisa waktunya
menurut jamnya sendiri, halaman menunggu sisa itu lalu memutar lagunya. Roblox
polling tiap POLL_MUSIK dan menunggu sisa waktu yang sama, jadi tarian ganti
di detik yang sama dengan lagunya.

Laporan lagu berikutnya dikirim SELAGI lagu sekarang masih bunyi, supaya
tidak ada hening di pergantian: lagu berikutnya masuk saat yang sekarang
tinggal "Sambung" detik, dan keduanya disilang-pudarkan.

Lapor dan spawn lewat server kecil ini, bukan langsung dari browser, supaya
API_TOKEN tidak pernah sampai ke halaman.

MODE PEMBELI (.exe Windows, lihat tt_rblx.py): tidak ada `make` di sana,
jadi tombolnya menjalankan perintahnya langsung dan cuma yang dipakai
pembeli saat live -- listener, lihat/kosongkan antrian. Deploy, tunnel, dan
Rojo urusan pemilik repo.
"""

import atexit
import itertools
import json
import os
import re
import signal
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from dotenv import load_dotenv

# .exe PyInstaller membongkar dirinya ke folder sementara, jadi __file__
# menunjuk ke sana. .env, asset/, dan blacklist ada di sebelah .exe-nya.
BEKU = getattr(sys, "frozen", False)
ROOT = Path(sys.executable).parent if BEKU else Path(__file__).parent
MODE_PEMBELI = BEKU or os.name == "nt"

load_dotenv(ROOT / ".env")

FOLDER = ROOT / "asset"
PORT = int(os.environ.get("PLAYER_PORT", "8765"))
EKSTENSI = {".mp3": "audio/mpeg", ".ogg": "audio/ogg", ".wav": "audio/wav",
            ".m4a": "audio/mp4"}

# Server antrian yang sama dengan listener: PUSH_URL di .env kalau ada (VM),
# kalau tidak `make server` di laptop.
_push = os.environ.get("PUSH_URL", "").strip()
BASE_URL = (_push.removesuffix("/api/push") if _push
            else "http://127.0.0.1:8000")
API_TOKEN = os.environ.get("API_TOKEN", "")

# Target make yang boleh dijalankan dari halaman.
#   terus   = proses yang jalan sampai dimatikan (tombol Start/Stop)
#   yakin   = minta konfirmasi dulu di browser
PERINTAH = {
    "listener": {"terus": True,  "ket": "baca komentar live TikTok"},
    "rojo":     {"terus": True,  "ket": "sinkron script ke Studio"},
    "server":   {"terus": True,  "ket": "server antrian di laptop (cadangan)"},
    "tunnel":   {"terus": True,  "ket": "tunnel SSH ke VM (cadangan)"},
    "mock":     {"terus": True,  "ket": "komentar palsu untuk tes"},
    "status":   {"terus": False, "ket": "cek server, tunnel, antrian"},
    "peek":     {"terus": False, "ket": "lihat isi antrian"},
    "clear":    {"terus": False, "ket": "kosongkan antrian", "yakin": True},
    "test":     {"terus": False, "ket": "lint + uji tier + uji sync"},
    "deploy":   {"terus": False, "ket": "kirim server ke VM", "yakin": True},
}

# Perintah untuk pembeli: nilainya argumen tt_rblx.py (lihat di sana).
#
# Listener-nya TikFinity SAJA, bukan `auto`: pembeli tidak punya key
# EulerStream, dan `auto` jatuh ke sana begitu TikFinity belum dibuka --
# yang terlihat pembeli jadi error EulerStream, bukan "buka TikFinity".
# Mode tikfinity cukup menunggu dan menyambung sendiri begitu aplikasinya
# jalan. Username TikTok juga tidak perlu: akun yang dibaca ditentukan
# TikFinity.
PERINTAH_PEMBELI = {
    "listener":    {"terus": True,  "ket": "baca komentar lewat TikFinity",
                    "argv": ["listener", "--source", "tikfinity"]},
    "mock":        {"terus": True,  "ket": "komentar palsu untuk tes, tanpa live",
                    "argv": ["mock"]},
    "peek":        {"terus": False, "ket": "lihat isi antrian",
                    "argv": ["peek"]},
    "clear":       {"terus": False, "ket": "kosongkan antrian", "yakin": True,
                    "argv": ["clear"]},
}
if MODE_PEMBELI:
    PERINTAH = PERINTAH_PEMBELI


def perintah(nama: str) -> list[str]:
    if not MODE_PEMBELI:
        return ["make", "--no-print-directory", nama]
    argv = PERINTAH_PEMBELI[nama]["argv"]
    if BEKU:
        return [sys.executable, *argv]
    return [sys.executable, str(ROOT / "tt_rblx.py"), *argv]

# Warna ANSI dari listener dan rojo tidak berarti apa-apa di HTML.
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


class Job:
    """Satu perintah yang sedang atau pernah dijalankan."""

    def __init__(self, nama: str):
        self.nama = nama
        self.proc: subprocess.Popen | None = None
        # (nomor, baris). Nomor terus naik supaya halaman cukup meminta
        # "baris sesudah nomor N" tanpa menerima ulang semuanya.
        self.baris: deque[tuple[int, str]] = deque(maxlen=3000)
        self.nomor = itertools.count(1)
        self.lock = threading.Lock()

    def jalan(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def tulis(self, teks: str) -> None:
        with self.lock:
            self.baris.append((next(self.nomor), teks))

    def start(self) -> None:
        if self.jalan():
            return
        self.tulis(f"$ {self.nama}   ({time.strftime('%H:%M:%S')})")
        self.proc = subprocess.Popen(
            perintah(self.nama), cwd=ROOT,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            # Grup proses sendiri: Stop harus ikut mematikan anak-anaknya
            # (python, rojo, autossh), bukan cuma `make`-nya. Windows tidak
            # punya grup proses POSIX -- di sana tidak ada `make` di tengah,
            # jadi mematikan prosesnya sendiri sudah cukup.
            start_new_session=os.name != "nt",
            # Tanpa PYTHONUNBUFFERED print() Python ditahan di buffer dan
            # log listener baru muncul bergerombol tiap beberapa KB.
            # PYTHONIOENCODING: di Windows pipa memakai cp1252, dan emoji
            # pertama di nama penonton TikTok mematikan listener.
            env={**os.environ, "PYTHONUNBUFFERED": "1",
                 "PYTHONIOENCODING": "utf-8"})
        threading.Thread(target=self._baca, args=(self.proc,),
                         daemon=True).start()

    def _baca(self, proc: subprocess.Popen) -> None:
        for raw in proc.stdout:
            self.tulis(ANSI.sub("", raw.decode(errors="replace").rstrip()))
        kode = proc.wait()
        self.tulis(f"-- selesai, kode {kode} ({time.strftime('%H:%M:%S')})")

    def stop(self) -> None:
        if not self.jalan():
            return
        if os.name == "nt":
            self.proc.terminate()
            return
        try:
            os.killpg(self.proc.pid, signal.SIGTERM)
            self.proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(self.proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    def ambil(self, dari: int) -> list[tuple[int, str]]:
        with self.lock:
            return [b for b in self.baris if b[0] > dari]


JOBS = {nama: Job(nama) for nama in PERINTAH}


def matikan_semua() -> None:
    for job in JOBS.values():
        job.stop()


atexit.register(matikan_semua)


def daftar_lagu() -> list[str]:
    if not FOLDER.is_dir():
        return []
    return sorted(p.name for p in FOLDER.iterdir()
                  if p.suffix.lower() in EKSTENSI)


def kirim_ke_server(path: str, body: bytes | None,
                    method: str = "POST") -> tuple[int, bytes]:
    req = urllib.request.Request(
        BASE_URL + path, data=body, method=method,
        # User-Agent bawaan urllib ("Python-urllib/3.x") diblokir
        # Cloudflare di depan VM -- balasannya "error code: 1010".
        headers={"Content-Type": "application/json", "X-Token": API_TOKEN,
                 "User-Agent": "tt-rblx-dashboard/1.0"})
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

    def json(self, data, code: int = 200) -> None:
        self.kirim(code, json.dumps(data).encode(), "application/json")

    def aman(self) -> bool:
        """Tolak permintaan yang bukan dari halaman dashboard ini sendiri.

        Dashboard ini bisa menjalankan `make deploy`. Tanpa pemeriksaan ini,
        situs mana pun yang kebetulan terbuka di browser yang sama bisa
        mengirim POST ke 127.0.0.1:8765 dan menjalankannya.
        - Host harus 127.0.0.1/localhost: menutup DNS rebinding.
        - POST wajib membawa header X-Dashboard: browser tidak mengizinkan
          situs lain menambahkan header sendiri tanpa izin CORS, dan izin
          itu tidak pernah diberikan server ini.
        """
        host = self.headers.get("Host", "").rsplit(":", 1)[0]
        if host not in ("127.0.0.1", "localhost"):
            return False
        return self.command != "POST" or self.headers.get("X-Dashboard") == "1"

    def do_GET(self):
        if not self.aman():
            self.kirim(403, b"ditolak", "text/plain")
            return
        path, _, query = self.path.partition("?")
        if path == "/":
            self.kirim(200, HALAMAN.encode(), "text/html; charset=utf-8")
        elif path == "/lagu":
            self.json(daftar_lagu())
        elif path.startswith("/asset/"):
            nama = urllib.request.url2pathname(path[len("/asset/"):])
            # Cuma nama yang ada di daftar -- tidak bisa dipakai membaca
            # file lain lewat "../".
            if nama not in daftar_lagu():
                self.kirim(404, b"tidak ada", "text/plain")
                return
            p = FOLDER / nama
            self.kirim(200, p.read_bytes(), EKSTENSI[p.suffix.lower()])
        elif path == "/jobs":
            self.json([{"nama": n, "jalan": JOBS[n].jalan(), **PERINTAH[n]}
                       for n in PERINTAH])
        elif path.startswith("/log/") and path[5:] in JOBS:
            m = re.search(r"dari=(\d+)", query)
            job = JOBS[path[5:]]
            self.json({"baris": job.ambil(int(m.group(1)) if m else 0),
                       "jalan": job.jalan()})
        else:
            self.kirim(404, b"tidak ada", "text/plain")

    def do_POST(self):
        if not self.aman():
            self.kirim(403, b"ditolak", "text/plain")
            return
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))

        if self.path == "/lapor":
            t = time.perf_counter()
            code, isi = kirim_ke_server("/api/music", body)
            ms = (time.perf_counter() - t) * 1000
            # Dicatat supaya lapor yang tersendat kelihatan. Tidak lagi
            # membuat tarian telat -- halaman menunggu sisa_ms dari server --
            # tapi tetap tanda jaringan sedang bermasalah.
            print(f"[lapor] {body.decode(errors='replace')} -> {code} "
                  f"dalam {ms:.0f} ms" + ("  (LAMBAT)" if ms > 1000 else ""))
            self.kirim(code, isi, "application/json")

        elif self.path == "/spawn":
            code, isi = kirim_ke_server("/api/push", body)
            print(f"[spawn] {body.decode(errors='replace')} -> {code}")
            self.kirim(code, isi, "application/json")

        elif (m := re.fullmatch(r"/jobs/([\w-]+)/(start|stop)", self.path)) \
                and m.group(1) in JOBS:
            job = JOBS[m.group(1)]
            job.start() if m.group(2) == "start" else job.stop()
            self.json({"jalan": job.jalan()})

        else:
            self.kirim(404, b"tidak ada", "text/plain")

    def log_message(self, fmt, *args):
        pass  # polling log tiap detik cuma bikin terminal berisik


HALAMAN = r"""<!doctype html>
<html lang="id">
<head>
<meta charset="utf-8">
<title>tt-rblx</title>
<style>
  body { font: 14px system-ui, sans-serif; background: #111; color: #ddd;
         margin: 0 auto; padding: 12px 16px; max-width: 1100px; }
  h2 { font-size: 15px; margin: 18px 0 8px; color: #fff; }
  button { font: inherit; padding: 5px 12px; margin: 0 4px 4px 0;
           background: #2a2a2a; color: #ddd; border: 1px solid #444;
           border-radius: 4px; cursor: pointer; }
  button:disabled { opacity: .4; cursor: default; }
  button.pilih { border-color: #6af; }
  input, select { font: inherit; padding: 4px 6px; background: #1c1c1c;
                  color: #ddd; border: 1px solid #444; border-radius: 4px; }
  .kolom { display: grid; grid-template-columns: 1fr 1fr; gap: 0 24px; }
  @media (max-width: 800px) { .kolom { grid-template-columns: 1fr; } }
  table { border-collapse: collapse; width: 100%; }
  td { padding: 3px 6px 3px 0; vertical-align: middle; }
  .titik { display: inline-block; width: 8px; height: 8px;
           border-radius: 50%; background: #555; margin-right: 6px; }
  .titik.on { background: #4c4; }
  .ket { color: #888; font-size: 12px; }
  #log { background: #000; color: #cfc; font: 12px/1.4 monospace;
         height: 360px; overflow: auto; padding: 8px; white-space: pre-wrap;
         border: 1px solid #333; border-radius: 4px; }
  ol { padding-left: 22px; margin: 6px 0; }
  li.aktif { color: #6f6; font-weight: 600; }
  .salah { color: #f77; }
  #status, #hasilSpawn { min-height: 1.4em; margin: 6px 0; }
</style>
</head>
<body>

<div class="kolom">
<div>
  <h2>Perintah</h2>
  <table id="jobs"></table>
</div>

<div>
  <h2>Putar lagu</h2>
  <button id="mulai">Mulai</button>
  <button id="lewati" disabled>Lewati</button>
  <button id="berhenti" disabled>Berhenti</button>
  <div id="status"></div>
  <ol id="daftar"></ol>
  <label>Geser suara <input id="geser" type="number" step="10" value="0"
    style="width:70px"> ms</label>
  <div class="ket">Positif = lagu dibunyikan lebih lambat. Naikkan kalau
  tarian terlihat telat dari lagunya, turunkan kalau tarian mendahului.</div>
  <label>Sambung <input id="sambung" type="number" min="0" max="10" step="0.5"
    value="3" style="width:60px"> detik</label>
  <div class="ket">Lagu berikutnya masuk sekian detik sebelum yang sekarang
  habis, keduanya disilang-pudarkan. 0 = tanpa tumpang tindih, tapi tetap
  tanpa jeda hening.</div>

  <h2>Spawn manual</h2>
  <form id="spawn">
    <input id="user" placeholder="username Roblox" required style="width:170px">
    <select id="tier">
      <option value="1">tier 1 - biasa</option>
      <option value="2">tier 2</option>
      <option value="3">tier 3 - sinematik</option>
      <option value="4">tier 4 - nova</option>
      <option value="5">tier 5 - raksasa</option>
    </select>
    <button>Spawn</button>
  </form>
  <div id="hasilSpawn"></div>
</div>
</div>

<h2>Log: <span id="judulLog">listener</span></h2>
<div id="log"></div>

<script>
const el = id => document.getElementById(id);

// Semua POST membawa X-Dashboard -- lihat Handler.aman di dashboard.py.
const kirim = (url, data) => fetch(url, {
  method: "POST",
  headers: { "Content-Type": "application/json", "X-Dashboard": "1" },
  body: data === undefined ? "" : JSON.stringify(data),
});

// ---------------------------------------------------------------- perintah

let jobs = [], lihat = "listener", dariNo = 0;

async function muatJobs() {
  jobs = await (await fetch("/jobs")).json();
  el("jobs").innerHTML = "";
  for (const j of jobs) {
    const tr = document.createElement("tr");
    const tombol = j.terus
      ? (j.jalan ? `<button data-a="stop">Stop</button>`
                 : `<button data-a="start">Start</button>`)
      : `<button data-a="start" ${j.jalan ? "disabled" : ""}>Jalankan</button>`;
    tr.innerHTML =
      `<td><span class="titik ${j.jalan ? "on" : ""}"></span>` +
      `<b>${j.nama}</b></td><td>${tombol}` +
      `<button data-a="log" class="${lihat === j.nama ? "pilih" : ""}">log</button></td>` +
      `<td class="ket">${j.ket}</td>`;
    tr.querySelectorAll("button").forEach(b => b.onclick = () => aksi(j, b.dataset.a));
    el("jobs").appendChild(tr);
  }
}

async function aksi(j, a) {
  if (a === "log") { gantiLog(j.nama); return; }
  if (a === "start" && j.yakin && !confirm("Yakin menjalankan " + j.nama + "?")) return;
  await kirim(`/jobs/${j.nama}/${a}`);
  gantiLog(j.nama);
  muatJobs();
}

function gantiLog(nama) {
  lihat = nama; dariNo = 0;
  el("judulLog").textContent = nama;
  el("log").textContent = "";
  muatJobs();
}

async function tarikLog() {
  try {
    const nama = lihat;
    const d = await (await fetch(`/log/${nama}?dari=${dariNo}`)).json();
    if (nama !== lihat || !d.baris.length) return;
    const box = el("log");
    const diBawah = box.scrollTop + box.clientHeight >= box.scrollHeight - 30;
    box.textContent += d.baris.map(b => b[1]).join("\n") + "\n";
    dariNo = d.baris[d.baris.length - 1][0];
    // Ikut turun cuma kalau memang sedang di bawah -- kalau kamu sedang
    // menggulir ke atas membaca log lama, jangan ditarik paksa.
    if (diBawah) box.scrollTop = box.scrollHeight;
  } catch (e) {}
}

setInterval(tarikLog, 1000);
setInterval(muatJobs, 3000);
muatJobs(); tarikLog();

// ------------------------------------------------------------------ spawn

el("spawn").onsubmit = async ev => {
  ev.preventDefault();
  const username = el("user").value.trim();
  if (!username) return;
  try {
    const res = await kirim("/spawn", { username, tier: Number(el("tier").value) });
    const d = await res.json().catch(() => ({}));
    el("hasilSpawn").className = res.ok && d.ok ? "" : "salah";
    el("hasilSpawn").textContent = res.ok && d.ok
      ? `${d.queued} masuk antrian (tier ${d.tier}, antrian ${d.size})`
      : "Gagal: " + (d.error || d.detail || "HTTP " + res.status);
  } catch (e) {
    el("hasilSpawn").className = "salah";
    el("hasilSpawn").textContent = "Gagal: " + e.message;
  }
};

// ------------------------------------------------------------------- lagu

// Jeda antara melapor dan membunyikan lagu. Harus lebih lama dari
// POLL_MUSIK di AvatarQueueV2 (0,5 dtk) plus waktu tempuh ke VM dan Roblox.
const JEDA_MS = 2000;

// Dua pemutar bergantian. Lagu berikutnya disiapkan dan DILAPORKAN selagi
// lagu sekarang masih bunyi, lalu masuk saat yang sekarang tinggal
// "sambung" detik dan keduanya disilang-pudarkan. Dulu lagu berikutnya baru
// dilaporkan sesudah yang sekarang habis, jadi tiap pergantian hening
// JEDA_MS ditambah hening di ekor file-nya.
const pemutar = [new Audio(), new Audio()];
let audio = pemutar[0];   // yang sedang / akan bunyi -- yang dipantau
let lagu = [], nomor = -1, timer = null, pudar = null, jalan = false;
// Naik tiap putar(). Lewati yang diklik dua kali cepat membuat dua laporan
// di jalan sekaligus; balasan yang lama tidak boleh ikut memasang timer.
let giliran = 0;

try { el("geser").value = localStorage.getItem("geser") || 0; } catch (e) {}
try { el("sambung").value = localStorage.getItem("sambung") ?? 3; } catch (e) {}
el("geser").onchange = () => {
  try { localStorage.setItem("geser", el("geser").value); } catch (e) {}
};
el("sambung").onchange = () => {
  try { localStorage.setItem("sambung", el("sambung").value); } catch (e) {}
};
const detikSambung = () => Math.max(0, Number(el("sambung").value) || 0);
const msGeser = () => Number(el("geser").value || 0);

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

function hentikanSemua() {
  clearInterval(pudar);
  pemutar.forEach(a => { a.pause(); a.volume = 1; });
}

// lama turun 1 -> 0, baru naik 0 -> 1, selama detikSambung().
function silang(lama, baru) {
  clearInterval(pudar);
  const durasi = detikSambung() * 1000;
  if (lama.paused || durasi <= 0) { lama.pause(); lama.volume = 1; baru.volume = 1; return; }
  const mulai = performance.now();
  baru.volume = 0;
  pudar = setInterval(() => {
    const t = Math.min(1, (performance.now() - mulai) / durasi);
    baru.volume = t;
    lama.volume = 1 - t;
    if (t >= 1) {
      clearInterval(pudar);
      lama.pause();
      lama.volume = 1;
    }
  }, 50);
}

// sambung = true: lagu sekarang dibiarkan bunyi dan dipudarkan saat yang
// baru masuk. false (Mulai, Lewati, file rusak): potong langsung.
async function putar(i, sambung) {
  const ini = ++giliran;
  clearTimeout(timer);
  const lama = audio;
  if (!sambung) hentikanSemua();
  nomor = i % lagu.length;
  gambar();
  const baru = pemutar[pemutar.indexOf(lama) ^ 1];
  baru.pause();
  baru.volume = 1;
  baru.src = "/asset/" + encodeURIComponent(lagu[nomor]);
  baru.load();
  audio = baru;

  const dikirim = performance.now();
  let sisa;
  try {
    const res = await kirim("/lapor", { index: nomor + 1, nama: lagu[nomor],
                                        mulai_dalam_ms: JEDA_MS });
    if (!res.ok) throw new Error("HTTP " + res.status + " " + await res.text());
    const d = await res.json();
    const pp = Math.round(performance.now() - dikirim);
    // Patokan yang sama dengan Roblox: jam VM. Lihat set_music di main.py.
    // Cadangan untuk server lama yang belum membalas sisa_ms: dihitung
    // dari saat laporan DIKIRIM, meleset sejauh lamanya laporan di jalan.
    sisa = typeof d.sisa_ms === "number" ? d.sisa_ms : JEDA_MS - pp;
    tulis("Lagu " + (nomor + 1) + " mulai sebentar lagi... (lapor " + pp + " ms)");
  } catch (e) {
    // Lagunya tetap diputar: live tidak boleh senyap cuma karena server
    // antrian sedang bermasalah. Tariannya saja yang tidak ikut ganti.
    tulis("Gagal lapor ke server, tarian tidak ikut ganti: " + e.message, true);
    sisa = 0;
  }
  if (ini !== giliran) return;

  timer = setTimeout(() => {
    if (!jalan) return;
    if (sambung) silang(lama, baru);
    baru.play().catch(e => tulis("Browser menolak memutar: " + e.message, true));
    tulis("Sedang diputar: " + lagu[nomor]);
  }, Math.max(0, sisa + msGeser()));
}

// Lagu berikutnya dipicu sejauh "sambung + waktu lapor" sebelum yang
// sekarang habis. Lagu yang lebih pendek dari dua kali jendela itu
// dibiarkan habis sendiri -- kalau tidak, dia dipotong begitu mulai.
function cekSambung() {
  if (this !== audio || !jalan || this.paused) return;
  const d = this.duration;
  const muka = detikSambung() + (JEDA_MS + msGeser()) / 1000;
  if (!isFinite(d) || d < muka * 2) return;
  if (d - this.currentTime <= muka) putar(nomor + 1, true);
}

pemutar.forEach(a => {
  a.ontimeupdate = cekSambung;
  // Cuma jalan kalau sambung tidak sempat memicu (lagu pendek). Yang sudah
  // disambung bukan `audio` lagi, jadi ekornya tidak memicu dua kali.
  a.onended = function () { if (this === audio && jalan) putar(nomor + 1); };
  a.onerror = function () {
    if (this !== audio || !jalan) return;
    tulis("File rusak / tidak bisa diputar: " + lagu[nomor] + " -- dilewati", true);
    setTimeout(() => putar(nomor + 1), 1000);
  };
});

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
  giliran++;
  clearTimeout(timer);
  hentikanSemua();
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


def _keluar(*_):
    matikan_semua()
    sys.exit(0)


def perintah_antrian(nama: str) -> int:
    """`peek` / `clear` untuk mode pembeli: pengganti curl di Makefile."""
    if nama == "peek":
        code, isi = kirim_ke_server("/api/peek", None, "GET")
    else:
        code, isi = kirim_ke_server("/api/clear", None, "DELETE")
    print(f"{BASE_URL} -> {code}")
    print(isi.decode("utf-8", errors="replace"))
    return 0 if code == 200 else 1


def main() -> None:
    # SIGTERM juga, bukan cuma Ctrl+C: atexit tidak jalan kalau proses
    # dibunuh sinyal, dan listener yang yatim terus mengirim ke antrian.
    signal.signal(signal.SIGTERM, _keluar)

    lagu = daftar_lagu()
    print(f"Lagu di {FOLDER}:")
    for i, nama in enumerate(lagu, 1):
        print(f"  {i}. {nama}  -> baris {i} PLAYLIST")
    print(f"Server antrian: {BASE_URL}"
          + ("" if API_TOKEN else "  (API_TOKEN kosong!)"))
    print(f"Buka http://127.0.0.1:{PORT}   Ctrl+C mematikan dashboard "
          "dan semua proses yang dinyalakan dari sana.")
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    if BEKU:
        # Pembeli mengklik .exe-nya dua kali, tidak mengetik alamat.
        import webbrowser
        webbrowser.open(f"http://127.0.0.1:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
