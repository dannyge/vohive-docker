# vohive-legacy

← 返回 [项目主页](../README.md)

闭源完整版 vohive v1.5.5，提供过渡兼容。**建议优先使用 [openvohive](../openvohive/README.md)，本镜像将逐步淡出。**

## 二进制来源

原项目（iniwex5/vohive）已删除所有 release。本镜像的二进制备份自 [6mb/vohive-release](https://github.com/6mb/vohive-release)，按架构（amd64/arm64）自动选择。构建时由 `scripts/fetch-assets.sh` 下载。

> ⚠️ 闭源二进制无法审计，使用风险自负。

## 与 openvohive 的区别

| | vohive-legacy | openvohive |
|---|---|---|
| 源码 | 闭源二进制 v1.5.5 | 开源可编译 |
| VoWiFi | ✅ 有 | ❌ 移除 |
| HTTP/SOCKS5 代理引擎 | ✅ 有 | ❌ 移除 |
| QQ / 飞书 / PushPlus | ✅ 有 | ❌ 移除 |
| 推荐度 | 过渡兼容 | ⭐ 主力 |

## 额外通知渠道

除 Telegram / Email / Webhook / Bark（与 openvohive 相同）外，vohive-legacy 额外支持以下渠道，通过 `PROXY_*` 环境变量配置：

| 渠道 | 环境变量前缀 | 示例 |
|---|---|---|
| 飞书 | `PROXY_FEISHU_*` | `PROXY_FEISHU_APP_ID`、`PROXY_FEISHU_APP_SECRET`、`PROXY_FEISHU_CHAT_IDS` |
| QQ | `PROXY_QQ_*` | `PROXY_QQ_APP_ID`、`PROXY_QQ_GROUP_IDS`、`PROXY_QQ_DIRECT_IDS` |
| PushPlus | `PROXY_PUSHPLUS_*` | `PROXY_PUSHPLUS_TOKEN`、`PROXY_PUSHPLUS_TOPIC`、`PROXY_PUSHPLUS_CHANNEL` |

通用配置变量（`PROXY_WEB_USERNAME`、`PROXY_WEB_PASSWORD` 等）见 [项目主页配置表](../README.md#配置)。
