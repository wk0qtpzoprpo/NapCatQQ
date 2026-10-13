#!/bin/bash
# NapCat × B2 容器入口（开箱即用版）
#
# 职责：
#   1) 数据卷为空且配置了 B2 时，先从 B2 拉取恢复（首次部署 / 换机恢复）
#   2) 启用内置备份调度器（后台常驻，每日定时触发停机备份，无需宿主机 cron）
#   3) 调用官方 NapCat 入口（/app/entrypoint.sh）启动 QQ
#
# 环境变量：B2_ACCOUNT_ID / B2_APPLICATION_KEY / B2_BUCKET / B2_PREFIX
#           BACKUP_ENABLED / BACKUP_HOUR / BACKUP_MINUTE
set -e

echo "[napcat-b2] $(date '+%F %T') entrypoint 启动"

# ---------- 1. B2 恢复 ----------
if [ -n "${B2_ACCOUNT_ID:-}" ] && [ -n "${B2_APPLICATION_KEY:-}" ] && [ -n "${B2_BUCKET:-}" ]; then
    if [ ! -d /app/.config/QQ ] || [ -z "$(ls -A /app/.config/QQ 2>/dev/null)" ]; then
        echo "[napcat-b2] 检测到空数据卷，尝试从 B2 恢复..."
        if bash /opt/napcat-b2/restore.sh; then
            echo "[napcat-b2] B2 恢复完成"
        else
            echo "[napcat-b2] WARN: B2 恢复未完全成功（首次部署无备份属正常），继续启动"
        fi
    else
        echo "[napcat-b2] 数据卷非空，跳过恢复"
    fi
else
    echo "[napcat-b2] 未配置 B2 环境变量，跳过恢复（纯本地模式）"
fi

# ---------- 2. 启动内置备份调度器（后台） ----------
if [ "${BACKUP_ENABLED:-true}" = "true" ]; then
    echo "[napcat-b2] 启动内置备份调度器（每日 ${BACKUP_HOUR:-4}:${BACKUP_MINUTE:-0}）"
    nohup bash /opt/napcat-b2/scheduler.sh >> /app/napcat/config/napcat-b2-scheduler.log 2>&1 &
else
    echo "[napcat-b2] 备份调度已禁用（BACKUP_ENABLED != true）"
fi

# ---------- 3. 调用官方入口 ----------
OFFICIAL_ENTRY=""
for f in /app/entrypoint.sh /entrypoint.sh; do
    if [ -f "$f" ]; then
        OFFICIAL_ENTRY="$f"
        break
    fi
done

if [ -n "$OFFICIAL_ENTRY" ]; then
    echo "[napcat-b2] 调用官方入口: $OFFICIAL_ENTRY"
    exec bash "$OFFICIAL_ENTRY"
fi

echo "[napcat-b2] FATAL: 未找到官方入口脚本（期望 /app/entrypoint.sh）。" >&2
echo "[napcat-b2] 请检查基础镜像 mlikiowa/napcat-docker 的 ENTRYPOINT 是否变化。" >&2
exit 1
