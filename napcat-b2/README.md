# NapCat × B2 备份式持久化

基于官方 NapCat Docker 镜像（`mlikiowa/napcat-docker`）定制，内置 rclone，实现：

- **每日 04:00 停机备份**到 Backblaze B2（保证 SQLite 一致性，天级丢失窗口）
- **首次启动 / 换机自动恢复**：数据卷为空时自动从 B2 拉取，登录态保留、无需重新扫码
- 镜像由 **GitHub Actions 自动构建**并推送到 GHCR（`ghcr.io/<owner>/napcat-b2:latest`）

```
容器(napcat-b2) ──本地卷──> ./data/{config,QQ,plugins} ──rclone sync──> B2 bucket（版本保留 3 天）
                                    ↑                                          │
                                    └──────── 空卷时自动恢复 ──────────────────┘
```

## 目录结构

| 路径 | 说明 |
|---|---|
| `Dockerfile` | 基于官方镜像 + 内置 rclone |
| `entrypoint.sh` | 容器入口：空卷恢复 → 调用官方入口启动 QQ |
| `restore.sh` | 从 B2 恢复到本地卷（容器内自动调用，也可宿主机手动执行） |
| `scripts/backup.sh` | **宿主机**停机备份脚本（cron 调用） |
| `scripts/install-cron.sh` | 安装每日 04:00 备份 cron |
| `docker-compose.yml` | 一键编排 |
| `.env.example` | 配置模板（复制为 `.env` 填写） |
| `.github/workflows/build-image.yml` | GitHub Actions 自动构建镜像 → GHCR |

## 快速开始

### 0. 准备

1. Backblaze B2 账号，创建一个 bucket（如 `napcat-backup`）：
   - Bucket Settings → File Versioning：**Keep all versions**
   - Lifecycle Rules：**Days from Hiding to Deleting = 3**（即旧版本保留 3 天，到期自动清理）
2. 创建 Application Key：capability 勾选 **读写 + List All Bucket Names**，记下 `keyID`（= B2_ACCOUNT_ID）和 `applicationKey`（= B2_APPLICATION_KEY）。

### 1. 构建镜像

**方式 A：GitHub Actions（推荐）**

本仓库已配置 `.github/workflows/build-image.yml`：

1. 首次使用需启用 Actions：仓库 **Settings → Actions → General → Allow all actions**（fork 默认关闭）；
2. push 到 `napcat-b2/**` 或在 **Actions** 页手动 **Run workflow**；
3. 构建完成后产物：`ghcr.io/<owner>/napcat-b2:latest`；
4. 拉取方式二选一：
   - 把包设为 public：仓库 **Settings → Packages → napcat-b2 → Make public**（推荐，部署机免登录）；
   - 或部署机 `docker login ghcr.io -u <owner> --password-stdin`（使用 GitHub PAT）。

**方式 B：本地构建**

```bash
docker build -t napcat-b2:latest ./napcat-b2
```

### 2. 配置

```bash
cp napcat-b2/.env.example napcat-b2/.env
# 编辑 .env：
#   ACCOUNT=<机器人QQ号>
#   B2_ACCOUNT_ID=<B2 keyID>
#   B2_APPLICATION_KEY=<B2 applicationKey>
#   B2_BUCKET=napcat-backup
#   IMAGE=ghcr.io/<owner>/napcat-b2:latest   # 使用 GHCR 镜像时
```

### 3. 启动

```bash
cd napcat-b2
docker compose up -d
```

首次启动：

1. 查看容器日志获取 WebUI token：`docker logs napcat | grep -i webui`；
2. 浏览器打开 `http://<服务器IP>:6099/webui`，用 token 登录；
3. 进入 **QQ 登录** → 扫码登录机器人账号；
4. 登录成功后配置 OneBot 网络连接（HTTP / WebSocket），保存并启用。

之后重启容器会自动登录，数据写入 `./data`。

### 4. 安装每日备份

```bash
cd napcat-b2
./scripts/install-cron.sh          # 默认每天 04:00
# 自定义时刻：BACKUP_CRON="30 3 * * *" ./scripts/install-cron.sh

# 手动跑一次验证
./scripts/backup.sh && tail backup.log
```

> 备份脚本运行在**宿主机**（需要 docker 命令）。它先 `docker stop` 容器，再用镜像内的 rclone 同步 `./data` 到 B2，最后 `docker start`，停机窗口约 1~5 分钟/天。

### 5. 恢复 / 换机

1. 新机器安装 docker，clone 本仓库，配置相同的 `.env`；
2. 确保 `./data` 为空（或删除后重建）；
3. `docker compose up -d` —— entrypoint 检测到空卷会自动从 B2 拉取数据再启动，**无需重新扫码登录**。

手动恢复（可选）：

```bash
cd napcat-b2
QQ_DIR=./data/QQ CONFIG_DIR=./data/config PLUGINS_DIR=./data/plugins \
B2_ACCOUNT_ID=... B2_APPLICATION_KEY=... B2_BUCKET=... B2_PREFIX=napcat \
docker run --rm -v $(pwd)/data:/data -e B2_ACCOUNT_ID=... -e B2_APPLICATION_KEY=... \
  --entrypoint bash <image> -c 'QQ_DIR=/data/QQ CONFIG_DIR=/data/config PLUGINS_DIR=/data/plugins /opt/napcat-b2/restore.sh'
```

## 备份内容

| 内容 | 备份 | 说明 |
|---|---|---|
| `./data/config` → `/app/napcat/config` | ✅ | OneBot 配置、WebUI token |
| `./data/QQ` → `/app/.config/QQ` | ✅ | **登录态 + SQLite 数据（最重要）** |
| `./data/plugins` → `/app/plugins` | ✅ | 插件 |
| `**/cache/**`、`**/log/**`、`**/crash-report/**`、`*.log` | ❌ 排除 | 可再生，压缩备份体积与请求成本 |

B2 上目录布局：`b2://<BUCKET>/<B2_PREFIX>/{QQ,config,plugins}`（`B2_PREFIX` 默认 `napcat`，多实例共用一桶时用于区分）。

## 注意事项

- **单实例约束**：同一个 B2 前缀同时只允许一个容器读写；
- **凭据安全**：B2 凭据只通过环境变量注入（`.env` 已在 `.gitignore` 中），不写入镜像；
- **恢复演练**：建议每月做一次"清空 data → 自动恢复"演练，确认流程可用；
- **版本回滚**：B2 保留 3 天旧版本，误删/数据异常时可从 B2 控制台或 `rclone backend` 找回历史版本；
- 本项目基于非官方 QQ Bot 框架，使用请遵守当地法律法规。
