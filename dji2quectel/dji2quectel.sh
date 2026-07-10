#!/bin/bash
# dji2quectel: 把大疆 4G 模块的 USB 身份永久改写为移远 Quectel EC25
# 改的是模块内部 NV，一次性、终身有效。
#
# 主形态：纯脚本，在 Linux VM/真机内直接 bash 执行
# 镜像形态：docker run（见同目录 Dockerfile）
#
# 环境变量（均可选）：
#   SRC_VIDPID    源 VID:PID，默认 2ca3:4006（大疆）
#   DST_VID       目标 VID，默认 0x2C7C（移远）
#   DST_PID       目标 PID，默认 0x0125（EC25）
#   AT_PORT       手动指定 AT 口（如 /dev/ttyUSB2），默认自动探测
#   WAIT_TIMEOUT  等待重新枚举秒数，默认 30
set -euo pipefail

SRC_VIDPID="${SRC_VIDPID:-2ca3:4006}"
DST_VID="${DST_VID:-0x2C7C}"
DST_PID="${DST_PID:-0x0125}"
AT_PORT="${AT_PORT:-}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-30}"

SRC_VID="${SRC_VIDPID%%:*}"
SRC_PID="${SRC_VIDPID##*:}"
DST_VIDPID_LOWER="$(echo "$DST_VID" | tr '[:upper:]' '[:lower:]'):$(printf '%04x' "0x${DST_PID#0x}" 2>/dev/null || echo "$DST_PID" | tr '[:upper:]' '[:lower:]')"

log()  { printf '[dji2quectel] %s\n' "$*"; }
err()  { printf '[dji2quectel] 错误: %s\n' "$*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "缺少命令: $1"; exit 1; }
}

for c in lsusb socat modprobe stty; do need_cmd "$c"; done

# 需要 root：写 /sys/new_id、访问 /dev/ttyUSB* 需特权
if [ "$(id -u)" -ne 0 ]; then
  err "需要 root 权限运行（写 /sys/new_id 和访问串口需要特权）。请用 sudo 或在 root 下运行。"
  exit 1
fi

# ── 1. 检测模块当前身份 ──────────────────────────────────
log "检测 USB 设备..."
if lsusb | grep -qi "$DST_VIDPID_LOWER"; then
  log "模块已是目标身份 ($DST_VIDPID_LOWER)，无需改写。跳过。"
  exit 0
fi

if ! lsusb | grep -qi "$SRC_VIDPID"; then
  err "未检测到大疆模块 ($SRC_VIDPID)。"
  err "请确认模块已通过 USB 直通进入本系统（orb usb attach / UTM 直通）。"
  exit 1
fi

log "检测到大疆模块 ($SRC_VIDPID)，开始改写为 Quectel ($DST_VID:$DST_PID)..."

# ── 2. 加载 USB serial 驱动（option 优先，回退 usbserial）─────────
# option 驱动是 Quectel 官方推荐（正确处理多接口），但某些定制内核
# （如 OrbStack VM 内核）未编译该模块，回退到 usbserial generic 驱动。
# 对一次性发几条 AT 指令改写身份，usbserial 足够。
log "加载 USB serial 驱动..."
NEW_ID_PATH=""
if modprobe option 2>/dev/null; then
  NEW_ID_PATH="/sys/bus/usb-serial/drivers/option1/new_id"
  log "  option 驱动已加载"
elif modprobe usbserial 2>/dev/null; then
  # usbserial 的驱动目录是 generic（不是 option1）
  NEW_ID_PATH="/sys/bus/usb-serial/drivers/generic/new_id"
  log "  option 不可用，回退到 usbserial generic 驱动"
else
  err "option 和 usbserial 驱动都加载失败（内核不支持 USB serial）"
  exit 1
fi

if [ ! -f "$NEW_ID_PATH" ]; then
  err "找不到 $NEW_ID_PATH（驱动未正确加载）"
  exit 1
fi

log "注册 VID:PID $SRC_VID $SRC_PID → 驱动..."
echo "$SRC_VID $SRC_PID" > "$NEW_ID_PATH" 2>/dev/null || {
  # 可能 VID:PID 已注册（重复运行），不致命
  log "  (写入 new_id 返回非零，可能已注册——继续)"
}

# 等串口节点生成
sleep 2

# ── 3. 探测 AT 口 ────────────────────────────────────────
# 关键：socat 打开设备会重置 termios，波特率/模式必须写进 socat 地址选项，
# 不能只靠前置的 stty。Quectel EC25/EG25-G AT 口默认 115200 8N1。
# 探测顺序：手动指定 > ttyUSB2（Quectel 标准 AT 口）> 遍历所有 ttyUSB*。
#
# 注意：DST_VIDPID_LOWER 的计算用 printf 对 0x125 这种短 hex 不会补零，
# 实际改写后 lsusb 显示的是小写 "2c7c:0125"，比较时用 grep -i 容错。
find_at_port() {
  # 生成候选端口列表：手动指定的优先，否则 ttyUSB2 先，其余按序
  local candidates=()
  if [ -n "$AT_PORT" ]; then
    candidates+=("$AT_PORT")
  else
    [ -e /dev/ttyUSB2 ] && candidates+=(/dev/ttyUSB2)
    for dev in /dev/ttyUSB*; do
      [ -e "$dev" ] || continue
      [ "$dev" = "/dev/ttyUSB2" ] && continue
      candidates+=("$dev")
    done
  fi

  for dev in "${candidates[@]}"; do
    [ -e "$dev" ] || continue
    # 完整 socat 参数：b115200,raw,echo=0,crnl（不能省 b115200 raw）
    local resp
    resp=$(printf 'AT\r' | timeout 4 socat - "$dev,b115200,raw,echo=0,crnl" 2>/dev/null || true)
    if echo "$resp" | grep -qi "OK"; then
      echo "$dev"
      return 0
    fi
  done
  return 1
}

log "探测 AT 口（优先 ttyUSB2，115200 8N1）..."
AT_PORT=$(find_at_port) || { err "找不到可响应 AT 的串口（/dev/ttyUSB*）"; exit 1; }
log "AT 口: $AT_PORT"

# ── 4. 发 AT 指令改写 USB 身份 ───────────────────────────
log "发送 AT+QCFG 改写 USB 身份 ($DST_VID:$DST_PID)..."
printf 'AT+QCFG="usbcfg",%s,%s,1,1,1,1,1,0,0\r' "$DST_VID" "$DST_PID" \
  | socat - "$AT_PORT,b115200,raw,echo=0,crnl"

# 等模块处理
sleep 1

# ── 5. 软重启使配置生效 ──────────────────────────────────
log "发送 AT+CFUN=1,1 软重启模块..."
printf 'AT+CFUN=1,1\r' | socat - "$AT_PORT,b115200,raw,echo=0,crnl" || true

# ── 6. 等待重新枚举 ──────────────────────────────────────
log "等待模块重新枚举为新身份，超时 ${WAIT_TIMEOUT}s..."
log "  (VID:PID 变化会导致 USB 直通断开——若超时，请重新绑定直通后再次运行)"
elapsed=0
while [ "$elapsed" -lt "$WAIT_TIMEOUT" ]; do
  if lsusb | grep -qi "$DST_VIDPID_LOWER"; then
    log "✓ 改写成功！模块现为 Quectel 身份 ($DST_VIDPID_LOWER)"
    log "  lsusb 输出:"
    lsusb | grep -i "$DST_VIDPID_LOWER" | sed 's/^/    /'
    exit 0
  fi
  sleep 1
  elapsed=$((elapsed + 1))
done

err "超时：${WAIT_TIMEOUT}s 内未检测到新身份。"
err "常见原因：软重启后 USB 直通按 VID:PID 绑定的规则失效。"
err "请在宿主机重新绑定 USB 直通，然后再次运行本脚本（脚本幂等，会跳过已完成的步骤）。"
exit 1
