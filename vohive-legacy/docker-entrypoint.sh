#!/bin/sh
set -eu

# ── 1. 随机密码（未传 PROXY_WEB_PASSWORD 时每次启动生成）──────────
if [ -z "${PROXY_WEB_PASSWORD:-}" ]; then
  PROXY_WEB_PASSWORD=$(head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 12)
  printf '\n======== vohive-legacy 未配置密码 ========\n'
  printf '  用户名: %s\n' "${PROXY_WEB_USERNAME:-admin}"
  printf '  密码:   %s\n' "$PROXY_WEB_PASSWORD"
  printf '  (docker logs 可再次查看；重启会换新密码)\n'
  printf '==========================================\n\n'
  export PROXY_WEB_PASSWORD
fi

# ── 2. 渲染 config.yaml（从 PROXY_* env）──────────────────────────
# 优先使用用户挂载的 config（若存在），否则从 env 渲染
CONFIG_PATH="${VOHIVE_CONFIG:-/app/data/config.yaml}"

if [ "$CONFIG_PATH" = "/app/data/config.yaml" ]; then
  mkdir -p /app/data/logs

  # server.port 处理：vohive 期望 ":7575" 格式
  PORT="${PROXY_SERVER_PORT:-7575}"
  case "$PORT" in
    :*) PORT_YAML="$PORT" ;;
    *)  PORT_YAML=":$PORT" ;;
  esac

  # webhook 文本模板默认值（含 {{}}，必须用显式空值判断；
  # 不能用 ${VAR:-...}，否则 {{device_label}} 里的 } 会提前截断参数展开）
  if [ -n "${PROXY_WEBHOOK_TEXT_TEMPLATE:-}" ]; then
    WEBHOOK_TEXT_TEMPLATE="$PROXY_WEBHOOK_TEXT_TEMPLATE"
  else
    WEBHOOK_TEXT_TEMPLATE='{{device_label}} {{text}}'
  fi

  cat > "$CONFIG_PATH" <<EOF
bark:
  enabled: ${PROXY_BARK_ENABLED:-false}
  group: ${PROXY_BARK_GROUP:-vohive}
  urls: ${PROXY_BARK_URLS:-[]}
email:
  enabled: ${PROXY_EMAIL_ENABLED:-false}
  smtp_host: "${PROXY_EMAIL_SMTP_HOST:-}"
  smtp_port: ${PROXY_EMAIL_SMTP_PORT:-0}
  username: "${PROXY_EMAIL_USERNAME:-}"
  password: "${PROXY_EMAIL_PASSWORD:-}"
  from_address: "${PROXY_EMAIL_FROM_ADDRESS:-}"
  to_addresses: ${PROXY_EMAIL_TO_ADDRESSES:-[]}
  use_ssl: ${PROXY_EMAIL_USE_SSL:-false}
feishu:
  enabled: ${PROXY_FEISHU_ENABLED:-false}
  app_id: "${PROXY_FEISHU_APP_ID:-}"
  app_secret: "${PROXY_FEISHU_APP_SECRET:-}"
  chat_ids: ${PROXY_FEISHU_CHAT_IDS:-[]}
pushplus:
  enabled: ${PROXY_PUSHPLUS_ENABLED:-false}
  token: "${PROXY_PUSHPLUS_TOKEN:-}"
  topic: "${PROXY_PUSHPLUS_TOPIC:-}"
  channel: ${PROXY_PUSHPLUS_CHANNEL:-wechat}
qq:
  enabled: ${PROXY_QQ_ENABLED:-false}
  app_id: "${PROXY_QQ_APP_ID:-}"
  app_secret: "${PROXY_QQ_APP_SECRET:-}"
  group_ids: "${PROXY_QQ_GROUP_IDS:-}"
  direct_ids: "${PROXY_QQ_DIRECT_IDS:-}"
server:
  port: "$PORT_YAML"
telegram:
  enabled: ${PROXY_TELEGRAM_ENABLED:-false}
  bot_token: "${PROXY_TELEGRAM_BOT_TOKEN:-}"
  admin_id: ${PROXY_TELEGRAM_ADMIN_ID:-0}
  chat_id: ${PROXY_TELEGRAM_CHAT_ID:-0}
  base_url: "${PROXY_TELEGRAM_BASE_URL:-}"
  proxy: "${PROXY_TELEGRAM_PROXY:-}"
web:
  username: "${PROXY_WEB_USERNAME:-admin}"
  password: "${PROXY_WEB_PASSWORD}"
webhook:
  enabled: ${PROXY_WEBHOOK_ENABLED:-false}
  urls: ${PROXY_WEBHOOK_URLS:-[]}
  secret: "${PROXY_WEBHOOK_SECRET:-}"
  headers: ${PROXY_WEBHOOK_HEADERS:-{}}
  timeout_ms: ${PROXY_WEBHOOK_TIMEOUT_MS:-5000}
  retry_max: ${PROXY_WEBHOOK_RETRY_MAX:-3}
  text_template: "${WEBHOOK_TEXT_TEMPLATE}"
devices: []
EOF
  chmod 600 "$CONFIG_PATH"
fi

# ── 3. 启动 ──────────────────────────────────────────────
exec /app/vohive -c "$CONFIG_PATH"
