# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

TikTok Live comments/gifts → queue server → Roblox avatars spawning on a stage. Code comments, identifiers, README, Makefile help and commit messages are in Indonesian; keep new ones in Indonesian to match. The README is long and partly historical (the big tier/podium section describes the deleted v13 script); when README and code disagree on numbers (e.g. tap thresholds), the code wins.

## Commands

All commands go through the [Makefile](Makefile) (`make` alone prints the list). Python is `./.venv/bin/python`.

```bash
make install                 # venv + requirements
make test                    # lint + test-tier + test-sync (run before claiming done)
make lint                    # lint_lua.py: undeclared UPPER_CASE globals in src/*.luau
make test-tier               # test_tier.py: AvatarQueueV2 functions run in real Lua (lupa)
make test-sync               # test_sync.py: KameraClientV2 dance-sync functions in real Lua
make selftest                # filter pipeline on a few sample comments
make mock [ARGS=...]         # needs a queue server; 19 checked scenarios, then random live-like traffic
make mock-tier3|4|5          # floods of Rose / Rosa / Doughnut
make mock-daftar [ARGS=...]  # mock_daftar.py: real usernames from tt-username-list.txt (giant first, Rose every 20 s)
make mock-komen              # same list, tier-1 comments only
make server                  # uvicorn main:app on :8000 (NO reload)
make listener [TIKTOK=acct]  # live listener; auto-picks TikFinity, else EulerStream
make watch                   # listener with --show-comments --dry-run (no queue writes)
make rojo                    # sync src/ into Studio via Rojo plugin
make peek | clear | status   # inspect the queue at BASE_URL (PUSH_URL from .env, else localhost)
make deploy                  # ship main.py + Dockerfile to the VM; EMPTIES the queue
```

There is no pytest. `test_tier.py` / `test_sync.py` are plain scripts with a `cek(label, cond)` helper; to run one test file directly: `./.venv/bin/python test_tier.py`. Useful mock knobs: `ARGS=--tanpa-pembuka` (skip fixed scenarios), `--seed N`, `--count N --fast`, `--dry-run`, and `USER_COOLDOWN_S=5 NAME_DEDUPE_S=8` to make the queue fill quickly.

Never use `make dev` / `--reload` or `make deploy` during a live session: the queue lives only in memory and is wiped on restart.

## Architecture

**Flow:** `tiktok_listener.py` (laptop) → `POST /api/push` (X-Token) → `main.py` (Docker container on VM behind Cloudflare + nginx) ← `GET /api/next` polled every 1–2 s by `AvatarQueueV2` in Roblox. Studio cannot call localhost, so Roblox always hits the public URL (`PUBLIC_URL` in Makefile).

**Listener (`tiktok_listener.py`)** — `Pipeline` class holds all filtering: format → blacklist → per-name dedupe (`NAME_DEDUPE_S`) → per-viewer cooldown (`USER_COOLDOWN_S`) → Roblox existence check (cached; fails *open* if Roblox is down). Gift → tier is by gift **name** (`GIFT_TIER`, default `rose:3,rosa:4,doughnut:5`), unknown gifts fall back to unit coin price (`tier_dari_koin`), combos upgrade via `GIFT_NAIK` (Rose×10 → tier 4). Each gift is one spawn; nothing is summed. Taps (likes) grant a spawn at `LIKE_PODIUM`/`LIKE_TIER`. Two event sources: TikTokLive/EulerStream (`run_live`) and TikFinity Desktop websocket (`run_tikfinity`); `run_auto` chooses. `mock_comments.py` **imports** `Pipeline` rather than copying it, so mock results equal live behavior.

**Queue server (`main.py`)** — `TIER_EFFECTS` defines per-tier scale/effects/spotlight. Paid entries (tier ≥ 2) bypass `QUEUE_MAX` and are inserted after all entries of equal-or-higher tier (higher tiers jump ahead; same tier keeps send order; tier 1 always last). `_ambil_entri` spaces out spotlights: a spotlight entry is held until both its tier's gap and the previous spotlight's duration + `SPOTLIGHT_NAPAS_S` have elapsed, serving free entries meanwhile. Startup checks (`_cek_sorotan_vs_jeda`, `_cek_kunci_lama`) validate `.env` spotlight/gap settings. `/api/settings` exposes timing so mock can pace itself; `/api/music` syncs songs from the dashboard to Roblox dances.

**Channels (Kanal) / buyers** — each `Kanal` has its own queue, spotlight state and music. Writers select a channel by `X-Token` (`API_TOKEN` → `utama`, or a buyer token from `buyers.json`); Roblox selects by `?owner=PrivateServerOwnerId` (no owner = Studio → `utama`; unknown owner → nothing served). `buyers.json` is hot-reloaded on mtime change, so adding buyers needs no restart. Gotcha: pushing with `API_TOKEN` lands in `utama`, which a buyer's Private Server never reads — `mock_daftar.py` therefore uses the buyer token (`--pembeli`, default `INSTANCE`).

**Per-buyer repos** — this checkout may be a buyer worktree (`../tt-rblx-<nama>` on branch `pembeli/<nama>`, created by `make pembeli-baru` / `pembeli.py`). `INSTANCE=<nama>` in `.env` makes `make deploy`, `vm-logs`, `exe` target container `tt-rblx-<nama>` and URL `…/<nama>` (nginx route via `deploy/nginx_route.sh`). Fixes land on `main` and are merged into buyer branches (`git merge main`). The compose service is deliberately named `server`, not `tt-rblx` (DNS collision on the nginx network).

**Deploy** — `make deploy` sends only `Dockerfile`, `main.py`, `roblox_ssl.py`, compose file; the VM `.env` is regenerated from the laptop `.env` filtered by `VM_ENV_KEYS` (`TIER*_SCALE|KOIN`, `SPOTLIGHT_*`, `QUEUE_MAX|BASI_S`, `API_TOKEN`). Listener/EulerStream/SSH settings stay local. VM address comes from `TUNNEL_SSH` in `.env` — the repo is public, never hard-code hosts or commit `.env`, `buyers.json`, `asset/`, `paket_pembeli/`. Fallback path: `make server` + `make tunnel` (autossh reverse tunnel), or `make up` for all three.

**Buyer .exe** — `tt_rblx.py` is the single PyInstaller entry (`tt_rblx.spec`, built from WSL by `build_exe.sh` / `make exe`): default runs `dashboard.py`, subcommands `listener`, `mock`, `peek`, `clear`. `dashboard.py` (`make dashboard`, :8765) runs whitelisted make targets, streams logs, plays `asset/laguN.mp3` (N-th file ↔ N-th `PLAYLIST` row in AvatarQueueV2), and proxies spawns so `API_TOKEN` never reaches the browser.

**Roblox side (`src/`, synced by Rojo per `default.project.json`)** — edit files in `src/`, never paste into Studio:
- `ServerScriptService/AvatarQueueV2.server.luau` — polls `/api/next`, spawns avatars into slots, tiers, aura, spotlight, nova "gempa" sweep, music.
- `StarterPlayer/StarterPlayerScripts/KameraClientV2.client.luau` — camera, spotlight shots, dance sync, hiding real players (`SEMBUNYI_PENONTON`).
- `ReplicatedStorage/TierNova.luau` — tier-4 nova cutscene module (plays its own SFX).

The Lua tests extract functions **verbatim** from these files by line markers (`local function name(` … column-0 `end`, and top-level `local CONST = …` tables), converting only `+=`. Keep that shape when refactoring tested functions or the tests will fail to find them. Many bugs here are silent in Studio (nil globals halt the main chunk, >31 Highlights silently not drawn), which is what `lint` and `test-tier` guard.

**`roblox_ssl.py`** — `_NoALPNContext` is required: httpx hangs on Roblox's edge when ALPN offers `http/1.1`. Every call to Roblox APIs (from `main.py` and the listener) must use `_make_ssl_context()`.
