#!/bin/bash
# vm-init.sh: 在 UTM Ubuntu VM 内部执行
# 由 setup.sh 通过 SSH 推入后运行
# 职责：装 docker → 改 USB 身份（首次）→ 拉 openvohive 镜像 → 起容器
set -euo pipefail

# 加载辅助函数
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/common.sh
. "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || . /opt/vohive/lib/common.sh

require_root

IMAGE="${VOHIVE_IMAGE:-ghcr.io/dannyge/openvohive:latest}"
DATA_DIR="/opt/vohive/data"
DEPLOY_DIR="${VOHIVE_DEPLOY_DIR:-/opt/vohive}"
CONTAINER="${VOHIVE_CONTAINER:-vohive}"

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

# ── 2. 改 USB 身份（幂等，首次部署时）────────────────────
# UTM Ubuntu VM 有完整内核（option 驱动），但大疆模块首次使用需改身份。
# dji2quectel.sh 会检测：已是 Quectel 则跳过；是大疆则改写。
D2Q="${DEPLOY_DIR}/dji2quectel.sh"
if [ -f "$D2Q" ]; then
  log "检查 USB 身份（幂等，已是 Quectel 则跳过）..."
  bash "$D2Q" 2>&1 || warn "改写未完成（可能模块已是 Quectel 身份，或需要重新绑定 USB 直通）"
  # UTM 完整内核：option 驱动会自动绑定 Quectel 设备生成 ttyUSB
  # 如果改身份后设备重新枚举，等驱动自动绑定
  if lsusb 2>/dev/null | grep -qi "2c7c:0125"; then
    log "Quectel 模块就绪"
    # 确保 option 和 qmi_wwan 已加载（通常自动，但保险）
    modprobe option 2>/dev/null || true
    modprobe qmi_wwan 2>/dev/null || true
    sleep 2
    TTY_COUNT=$(ls /dev/ttyUSB* 2>/dev/null | wc -l)
    CDC=$(ls /dev/cdc-wdm0 2>/dev/null && echo "有" || echo "无")
    log "设备节点: ${TTY_COUNT} 个 ttyUSB, cdc-wdm0=${CDC}"
  fi
fi

# ── 3. 拉取/更新 openvohive 镜像 ─────────────────────────
log "拉取 openvohive 镜像..."
docker pull "$IMAGE" 2>&1 | tail -2
ok "镜像就绪"

# ── 4. 启动平台容器（幂等）──────────────────────────────
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    ok "容器 $CONTAINER 已在运行，跳过"
  else
    warn "容器 $CONTAINER 已存在但未运行，删除后重建"
    docker rm -f "$CONTAINER"
    # 继续到下面的 docker run
    CONTAINER_EXISTS=0
  fi
  CONTAINER_EXISTS=1
else
  CONTAINER_EXISTS=0
fi

if [ "$CONTAINER_EXISTS" -eq 0 ]; then
  log "启动 $CONTAINER 容器..."
  mkdir -p "$DATA_DIR"
  # 构建 PROXY_* 环境变量参数
  ENV_ARGS=""
  while IFS= read -r line; do
    ENV_ARGS="$ENV_ARGS -e $line"
  done < <(env | grep '^PROXY_')
  # shellcheck disable=SC2086
  docker run -d \
    --name "$CONTAINER" \
    --restart unless-stopped \
    --privileged \
    -v /dev:/dev \
    -v /sys:/sys \
    -v "$DATA_DIR":/app/data \
    -p 7575:7575 \
    $ENV_ARGS \
    "$IMAGE"
  ok "容器 $CONTAINER 已启动"
  sleep 5
fi

# ── 5. 输出访问信息 ─────────────────────────────────────
VM_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost")
ok "VM 内部署完成！"
printf "\n"
printf "  后台地址: http://%s:7575\n" "$VM_IP"
printf "  查看密码: docker logs %s 2>&1 | grep 密码\n" "$CONTAINER"
printf "  （未传 PROXY_WEB_PASSWORD 时每次启动生成随机密码）\n"
printf "\n"
printf "  注意：设备需通过 openvohive 后台或 API 添加（device_backend=qmi, control_device=/dev/cdc-wdm0）\n"
printf "  setup.sh 会自动处理这步。\n"
printf "\n"
