#!/bin/bash
# 从 Backblaze B2 恢复持久化数据到本地卷
#
# 容器内默认恢复至 /app 下（entrypoint 自动调用）；
# 宿主机手动执行时可覆盖目标路径：
#   QQ_DIR=/data/QQ CONFIG_DIR=/data/config PLUGINS_DIR=/data/plugins ./restore.sh
#
# B2 上的目录布局（与备份脚本一致）：
#   b2://<BUCKET>/<B2_PREFIX>/{QQ,config,plugins}
set -uo pipefail

: "${B2_ACCOUNT_ID:?需要设置 B2_ACCOUNT_ID}"
: "${B2_APPLICATION_KEY:?需要设置 B2_APPLICATION_KEY}"
: "${B2_BUCKET:?需要设置 B2_BUCKET}"

B2_PREFIX="${B2_PREFIX:-napcat}"
QQ_DIR="${QQ_DIR:-/app/.config/QQ}"
CONFIG_DIR="${CONFIG_DIR:-/app/napcat/config}"
PLUGINS_DIR="${PLUGINS_DIR:-/app/plugins}"

export RCLONE_B2_ACCOUNT="$B2_ACCOUNT_ID"
export RCLONE_B2_KEY="$B2_APPLICATION_KEY"

REMOTE=":b2:$B2_BUCKET/$B2_PREFIX"
FLAGS=(--fast-list --transfers 8 --checkers 8)

mkdir -p "$QQ_DIR" "$CONFIG_DIR" "$PLUGINS_DIR"

echo "[napcat-b2] 恢复 QQ 数据 → $QQ_DIR"
rclone copy "$REMOTE/QQ" "$QQ_DIR" "${FLAGS[@]}" \
    || echo "  WARN: QQ 无备份或恢复失败"

echo "[napcat-b2] 恢复 NapCat 配置 → $CONFIG_DIR"
rclone copy "$REMOTE/config" "$CONFIG_DIR" "${FLAGS[@]}" \
    || echo "  WARN: config 无备份或恢复失败"

echo "[napcat-b2] 恢复插件 → $PLUGINS_DIR"
rclone copy "$REMOTE/plugins" "$PLUGINS_DIR" "${FLAGS[@]}" \
    || echo "  WARN: plugins 无备份或恢复失败"

echo "[napcat-b2] 恢复完成"
