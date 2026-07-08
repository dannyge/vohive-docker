#!/bin/bash
# vm-init.sh: 在 OrbStack Linux VM 内部执行
# 由 setup.sh 推入 VM 后运行（orb push + orb -m <vm> bash）
# 职责：装 docker → 改 USB 身份 → 起 openvohive 容器
set -euo pipefail

# 加载辅助函数（与 setup.sh 共用同一份）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || . /tmp/lib/common.sh

require_root

VM_NAME="${VOHIVE_VM_NAME:-vohive}"
IMAGE="${VOHIVE_IMAGE:-openvohive:latest}"
DATA_DIR="/opt/vohive/data"

# ── 1. 安装 Docker（若未装）──────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  log "安装 Docker..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl socat usbutils
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -qq
  apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
  ok "Docker 已安装并启动"
else
  ok "Docker 已存在，跳过安装"
fi

# ── 2. 改 USB 身份（幂等）────────────────────────────────
# dji2quectel.sh 由 setup.sh 一并推入 /tmp/
if [ -f /tmp/dji2quectel.sh ]; then
  log "执行 USB 身份改写（幂等，已是 Quectel 则跳过）..."
  bash /tmp/dji2quectel.sh || warn "改写未完成或需要重新绑定 USB 直通后重试"
fi

# ── 3. 加载镜像（若 VM 内无）────────────────────────────
# setup.sh 会 docker save 推入 /tmp/*.tar，这里 load
for tarball in /tmp/openvohive.tar /tmp/vohive-legacy.tar; do
  [ -f "$tarball" ] || continue
  log "加载镜像: $tarball"
  docker load -i "$tarball" && rm -f "$tarball"
done

# ── 4. 启动平台容器（幂等）──────────────────────────────
CONTAINER="${VOHIVE_CONTAINER:-vohive}"
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    ok "容器 $CONTAINER 已在运行，跳过"
  else
    warn "容器 $CONTAINER 已存在但未运行，启动之"
    docker start "$CONTAINER"
  fi
else
  log "启动 $CONTAINER 容器..."
  mkdir -p "$DATA_DIR"
  # 透传 PROXY_* 环境变量（setup.sh 已 export 或用户预设）
  docker run -d \
    --name "$CONTAINER" \
    --restart unless-stopped \
    --privileged \
    -v /dev:/dev \
    -v "$DATA_DIR":/app/data \
    -p 7575:7575 \
    $(env | grep '^PROXY_' | sed 's/^/-e /') \
    "$IMAGE"
  ok "容器 $CONTAINER 已启动"
fi

# ── 5. 输出访问信息 ─────────────────────────────────────
VM_IP=$(hostname -I | awk '{print $1}')
ok "部署完成！"
printf "\n"
printf "  后台地址: http://%s:7575\n" "$VM_IP"
printf "  查看密码: docker logs %s | grep 密码\n" "$CONTAINER"
printf "  （未传 PROXY_WEB_PASSWORD 时每次启动生成随机密码）\n\n"
