#!/bin/bash
# NapCat × B2 停机备份 —— 运行于 sidecar 容器
#
# sidecar 挂载：docker.sock + 宿主数据目录(/data:ro)
# 流程：停止目标容器（保证 SQLite/WAL 一致）→ rclone sync → 启动目标容器
# 环境变量：TARGET_CONTAINER / B2_ACCOUNT_ID / B2_APPLICATION_KEY / B2_BUCKET / B2_PREFIX
set -euo pipefail

: "${TARGET_CONTAINER:?需要 TARGET_CONTAINER}"
: "${B2_ACCOUNT_ID:?需要 B2_ACCOUNT_ID}"
: "${B2_APPLICATION_KEY:?需要 B2_APPLICATION_KEY}"
: "${B2_BUCKET:?需要 B2_BUCKET}"

B2_PREFIX="${B2_PREFIX:-napcat}"
export RCLONE_B2_ACCOUNT="$B2_ACCOUNT_ID"
export RCLONE_B2_KEY="$B2_APPLICATION_KEY"

log() { echo "[napcat-b2] $(date '+%F %T') $*"; }

# 任何退出路径都保证目标容器被拉起来（防 sidecar 崩溃导致停机）
trap 'docker start "$TARGET_CONTAINER" 2>/dev/null || true' EXIT

log "备份开始 | 目标容器: $TARGET_CONTAINER | b2://$B2_BUCKET/$B2_PREFIX"

# 1. 停止目标容器
log "停止容器 $TARGET_CONTAINER ..."
docker stop -t 120 "$TARGET_CONTAINER"

# 2. 同步到 B2
RC=0
log "rclone sync → B2 ..."
rclone sync /data ":b2:$B2_BUCKET/$B2_PREFIX" \
    --fast-list \
    --transfers 8 \
    --checkers 8 \
    --exclude "**/cache/**" \
    --exclude "**/log/**" \
    --exclude "**/crash-report/**" \
    --exclude "*.log" || RC=$?

# 3. 启动目标容器
log "启动容器 $TARGET_CONTAINER ..."
docker start "$TARGET_CONTAINER" || true

if [ $RC -eq 0 ]; then
    log "备份完成 ✓"
else
    log "备份失败 ✗ (rc=$RC)"
fi
exit $RC
