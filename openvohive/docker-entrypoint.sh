#!/bin/sh
set -eu

# ── 随机密码（未传 PROXY_WEB_PASSWORD 时每次启动生成）──────────
if [ -z "${PROXY_WEB_PASSWORD:-}" ]; then
  PROXY_WEB_PASSWORD=$(head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 12)
  printf '\n======== openvohive 未配置密码 ========\n'
  printf '  用户名: %s\n' "${PROXY_WEB_USERNAME:-admin}"
  printf '  密码:   %s\n' "$PROXY_WEB_PASSWORD"
  printf '  (docker logs 可再次查看；重启会换新密码)\n'
  printf '=======================================\n\n'
  export PROXY_WEB_PASSWORD
fi

# ── 配置路径：默认内置骨架，用户可挂载自定义覆盖 ─────────────────
CONFIG="${VOHIVE_CONFIG:-/app/config/config.yaml}"

# ── 数据/日志目录 ─────────────────────────────────────────
mkdir -p /app/data/logs

# ── 启动（viper AutomaticEnv 自动读取 PROXY_* 环境变量）────
exec /app/server -c "$CONFIG" ${VOHIVE_ARGS:-}
