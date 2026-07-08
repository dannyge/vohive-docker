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
DST_VIDPID_LOWER="$(echo "$DST_VID" | tr '[:upper:]' '[:lower:]'):$(printf '%04x' "0x$DST_PID" 2>/dev/null || echo "$DST_PID" | tr '[:upper:]' '[:lower:]')"

log()  { printf '[dji2quectel] %s\n' "$*"; }
err()  { printf '[dji2quectel] 错误: %s\n' "$*" >&2; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "缺少命令: $1"; exit 1; }
}

for c in lsusb socat modprobe; do need_cmd "$c"; done

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

# ── 2. 加载 USB serial 驱动 ──────────────────────────────
log "加载 option 驱动..."
modprobe option 2>/dev/null || { err "modprobe option 失败（内核可能无此模块）"; exit 1; }

NEW_ID_PATH="/sys/bus/usb-serial/drivers/option1/new_id"
if [ ! -f "$NEW_ID_PATH" ]; then
  err "找不到 $NEW_ID_PATH（option 驱动未正确加载）"
  exit 1
fi

log "注册 VID:PID $SRC_VID $SRC_PID → option 驱动..."
echo "$SRC_VID $SRC_PID" > "$NEW_ID_PATH" || { err "写入 new_id 失败（需要 root/特权）"; exit 1; }

# 等串口节点生成
sleep 2

# ── 3. 探测 AT 口（不写死 ttyUSB2）──────────────────────
find_at_port() {
  if [ -n "$AT_PORT" ]; then
    if [ -e "$AT_PORT" ]; then echo "$AT_PORT"; return 0; fi
    err "指定的 AT_PORT ($AT_PORT) 不存在"
    return 1
  fi
  for dev in /dev/ttyUSB*; do
    [ -e "$dev" ] || continue
    # 试发 AT，收 OK 即为 AT 口
    resp=$(printf 'AT\r' | timeout 3 socat - "$dev,crnl" 2>/dev/null || true)
    if echo "$resp" | grep -qi "OK"; then
      echo "$dev"
      return 0
    fi
  done
  return 1
}

log "探测 AT 口..."
AT_PORT=$(find_at_port) || { err "找不到可响应 AT 的串口（/dev/ttyUSB*）"; exit 1; }
log "AT 口: $AT_PORT"

# ── 4. 发 AT 指令改写 USB 身份 ───────────────────────────
log "发送 AT+QCFG 改写 USB 身份..."
printf 'AT+QCFG="usbcfg",%s,%s,1,1,1,1,1,0,0\r' "$DST_VID" "$DST_PID" | socat - "$AT_PORT,crnl"

# ── 5. 软重启使配置生效 ──────────────────────────────────
log "发送 AT+CFUN=1,1 软重启模块..."
printf 'AT+CFUN=1,1\r' | socat - "$AT_PORT,crnl"

# ── 6. 等待重新枚举 ──────────────────────────────────────
log "等待模块重新枚举为新身份 ($DST_VIDPID_LOWER)，超时 ${WAIT_TIMEOUT}s..."
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
err "可能是软重启后 USB 直通断开——请重新绑定直通后再次运行本脚本。"
exit 1
