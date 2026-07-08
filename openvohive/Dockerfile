# syntax=docker/dockerfile:1.4
# openvohive: 开源版 vohive（聚焦短信收发/转发）
# 多阶段构建：前端(Vue/Bun) → 后端(Go) → 运行时(Alpine)
# 源码来自 openvohive/src/ git submodule

# ── Stage 1: 前端构建 ──────────────────────────────────────
FROM oven/bun:1-alpine AS frontend

WORKDIR /build
# 只拷 web 目录，利用缓存
COPY openvohive/src/web/package.json openvohive/src/web/bun.lock* ./web/
RUN cd web && bun install --frozen-lockfile || bun install

COPY openvohive/src/web/ ./web/
RUN cd web && bun run build

# ── Stage 2: 后端构建 ──────────────────────────────────────
FROM golang:1.26-alpine AS backend

RUN apk add --no-cache git

WORKDIR /build
# 拷贝完整源码
COPY openvohive/src/ ./
# 拷入前端构建产物（go:embed 需要 dist 在位）
COPY --from=frontend /build/web/dist ./web/dist

# 注：不执行 `go generate ./...`。
#   - web/generate.go 会调用 `bun run build`（此 stage 无 bun），且 dist 已从 stage 1 拷入
#   - internal/esim/pki/pki.go 会调用 `curl`（此 stage 无 curl），且 ci.json/accredited.json
#     已在 submodule 中提交
# 因此直接编译即可。
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w" -trimpath \
    -o /out/server .

# ── Stage 3: 运行时 ────────────────────────────────────────
FROM alpine:latest

RUN apk add --no-cache ca-certificates tzdata libc6-compat socat && \
    cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null || true

WORKDIR /app

COPY --from=backend /out/server /app/server
RUN chmod +x /app/server

COPY openvohive/config.example.yaml /app/config/config.yaml
COPY openvohive/docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

ENTRYPOINT ["/app/docker-entrypoint.sh"]
