# AGENTS.md — VoHive Docker

Guidance for ZCode agents working in this repo. Read this before editing.

## What this repo is

Docker **packaging and deployment** for VoHive — a platform that manages Quectel 4G/LTE modems (EC20/EC25/EG25, etc.) and does SMS send/receive + forwarding (Telegram / Email / Webhook / Bark). This outer repo contains **only** Dockerfiles, entrypoints, deploy scripts, and CI. The actual application source lives in the `openvohive/src` git submodule.

This is **not** the app source repo. To change app behavior, edit code in `openvohive/src/` (a separate git repo), commit there, then bump the submodule pointer in this repo.

## Major directories

| Path | Role |
|---|---|
| `openvohive/` | Dockerfile + entrypoint + config for the **open-source** image (main). Source is the `openvohive/src` submodule (Go backend + Vue3 frontend). |
| `openvohive/src/` | **Git submodule** — the application. Go module `github.com/openvohive/openvohive`. `internal/` (api, device, notify, esim, modem, sms, qmi, mbim, db, config, backend, global, …), `pkg/` (logger, quectel-qmi, mbim, smscodec, taskpool), `web/` (Vue3 + Vite + Element Plus + Tailwind). |
| `vohive-legacy/` | Dockerfile for **closed-source** binary v1.5.5 (transition, being phased out). Binaries fetched into `assets/` via `scripts/fetch-assets.sh`. |
| `dji2quectel/` | One-time tool: rewrites DJI 4G module USB identity (`2ca3:4006` → Quectel `2c7c:0125`). Idempotent. Needs `--privileged` + `/sys` `/lib/modules` `/dev` mounts. |
| `scripts/` | `setup.sh` (macOS→UTM VM one-shot deploy), `vm-init.sh` (runs inside VM), `fetch-assets.sh` (fetch legacy binaries), `lib/common.sh` (shared log helpers). |
| `assets/` | Vendored third-party binaries + `mcc-mnc-table.json`. Committed on purpose (upstream sources may disappear). |
| `ref/` | Reference submodules (`vohive-release`, `dji-4g-vohive-mac`) — read-only material, do not edit. |
| `docs/` | Runbooks + deploy guides + `superpowers/` design specs/plans. |
| `.github/workflows/build.yml` | Multi-arch CI (GHCR). |
| `docker-bake.hcl`, `docker-compose.yml` | Build + compose orchestration. |

## Commands

### Build (outer repo — Docker images)
```bash
git submodule update --init --recursive     # REQUIRED before first build
bash scripts/fetch-assets.sh                # REQUIRED before building vohive-legacy
docker buildx bake --load                   # build all 3 images, local arch
docker buildx bake openvohive               # single target
REGISTRY=ghcr.io/owner docker buildx bake --push   # push to registry
```

### App source build (inside `openvohive/src/` submodule)
```bash
# Frontend
cd web && bun install && bun run build       # build = typecheck + vite build
bun run typecheck                             # vue-tsc --noEmit
bun run lint                                  # eslint src/**/*.{ts,vue}

# Backend
go generate ./...        # only when building OUTSIDE Docker (needs bun + curl)
CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -trimpath .
```

### Deploy
- macOS: `./scripts/setup.sh` (UTM Ubuntu VM, interactive)
- Native Linux: `docker compose up`
- See `docs/unraid-deploy.md` for Unraid.

## Architecture boundaries & rules

- **Packaging vs source**: This repo = Dockerfiles/scripts/CI only. App logic = `openvohive/src/` submodule. Don't duplicate app code here.
- **Backend stack**: Go 1.26 + Gin + GORM + Viper + SQLite. Frontend: Bun + Vue 3 + Vite + Element Plus + Tailwind.
- **`notify` channels** (open fork): `bark`, `email`, `telegram`, `webhook`. Legacy-only channels (QQ/feishu/pushplus) were removed — don't reintroduce.
- **Version injection**: `-ldflags -X` writes into `github.com/openvohive/openvohive/internal/global.{Version,BuildTime}`. Build arg is `VOHIVE_VERSION`.
- **Config**: all runtime config via `PROXY_*` env vars (Viper `AutomaticEnv`). Persisted to `/app/data/config.yaml`. See root `README.md` config table.

## Critical gotchas

- **Submodule is mandatory.** `openvohive/src` is a git submodule. Builds fail without `git submodule update --init --recursive`.
- **AVX / QEMU limitation.** openvohive's frontend uses bun; bun's x86_64 build needs AVX, which QEMU can't emulate. You **cannot** cross-build amd64 openvohive on an arm64 Mac locally. CI avoids this by building each arch on a **native runner** and merging manifests with `imagetools create`. Locally, only build your native arch.
- **`go generate` is NOT run inside the Dockerfile** (see comment in `openvohive/Dockerfile`): stage 2 has no bun/curl, and `web/dist` + `ci.json`/`accredited.json` are already committed in the submodule. Don't add `go generate` to the Dockerfile.
- **Kernel requirements.** openvohive needs a **full Linux kernel** with `option`/`qmi_wwan` drivers + USB uevent. Real Linux host or UTM Ubuntu VM only. **OrbStack's custom kernel lacks these drivers** — it can run dji2quectel (identity rewrite) but **cannot run openvohive**.
- **DJI module identity.** DJI QDC507 modules ship with private VID:PID `2ca3:4006` and must be rewritten to Quectel EC25 `2c7c:0125` (one-time, permanent via internal NV). `dji2quectel.sh` is idempotent (skips if already Quectel). After `AT+CFUN=1,1` the USB passthrough re-enumerates — may need rebinding.
- **Random password.** If `PROXY_WEB_PASSWORD` is unset, a new random password is generated each start and printed to logs: `docker logs vohive | grep 密码`.
- **Log persistence.** openvohive hardcodes `logs/app.log` relative to `/app`; the entrypoint symlinks `/app/logs → /app/data/logs` so logs survive restarts. Preserve this symlink logic if editing the entrypoint.
- **CI GHCR push** requires repo Settings → Actions → General → Workflow permissions = "Read and write permissions".

## Conventions

- **Comments and docs are in Chinese (中文).** Match the surrounding language when editing.
- Shell scripts use `set -euo pipefail` and stay **bash 3.2 compatible** (macOS default `/bin/bash`) — no associative arrays (see the deliberate avoidance in `scripts/fetch-assets.sh`).
- Scripts source `scripts/lib/common.sh` for `log`/`ok`/`warn`/`err`/`need_cmd`/`require_root` helpers.
- **Idempotency** is a design goal across scripts (dji2quectel, fetch-assets, config bootstrap) — preserve it.

## Read before sensitive changes

- `docs/dji2quectel-runbook.md` — before touching DJI→Quectel identity rewrite (has checkpoints + troubleshooting).
- `docs/superpowers/specs/2026-07-08-vohive-docker-images-design.md` + `docs/superpowers/plans/2026-07-08-vohive-docker-images.md` — design rationale for the image/CI architecture.
- Root `README.md` + per-module `README.md` — overview, config table, deploy paths.
- `openvohive/Dockerfile` header comment — explains why `go generate` is skipped.
