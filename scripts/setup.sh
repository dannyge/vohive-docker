#!/bin/bash
# setup.sh: macOS 上一键部署 vohive
# 流程: 检查 OrbStack → 建 VM → USB 直通 → 推送脚本/镜像 → VM 内初始化
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

VM_NAME="${VOHIVE_VM_NAME:-vohive}"
VM_IMAGE="${VOHIVE_VM_IMAGE:-ubuntu:24.04}"
PLATFORM_IMAGE="${VOHIVE_IMAGE:-openvohive:latest}"

# ── 1. 检查 OrbStack ────────────────────────────────────
log "检查 OrbStack..."
if ! command -v orb >/dev/null 2>&1; then
  warn "未检测到 OrbStack。安装中..."
  need_cmd brew
  brew install --cask orbstack
  err "OrbStack 已安装。请先启动 OrbStack 应用并完成首次授权，然后重新运行本脚本。"
  exit 1
fi
ok "OrbStack 已就绪"

# ── 2. 创建 VM（幂等）───────────────────────────────────
if orb list 2>/dev/null | grep -qw "$VM_NAME"; then
  ok "VM '$VM_NAME' 已存在，跳过创建"
else
  log "创建 VM '$VM_NAME'（镜像 $VM_IMAGE）..."
  orb create "$VM_IMAGE" "$VM_NAME"
  ok "VM 已创建"
fi

# 确保 VM 运行
orb -m "$VM_NAME" start 2>/dev/null || true
log "等待 VM 就绪..."
for i in $(seq 1 30); do
  if orb -m "$VM_NAME" true >/dev/null 2>&1; then
    ok "VM 已就绪"
    break
  fi
  sleep 2
  [ "$i" -eq 30 ] && { err "VM 启动超时"; exit 1; }
done

# ── 3. USB 直通 ─────────────────────────────────────────
log "检测大疆 4G 模块（VID:PID 2ca3:4006 或已改写的 2c7c:0125）..."
SRC_DEV=""
DST_DEV=""
SRC_DEV=$(orb usb list 2>/dev/null | grep -i "2ca3:4006" | awk '{print $1}' | head -1 || true)
DST_DEV=$(orb usb list 2>/dev/null | grep -i "2c7c:0125" | awk '{print $1}' | head -1 || true)

if [ -n "$DST_DEV" ]; then
  ok "模块已是 Quectel 身份（2c7c:0125），直通到 VM"
  orb usb attach "$DST_DEV" "$VM_NAME" 2>/dev/null || warn "直通可能已绑定"
elif [ -n "$SRC_DEV" ]; then
  ok "检测到大疆模块，直通到 VM（改身份会触发重新枚举，稍后需重绑）"
  orb usb attach "$SRC_DEV" "$VM_NAME" 2>/dev/null || warn "直通可能已绑定"
else
  warn "未检测到大疆模块（2ca3:4006 / 2c7c:0125）"
  warn "请插入模块后继续，或按 Ctrl+C 取消"
  printf "  按回车继续（跳过 USB 直通，仅部署平台）..."
  read -r
fi

# ── 4. 构建或确认平台镜像存在 ───────────────────────────
log "检查平台镜像 $PLATFORM_IMAGE..."
if ! docker image inspect "$PLATFORM_IMAGE" >/dev/null 2>&1; then
  warn "本地无 $PLATFORM_IMAGE，开始构建..."
  cd "$PROJECT_ROOT"
  docker buildx bake --load --set *.platform=linux/$(uname -m | sed 's/x86_64/amd64/;s/arm64/arm64/') openvohive
  cd "$SCRIPT_DIR"
fi
ok "平台镜像就绪"

# ── 5. 传输脚本和镜像到 VM ──────────────────────────────
# 注意：OrbStack machine 的 /tmp 是只读挂载，用 /opt/vohive（可写）
log "传输部署脚本到 VM..."
DEPLOY_DIR="/opt/vohive"
orb -m "$VM_NAME" sudo mkdir -p "$DEPLOY_DIR/lib"
cat "$SCRIPT_DIR/vm-init.sh" | orb -m "$VM_NAME" sudo tee "$DEPLOY_DIR/vm-init.sh" >/dev/null
cat "$SCRIPT_DIR/lib/common.sh" | orb -m "$VM_NAME" sudo tee "$DEPLOY_DIR/lib/common.sh" >/dev/null
cat "$PROJECT_ROOT/dji2quectel/dji2quectel.sh" | orb -m "$VM_NAME" sudo tee "$DEPLOY_DIR/dji2quectel.sh" >/dev/null
orb -m "$VM_NAME" sudo chmod +x "$DEPLOY_DIR"/*.sh

log "传输平台镜像到 VM（docker save | load）..."
docker save "$PLATFORM_IMAGE" | orb -m "$VM_NAME" docker load

# ── 6. VM 内执行初始化 ──────────────────────────────────
log "在 VM 内执行初始化..."
orb -m "$VM_NAME" sudo bash "$DEPLOY_DIR/vm-init.sh"

# ── 7. 输出访问信息 ─────────────────────────────────────
VM_IP=$(orb -m "$VM_NAME" ip 2>/dev/null | head -1 || orb -m "$VM_NAME" hostname -I | awk '{print $1}')
printf "\n"
ok "全部完成！"
printf "\n  后台地址: http://%s:7575\n" "$VM_IP"
printf "  查看密码: orb -m %s docker logs vohive 2>&1 | grep 密码\n" "$VM_NAME"
printf "  （未传 PROXY_WEB_PASSWORD 时每次启动生成随机密码）\n\n"
