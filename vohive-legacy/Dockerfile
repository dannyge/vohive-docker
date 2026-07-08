# vohive-legacy: 闭源完整版 vohive v1.5.5（过渡，将淡出）
# 二进制来自 6mb/vohive-release 备份（见 assets/fetch-assets.sh）
# buildx 会按 TARGETARCH 自动注入 amd64/arm64
FROM alpine:latest

ARG TARGETARCH

RUN apk add --no-cache ca-certificates tzdata libc6-compat socat && \
    [ ! -d /usr/share/zoneinfo/Asia ] || cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime 2>/dev/null || true

WORKDIR /app

# 按架构选二进制
COPY assets/vohive_legacy_${TARGETARCH} /app/vohive
RUN chmod +x /app/vohive

# 运营商表（完整版需要）
COPY assets/mcc-mnc-table.json /app/data/mcc-mnc-table.json

# 配置模板和入口脚本
COPY vohive-legacy/config.template.yaml /app/config.template.yaml
COPY vohive-legacy/docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh

ENTRYPOINT ["/app/docker-entrypoint.sh"]
