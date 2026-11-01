# 最小的「Debian VPS」：systemd 当 PID 1，procps 提供 pgrep、iproute2 提供 ip（云镜像标配；chain 腿用 ip 把出口机路由掉）。
# 其余工具由 install.sh 自己装，这里故意不预装。
FROM debian:bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends systemd systemd-sysv ca-certificates procps iproute2 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*
CMD ["/sbin/init"]
