# dji2quectel: 把大疆 4G 模块改写为移远 Quectel EC25 身份
# 一次性任务容器，运行需 --privileged + 挂载 /sys /lib/modules /dev
FROM alpine:latest

RUN apk add --no-cache socat usbutils kmod bash

COPY dji2quectel.sh /app/dji2quectel.sh
RUN chmod +x /app/dji2quectel.sh

WORKDIR /app
ENTRYPOINT ["/app/dji2quectel.sh"]
