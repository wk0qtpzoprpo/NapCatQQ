#!/bin/bash
# NapCat × B2 内置备份调度器（主容器内后台常驻）
#
# 到点后启动一个 sidecar 容器（同镜像）执行停机备份：
#   sidecar 挂载 docker.sock + 宿主数据目录(/data:ro)，
#   在 sidecar 内完成 docker stop → rclone sync → docker start，
#   因此主容器被停止时不影响备份流程本身。
#
# 依赖：容器挂载 /var/run/docker.sock 与 /backup-data
# 环境变量：BACKUP_HOUR / BACKUP_MINUTE / B2_*
set -uo pipefail

log() { echo "[napcat-b2] $(date '+%F %T') $*"; }

# 等待 docker.sock 就绪
for _ in $(seq 1 30); do
    [ -S /var/run/docker.sock ] && break
    sleep 1
done

if [ ! -S /var/run/docker.sock ]; then
    log "FATAL: 未挂载 /var/run/docker.sock，内置备份不可用（请检查 compose 挂载）"
    exit 1
fi

SELF_ID="$(cat /etc/hostname)"
IMAGE="$(docker inspect -f '{{.Config.Image}}' "$SELF_ID" 2>/dev/null || echo napcat-b2:latest)"
SELF_NAME="$(docker inspect -f '{{.Name}}' "$SELF_ID" 2>/dev/null | sed 's#^/##')"
DATA_HOST="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/backup-data"}}{{.Source}}{{end}}{{end}}' "$SELF_ID" 2>/dev/null)"

log "调度器启动 | 容器: $SELF_NAME | 数据宿主路径: ${DATA_HOST:-<未找到 /backup-data>}"

while true; do
    HOUR="${BACKUP_HOUR:-4}"
    MINUTE="${BACKUP_MINUTE:-0}"
    NEXT="$(date -d "today ${HOUR}:${MINUTE}:00" +%s 2>/dev/null)"
    NOW="$(date +%s)"
    if [ -z "$NEXT" ] || [ "$NEXT" -le "$NOW" ]; then
        NEXT=$((NOW + 60))
    fi
    log "下次备份: $(date -d "@$NEXT" '+%F %T')"
    sleep $((NEXT - NOW))

    if [ -z "$DATA_HOST" ] || [ -z "$SELF_NAME" ]; then
        log "WARN: 缺少 /backup-data 挂载或容器名，跳过本次备份"
        continue
    fi

    log "启动 sidecar 执行停机备份..."
    docker run --rm \
        --name "napcat-b2-backup-$(date +%s)" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$DATA_HOST":/data:ro \
        -e TARGET_CONTAINER="$SELF_NAME" \
        -e B2_ACCOUNT_ID="${B2_ACCOUNT_ID:-}" \
        -e B2_APPLICATION_KEY="${B2_APPLICATION_KEY:-}" \
        -e B2_BUCKET="${B2_BUCKET:-}" \
        -e B2_PREFIX="${B2_PREFIX:-napcat}" \
        --entrypoint bash \
        "$IMAGE" /opt/napcat-b2/backup.sh || log "WARN: sidecar 备份执行异常"
done
