# dji2quectel

把大疆 4G 模块（本质移远 Quectel EG25-G，大疆型号 QDC507）的 USB 身份从大疆私有 `2ca3:4006` **永久改写**为移远 EC25 的 `2C7C:0125`，使通用驱动和 VoHive/openvohive 能识别。改的是模块内部 NV，一次性、终身有效。

> **实测验证**：已在真实 DJI QDC507 模块（固件 QDC507GLEFM21）+ OrbStack Ubuntu 24.04 VM 上成功改写并验证。改写后 `lsusb` 显示 `Quectel Wireless Solutions Co., Ltd. EC25 LTE modem`，AT 通信正常。

## 两种用法

### 1. 纯脚本（VM 内直接运行，推荐）

在 Linux VM 或真机内（需 root）：
```bash
sudo bash dji2quectel.sh
```

### 2. Docker 镜像（原生 Linux 用户一句 docker run）

```bash
docker run --rm --privileged \
  -v /sys:/sys \
  -v /lib/modules:/lib/modules:ro \
  -v /dev:/dev \
  dji2quectel:latest
```

## 环境变量（可选）

| 变量 | 默认 | 说明 |
|---|---|---|
| `SRC_VIDPID` | `2ca3:4006` | 源身份（大疆） |
| `DST_VID` | `0x2C7C` | 目标 VID（移远） |
| `DST_PID` | `0x0125` | 目标 PID（EC25） |
| `AT_PORT` | 自动探测 | 手动指定 AT 口 |
| `WAIT_TIMEOUT` | `30` | 等待重新枚举秒数 |

## 反向操作（改回大疆身份，基本用不到）

```bash
sudo SRC_VIDPID=2c7c:0125 DST_VID=0x2CA3 DST_PID=0x4006 bash dji2quectel.sh
```

## 特性

- **幂等**：已是 Quectel 身份则直接跳过，重复运行不出错
- **双驱动支持**：优先用 `option` 驱动（Quectel 官方推荐），内核无该模块时自动回退到 `usbserial generic`（适用于 OrbStack 等定制内核——实测 OrbStack 7.0.x 内核无 `option` 模块）
- **自动探测 AT 口**：优先试 `ttyUSB2`（[Quectel 官方指南](https://sixfab.com/wp-content/uploads/2020/12/Quectel_LTE5G_Linux_USB_Driver_User_Guide_V2.0.pdf)确认 EC25/EG25-G 标准 AT 口，实测验证），无响应则遍历 `/dev/ttyUSB*`
- **正确串口配置**：socat 内联 `b115200,raw,echo=0,crnl`（不依赖前置 stty——实测 socat 打开设备会重置 termios，导致裸 `crnl` 收不到响应）
- **VID:PID 可配置**：支持改写其他模块身份

## 改写流程（实测）

脚本执行顺序：
1. `lsusb` 检测当前身份（`2ca3:4006` 大疆 / `2c7c:0125` 已是 Quectel / 都没有则报错）
2. 加载 USB serial 驱动（`option` 优先，失败回退 `usbserial generic`）
3. 写 `new_id` 注册源 VID:PID → 生成 `/dev/ttyUSB*`
4. 探测 AT 口（ttyUSB2 优先）→ 发 `AT` 确认响应
5. 发 `AT+QCFG="usbcfg",0x2C7C,0x0125,...` 改写身份
6. 发 `AT+CFUN=1,1` 软重启使配置生效
7. 轮询 `lsusb` 等待新身份出现（超时 30s）

**关键：软重启后 USB 直通会断开**。`AT+CFUN=1,1` 触发模块重新枚举，VID:PID 从 `2ca3:4006` 变 `2c7c:0125`，USB 直通（OrbStack/UTM）需要重新绑定：

```bash
# OrbStack：脚本超时后，在 Mac 侧重新绑定
orb usb detach <设备ID>
orb usb attach <设备ID>

# 然后重新跑脚本（幂等，会检测到已是 Quectel 身份直接跳过改写）
# 或手动加载驱动让 ttyUSB 重新生成：
sudo modprobe usbserial
echo "2c7c 0125" > /sys/bus/usb-serial/drivers/generic/new_id
```

## 约束

需 Linux 内核 + USB serial 驱动（`option` 或 `usbserial`）。仅能在真实 Linux 主机或 Linux VM（UTM/OrbStack machine）内运行，不能在 macOS 裸机直接 docker run（无 Linux 内核）。脚本需 root 权限（写 `/sys/new_id`、访问串口）。

> **OrbStack 注意**：OrbStack 的定制内核未编译 `option` 模块，脚本会回退到 `usbserial generic`。改身份这步（一次性发几条 AT 指令）generic 驱动完全够用。但改完身份后，openvohive **长期运行**建议用有完整 `option` 驱动的环境（真实 Linux 主机或 UTM Ubuntu VM），因为 generic 驱动不处理 QMI/网络接口的预留，可能影响数据连接稳定性。

