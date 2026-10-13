# NapCat × B2 备份式持久化镜像
#
# 基于官方 NapCat Docker 镜像（mlikiowa/napcat-docker）定制：
#   1) 内置 rclone（B2 原生 backend），用于向 Backblaze B2 定时备份与恢复
#   2) 入口脚本：数据卷为空且配置了 B2 时，先从 B2 拉取恢复，再启动 NapCat
#
# 构建：docker build -t napcat-b2:latest .
FROM mlikiowa/napcat-docker:latest

# 安装 rclone（官方静态二进制）
RUN set -eux; \
    ARCH="$(dpkg --print-architecture)"; \
    case "$ARCH" in \
      amd64) RCLONE_ARCH="amd64" ;; \
      arm64) RCLONE_ARCH="arm64" ;; \
      *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;; \
    esac; \
    curl -fL -o /tmp/rclone.zip "https://downloads.rclone.org/rclone-current-linux-${RCLONE_ARCH}.zip"; \
    unzip -o /tmp/rclone.zip -d /tmp/rclone; \
    cp /tmp/rclone/rclone-*-linux-${RCLONE_ARCH}/rclone /usr/local/bin/rclone; \
    chmod +x /usr/local/bin/rclone; \
    rm -rf /tmp/rclone /tmp/rclone.zip; \
    rclone version | head -1

# 编排脚本：入口（恢复+调度+启动）、备份（sidecar 内停机备份）、恢复、调度器
COPY entrypoint.sh restore.sh backup.sh scheduler.sh /opt/napcat-b2/
RUN chmod +x /opt/napcat-b2/*.sh

# 数据卷（与官方镜像约定一致）
VOLUME /app/napcat/config
VOLUME /app/.config/QQ

ENTRYPOINT ["bash", "/opt/napcat-b2/entrypoint.sh"]
