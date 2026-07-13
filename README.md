# VoHive Docker 镜像

面向高通 4G/5G 模组（Quectel EC20/EC25/EG25 等）的 VoHive 部署方案，提供 Docker 镜像和一键部署脚本。

## 交付物

| 镜像/脚本 | 说明 |
|---|---|
| [**openvohive**](https://github.com/users/dannyge/packages/container/openvohive) | 开源版，聚焦短信收发/转发（Telegram/Email/Webhook/**Bark**），主力 |
| [**vohive-legacy**](https://github.com/users/dannyge/packages/container/vohive-legacy) | 闭源完整版 v1.5.5（含 VoWiFi/代理等），过渡兼容 |
| [**dji2quectel**](https://github.com/users/dannyge/packages/container/dji2quectel)（[组件文档](dji2quectel/README.md)） | 把大疆 4G 模块改写为移远 Quectel 身份（一次性工具） |
| [`scripts/setup.sh`](scripts/setup.sh) | macOS 上用 UTM VM + SSH 一键部署（含设备自动添加） |

## 快速开始

> **⚠️ 环境要求（实测确认）**：openvohive 需要**完整 Linux 内核**（含 `option`/`qmi_wwan` 驱动 + USB uevent 支持）才能发现和管理 4G 模块。OrbStack 的定制内核缺少这些模块，**仅能用于 dji2quectel 改身份**，不能跑 openvohive。完整运行环境请用 UTM Ubuntu VM 或真实 Linux 主机。

### macOS 用户（UTM Ubuntu VM，推荐）

**前置准备**（一次性，约 20 分钟）：
1. 安装 UTM：`brew install --cask utm`
2. 下载 Ubuntu 24.04 ARM64 ISO（[cdimage.ubuntu.com](https://cdimage.ubuntu.com/releases/24.04.4/release/ubuntu-24.04.4-live-server-arm64.iso)）
3. 在 UTM 里创建 Ubuntu VM（Virtualize + aarch64 + 2GB RAM + 20GB 磁盘 + 勾选 OpenSSH server）
4. 在 UTM 工具栏 USB 图标里勾选大疆/Quectel 模块做直通

**一键部署**（在 Mac 上运行）：
```bash
git clone --recurse-submodules https://github.com/dannyge/vohive-docker.git
cd vohive-docker
./scripts/setup.sh    # 交互式输入 VM IP/用户名/密码，自动完成部署
```

setup.sh 会自动：装 Docker → 改 USB 身份（首次）→ 拉 openvohive 镜像 → 起容器 → 添加设备到 openvohive（API 调用）。

> **大疆模块首次使用**：大疆 4G 模块（QDC507，本质 Quectel EG25-G）的 USB 身份是大疆私有的 `2ca3:4006`，openvohive 无法识别，必须先改写为 Quectel EC25 的 `2c7c:0125`（一次性、终身有效）。setup.sh 会自动处理；若需手动执行或排查，见 [改写操作手册](docs/dji2quectel-runbook.md)。

> **OrbStack 用户**：OrbStack 可用于运行 dji2quectel 改身份（`usbserial generic` 回退驱动够用），但**不能跑 openvohive**（定制内核缺 QMI/uevent）。改完身份后请把模块直通到 UTM Ubuntu VM。

### 原生 Linux 用户

```bash
git clone --recurse-submodules https://github.com/dannyge/vohive-docker.git
cd vohive-docker
bash scripts/fetch-assets.sh
docker buildx bake --load           # 构建三镜像
docker compose up                   # 改身份 + 起平台
```

访问 `http://<IP>:7575`，默认账号 `admin`。未设密码时 `docker logs vohive | grep 密码` 查看随机密码。

> **Unraid 用户**：直接拉取 `ghcr.io/dannyge/openvohive:latest` 镜像，通过 Web UI 创建容器。详见 [Unraid 部署指南](docs/unraid-deploy.md)。

## 配置

全部通过环境变量注入（`PROXY_*` 前缀），无需挂载配置文件：

| 变量 | 默认 | 说明 |
|---|---|---|
| `PROXY_WEB_USERNAME` | `admin` | Web 用户名 |
| `PROXY_WEB_PASSWORD` | 随机生成 | Web 密码（不设则每次启动随机，见日志） |
| `PROXY_SERVER_PORT` | `7575` | 服务端口 |
| `PROXY_TELEGRAM_*` | 禁用 | Telegram 转发配置 |
| `PROXY_WEBHOOK_*` | 禁用 | Webhook 配置 |
| `PROXY_EMAIL_*` | 禁用 | Email 配置 |
| `PROXY_BARK_*` | 禁用 | Bark 推送配置（官方/自建节点，含验证码自动复制） |

### Bark 推送（含验证码自动复制）

openvohive 支持 Bark 推送通知——收到短信时自动推送到 iPhone，并**自动提取验证码**设为 `copy` 字段，长按推送即可粘贴验证码。

在 openvohive 后台 → 设置 → 通知 → **Bark** 面板配置：
- **服务器地址**：`https://api.day.app`（官方）或自建 `http://your-ip:port`
- **Device Key**：Bark App 里复制的 key
- 启用后收到短信自动推送，验证码自动提取（4-8 位数字，支持中文"验证码"/英文"code"格式）

> iOS 14.5 以上需**长按或下拉推送**触发复制（系统限制）。

## 构建

```bash
# 多架构（amd64 + arm64）
docker buildx bake --load

# 推送到 registry
REGISTRY=your-registry.com docker buildx bake --push
```

> **本地构建限制**：openvohive 的 amd64 镜像在 arm64 Mac 上无法本地构建（bun 的 x86_64 版需要 AVX，QEMU 模拟不提供）。amd64 构建请在 amd64 机器上跑，或使用下面的 GitHub Actions 自动构建。

## CI 自动构建（GitHub Actions）

推送到 GitHub 后，`.github/workflows/build.yml` 会自动构建三镜像的多架构（amd64+arm64）版本，推送到 GHCR：

- **push 到 main** → 构建 `:latest` + `:sha-<short>`
- **tag `v*`** → 构建正式发布 `:<tag>`
- **PR** → 仅验证构建（不推送）

每个架构在对应**原生 runner** 上构建（`ubuntu-latest`=amd64、`ubuntu-24.04-arm`=arm64），避免 QEMU 模拟导致的 AVX 问题，再用 `imagetools create` 合并成多架构 manifest。

镜像地址：`ghcr.io/dannyge/<image>:latest`（如 `ghcr.io/dannyge/openvohive:latest`）

**首次使用前**：仓库 Settings → Actions → General → Workflow permissions，选 "Read and write permissions"。

## 数据持久化

挂载 `/app/data` 目录（含 SQLite 库、日志、配置）：
```bash
-v vohive-data:/app/data
```

容器重启后以下数据自动恢复：
- SQLite 数据库（短信、联系人、eSIM）
- 设备配置（含已添加的设备，无需重新添加）
- 通知设置（Telegram/Webhook/Email/Bark 配置）
- 应用日志

## 子模块

本仓库使用 git submodule 管理外部依赖。clone 后需：
```bash
git submodule update --init --recursive
```

| submodule | 来源 | 用途 |
|---|---|---|
| `ref/vohive-release` | [iniwex5/vohive-release](https://github.com/iniwex5/vohive-release) | 参考（install.sh 模板） |
| `ref/dji-4g-vohive-mac` | [wlzh/dji-4g-vohive-mac](https://github.com/wlzh/dji-4g-vohive-mac) | 参考（mcc-mnc-table.json、改身份教程） |
| `openvohive/src` | [dannyge/openvohive](https://github.com/dannyge/openvohive)（fork，含 Bark 渠道） | openvohive 镜像的源码 |

## 文档

| 文档 | 内容 |
|---|---|
| [Unraid 部署指南](docs/unraid-deploy.md) | 在 Unraid（x86_64）上通过 Docker Web UI 部署 openvohive 的完整步骤 |
| [改写操作手册](docs/dji2quectel-runbook.md) | 大疆→Quectel USB 身份改写的分步执行手册（agent 可直接执行，含检查点和故障排除） |
| [dji2quectel 组件文档](dji2quectel/README.md) | dji2quectel 工具的用法、环境变量、特性与约束 |
| [设计文档](docs/superpowers/specs/2026-07-08-vohive-docker-images-design.md) | 完整架构设计：背景核实、镜像设计、风险与约束、验收标准 |
| [实施计划](docs/superpowers/plans/2026-07-08-vohive-docker-images.md) | 9 个 Task 的逐步实施记录 |

## License 与免责

- openvohive 镜像基于 [openvohive/openvohive](https://github.com/openvohive/openvohive)（PolyForm Noncommercial，仅非商业）
- vohive-legacy 含闭源二进制（原作者 iniwex5，已停维），仅供过渡兼容
- 本软件仅供个人内部测试，严禁商业及非法用途，使用者自行承担法律责任

更多设计细节见 [文档](#文档) 段落。
