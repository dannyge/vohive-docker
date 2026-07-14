# openvohive

← 返回 [项目主页](../README.md)

开源版 vohive，聚焦模组管理与短信收发/转发。基于 [openvohive/openvohive](https://github.com/openvohive/openvohive)（PolyForm Noncommercial），通过 git submodule 引入源码。

## 与 vohive-legacy 的区别

| | openvohive | vohive-legacy |
|---|---|---|
| 源码 | 开源可编译 | 闭源二进制（v1.5.5） |
| VoWiFi | ❌ 移除 | ✅ 有 |
| HTTP/SOCKS5 代理引擎 | ❌ 移除 | ✅ 有 |
| 通知渠道 | Telegram / Email / Webhook / Bark | 同前 + QQ / 飞书 / PushPlus |
| 推荐度 | ⭐ 主力，积极维护 | 过渡兼容，将淡出 |

## 支持的模组

Quectel EC20 / EC25 / EC21 / EG25 / EM20 等 USB 接口 4G/LTE 模组。也支持经 [dji2quectel](../dji2quectel/README.md) 改写身份后的大疆 QDC507 模块。

## 内核要求

openvohive 需要**完整 Linux 内核**（含 `option`/`qmi_wwan` 驱动 + USB uevent 支持）才能发现和管理 4G 模块。

| 环境 | 能否运行 | 说明 |
|---|---|---|
| 真实 Linux 主机 | ✅ | 最佳选择 |
| UTM Ubuntu VM | ✅ | macOS 推荐方案 |
| Unraid | ✅ | 用 AT 模式（内核无 qmi_wwan） |
| OrbStack | ❌ | 定制内核缺 option/qmi_wwan，仅能跑 dji2quectel |

> 部署方式（UTM/原生 Linux/Unraid）见 [项目主页](../README.md#快速开始)。

## 通知渠道

| 渠道 | 配置前缀 | 说明 |
|---|---|---|
| Telegram | `PROXY_TELEGRAM_*` | Bot 推送 |
| Email | `PROXY_EMAIL_*` | SMTP 邮件 |
| Webhook | `PROXY_WEBHOOK_*` | 自定义 HTTP 回调 |
| Bark | `PROXY_BARK_*` | iOS 推送 |

通用配置变量（`PROXY_WEB_USERNAME`、`PROXY_WEB_PASSWORD`、`PROXY_SERVER_PORT` 等）见 [项目主页配置表](../README.md#配置)。

### Bark 推送

Bark 是 iOS 推送工具，收到短信时自动推送到 iPhone。支持官方节点（`https://api.day.app`）或自建服务器。

通过环境变量或 openvohive 后台 → 设置 → 通知 → **Bark** 面板配置。面板内附有 [Bark 官方文档](https://bark.day.app/) 和 [API V2 文档](https://github.com/Finb/bark-server/blob/master/docs/API_V2.md) 链接。

## 源码与构建

源码在 `openvohive/src/`（git submodule，指向 [dannyge/openvohive](https://github.com/dannyge/openvohive) fork）。构建方式见 [项目主页构建章节](../README.md#构建)。
