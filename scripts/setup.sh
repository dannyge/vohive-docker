#!/bin/bash
# setup.sh: macOS 上一键部署 openvohive（UTM Ubuntu VM 方式）
#
# 流程: 检查 UTM → 启动 VM → USB 直通 → SSH 部署 → 设备发现
#
# 环境变量（可选）:
#   VOHIVE_VM_NAME      UTM 虚拟机名称（默认 vohive）
#   VOHIVE_VM_USER      VM SSH 用户名（必填，或交互输入）
#   VOHIVE_VM_IP        VM IP 地址（必填，或交互输入）
#   VOHIVE_VM_PASS      VM SSH 密码（必填，或交互输入）
#   VOHIVE_IMAGE        openvohive 镜像（默认 ghcr.io/dannyge/openvohive:latest）
#   PROXY_WEB_PASSWORD  Web 密码（不设则随机生成）
#   PROXY_TELEGRAM_*    Telegram 转发配置（可选）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=lib/common.sh
. "$SCRIPT_DIR/lib/common.sh"

VM_NAME="${VOHIVE_VM_NAME:-vohive}"
VM_USER="${VOHIVE_VM_USER:-}"
VM_IP="${VOHIVE_VM_IP:-}"
VM_PASS="${VOHIVE_VM_PASS:-}"
PLATFORM_IMAGE="${VOHIVE_IMAGE:-ghcr.io/dannyge/openvohive:latest}"
DEVICE_ID="${VOHIVE_DEVICE_ID:-quectel-1}"

# ── 1. 检查依赖 ──────────────────────────────────────────
log "检查依赖..."
need_cmd sshpass
need_cmd ssh

# 检查 UTM（可选——VM 可能已手动建好）
if command -v utmctl >/dev/null 2>&1; then
  ok "UTM 已安装"
else
  warn "UTM 未安装（如 VM 已在运行可忽略）"
fi

# ── 2. 确认 VM 连接信息 ──────────────────────────────────
if [ -z "$VM_USER" ]; then
  printf "VM SSH 用户名: "
  read -r VM_USER
fi
if [ -z "$VM_IP" ]; then
  printf "VM IP 地址（如 192.168.64.6）: "
  read -r VM_IP
fi
if [ -z "$VM_PASS" ]; then
  printf "VM SSH 密码: "
  read -rs VM_PASS
  printf "\n"
fi

SSH_CMD="sshpass -p '$VM_PASS' ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${VM_USER}@${VM_IP}"

# 测试 SSH 连接
log "测试 SSH 连接 ${VM_USER}@${VM_IP}..."
if eval "$SSH_CMD 'echo ok'" 2>/dev/null | grep -q ok; then
  ok "SSH 连接成功"
else
  err "SSH 连接失败。请确认 VM 在运行、IP/用户名/密码正确。"
  exit 1
fi

# 检查内核（确认是完整 Linux 内核，不是 OrbStack 精简版）
KERNEL=$(eval "$SSH_CMD 'uname -r'" 2>/dev/null)
log "VM 内核: $KERNEL"
if echo "$KERNEL" | grep -q "orbstack"; then
  err "检测到 OrbStack 内核——openvohive 需要 UTM Ubuntu VM（完整内核）。"
  exit 1
fi
ok "完整 Linux 内核确认"

# ── 3. USB 直通提示 ──────────────────────────────────────
log "检查 Quectel 模块是否在 VM 内可见..."
QUECTEL=$(eval "$SSH_CMD 'lsusb 2>/dev/null | grep -i quectel'" 2>/dev/null || true)
if [ -n "$QUECTEL" ]; then
  ok "Quectel 模块已在 VM 内: $QUECTEL"
else
  warn "VM 内未检测到 Quectel 模块"
  warn "请在 UTM 窗口工具栏点 USB 图标，勾选大疆/Quectel 设备（2C7C:0125）"
  printf "  操作完成后按回车继续..."
  read -r
  # 再次检查
  QUECTEL=$(eval "$SSH_CMD 'lsusb 2>/dev/null | grep -i quectel'" 2>/dev/null || true)
  if [ -z "$QUECTEL" ]; then
    err "仍未检测到 Quectel 模块。请确认 USB 直通已启用。"
    exit 1
  fi
  ok "Quectel 模块已直通: $QUECTEL"
fi

# 检查设备节点（option 驱动应自动生成）
TTYUSB=$(eval "$SSH_CMD 'ls /dev/ttyUSB* 2>/dev/null | wc -l'" 2>/dev/null || echo 0)
CDCWDM=$(eval "$SSH_CMD 'ls /dev/cdc-wdm0 2>/dev/null'" 2>/dev/null || true)
if [ "$TTYUSB" -gt 0 ] && [ -n "$CDCWDM" ]; then
  ok "设备节点就绪: $TTYUSB 个 ttyUSB + cdc-wdm0"
else
  warn "设备节点不完整（ttyUSB=$TTYUSB cdc-wdm=$CDCWDM）"
  warn "可能需要物理拔插模块重新枚举。请拔插后按回车继续..."
  read -r
  TTYUSB=$(eval "$SSH_CMD 'ls /dev/ttyUSB* 2>/dev/null | wc -l'" 2>/dev/null || echo 0)
  CDCWDM=$(eval "$SSH_CMD 'ls /dev/cdc-wdm0 2>/dev/null'" 2>/dev/null || true)
  if [ "$TTYUSB" -eq 0 ] || [ -z "$CDCWDM" ]; then
    err "设备节点仍不完整。请确认 option 和 qmi_wwan 驱动已加载。"
    exit 1
  fi
  ok "设备节点就绪（拔插后恢复）"
fi

# ── 4. 在 VM 内安装 Docker + 部署 openvohive ─────────────
log "传输部署脚本到 VM..."
DEPLOY_DIR="/opt/vohive"
eval "$SSH_CMD 'echo $VM_PASS | sudo -S mkdir -p $DEPLOY_DIR'" 2>/dev/null

# 传 vm-init.sh
sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no \
  "$SCRIPT_DIR/vm-init.sh" "${VM_USER}@${VM_IP}:/tmp/vm-init.sh" 2>/dev/null
eval "$SSH_CMD 'echo $VM_PASS | sudo -S cp /tmp/vm-init.sh $DEPLOY_DIR/vm-init.sh && sudo chmod +x $DEPLOY_DIR/vm-init.sh'" 2>/dev/null

# 传 lib/common.sh
eval "$SSH_CMD 'echo $VM_PASS | sudo -S mkdir -p $DEPLOY_DIR/lib'" 2>/dev/null
sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no \
  "$SCRIPT_DIR/lib/common.sh" "${VM_USER}@${VM_IP}:/tmp/common.sh" 2>/dev/null
eval "$SSH_CMD 'echo $VM_PASS | sudo -S cp /tmp/common.sh $DEPLOY_DIR/lib/common.sh'" 2>/dev/null

# 传 dji2quectel.sh（首次改身份用，已是 Quectel 则跳过）
sshpass -p "$VM_PASS" scp -o StrictHostKeyChecking=no \
  "$PROJECT_ROOT/dji2quectel/dji2quectel.sh" "${VM_USER}@${VM_IP}:/tmp/dji2quectel.sh" 2>/dev/null
eval "$SSH_CMD 'echo $VM_PASS | sudo -S cp /tmp/dji2quectel.sh $DEPLOY_DIR/dji2quectel.sh && sudo chmod +x $DEPLOY_DIR/dji2quectel.sh'" 2>/dev/null

# 在 VM 内执行初始化（装 docker、改身份、起容器）
log "在 VM 内执行部署..."
eval "$SSH_CMD 'echo $VM_PASS | sudo -S bash $DEPLOY_DIR/vm-init.sh'" 2>&1 || true

# ── 5. 添加设备到 openvohive（API 调用）──────────────────
# 实测发现：openvohive 的 rescan 发现 QMI 但不自动注册设备，
# 需通过 API 手动添加（device_backend=qmi, control_device=/dev/cdc-wdm0）
log "添加设备到 openvohive..."
eval "$SSH_CMD 'echo $VM_PASS | sudo -S bash -c \"
  TOKEN=\\\$(curl -s -X POST http://localhost:7575/api/auth/login -H \\\"Content-Type: application/json\\\" -d \\\"{\\\\\\\"username\\\\\\\":\\\\\\\"admin\\\\\\\",\\\\\\\"password\\\\\\\":\\\\\\\"${PROXY_WEB_PASSWORD:-admin}\\\\\\\"}\\\" | python3 -c \\\"import sys,json; print(json.load(sys.stdin)[\\\\\\\"token\\\\\\\"])\\\" 2>/dev/null)
  if [ -z \\\"\\\$TOKEN\\\" ]; then
    # 随机密码模式：从日志提取
    PASS=\\\$(docker logs vohive 2>&1 | grep \\\"密码\\\" | tail -1 | grep -oE '[A-Za-z0-9]{12}' | tail -1)
    [ -z \\\"\\\$PASS\\\" ] && PASS=\\\$(docker logs vohive 2>&1 | grep \\\"password\\\" | tail -1 | grep -oE \\\"[A-Za-z0-9]{12}\\\" | tail -1)
    TOKEN=\\\$(curl -s -X POST http://localhost:7575/api/auth/login -H \\\"Content-Type: application/json\\\" -d \\\"{\\\\\\\"username\\\\\\\":\\\\\\\"admin\\\\\\\",\\\\\\\"password\\\\\\\":\\\\\\\"\\\$PASS\\\\\\\"}\\\" | python3 -c \\\"import sys,json; print(json.load(sys.stdin)[\\\\\\\"token\\\\\\\"])\\\" 2>/dev/null)
  fi
  echo \\\"token=\\\$TOKEN\\\"
  # 检查设备是否已存在
  EXISTING=\\\$(curl -s http://localhost:7575/api/devices -H \\\"Authorization: Bearer \\\$TOKEN\\\" | python3 -c \\\"import sys,json; d=json.load(sys.stdin); print(len(d.get(\\\\\\\"devices\\\\\\\",[])))\\\" 2>/dev/null)
  if [ \\\"\\\$EXISTING\\\" = \\\"0\\\" ]; then
    echo \\\"添加设备 $DEVICE_ID...\\\"
    curl -s -X POST http://localhost:7575/api/devices -H \\\"Authorization: Bearer \\\$TOKEN\\\" -H \\\"Content-Type: application/json\\\" -d \\\"{\\\\\\\"config\\\\\\\":{\\\\\\\"id\\\\\\\":\\\\\\\"$DEVICE_ID\\\\\\\",\\\\\\\"device_backend\\\\\\\":\\\\\\\"qmi\\\\\\\",\\\\\\\"control_device\\\\\\\":\\\\\\\"/dev/cdc-wdm0\\\\\\\"}}\\\"
  else
    echo \\\"设备已存在（\\\$EXISTING 个），跳过添加\\\"
  fi
\"'" 2>&1

# ── 6. 输出访问信息 ─────────────────────────────────────
printf "\n"
ok "部署完成！"
printf "\n"
printf "  后台地址: http://%s:7575\n" "$VM_IP"
printf "  登录账号: admin\n"
if [ -n "${PROXY_WEB_PASSWORD:-}" ]; then
  printf "  登录密码: %s\n" "$PROXY_WEB_PASSWORD"
else
  printf "  登录密码: 见 docker logs（随机生成）\n"
  printf "    ssh %s@%s 'sudo docker logs vohive 2>&1 | grep 密码'\n" "$VM_USER" "$VM_IP"
fi
printf "\n"
printf "  设备 ID:  %s\n" "$DEVICE_ID"
printf "  管理接口: http://%s:7575\n" "$VM_IP"
printf "\n"
