# Unraid 部署 openvohive

在 Unraid（x86_64）上通过 Docker 部署 openvohive，管理 Quectel 4G 模块（收发短信）。

> **前提**：4G 模块的 USB 身份必须已是 Quectel `2c7c:0125`（不是大疆原始的 `2ca3:4006`）。如果没改过，先在 Mac/UTM 上用 [dji2quectel](../dji2quectel/README.md) 改写身份（一次性、终身有效），再插到 Unraid 上。

---

## 步骤 1：插入模块并确认（SSH）

SSH 进 Unraid，确认模块被识别且驱动自动绑定：

```bash
# 确认模块可见（应为 Quectel EC25）
lsusb | grep -i quectel
# 预期: Bus 001 Device 00X: ID 2c7c:0125 Quectel Wireless Solutions Co., Ltd. EC25 LTE modem

# 确认设备节点已生成（option 驱动自动绑定）
ls /dev/ttyUSB* /dev/cdc-wdm0
# 预期: /dev/cdc-wdm0  /dev/ttyUSB0  /dev/ttyUSB1  /dev/ttyUSB2  /dev/ttyUSB3
```

**如果设备节点不完整**（缺 ttyUSB 或 cdc-wdm0），手动加载驱动：
```bash
modprobe option
modprobe qmi_wwan
sleep 2
ls /dev/ttyUSB* /dev/cdc-wdm0
```

> **Unraid 内核模块说明**：
> - `option` 驱动（生成 ttyUSB）通常可用——Quectel EC25 的串口接口能正常绑定。
> - `qmi_wwan` 驱动（生成 cdc-wdm0）**在 Unraid stock 内核中可能不存在**（实测 Unraid 7.3.x / 内核 `6.18.33-Unraid` 缺此模块，`modprobe qmi_wwan` 报 `Module not found`）。
> - **缺 cdc-wdm0 不影响短信收发**——使用 AT 模式部署即可（见步骤 5 方式 B）。AT 模式只通过 `/dev/ttyUSB2` 发 AT 指令，不需要 QMI 接口。
> - 如果需要 QMI 功能（数据连接等），需要自行编译 `qmi_wwan` 内核模块——Unraid 从 RAM 运行，需用 User Scripts 插件在开机时加载编译好的模块。

---

## 步骤 2：Unraid Web UI 创建容器

打开 Unraid Web UI → **Docker** 标签页 → **Add Container**（或点击容器图标 → Add Container）。

### 基本信息

| 字段 | 值 |
|---|---|
| **Name** | `openvohive` |
| **Repository** | `ghcr.io/dannyge/openvohive:latest` |
| **Template** | 选 `None`（自定义配置） |

### Network

| 字段 | 值 |
|---|---|
| **Network Type** | `Bridge` |

### Port

| 字段 | 值 |
|---|---|
| **Host Port** | `7575` |
| **Container Port** | `7575` |
| **Protocol** | `tcp` |

### Path（持久化存储）

| 字段 | 值 |
|---|---|
| **Host Path** | `/mnt/user/appdata/openvohive` |
| **Container Path** | `/app/data` |

> 这个目录存放 SQLite 数据库（短信、联系人、设备配置）和日志。Unraid 重启后数据不丢失。

### Variable（Web 账号密码）

| Key | Value | 说明 |
|---|---|---|
| `PROXY_WEB_USERNAME` | `admin` | Web 登录用户名（默认 admin） |
| `PROXY_WEB_PASSWORD` | `你的密码` | Web 登录密码（**不设则每次启动随机生成**，见容器日志） |

> 建议显式设置密码，否则每次容器重启都会换一个随机密码（需 `docker logs openvohive \| grep 密码` 查看）。

### Bark 推送配置（推荐）

openvohive 支持 Bark 推送——收到短信时自动推送到 iPhone，并**自动提取验证码**到剪贴板。推荐在后台 Web UI 配置（见步骤 4 后的 Bark 设置），也可以通过变量预配：

| Key | Value | 说明 |
|---|---|---|
| `PROXY_BARK_ENABLED` | `true` | 启用 Bark 推送 |
| `PROXY_BARK_DEVICE_KEY` | `你的BarkKey` | Bark App 里复制的 key（必填） |
| `PROXY_BARK_SERVER_URL` | `https://api.day.app` | 官方节点（默认）或自建 `http://ip:port` |

> **验证码自动复制**：收到短信时 Bark 推送会自动提取 4-8 位验证码（支持中文"验证码"/英文"code"格式），设为 `copy` 字段。iOS 14.5 以上需长按推送触发复制，14.5 以下自动复制。

其他可选变量（按需添加）：

| Key | 说明 |
|---|---|
| `PROXY_TELEGRAM_ENABLED` | `true` 启用 Telegram 转发 |
| `PROXY_TELEGRAM_BOT_TOKEN` | Telegram Bot Token |
| `PROXY_TELEGRAM_ADMIN_ID` | 你的 Telegram 用户 ID |
| `PROXY_WEBHOOK_ENABLED` | `true` 启用 Webhook 转发 |
| `PROXY_WEBHOOK_URLS` | Webhook URL 列表 |

### Privileged 和设备访问（关键）

openvohive 需要访问 `/dev/ttyUSB*`、`/dev/cdc-wdm0` 和 `/sys/bus/usb`（设备发现）。有两种方式：

#### 方式 A：Privileged + 挂载 /dev 和 /sys（推荐，最简单）

在 **Extra Parameters** 字段填入：
```
--privileged -v /dev:/dev -v /sys:/sys
```

> `--privileged` 让容器能访问所有设备；`-v /dev:/dev` 和 `-v /sys:/sys` 让容器看到 USB 设备节点和 sysfs。这是实测验证过的方式（UTM Ubuntu + Docker），openvohive 能完整发现设备。

#### 方式 B：逐设备映射（更安全，但不推荐）

在 **Extra Parameters** 字段填入：
```
--device=/dev/ttyUSB0 --device=/dev/ttyUSB1 --device=/dev/ttyUSB2 --device=/dev/ttyUSB3 --device=/dev/cdc-wdm0 -v /sys:/sys
```

> 不用 `--privileged`，只映射需要的设备节点。但设备路径（ttyUSB0/1/2/3）可能因 USB 插拔顺序变化，且 sysfs 仍需挂载（openvohive 读 VID:PID 发现设备）。如果模块不拔插，这种方式可行。

---

## 步骤 3：启动容器

点击 **Create**（或 **Apply**）创建并启动容器。

Unraid 会自动拉取镜像（约 70MB）并启动。在 Docker 标签页看到 `openvohive` 状态为 `running` 即成功。

---

## 步骤 4：访问后台

浏览器打开：
```
http://<unraid-ip>:7575
```

- 用户名：`admin`
- 密码：你设的 `PROXY_WEB_PASSWORD`，或从容器日志获取（随机密码）

获取随机密码（SSH 进 Unraid）：
```bash
docker logs openvohive 2>&1 | grep 密码
```

---

## 步骤 5：添加设备

openvohive 启动后不会自动发现设备（需要手动添加一次，之后重启自动恢复）。

> **Unraid 内核可能缺 `qmi_wwan` 模块**（实测 Unraid 7.3.x 内核 `6.18.33-Unraid` 未编译该模块）。如果步骤 1 确认 `/dev/cdc-wdm0` 不存在，使用下面的 **AT 模式**（不需要 cdc-wdm0，只用 ttyUSB 发 AT 指令）。短信收发功能完全不受影响。

### 方式 A：QMI 模式（有 /dev/cdc-wdm0 时）

在 openvohive 后台 Web UI 添加设备：

| 字段 | 值 |
|---|---|
| **设备 ID** | 自定义，如 `quectel-1` |
| **设备后端** | `qmi` |
| **控制设备** | `/dev/cdc-wdm0` |

或通过 API 添加（SSH）：
```bash
TOKEN=$(curl -s -X POST http://localhost:7575/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"你的密码"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

curl -s -X POST http://localhost:7575/api/devices \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"config":{"id":"quectel-1","device_backend":"qmi","control_device":"/dev/cdc-wdm0"}}'
```

### 方式 B：AT 模式（无 /dev/cdc-wdm0 时，Unraid 常见）

> Unraid 内核通常缺 `qmi_wwan` 模块，导致没有 `/dev/cdc-wdm0`。此时用 AT 模式——只通过 `/dev/ttyUSB2`（Quectel 标准 AT 口）发 AT 指令，不需要 QMI 接口。**短信收发完全正常**，仅 QMI 相关功能（数据连接、网络模式查询等）不可用。

在 openvohive 后台 Web UI 添加设备：

| 字段 | 值 |
|---|---|
| **设备 ID** | 自定义，如 `quectel-1` |
| **设备后端** | `at` |
| **AT 端口** | `/dev/ttyUSB2` |

或通过 API 添加（SSH）：
```bash
TOKEN=$(curl -s -X POST http://localhost:7575/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"你的密码"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

curl -s -X POST http://localhost:7575/api/devices \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"config":{"id":"quectel-1","device_backend":"at","at_port":"/dev/ttyUSB2"}}'
```

预期返回：`{"started":true,"status":"ok"}`

---

## 验证

### 设备在线确认

```bash
TOKEN=$(curl -s -X POST http://localhost:7575/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"你的密码"}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

curl -s http://localhost:7575/api/devices \
  -H "Authorization: Bearer $TOKEN"
```

预期返回含：
- `"running": true`
- `"control_online": true`
- `"modem": {"operator": "运营商名", "signal_dbm": 信号值, "imei": "..."}`
- `"sms_enabled": true`

### 短信收发

在 openvohive 后台 Web UI 的短信页面测试收发。

---

## 故障排除

| 现象 | 原因 | 处理 |
|---|---|---|
| `lsusb` 看不到 Quectel | 模块没插好 / USB 口问题 | 换 USB 口；确认模块身份是 `2c7c:0125`（不是 `2ca3:4006`） |
| 无 `/dev/ttyUSB*` | option 驱动未加载 | `modprobe option && modprobe qmi_wwan`；确认 Unraid 内核版本支持 USB serial |
| 无 `/dev/cdc-wdm0` | qmi_wwan 驱动未加载 | `modprobe qmi_wwan`；检查 `dmesg \| grep qmi` |
| 容器内看不到设备 | 没挂载 /dev 或没用 privileged | 确认 Extra Parameters 含 `--privileged -v /dev:/dev -v /sys:/sys` |
| 添加设备返回 "未发现调制解调器" | 容器内无 cdc-wdm0 | SSH 进 Unraid 确认 `/dev/cdc-wdm0` 存在；确认容器 privileged + /dev 挂载 |
| 登录提示密码错误 | 密码不匹配 | 检查 `PROXY_WEB_PASSWORD` 变量；或从日志取随机密码 |
| 容器重启后设备消失 | config.yaml 路径映射不对 | 确认 `/mnt/user/appdata/openvohive` → `/app/data` 映射正确；config.yaml 存在 `/app/data/config.yaml`（自动持久化） |
| Bark 推送收不到 | device_key 错误 / 网络不通 | 确认 Bark App 里的 key 正确；自建服务器确认网络可达 |
| Bark 推送没有自动复制验证码 | iOS 版本限制 / 镜像未更新 | iOS 14.5 以上需长按推送；确认镜像含 `autoCopy` 修复（拉取最新 `:latest`） |
| 端口 7575 被占用 | 其他容器占用了该端口 | 换一个 Host Port（如 7576），或在 Unraid 里停掉占用端口的容器 |

---

## 持久化说明

以下数据持久化在 `/mnt/user/appdata/openvohive`（容器内 `/app/data`）：

| 文件 | 用途 |
|---|---|
| `vohive.db` | SQLite 数据库（短信、联系人、eSIM） |
| `config.yaml` | 运行时配置（含已添加的设备、通知设置——重启后自动恢复） |
| `logs/app.log` | 应用日志 |

> **config.yaml 自动持久化**：首次启动时从镜像内置模板复制到 `/app/data/config.yaml`；后续重启沿用持久化的配置。添加的设备和 Bark/Telegram/Email 通知设置都会保存，重启不丢。

---

## 可选：开机自启

Unraid Docker 容器默认开机自启。确认：

1. Unraid Web UI → Docker → 选中 `openvohive` → 编辑
2. **Autostart** 设为 `ON`（默认开启）

这样 Unraid 重启后 openvohive 自动启动，设备自动恢复。
