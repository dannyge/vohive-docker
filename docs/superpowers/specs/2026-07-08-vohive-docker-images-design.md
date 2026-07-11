# VoHive Docker 镜像与部署方案设计

- **日期**：2026-07-08
- **状态**：待审阅
- **作者**：dannyge（与 ZCode 协作设计）

## 1. 背景与目标

### 1.1 起源

工作区 `ref/` 下有两个参考项目：

- `ref/vohive-release/`：VoHive 官方发布仓库（作者 `iniwex5`，已宣布无限期停止维护并删库）。仅含安装脚本、systemd 单元、文档，不含源码。最新 tag `v1.5.5`。
- `ref/dji-4g-vohive-mac/`：第三方（`wlzh`）为 Mac 用户写的操作手册，通过 UTM 跑 Linux VM，把大疆 4G 模块（本质移远 Quectel EG25-G）的 USB 身份从大疆私有 `2ca3:4006` 永久改写为移远 EC25 的 `2C7C:0125`，从而接入 VoHive。内置离线包 `vohive-backup.tar.gz`（含 x86-64 二进制）。

### 1.2 目标

构建 Docker 化的 VoHive 部署方案，交付：

1. **`openvohive` 镜像**（主力）：基于开源 fork `openvohive/openvohive` 源码构建，聚焦短信收发与转发，长期维护。
2. **`vohive-legacy` 镜像**（过渡）：基于 6mb 备份的闭源完整版二进制（v1.5.5），仅作兼容保留，将逐步淡出。
3. **`dji2quectel`**（工具）：把大疆模块 USB 身份永久改写为移远 Quectel EC25。主形态为纯 shell 脚本，额外打包成 Docker 镜像供原生 Linux 用户一句 `docker run` 使用。
4. **`setup.sh` 编排脚本**（macOS 场景）：在 Mac 上通过 SSH 连接 UTM Ubuntu VM，一键完成 USB 直通检查 + 改身份 + 部署 openvohive + 设备自动添加。

### 1.3 核心需求

- 用户主要使用场景：**短信接发与转发**（Telegram / Email / Webhook）。
- 配置以**环境变量注入**为主，不挂载 config 文件即可运行。
- 同时支持 **amd64 + arm64** 两种架构。
- 在 macOS（Apple Silicon / Intel）上可用。

## 2. 关键事实核实

本节所有事实均经实测确认，非推测。

### 2.1 arm64 二进制来源（原方案的阻塞点，现已解决）

| 渠道 | 实测结果 |
|---|---|
| 上游 `iniwex5/vohive-release` v1.5.0~v1.5.5 | release 存在，但 **assets 列表全空**（被删） |
| 上游 `v9.9.9`（唯一有 asset 的 release） | 三架构"二进制"均为 **12 字节文本"江湖再见"**，非真二进制 |
| Docker Hub `iniwex/vohive`（原 README 引用） | **404，已删除** |
| GHCR / Docker Hub 用户 iniwex、iniwex5 | 无 vohive 仓库 |
| 源码仓库 `iniwex5/vohive` | 已"复活"但仅剩 185 字节告别 README，Dockerfile/源码全删 |
| GitHub fork（471 个） | **不含 Release assets**（GitHub fork 不复制 assets，属平台机制） |
| **`6mb/vohive-release`** ⭐ | **备份了真二进制！** v1.5.5 release 含三架构：amd64(13.5MB)、arm64(11.4MB)、armv7(10MB)，文件名 `vohive_v1.5.5-10-gf9eb85d_linux_<arch>` |

**结论**：`6mb/vohive-release` 是原版闭源二进制（含 VoWiFi/代理等全功能）的可靠备份来源。arm64 真实可用。

### 2.2 openvohive 开源 fork

| 维度 | 实测 |
|---|---|
| 仓库 | `openvohive/openvohive`，Go 1.26.3 + Vue3 + Bun |
| 来源 | fork 自 `iniwex5/vohive`，移除闭源依赖后**可独立编译** |
| 关键改造 | 移除 VoWiFi 子系统、HTTP/SOCKS5 代理引擎；清理许可弹窗/自毁逻辑；聚焦模组管理与短信核心 |
| 多架构 | `CGO_ENABLED=0` 纯静态，buildx 可交叉编译 amd64/arm64/armv7 |
| 配置注入 | **原生支持 `PROXY_*` 环境变量**：`viper.SetEnvPrefix("PROXY")` + `SetEnvKeyReplacer(".","_")` + `AutomaticEnv()` |
| License | PolyForm Noncommercial 1.0.0（仅非商业） |
| 已有 Dockerfile | 有，但为单阶段（先本地 `go build` 出 `./app` 再 `docker build`），需改造为多阶段 |

**config 环境变量映射规则**（来自 `internal/config/config.go` 的 `Load()`）：
- 前缀 `PROXY_`，yaml 点号层级映射为下划线
- 例：`web.username` → `PROXY_WEB_USERNAME`；`telegram.bot_token` → `PROXY_TELEGRAM_BOT_TOKEN`
- 仍要求一个 config 文件存在（`ReadInConfig()` 在文件缺失时报错）→ 镜像内置最小骨架 yaml

### 2.3 二进制指纹（写进 assets/ 的确切文件）

**6mb 备份（vohive-legacy 用）**：

| 架构 | 文件名 | 大小 | sha1 | URL |
|---|---|---|---|---|
| amd64 | `vohive_v1.5.5-10-gf9eb85d_linux_amd64` | 13515752 B | `7dfe34acbb194e01f3144045a01749bba680089b` | `https://github.com/6mb/vohive-release/releases/download/v1.5.5/...` |
| arm64 | `vohive_v1.5.5-10-gf9eb85d_linux_arm64` | 11376872 B | `21cf55988ce5c1b3cb01ee72de273d6887cd283b` | 同上 |
| armv7 | `vohive_v1.5.5-10-gf9eb85d_linux_armv7` | 10030348 B | （未实测，armv7 非本期目标） | 同上 |

均为 ELF，静态链接，`no section header`（被 strip/混淆处理）。

**backup 包（`ref/dji-4g-vohive-mac/vohive-backup.tar.gz` 内）**：
- 仅 amd64，sha1 `ee16a5c0cd04505df43805fc81838f3e20b16aee`，13MB
- 注意：与 6mb 的 amd64（`7dfe34ac...`）**不同**——backup 的是原版发布二进制，6mb 的是从源码重新编译（带 `v1.5.5-10-gf9eb85d` git 描述后缀）。两者功能等价。本期统一采用 6mb 版本（含 arm64）。
- 另含 `mcc-mnc-table.json`（172KB，运营商 MCC/MNC 表）和 `install.sh`（离线安装脚本，含完整 config.yaml 模板，作为 `config.template.yaml` 的参考来源）。

### 2.4 OrbStack USB 直通与内核模块（运行环境的关键约束）

> **实测结论**：OrbStack **不能跑 openvohive**。以下事实均经真实硬件（DJI QDC507 模块）实测确认，非推测。OrbStack 仅可用于 dji2quectel 改身份（usbserial generic 回退驱动够用）。openvohive 的完整运行环境请用 UTM Ubuntu VM 或真实 Linux 主机。

| 事实 | 来源 |
|---|---|
| OrbStack v2.2.0（2025-06-04）起支持 USB 设备直通，支持 serial/UART | 官方 release notes |
| USB 直通支持**容器**和**Linux machine**两种形态 | 官方站点描述 + Reddit 实测帖 |
| OrbStack 用**自研定制 Linux 内核**（实测版本 `7.0.11-orbstack-00360-gc9bc4d96ac70`），模块支持取决于编译内容 | 官方文档 + 实测 `uname -r` |
| **OrbStack 内核无 `option` 驱动（实测确认）**：`modprobe option` 报 `Module option not found in directory /lib/modules/7.0.11-orbstack-...` | 实测 |
| **OrbStack 内核无 `qmi_wwan` 驱动（实测确认）**：`modprobe qmi_wwan` 报同样错误；无 `/dev/cdc-wdm0`；无 USB 网络接口 | 实测 |
| **OrbStack 内核不广播 USB uevent（实测确认）**：用 Python netlink 监听器（NETLINK_KOBJECT_UEVENT）测试，`authorized 0/1`、USB `unbind/rebind`、物理插拔均不产生任何 uevent（60s 超时无事件） | 实测 |
| 自编译/加载自定义模块**不被官方支持**，每次 OrbStack 更新内核版本即失效 | 官方 Linux machines 文档 |
| **Issue #2511**：OrbStack 2.2.1，USB 串口设备在 Linux machine 可用，但从 Docker 容器打开**失败**（已知 bug） | GitHub issue |
| Docker Desktop on macOS **不支持** USB 直通到容器（无 hypervisor 级支持） | Docker 官方论坛 |
| **Lume 基于 Apple Virtualization Framework，该框架不暴露 USB 直通 API** → Lume **不能** USB 直通 | Apple Developer Forums #825379、UTM Issue #3778 |

**实测时使用的 OrbStack 版本**：
- OrbStack 应用版本：v2.2.1（含 USB 直通功能，v2.2.0 起支持）
- OrbStack 定制内核版本：`7.0.11-orbstack-00360-gc9bc4d96ac70`
- VM 镜像：Ubuntu 24.04（通过 `orb create ubuntu:24.04` 创建）

**结论**：
- OrbStack 的定制内核精简了移动通信相关的全部内核模块（`option`、`qmi_wwan`、`cdc_mbim` 均不存在），且不通过 NETLINK_KOBJECT_UEVENT 广播 USB 事件。
- `dji2quectel` 可在 OrbStack 上运行（`usbserial generic` 回退驱动够用，实测改写成功）。
- **openvohive 无法在 OrbStack 上发现设备**（缺 QMI 接口 + 无 uevent 触发设备发现）。
- macOS 场景的完整运行环境改为 **UTM Ubuntu VM**（完整内核：`option`/`qmi_wwan` 自动绑定，uevent 正常工作，实测 openvohive 成功发现设备并收发短信）。
- `dji2quectel` 的 Docker 镜像版本仅供**原生 Linux 用户**一句 `docker run` 使用。

### 2.5 大疆改 Quectel 的 AT 指令（来自 mac 项目 README 第 5 节）

```bash
# 1. 加载 USB serial 驱动
modprobe option
# 2. 让驱动认大疆 VID:PID，生成 /dev/ttyUSB*
echo "2ca3 4006" > /sys/bus/usb-serial/drivers/option1/new_id
# 3. 通过 AT 口发指令，永久改 USB 身份为移远 EC25
echo 'AT+QCFG="usbcfg",0x2C7C,0x0125,1,1,1,1,1,0,0' | socat - /dev/ttyUSB2,crnl
# 4. 软重启模块使配置生效
echo 'AT+CFUN=1,1' | socat - /dev/ttyUSB2,crnl
# 5. 验证: lsusb 应显示 2c7c:0125 Quectel EC25
```

改的是模块内部 NV，**一次性、终身有效**。`AT+CFUN=1,1` 软重启时 VID/PID 变化会导致按 VID/PID 绑定的 USB 直通短暂断开。

## 3. 总体架构

### 3.1 仓库布局

```
vohive/                               # ★ 本仓库需先 git init（当前工作区尚非 git 仓库）
├── ref/                              # 参考项目（git submodule）
│   ├── vohive-release/               # → github.com/iniwex5/vohive-release（pin v1.5.5 tag）
│   └── dji-4g-vohive-mac/            # → github.com/wlzh/dji-4g-vohive-mac（pin main HEAD）
├── docs/superpowers/specs/           # 本设计文档
├── openvohive/                       # 【镜像 A·主力】openvohive 源码构建
│   ├── Dockerfile                    # 多阶段: frontend-builder → backend-builder → runtime
│   ├── docker-entrypoint.sh          # PROXY_* env 透传 + 随机密码生成
│   ├── config.example.yaml           # 最小配置骨架（让 ReadInConfig 不报错）
│   └── src/                          # openvohive 上游源码（git submodule，pin main HEAD 951727cea2db）
├── .gitmodules                       # 记录上述 3 个 submodule
├── vohive-legacy/                    # 【镜像 B·过渡】闭源二进制
│   ├── Dockerfile                    # 单阶段, ARG TARGETARCH 选二进制
│   ├── docker-entrypoint.sh          # 从 PROXY_* env 渲染 config.yaml + 随机密码
│   └── config.template.yaml          # 全字段模板（telegram/webhook/email/qq/feishu/bark/pushplus）
├── dji2quectel/                      # 【工具】大疆→移远改身份
│   ├── Dockerfile                    # alpine + socat + kmod, COPY 脚本（供原生Linux用）
│   └── dji2quectel.sh                # ★ 主形态: 纯脚本（VM内直接bash执行）
├── scripts/                          # 部署编排（类比 Vagrant 的 provisioner，声明式+可重入）
│   ├── dji2quectel.sh → ../dji2quectel/dji2quectel.sh  (同一份脚本)
│   ├── setup.sh                      # Mac端: OrbStack建VM + USB直通 + 跑镜像（类比 vagrant up）
│   ├── vm-init.sh                    # VM内: 装docker + bash改身份 + docker run平台（类比 provision）
│   └── lib/                          # setup 辅助函数
├── assets/                           # 构建用二进制资产（构建时从 submodule 下载/提取）
│   ├── vohive_legacy_amd64           # 6mb 备份的闭源 amd64
│   ├── vohive_legacy_arm64           # 6mb 备份的闭源 arm64
│   └── mcc-mnc-table.json            # backup 包提取（完整版用）
├── docker-bake.hcl                   # 多架构构建编排（buildx）
├── docker-compose.yml                # 示例（原生Linux场景）
└── README.md                         # 使用说明
```

**git submodule 说明**：
- 引入 submodule 前需先 `git init` 本工作区（当前非 git 仓库）。此为实施阶段第一步。
- 三个 submodule 及 pin 点：
  - `ref/vohive-release` → `github.com/iniwex5/vohive-release`，pin tag `v1.5.5`
  - `ref/dji-4g-vohive-mac` → `github.com/wlzh/dji-4g-vohive-mac`，pin `main` 分支当前 HEAD
  - `openvohive/src` → `github.com/openvohive/openvohive`，pin commit `951727cea2db`（无 tag）
- ref/ 的 submodule 用途：构建 `vohive-legacy` 时从 `ref/dji-4g-vohive-mac/vohive-backup.tar.gz` 提取 `mcc-mnc-table.json`；从 `ref/vohive-release` 提取 install.sh 模板作为 `config.template.yaml` 参考。二进制本身从 `6mb/vohive-release` 下载（见 2.3），不依赖 ref submodule。
- 用户 clone 本仓库后需执行 `git submodule update --init --recursive` 拉取全部依赖。README 须注明。

### 3.2 交付物总览

| 交付物 | 形态 | 架构 | 用途 | 优先级 |
|---|---|---|---|---|
| `openvohive` | Docker 镜像（源码构建） | amd64+arm64 | 短信收发/转发，主力平台 | 主要·长期维护 |
| `vohive-legacy` | Docker 镜像（闭源二进制） | amd64+arm64 | 原版全功能（VoWiFi/代理等），过渡 | 次要·淡出 |
| `dji2quectel` | 纯脚本（主）+ Docker 镜像（辅） | 脚本跨架构；镜像 amd64+arm64 | 大疆模块改 Quectel 身份，一次性 | 工具 |
| `setup.sh` | shell 脚本（Mac 端） | — | OrbStack 一键拉起 VM+部署 | macOS 场景 |

### 3.3 三种用户场景

**场景 1：macOS 用户（Apple Silicon / Intel）**
```
./scripts/setup.sh
  → 装 OrbStack（若未装）
  → orb create ubuntu:24.04 vohive
  → 提示插入大疆模块，orb usb attach
  → VM 内: bash dji2quectel.sh（改身份，一次性）
  → VM 内: docker run -d openvohive（起平台）
  → 打印 http://<VM-IP>:7575 + 随机密码
```

**场景 2：原生 Linux 用户**
```bash
# 改身份（可选，已有 Quectel 身份则跳过）
docker run --rm --privileged -v /sys:/sys -v /lib/modules:/lib/modules:ro -v /dev:/dev \
  dji2quectel:latest

# 起平台
docker run -d -p 7575:7575 --privileged -v /dev:/dev -v vohive-data:/app/data \
  -e PROXY_WEB_PASSWORD=xxx openvohive:latest
```

**场景 3：已有 Linux VM（UTM/其他）用户**
```bash
bash dji2quectel.sh              # 改身份
docker run ... openvohive:latest # 起平台
```

## 4. 镜像 A：`openvohive` 详细设计

### 4.1 Dockerfile：多阶段构建

```
┌─ stage 1: frontend-builder ──────────────┐
│  FROM oven/bun:1 AS frontend              │
│  COPY web/                                │
│  RUN bun install && bun run build         │
│  产出: web/dist（Vue 静态资源）            │
└───────────────────────────────────────────┘
┌─ stage 2: backend-builder ───────────────┐
│  FROM golang:1.26-alpine AS backend       │
│  COPY 源码 + stage1 的 dist               │
│  RUN go generate ./...                    │
│  RUN CGO_ENABLED=0 GOOS=linux \           │
│      go build -ldflags="-s -w" -trimpath  │
│      -o /out/server .                     │
│  （GOARCH 由 buildx 自动注入）             │
└───────────────────────────────────────────┘
┌─ stage 3: runtime ───────────────────────┐
│  FROM alpine:latest                       │
│  RUN apk add --no-cache ca-certificates   │
│      tzdata libc6-compat socat            │
│  COPY --from=backend /out/server /app/server
│  COPY config.example.yaml /app/config/config.yaml
│  COPY docker-entrypoint.sh /app/          │
│  WORKDIR /app                             │
│  ENTRYPOINT ["/app/docker-entrypoint.sh"] │
└───────────────────────────────────────────┘
```

**多架构**：`CGO_ENABLED=0` 纯静态，buildx 在单节点交叉编译出 amd64/arm64，无需 QEMU。前端阶段用多架构 bun 镜像。`.dockerignore` 已排除 git 历史。

**源码获取策略**：openvohive 上游源码以 **git submodule** 引入 `openvohive/src/`，pin 到固定 commit `951727cea2db`（无 tag，故用 commit pin）。三个 submodule 的统一说明见 3.1 节末尾。好处：
- 构建上下文自洽——`docker buildx bake` 一条命令即可（前提 `git submodule update --init`），用户无需手动 clone
- 可复现——固定 commit，避免上游变更导致构建漂移
- 可审计——源码在本地可见，符合 openvohive 作者"拉到本地可控编译"的建议
- 升级时显式 `git submodule update --remote` + 重新 pin commit

README 须标明源码出处（`openvohive/openvohive`）与 license（PolyForm Noncommercial，仅非商业）。

Dockerfile 中 `COPY` 路径基于 `openvohive/src/` 作为源码根，例如 `COPY openvohive/src/web/`、`COPY openvohive/src/`。bake 的 `context` 设为仓库根（`.`），使 assets/ 与各子目录都可被引用。

### 4.2 配置注入：环境变量优先

openvohive 用 viper，`Load()` 已启用 `PROXY_*` 环境变量覆盖。镜像内置最小 `config.yaml` 骨架（仅让 `ReadInConfig()` 不报错），所有实际配置走环境变量。

| 配置项 | 环境变量 | 默认 |
|---|---|---|
| Web 用户名 | `PROXY_WEB_USERNAME` | `admin` |
| Web 密码 | `PROXY_WEB_PASSWORD` | 未传则生成随机（见 4.3） |
| 服务端口 | `PROXY_SERVER_PORT` | `7575` |
| 调试模式 | `PROXY_SERVER_DEBUG` | `false` |
| Telegram 开关 | `PROXY_TELEGRAM_ENABLED` | `false` |
| Telegram token | `PROXY_TELEGRAM_BOT_TOKEN` | 空 |
| Telegram admin_id | `PROXY_TELEGRAM_ADMIN_ID` | `0` |
| Telegram chat_id | `PROXY_TELEGRAM_CHAT_ID` | `0` |
| Telegram 代理 | `PROXY_TELEGRAM_PROXY` | 空 |
| Webhook 开关 | `PROXY_WEBHOOK_ENABLED` | `false` |
| Webhook URLs | `PROXY_WEBHOOK_URLS` | `[]` |
| Webhook secret | `PROXY_WEBHOOK_SECRET` | 空 |
| Email 开关 | `PROXY_EMAIL_ENABLED` | `false` |
| Email 各项 | `PROXY_EMAIL_*` | 空 |

viper 的 `AutomaticEnv()` 自动处理映射，entrypoint 无需渲染 yaml。

### 4.3 随机密码生成

未传 `PROXY_WEB_PASSWORD` 时，entrypoint 每次启动生成随机密码并打印到 stdout（进 `docker logs`），**不持久化**，每次重启换新。

```sh
if [ -z "${PROXY_WEB_PASSWORD:-}" ]; then
  PROXY_WEB_PASSWORD=$(head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 12)
  printf '\n======== openvohive 未配置密码 ========\n'
  printf '  用户名: %s\n' "${PROXY_WEB_USERNAME:-admin}"
  printf '  密码:   %s\n' "$PROXY_WEB_PASSWORD"
  printf '  (docker logs 可再次查看)\n'
  printf '=======================================\n\n'
  export PROXY_WEB_PASSWORD
fi
```

行为表：

| 场景 | 结果 |
|---|---|
| 传了 `PROXY_WEB_PASSWORD=xxx` | 每次用此固定值 |
| 未传 | 每次启动生成新随机密码，打印日志 |

### 4.4 数据持久化与设备访问

| 路径 | 用途 | 挂载 |
|---|---|---|
| `/app/data/` | SQLite 库 + logs/ 子目录 | **建议挂载**（否则重启丢数据） |
| `/app/config/config.yaml` | 配置 | 默认内置；高级用户可挂载自定义覆盖 |
| `/dev/ttyUSB*` 等 | 4G 模组设备 | `--privileged -v /dev:/dev`（openvohive 运行时按 IMEI 自动发现，不写死端口） |

目录结构：
```
/app/data/
├── vohive.db          # SQLite
└── logs/
    └── app.log
```

### 4.5 典型运行命令

```bash
# 最简
docker run -d -p 7575:7575 \
  -e PROXY_WEB_PASSWORD=改成强密码 \
  -v vohive-data:/app/data \
  --privileged -v /dev:/dev \
  openvohive:latest

# 配 Telegram 转发
docker run -d -p 7575:7575 \
  -e PROXY_WEB_PASSWORD=xxx \
  -e PROXY_TELEGRAM_ENABLED=true \
  -e PROXY_TELEGRAM_BOT_TOKEN=123:abc \
  -e PROXY_TELEGRAM_ADMIN_ID=你的ID \
  -v vohive-data:/app/data \
  --privileged -v /dev:/dev \
  openvohive:latest
```

## 5. 镜像 B：`vohive-legacy` 详细设计

### 5.1 与 openvohive 的差异

| 维度 | openvohive | vohive-legacy |
|---|---|---|
| 二进制来源 | openvohive 源码编译 | 6mb 备份的闭源二进制（COPY 进镜像） |
| 多架构实现 | buildx 交叉编译 | `ARG TARGETARCH` 选对应预编译二进制 COPY |
| config 注入 | viper 原生 `PROXY_*` env | entrypoint 从 env 渲染 yaml（二进制混淆，无法确认支持 viper env） |
| 随机密码 | entrypoint 生成 | 同款逻辑 |
| 数据卷 | `/app/data/` | 同 |
| 设备访问 | `--privileged -v /dev:/dev` | 同 |

### 5.2 Dockerfile：单阶段，按架构选二进制

```
┌─ runtime ────────────────────────────────┐
│  FROM alpine:latest                       │
│  ARG TARGETARCH                           │
│  RUN apk add --no-cache ca-certificates   │
│      tzdata libc6-compat socat            │
│  COPY assets/vohive_legacy_${TARGETARCH}  │
│       /app/vohive                         │
│  RUN chmod +x /app/vohive                 │
│  COPY assets/mcc-mnc-table.json /app/data/│
│  COPY vohive-legacy/config.template.yaml /app/│
│  COPY vohive-legacy/docker-entrypoint.sh /app/│
│  WORKDIR /app                             │
│  ENTRYPOINT ["/app/docker-entrypoint.sh"] │
└───────────────────────────────────────────┘
```

`TARGETARCH` 由 buildx 自动注入（`amd64`/`arm64`）。二进制已预编译静态链接，无需编译阶段，构建极快。

### 5.3 config 渲染：entrypoint 从 env 生成完整 yaml

闭源二进制需完整 config.yaml（含 telegram/webhook/email/qq/feishu/bark/pushplus 全字段，参考 backup 包 install.sh 的模板）。策略：

1. 镜像内置完整 `config.template.yaml`（所有字段在，默认禁用）
2. entrypoint 启动时读 `PROXY_*` env，用纯 shell heredoc 渲染生成 `/app/data/config.yaml`（不用 envsubst，因 alpine 默认无且 heredoc 原生支持 `${VAR:-default}` 默认值语法）
3. 未传的 env 保持模板默认值（禁用）

entrypoint 逻辑：

```sh
#!/bin/sh
set -eu

# 1. 随机密码（与 openvohive 同款）
if [ -z "${PROXY_WEB_PASSWORD:-}" ]; then
  PROXY_WEB_PASSWORD=$(head -c 12 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 12)
  printf '\n======== vohive-legacy 未配置密码 ========\n'
  printf '  用户名: %s\n' "${PROXY_WEB_USERNAME:-admin}"
  printf '  密码:   %s\n' "$PROXY_WEB_PASSWORD"
  printf '==========================================\n\n'
  export PROXY_WEB_PASSWORD
fi

# 2. 渲染 config.yaml（heredoc，变量已 export，默认值生效）
mkdir -p /app/data/logs
cat > /app/data/config.yaml <<EOF
server:
  port: ${PROXY_SERVER_PORT:-7575}
web:
  username: ${PROXY_WEB_USERNAME:-admin}
  password: ${PROXY_WEB_PASSWORD}
telegram:
  enabled: ${PROXY_TELEGRAM_ENABLED:-false}
  bot_token: "${PROXY_TELEGRAM_BOT_TOKEN:-}"
  admin_id: ${PROXY_TELEGRAM_ADMIN_ID:-0}
  chat_id: ${PROXY_TELEGRAM_CHAT_ID:-0}
  proxy: "${PROXY_TELEGRAM_PROXY:-}"
webhook:
  enabled: ${PROXY_WEBHOOK_ENABLED:-false}
  urls: ${PROXY_WEBHOOK_URLS:-[]}
  secret: "${PROXY_WEBHOOK_SECRET:-}"
  timeout_ms: ${PROXY_WEBHOOK_TIMEOUT_MS:-5000}
  retry_max: ${PROXY_WEBHOOK_RETRY_MAX:-3}
  text_template: "${PROXY_WEBHOOK_TEXT_TEMPLATE:-{{device_label}} {{text}}}"
email:
  enabled: ${PROXY_EMAIL_ENABLED:-false}
  smtp_host: "${PROXY_EMAIL_SMTP_HOST:-}"
  smtp_port: ${PROXY_EMAIL_SMTP_PORT:-0}
  username: "${PROXY_EMAIL_USERNAME:-}"
  password: "${PROXY_EMAIL_PASSWORD:-}"
  from_address: "${PROXY_EMAIL_FROM_ADDRESS:-}"
  to_addresses: ${PROXY_EMAIL_TO_ADDRESSES:-[]}
  use_ssl: ${PROXY_EMAIL_USE_SSL:-false}
devices: []
EOF
chmod 600 /app/data/config.yaml

# 3. 启动
exec /app/vohive -c /app/data/config.yaml
```

> 完整模板还应含 qq/feishu/bark/pushplus 段（从 backup install.sh 提取），此处省略展示。qq/feishu 默认禁用，openvohive 已移除这些渠道——legacy 版保留以维持原版功能。

## 6. `dji2quectel` 详细设计

### 6.1 双形态

| 形态 | 文件 | 适用 |
|---|---|---|
| **主形态：纯脚本** | `dji2quectel/dji2quectel.sh` | VM 内直接 `bash` 执行（macOS 场景 setup 调用、已有 VM 用户） |
| 辅助形态：Docker 镜像 | `dji2quectel/Dockerfile`（COPY 同一脚本） | 原生 Linux 用户一句 `docker run` |

两者内容完全一致（镜像只是 `alpine + socat + kmod` + COPY 脚本）。

### 6.2 脚本全流程

```
检测模块（lsusb 查 2ca3:4006 / 2c7c:0125）
  ├─ 已是 2c7c:0125（Quectel）→ 报"已是目标身份，跳过"，exit 0（幂等）
  ├─ 两个都没有 → 报错"设备未直通进来"，exit 1
  └─ 看到 2ca3:4006（大疆）→ 执行改写 ↓
modprobe option                          # 加载 USB serial 驱动
echo "2ca3 4006" > .../option1/new_id    # 让驱动认 VID:PID，生成 /dev/ttyUSB*
探测 AT 口（遍历 /dev/ttyUSB* 试发 AT，收 OK 者即 AT 口）# 不写死 ttyUSB2
  └─ 全部无响应 → 报错"找不到 AT 口"，exit 1
发 AT+QCFG="usbcfg",0x2C7C,0x0125,1,1,1,1,1,0,0
发 AT+CFUN=1,1                           # 软重启
轮询 lsusb 直到 2c7c:0125 出现（超时退出）
验证成功 → 打印结果，exit 0
```

### 6.3 关键设计决策

1. **不写死 `ttyUSB2`**：遍历 `/dev/ttyUSB*` 逐个试发 `AT`，收 `OK` 者即 AT 口。
2. **幂等**：已是 Quectel 身份则跳过，重复运行不出错。
3. **VID:PID 可配置**（环境变量）：

| 环境变量 | 默认 | 用途 |
|---|---|---|
| `SRC_VIDPID` | `2ca3:4006` | 源身份（大疆） |
| `DST_VID` | `0x2C7C` | 目标 VID（移远） |
| `DST_PID` | `0x0125` | 目标 PID（EC25） |
| `AT_PORT` | 自动探测 | 手动指定 AT 口（覆盖自动探测） |
| `WAIT_TIMEOUT` | `30` | 等待重新枚举秒数 |

支持反向操作（改回大疆身份）：
```bash
docker run --rm --privileged -v /sys:/sys -v /lib/modules:/lib/modules:ro -v /dev:/dev \
  -e SRC_VIDPID=2c7c:0125 -e DST_VID=0x2CA3 -e DST_PID=0x4006 \
  dji2quectel:latest
```

### 6.4 Dockerfile

```
FROM alpine:latest
RUN apk add --no-cache socat usbutils kmod bash
COPY dji2quectel.sh /app/dji2quectel.sh
RUN chmod +x /app/dji2quectel.sh
ENTRYPOINT ["/app/dji2quectel.sh"]
```

多架构：脚本和 alpine 均跨架构，buildx 直接出 amd64+arm64。无二进制依赖。

### 6.5 运行方式（镜像形态）

```bash
docker run --rm --privileged \
  -v /sys:/sys \
  -v /lib/modules:/lib/modules:ro \
  -v /dev:/dev \
  dji2quectel:latest
```

挂载说明：`--privileged`（写 new_id 需特权）；`-v /sys:/sys`（sysfs）；`-v /lib/modules:/lib/modules:ro`（modprobe 读宿主内核模块，只读）；`-v /dev:/dev`（USB 设备节点）。

**约束**：`modprobe` 加载的 `option` 驱动须匹配**宿主内核版本**。故仅能在真实 Linux 主机或 Linux VM（UTM/OrbStack machine）内跑，不能在 macOS 裸机直接 `docker run`。

## 7. `setup.sh` 编排（macOS 场景，UTM Ubuntu VM）

> **方案变更说明**：原设计使用 OrbStack 作为 macOS VM 方案。经真实硬件实测，OrbStack 定制内核缺 `option`/`qmi_wwan`/uevent（见 2.4 节），**无法运行 openvohive**。已改为 UTM Ubuntu VM（完整内核，实测 openvohive 成功发现设备并收发短信）。OrbStack 仍可用于 dji2quectel 改身份（usbserial generic 回退）。

### 7.1 职责

在 Mac 上通过 SSH 连接 UTM Ubuntu VM，完成：USB 直通检查 → 装 Docker → 改身份 → 部署 openvohive → 设备自动添加 → 输出后台地址。

### 7.2 前置条件（一次性手动）

1. 安装 UTM：`brew install --cask utm`
2. 下载 Ubuntu 24.04 ARM64 ISO，在 UTM 里创建 VM（Virtualize + aarch64 + 2GB + 20GB + OpenSSH）
3. 在 UTM 工具栏 USB 图标里勾选大疆/Quectel 模块做直通
4. VM IP/用户名/密码准备好

### 7.3 流程

```
./scripts/setup.sh
  ├─ 1. 检查依赖（sshpass、ssh、utmctl）
  ├─ 2. 交互式输入 VM IP/用户名/密码（或通过环境变量）
  ├─ 3. SSH 测试 + 内核检查（拒绝 OrbStack 内核）
  ├─ 4. 检查 Quectel 模块在 VM 内可见（lsusb）+ 设备节点（ttyUSB + cdc-wdm0）
  │      └─ 不可见时提示 UTM GUI USB 勾选 / 物理拔插
  ├─ 5. SCP 传 vm-init.sh + dji2quectel.sh 到 VM
  ├─ 6. SSH 执行 vm-init.sh
  │      ├─ 装 docker（VM 内）
  │      ├─ bash dji2quectel.sh（改身份，幂等，已是 Quectel 则跳过）
  │      ├─ docker pull ghcr.io/dannyge/openvohive:latest
  │      └─ docker run -d openvohive（privileged + /dev + /sys）
  ├─ 7. API 调用：添加设备到 openvohive
  │      POST /api/devices {id, device_backend:qmi, control_device:/dev/cdc-wdm0}
  └─ 8. 打印 http://<VM-IP>:7575 + 密码信息
```

### 7.4 关键设计点

1. **UTM 而非 OrbStack**：实测确认 OrbStack 内核（`7.0.11-orbstack`）缺 `option`/`qmi_wwan`/uevent，openvohive 无法发现设备。UTM Ubuntu VM（内核 `6.8.0-134-generic`）有完整内核模块，option/qmi_wwan 自动绑定，openvohive 成功发现设备。
2. **设备添加需 API 调用**：openvohive 的 `POST /api/devices/actions/rescan` 发现 QMI 但不自动注册设备。需手动 `POST /api/devices` 带 `device_backend=qmi, control_device=/dev/cdc-wdm0`（实测确认）。
3. **幂等**：可重复跑。已改身份跳过（脚本自身幂等）；已在跑容器不重启（`docker ps` 检查）；设备已存在跳过添加。
4. **内核检查**：setup.sh 检测 `uname -r`，如含 `orbstack` 则拒绝并提示用 UTM。
5. **设备节点检查**：验证 `/dev/ttyUSB*` + `/dev/cdc-wdm0` 存在；不完整时提示物理拔插（authorized 0/1 会导致 `can't set config #1, error -110`，物理拔插才能恢复）。
6. **Lume 排除**：基于 Apple Virtualization Framework，无 USB 直通 API。
7. **VM 创建自动化**：UTM 支持通过 AppleScript（`osascript`）创建 VM（`make new virtual machine with properties`），但需 GUI session 授权。VM 创建为一次性手动操作，日常运行通过 SSH 自动化。

### 7.5 文件位置

```
scripts/
├── setup.sh              # Mac 端主编排（SSH + UTM）
├── vm-init.sh            # VM 内部执行（装docker+改身份+起容器）
├── dji2quectel.sh        # 与 dji2quectel/ 目录同一份（symlink）
└── lib/                  # 辅助函数（日志、错误处理）
```

## 8. 多架构构建（docker-bake.hcl）

用 buildx bake 统一编排三个镜像的多架构构建：

```hcl
group "default" {
  targets = ["openvohive", "vohive-legacy", "dji2quectel"]
}

target "openvohive" {
  context = "."
  dockerfile = "openvohive/Dockerfile"
  platforms = ["linux/amd64", "linux/arm64"]
  tags = ["openvohive:latest"]
}

target "vohive-legacy" {
  context = "."
  dockerfile = "vohive-legacy/Dockerfile"
  platforms = ["linux/amd64", "linux/arm64"]
  tags = ["vohive-legacy:latest"]
}

target "dji2quectel" {
  context = "./dji2quectel"
  platforms = ["linux/amd64", "linux/arm64"]
  tags = ["dji2quectel:latest"]
}
```

构建命令：`docker buildx bake --push`（或 `--load` 本地）。

## 9. 风险与约束

| 风险/约束 | 说明 | 缓解 |
|---|---|---|
| openvohive 二进制为源码编译，需 Go 1.26.3 + Bun 环境 | 多阶段 Dockerfile 内解决，用户无需本地装 | 构建阶段镜像含完整 toolchain |
| openvohive license 非商业 | PolyForm Noncommercial | README 明确标注，限定使用场景 |
| 闭源 vohive-legacy 二进制不可审计、作者停维 | 可能含未知的许可/自毁逻辑；无安全更新 | 定位为过渡，鼓励迁移到 openvohive |
| **OrbStack 内核无 `option` 驱动（实测确认）** | OrbStack 定制内核（7.0.x）未编译 `option` 模块，`modprobe option` 报 Module not found | dji2quectel.sh 已加 `usbserial generic` 回退（实测可用）；openvohive 长期运行建议用真实 Linux 或 UTM Ubuntu VM |
| **OrbStack 内核无 QMI 驱动（实测确认）** | `qmi_wwan` 模块不存在，无 `/dev/cdc-wdm0`，无 USB 网络接口。openvohive 设备发现依赖 QMI 接口识别调制解调器，缺它则扫描结果"未发现调制解调器" | openvohive 无法在 OrbStack 上发现设备。必须用完整内核环境（UTM Ubuntu / 真实 Linux） |
| **OrbStack 内核不广播 USB uevent（实测确认）** | NETLINK_KOBJECT_UEVENT 在 OrbStack VM 不工作——sysfs authorized 0/1、USB unbind/rebind、物理插拔均不产生 uevent（Python netlink 监听器 60s+物理插拔均无事件）。openvohive 的热插拔发现 100% 依赖 uevent | openvohive 的 udev 监听器在 OrbStack 上无效。有 `POST /api/devices/actions/rescan` 可手动触发扫描，但受限于 QMI 缺失仍无法发现 |
| **socat 探测需内联串口参数** | socat 打开设备会重置 termios，前置 stty 无效；裸 `socat -,crnl` 收不到 Quectel 响应 | dji2quectel.sh 改用 `socat - $dev,b115200,raw,echo=0,crnl`（实测修复） |
| **openvohive 只认 VID `2c7c`(Quectel)/`05c6`(高通)** | 源码 `discovery_compat.go` 硬编码 VID 过滤，大疆 `2ca3` 不会被识别 | 这正是必须改写 USB 身份的根本原因；改写后 VID=2c7c 能被 sysfs 扫描识别（实测 OrbStack 容器可读 `/sys/bus/usb`，VID 正确） |
| **openvohive 设备发现机制** | 启动时只处理 config.yaml 预置的 devices；自动发现靠 udev netlink uevent；有 `POST /api/devices/actions/rescan` 手动触发扫描（不依赖 uevent） | 完整内核环境下 uevent 自动工作；OrbStack 下可用 rescan API 但受 QMI 缺失限制 |
| 6mb 备份二进制来源第三方 | 非 iniwex5 官方发布，信任度需用户自评 | README 注明来源，提供 sha1 供校验 |
| `AT+CFUN=1,1` 软重启致 USB 直通短暂断开 | VID/PID 变化触发重新枚举 | setup 脚本等待重新枚举后重绑直通 |
| `modprobe option` 须匹配宿主内核版本 | 容器场景模块版本不匹配会失败 | 约束文档化；VM/真机场景内核一致 |
| 引入 git submodule 需先 `git init` 工作区 | 当前 `vohive` 工作区非 git 仓库 | 实施阶段第一步先 `git init` 再 `submodule add` |
| Vagrant 不适用于 Apple Silicon Mac | VirtualBox 不支持 ARM 虚拟化；HashiCorp 2022 起将 Vagrant 推向 EOL；无可用 provider | 不采用 Vagrant，改用 OrbStack + 标准化 `setup.sh`/`vm-init.sh`（类比 Vagrant 的 up/provision，但原生支持 ARM+USB 直通） |

## 10. 范围边界（本期不做）

- **不采用 Vagrant**：核实确认 Vagrant 在 Apple Silicon Mac 上不可用（VirtualBox 无 ARM 支持、HashiCorp 推向 EOL）。其标准化/可重复诉求已由 OrbStack + `setup.sh`/`vm-init.sh` 覆盖（`orb create` 等同 box、`vm-init.sh` 等同 provisioner、`setup.sh` 等同 `vagrant up`，且幂等可重入）。
- 不自研 VM 镜像（ISO/qcow2）：VM 层交给 OrbStack/UTM 等现有工具。
- 不实现 UTM 的完整 CLI 自动化（ROI 低，仅文档降级）。
- 不做 armv7 镜像（虽有二进制，非本期目标）。
- 不实现 openvohive 的源码改造/功能增强（仅打包构建）。
- 不自建镜像仓库推送（bake 输出本地或用户自定 registry）。

## 11. 验收标准

- [ ] `docker buildx bake` 成功构建三个镜像的 amd64+arm64 manifest
- [ ] `openvohive` 镜像：传入 `PROXY_WEB_PASSWORD` 能登录后台；不传时日志打印随机密码
- [ ] `openvohive` 镜像：`PROXY_TELEGRAM_*` 配置后能收到短信转发
- [ ] `vohive-legacy` 镜像：entrypoint 正确渲染 config.yaml，二进制能启动
- [ ] `dji2quectel.sh`：在大疆模块上执行后 `lsusb` 显示 `2c7c:0125`
- [ ] `dji2quectel.sh`：对已是 Quectel 身份的模块幂等跳过
- [ ] `setup.sh`：在干净 Mac 上执行，最终能访问 `http://<VM-IP>:7575`
