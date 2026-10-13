#!/bin/bash
# NapCat × B2 每日停机备份脚本 —— 运行在宿主机（由 cron 调用）
#
# 流程：停止容器（保证 SQLite/WAL 一致）→ rclone sync → 启动容器
# 说明：备份必须停机进行。QQ 的 SQLite 库运行中持续写页，直接复制活文件
#       可能得到"写到一半"的库；停掉容器才能获得一致快照。
#
# 依赖：宿主机 docker 可用；镜像已构建（napcat-b2:latest）；容器以 compose 启动。
# 定时安装：./scripts/install-cron.sh  （默认每天 04:00）
#
# 环境变量（可来自 .env）：B2_ACCOUNT_ID / B2_APPLICATION_KEY / B2_BUCKET /
#                          B2_PREFIX / DATA_DIR / CONTAINER_NAME / IMAGE
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 读取 .env（若存在）
if [ -f "$PROJECT_DIR/.env" ]; then
    set -a; . "$PROJECT_DIR/.env"; set +a
fi

CONTAINER_NAME="${CONTAINER_NAME:-napcat}"
DATA_DIR="${DATA_DIR:-$PROJECT_DIR/data}"
IMAGE="${IMAGE:-napcat-b2:latest}"

: "${B2_ACCOUNT_ID:?需要 B2_ACCOUNT_ID（写入 .env 或环境变量）}"
: "${B2_APPLICATION_KEY:?需要 B2_APPLICATION_KEY}"
: "${B2_BUCKET:?需要 B2_BUCKET}"
B2_PREFIX="${B2_PREFIX:-napcat}"

log() { echo "[napcat-b2] $(date '+%F %T') $*"; }

log "开始备份（容器: $CONTAINER_NAME | 数据: $DATA_DIR | 目标: b2://$B2_BUCKET/$B2_PREFIX）"

# ---------- 1. 停止容器 ----------
RUNNING=$(docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_NAME" && echo yes || echo no)
if [ "$RUNNING" = "yes" ]; then
    log "停止容器 $CONTAINER_NAME ..."
    docker stop -t 120 "$CONTAINER_NAME"
else
    log "容器未运行，跳过 stop"
fi

# ---------- 2. 同步到 B2 ----------
# 使用镜像内的 rclone（--entrypoint 直连，不走入口脚本）
RC=0
log "rclone sync → B2 ..."
docker run --rm --entrypoint rclone \
    -e B2_ACCOUNT_ID="$B2_ACCOUNT_ID" \
    -e B2_APPLICATION_KEY="$B2_APPLICATION_KEY" \
    -v "$DATA_DIR":/data:ro \
    "$IMAGE" \
    sync /data ":b2:$B2_BUCKET/$B2_PREFIX" \
        --fast-list \
        --transfers 8 \
        --checkers 8 \
        --exclude "**/cache/**" \
        --exclude "**/log/**" \
        --exclude "**/crash-report/**" \
        --exclude "*.log" || RC=$?

# ---------- 3. 重启容器 ----------
EXISTS=$(docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER_NAME" && echo yes || echo no)
if [ "$EXISTS" = "yes" ]; then
    log "启动容器 $CONTAINER_NAME ..."
    docker start "$CONTAINER_NAME"
fi

if [ $RC -eq 0 ]; then
    log "备份完成 ✓"
else
    log "备份失败 ✗ (rc=$RC)"
fi
exit $RC
