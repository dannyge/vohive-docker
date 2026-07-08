# dji2quectel

把大疆 4G 模块（本质移远 Quectel EG25-G）的 USB 身份从大疆私有 `2ca3:4006` **永久改写**为移远 EC25 的 `2C7C:0125`，使通用驱动和 VoHive 能识别。改的是模块内部 NV，一次性、终身有效。

## 两种用法

### 1. 纯脚本（VM 内直接运行，推荐）

在 Linux VM 或真机内：
```bash
bash dji2quectel.sh
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
SRC_VIDPID=2c7c:0125 DST_VID=0x2CA3 DST_PID=0x4006 bash dji2quectel.sh
```

## 特性

- **幂等**：已是 Quectel 身份则直接跳过，重复运行不出错
- **自动探测 AT 口**：遍历 `/dev/ttyUSB*`，不写死 `ttyUSB2`
- **VID:PID 可配置**：支持改写其他模块身份

## 约束

需 Linux 内核 + `option` 驱动。仅能在真实 Linux 主机或 Linux VM（UTM/OrbStack machine）内运行，不能在 macOS 裸机直接 docker run（无 Linux 内核）。
