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

# ── 配置路径：持久化到 /app/data/config.yaml（容器重启不丢）──────
# 首次启动时从内置模板复制；后续重启沿用已持久化的配置（含设备/通知设置）
PERSIST_CONFIG="/app/data/config.yaml"
if [ -n "${VOHIVE_CONFIG:-}" ]; then
  CONFIG="$VOHIVE_CONFIG"
elif [ -f "$PERSIST_CONFIG" ]; then
  CONFIG="$PERSIST_CONFIG"
else
  # 首次启动：从内置模板复制到持久化目录
  cp /app/config/config.yaml "$PERSIST_CONFIG"
  CONFIG="$PERSIST_CONFIG"
fi

# ── 数据/日志目录 ─────────────────────────────────────────
mkdir -p /app/data/logs
# openvohive 硬编码日志路径为 logs/app.log（相对于 /app），
# 用符号链接将其重定向到持久化的 /app/data/logs/
if [ ! -e /app/logs ]; then
  ln -s /app/data/logs /app/logs
fi

# ── 启动（viper AutomaticEnv 自动读取 PROXY_* 环境变量）────
exec /app/server -c "$CONFIG" ${VOHIVE_ARGS:-}
