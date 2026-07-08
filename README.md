# VoHive Docker 镜像

面向高通 4G/5G 模组（Quectel EC20/EC25/EG25 等）的 VoHive 部署方案，提供 Docker 镜像和一键部署脚本。

## 交付物

| 镜像/脚本 | 说明 |
|---|---|
| **openvohive** | 开源版，聚焦短信收发/转发（Telegram/Email/Webhook），主力 |
| **vohive-legacy** | 闭源完整版 v1.5.5（含 VoWiFi/代理等），过渡兼容 |
| **dji2quectel** | 把大疆 4G 模块改写为移远 Quectel 身份（一次性工具） |
| **setup.sh** | macOS 上用 OrbStack 一键部署 |

## 快速开始

### macOS 用户

```bash
git clone --recurse-submodules <本仓库>
cd vohive
bash scripts/fetch-assets.sh        # 下载 legacy 二进制（构建 legacy 时需要）
./scripts/setup.sh                  # 一键部署
```

### 原生 Linux 用户

```bash
git clone --recurse-submodules <本仓库>
cd vohive
bash scripts/fetch-assets.sh
docker buildx bake --load           # 构建三镜像
docker compose up                   # 改身份 + 起平台
```

访问 `http://<IP>:7575`，默认账号 `admin`。未设密码时 `docker logs vohive | grep 密码` 查看随机密码。

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

## 构建

```bash
# 多架构（amd64 + arm64）
docker buildx bake --load

# 推送到 registry
REGISTRY=your-registry.com docker buildx bake --push
```

## 数据持久化

挂载 `/app/data` 目录（含 SQLite 库和日志）：
```bash
-v vohive-data:/app/data
```

## 子模块

本仓库使用 git submodule 管理外部依赖。clone 后需：
```bash
git submodule update --init --recursive
```

| submodule | 来源 | 用途 |
|---|---|---|
| `ref/vohive-release` | iniwex5/vohive-release | 参考（install.sh 模板） |
| `ref/dji-4g-vohive-mac` | wlzh/dji-4g-vohive-mac | 参考（mcc-mnc-table.json、改身份教程） |
| `openvohive/src` | openvohive/openvohive | openvohive 镜像的源码 |

## License 与免责

- openvohive 镜像基于 [openvohive/openvohive](https://github.com/openvohive/openvohive)（PolyForm Noncommercial，仅非商业）
- vohive-legacy 含闭源二进制（原作者 iniwex5，已停维），仅供过渡兼容
- 本软件仅供个人内部测试，严禁商业及非法用途，使用者自行承担法律责任

详见 `docs/superpowers/specs/2026-07-08-vohive-docker-images-design.md`。
