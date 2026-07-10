#!/bin/bash
# vm-init.sh: 在 OrbStack Linux VM 内部执行
# 由 setup.sh 推入 VM 后运行（orb push + orb -m <vm> bash）
# 职责：装 docker → 改 USB 身份 → 起 openvohive 容器
set -euo pipefail

# 加载辅助函数（与 setup.sh 共用同一份）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || . /opt/vohive/lib/common.sh

require_root

VM_NAME="${VOHIVE_VM_NAME:-vohive}"
IMAGE="${VOHIVE_IMAGE:-openvohive:latest}"
DATA_DIR="/opt/vohive/data"
DEPLOY_DIR="${VOHIVE_DEPLOY_DIR:-/opt/vohive}"

# ── 1. 安装 Docker（若未装）──────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  log "安装 Docker..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl socat usbutils kmod
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
# dji2quectel.sh 由 setup.sh 一并传入 /opt/vohive/
D2Q="${DEPLOY_DIR}/dji2quectel.sh"
if [ -f "$D2Q" ]; then
  log "执行 USB 身份改写（幂等，已是 Quectel 则跳过）..."
  bash "$D2Q" || warn "改写未完成或需要重新绑定 USB 直通后重试"
  # 改身份后模块重新枚举，需重新加载驱动生成 ttyUSB（OrbStack 无 option，用 usbserial）
  if lsusb 2>/dev/null | grep -qi "2c7c:0125"; then
    log "为 Quectel 身份加载 usbserial 驱动..."
    modprobe usbserial 2>/dev/null || true
    NEW_ID="/sys/bus/usb-serial/drivers/generic/new_id"
    [ -f "$NEW_ID" ] && echo "2c7c 0125" > "$NEW_ID" 2>/dev/null || true
    # 也试 option（真实 Linux/UTM 环境有此驱动）
    modprobe option 2>/dev/null && echo "2c7c 0125" > /sys/bus/usb-serial/drivers/option1/new_id 2>/dev/null || true
    sleep 2
    log "ttyUSB 设备: $(ls /dev/ttyUSB* 2>/dev/null | wc -l) 个"
  fi
fi

# ── 3. 加载镜像（若 VM 内无）────────────────────────────
# setup.sh 会 docker save 推入；docker load 从 stdin 读
for img in openvohive vohive-legacy; do
  TARBALL="${DEPLOY_DIR}/${img}.tar"
  [ -f "$TARBALL" ] || continue
  log "加载镜像: $TARBALL"
  docker load -i "$TARBALL" && rm -f "$TARBALL"
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
