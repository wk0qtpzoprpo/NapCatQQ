#!/bin/bash
# 安装 NapCat × B2 每日备份 cron（默认每天 04:00）
#
# 自定义时刻：BACKUP_CRON="30 3 * * *" ./scripts/install-cron.sh
# 卸载：crontab -e 删除含 napcat-b2/scripts/backup.sh 的行
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BACKUP_CRON="${BACKUP_CRON:-0 4 * * *}"
CRON_LINE="$BACKUP_CRON cd $PROJECT_DIR && ./scripts/backup.sh >> $PROJECT_DIR/backup.log 2>&1"

# 先删除旧的 napcat-b2 备份任务，再写入新行（避免重复）
( crontab -l 2>/dev/null | grep -v "napcat-b2/scripts/backup.sh" || true; echo "$CRON_LINE" ) | crontab -

echo "[napcat-b2] 已安装 cron："
crontab -l | grep "napcat-b2/scripts/backup.sh" || true
echo "[napcat-b2] 日志文件：$PROJECT_DIR/backup.log"
