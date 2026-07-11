# DJI→Quectel USB 身份改写 Runbook（Agent 可执行）

> 本文档是自包含的执行手册。Agent 按顺序执行即可，无需阅读其他文件。
> 每步带验证检查点和预期输出。**遇到任何"预期输出"不匹配，立即停止并报告。**

## 前提条件

- **宿主机**：macOS（Apple Silicon 或 Intel），已安装 UTM 且有一个运行中的 Ubuntu VM
- **硬件**：大疆 4G 模块（型号 QDC507，本质 Quectel EG25-G）已通过 USB 插入 Mac
- **目标**：把模块 USB 身份从大疆 `2ca3:4006` 永久改写为 Quectel EC25 `2c7c:0125`
- **VM 连接信息**：VM 的 IP 地址、SSH 用户名、密码（用于远程执行脚本）

> **OrbStack 也可用于改身份**：OrbStack 的定制内核（`7.0.11-orbstack`）没有 `option` 模块，但脚本会自动回退到 `usbserial generic`（实测可用）。但 **OrbStack 不能跑 openvohive**（缺 QMI/uevent），改完身份后请把模块直通到 UTM Ubuntu VM。

## 背景知识（必读）

- 改写的是**模块内部 NV（永久存储）**，一次终身有效，插任何机器都是 Quectel 身份
- 脚本依赖 Linux 内核的 `option`/`usbserial` 驱动 + `socat` + `/sys`——**不能在 macOS 裸机跑**，必须在 Linux VM 内
- UTM Ubuntu VM 有完整内核（`option` 驱动可用），脚本优先用 `option`，回退 `usbserial generic`
- OrbStack 定制内核（`7.0.11-orbstack`）无 `option` 模块，脚本回退到 `usbserial generic`（实测可用，仅限改身份）
- `AT+CFUN=1,1` 软重启后 USB 直通会断开，需要重新绑定（见步骤 5）

---

## 步骤 1：确认硬件已连接

在 Mac 上检查 USB 设备（UTM 或 OrbStack 均可）：

**UTM 方式**：
```bash
utmctl usb list
```

**OrbStack 方式**：
```bash
orb usb list
```

**预期输出**（含大疆模块）：
```
Baiwang (5:1)  2C7C:0125  327681    # 已是 Quectel 身份（之前改过）
```
或
```
05100000  2ca3:4006  BAIWANG Baiwang  # 仍是大疆身份（首次改写）
```

**检查**：输出里必须有一行含 `2ca3:4006`（大疆）或 `2c7c:0125`（已改过）。如果没有，说明模块没插好——停止，提示用户检查 USB 连接。

---

## 步骤 2：确认 VM 就绪 + USB 直通

**UTM 方式**（推荐）：
```bash
# 确认 VM 在运行
utmctl status <VM名称>

# 在 UTM 窗口工具栏点 USB 图标，勾选大疆/Quectel 设备做直通
# 然后通过 SSH 确认 VM 内可见：
sshpass -p '<密码>' ssh <用户名>@<VM_IP> 'lsusb | grep -i "2ca3\|2c7c\|quectel"'
```

**OrbStack 方式**（仅用于改身份，不能跑 openvohive）：
```bash
# 创建 VM（如已有则跳过）
orb create ubuntu:24.04 vohive-test
orb usb attach <DEV_ID>
# 确认 VM 内可见
orb -m vohive-test lsusb
```

**检查**：VM 内 `lsusb` 必须看到 `2ca3:4006`（大疆）或 `2c7c:0125`（Quectel）。

> 后续步骤中，`<SSH>` 代表 SSH 连接命令：
> - UTM：`sshpass -p '<密码>' ssh <用户名>@<VM_IP>`
> - OrbStack：`orb -m vohive-test`

---

## 步骤 3：安装 VM 内依赖

```bash
# UTM 方式
sshpass -p '<密码>' ssh <用户名>@<VM_IP> 'echo <密码> | sudo -S bash -c "apt-get update -qq && apt-get install -y -qq usbutils socat kmod"'

# OrbStack 方式
orb -m vohive-test sudo bash -c 'apt-get update -qq && apt-get install -y -qq usbutils socat kmod'
```

**验证**：
```bash
# UTM
sshpass -p '<密码>' ssh <用户名>@<VM_IP> 'command -v lsusb socat modprobe'
# OrbStack
orb -m vohive-test bash -c 'command -v lsusb socat modprobe'
```
**预期**：三行输出（三个命令的路径），都存在。

---

## 步骤 4：执行改写脚本

### 4a. 确认设备在 VM 内可见

```bash
# UTM（USB 直通在步骤 2 已通过 UTM GUI 完成）
sshpass -p '<密码>' ssh <用户名>@<VM_IP> 'lsusb | grep -i "2ca3\|quectel"'

# OrbStack
orb -m vohive-test lsusb
```

**预期输出**（含大疆模块）：
```
Bus 001 Device 002: ID 2ca3:4006 DJI Technology Co., Ltd. Baiwang
```

**检查**：必须看到 `2ca3:4006`（大疆身份）。如果已是 `2c7c:0125`（Quectel），说明之前改过，跳到步骤 6 验证。

### 4b. 执行改写脚本

```bash
# UTM 方式：用 SCP 传脚本到 VM，然后 SSH 执行
sshpass -p '<密码>' scp dji2quectel/dji2quectel.sh <用户名>@<VM_IP>:/tmp/dji2quectel.sh
sshpass -p '<密码>' ssh <用户名>@<VM_IP> 'echo <密码> | sudo -S bash /tmp/dji2quectel.sh'

# OrbStack 方式：通过 stdin 传入（machine 的 /tmp 只读）
cat dji2quectel/dji2quectel.sh | orb -m vohive-test sudo bash
```

> 如果脚本不在当前目录的 `dji2quectel/` 下，用实际路径替换。

**预期输出**（成功改写）：
```
[dji2quectel] 检测 USB 设备...
[dji2quectel] 检测到大疆模块 (2ca3:4006)，开始改写为 Quectel (0x2C7C:0x0125)...
[dji2quectel] 加载 USB serial 驱动...
[dji2quectel]   option 不可用，回退到 usbserial generic 驱动
[dji2quectel] 注册 VID:PID 2ca3 4006 → 驱动...
[dji2quectel] 探测 AT 口（优先 ttyUSB2，115200 8N1）...
[dji2quectel] AT 口: /dev/ttyUSB2
[dji2quectel] 发送 AT+QCFG 改写 USB 身份 (0x2C7C:0x0125)...
AT+QCFG="usbcfg",0x2C7C,0x0125,1,1,1,1,1,0,0
OK
[dji2quectel] 发送 AT+CFUN=1,1 软重启模块...
AT+CFUN=1,1
OK
[dji2quectel] 等待模块重新枚举为新身份，超时 30s...
[dji2quectel] 错误: 超时：30s 内未检测到新身份。
```

**关键检查**：
- `AT+QCFG=...` 后必须出现 `OK`（模块接受了改写指令）
- `AT+CFUN=1,1` 后必须出现 `OK`（软重启已执行）
- **最后的"超时"是预期内的**——软重启后 USB 直通断开，脚本在 VM 内看不到新设备。这不是失败，进入步骤 5。

**如果 `OK` 没出现**（如 `ERROR` 或无响应）：模块拒绝改写，停止并报告——可能是模块被锁或固件不支持。

---

## 步骤 5：重新绑定 USB 直通（软重启后的必要步骤）

`AT+CFUN=1,1` 让模块软重启，VID:PID 变成 `2c7c:0125`，USB 直通需要重连。

### 5a. Mac 侧确认新身份

```bash
# UTM
utmctl usb list
# OrbStack
orb usb list
```

**预期输出**：
```
Baiwang (5:1)  2C7C:0125  327681    # UTM
05100000  2c7c:0125  BAIWANG Baiwang  attached  # OrbStack
```

**检查**：VID:PID 已从 `2ca3:4006` 变成 `2c7c:0125`。如果还是旧的，等 5 秒重试（模块重启需要时间）。

### 5b. 重新绑定 USB 直通

**UTM 方式**：在 UTM 窗口工具栏 USB 图标里，先取消勾选再重新勾选设备。或物理拔插模块。

**OrbStack 方式**：
```bash
orb usb detach <DEV_ID>
sleep 2
orb usb attach <DEV_ID>
sleep 3
```

### 5c. 确认 VM 内看到新身份

```bash
# UTM
sshpass -p '<密码>' ssh <用户名>@<VM_IP> 'lsusb | grep -i quectel'
# OrbStack
orb -m vohive-test lsusb
```

**预期输出**：
```
Bus 001 Device 003: ID 2c7c:0125 Quectel Wireless Solutions Co., Ltd. EC25 LTE modem
```

**检查**：必须看到 `2c7c:0125` 和 `Quectel` / `EC25`。这是改写成功的最终确认。

---

## 步骤 6：加载驱动生成 ttyUSB（为后续 openvohive 准备）

> **UTM Ubuntu VM**：`option` 驱动会自动绑定 Quectel 设备，ttyUSB 和 cdc-wdm0 自动生成，通常无需手动操作。以下仅用于 OrbStack 或驱动未自动绑定的场景。

```bash
# UTM（通常自动完成，检查即可）
sshpass -p '<密码>' ssh <用户名>@<VM_IP> 'ls /dev/ttyUSB* /dev/cdc-wdm0 2>/dev/null'

# OrbStack（需手动加载 usbserial generic）
orb -m vohive-test sudo bash -c '
  modprobe usbserial 2>/dev/null
  echo "2c7c 0125" > /sys/bus/usb-serial/drivers/generic/new_id 2>/dev/null
  sleep 2
  ls /dev/ttyUSB*
'
```

**预期输出**（UTM 通常 4 个 ttyUSB + cdc-wdm0；OrbStack 5 个 ttyUSB，无 cdc-wdm0）：
```
/dev/cdc-wdm0
/dev/ttyUSB0
/dev/ttyUSB1
/dev/ttyUSB2
/dev/ttyUSB3
```

---

## 步骤 7：最终验证（AT 通信正常）

```bash
# UTM
sshpass -p '<密码>' ssh <用户名>@<VM_IP> 'echo <密码> | sudo -S bash -c "stty -F /dev/ttyUSB2 115200 cs8 raw -echo 2>/dev/null; timeout 3 cat /dev/ttyUSB2 > /tmp/v.bin 2>/dev/null & P=\$!; sleep 0.5; printf \"ATI\r\" > /dev/ttyUSB2; sleep 2; kill \$P 2>/dev/null; tr -cd \"[:print:]\n\r\" < /tmp/v.bin | grep -v \"^\$\""'

# OrbStack
orb -m vohive-test sudo bash -c '
  stty -F /dev/ttyUSB2 115200 cs8 -cstopb -parenb raw -echo 2>/dev/null
  timeout 3 cat /dev/ttyUSB2 > /tmp/verify.bin 2>/dev/null &
  P=$!; sleep 0.5
  sh -c "printf \"ATI\r\" > /dev/ttyUSB2"
  sleep 2; kill $P 2>/dev/null
  tr -cd "[:print:]\n\r" < /tmp/verify.bin | grep -v "^$"
'
```

**预期输出**：
```
ATI
Baiwang
QDC507
Revision: QDC507GLEFM21

OK
```

**检查**：有 `OK` 且返回型号信息 = 模块功能完全正常。改写成功。

---

## 完成判定

全部满足才算成功：
- [ ] 步骤 4b：`AT+QCFG` 返回 `OK`
- [ ] 步骤 5c：VM 内 `lsusb` 显示 `2c7c:0125 Quectel EC25`
- [ ] 步骤 6：`/dev/ttyUSB*` 生成（UTM 通常 4 个 + cdc-wdm0；OrbStack 5 个无 cdc-wdm0）
- [ ] 步骤 7：`ATI` 返回型号 + `OK`

## 故障排除

| 现象 | 原因 | 处理 |
|---|---|---|
| 步骤 1 看不到 `2ca3:4006` | 模块未插好 / Mac 未识别 | 拔插 USB，检查系统报告 |
| 步骤 4a VM 内看不到设备 | USB 直通未成功 | UTM：工具栏 USB 重新勾选；OrbStack：`orb usb detach` 后重新 attach |
| 步骤 4b `AT+QCFG` 返回 `ERROR` | 模块被锁 / 固件不支持 | 停止，报告模块状态（先发 `ATI` 看型号） |
| 步骤 4b 探测不到 AT 口 | ttyUSB 未生成 / 波特率不对 | 确认步骤 3 依赖已装；手动 `stty -F /dev/ttyUSB2 115200 raw` 后重试 |
| 步骤 5c 还是 `2ca3:4006` | 软重启未完成 | 等 10 秒重试；极端情况拔插模块 |
| 步骤 5c 设备消失 | 直通彻底断了 | UTM：工具栏 USB 重新勾选或物理拔插；OrbStack：`orb usb list` 确认设备在，重新 attach |
| 步骤 5c `can't set config #1, error -110` | `authorized 0/1` 操作搞坏设备 | **物理拔插模块**（唯一恢复方式，sysfs 操作无法修复） |
| 步骤 6 ttyUSB 不生成 | 驱动未注册 VID:PID | UTM：`modprobe option`；OrbStack：`echo "2c7c 0125" > /sys/bus/usb-serial/drivers/generic/new_id` |
| 步骤 7 ATI 无响应 | ttyUSB2 不是 AT 口 | 遍历探测：`for d in /dev/ttyUSB*; do printf "AT\r" \| socat - $d,b115200,raw,echo=0,crnl; done` |

## 回滚（改回大疆身份，极少需要）

如果需要恢复大疆身份（VID:PID `2ca3:4006`）：

```bash
# UTM
sshpass -p '<密码>' ssh <用户名>@<VM_IP> 'echo <密码> | sudo -S bash -c "
  stty -F /dev/ttyUSB2 115200 cs8 raw -echo 2>/dev/null
  printf \"AT+QCFG=\\\"usbcfg\\\",0x2CA3,0x4006,1,1,1,1,1,0,0\r\" > /dev/ttyUSB2
  sleep 1
  printf \"AT+CFUN=1,1\r\" > /dev/ttyUSB2
"'

# OrbStack
orb -m vohive-test sudo bash -c '
  stty -F /dev/ttyUSB2 115200 cs8 raw -echo 2>/dev/null
  printf "AT+QCFG=\"usbcfg\",0x2CA3,0x4006,1,1,1,1,1,0,0\r" > /dev/ttyUSB2
  sleep 1
  printf "AT+CFUN=1,1\r" > /dev/ttyUSB2
'
# 然后重复步骤 5 的重新绑定 + 步骤 6 的驱动加载（VID:PID 换回 2ca3 4006）
```
