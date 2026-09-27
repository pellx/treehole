# Treehole 视频功能：生产操作手册

本手册供有服务器管理权限的操作人逐步执行。代码已在本地准备；**数据库、密钥、依赖安装、服务重启和视频登记均尚未在生产执行**。服务器信息以 2026-09-23 的只读核对为准，执行前仍按第 1 步复核。

## 0. 文件与约定

- 后端补丁：本目录的 `video-player-backend.patch`；它包含 NestJS 视频模块、BullMQ 转码、SQL 迁移与一次性迁移脚本。
- 依赖安全补丁：本目录的 `video-dependency-security.patch`；它更新运行时依赖，并将 NestJS 11 使用的 Multer 固定到修复版 2.3.0。先应用后端补丁，再应用此补丁。
- Flutter 改动在当前仓库；App 需另行构建、安装和真机验收。
- 后端目录：`/var/www/treehole-nest`；媒体根目录：`/var/www/img`。
- API：`https://tree.leisure.xin/node/videos`；媒体：`https://www.leisure.xin:33433`。
- 后端 `.env` 属于 `www-data`，权限为 `600`。以下涉及它的命令需要可交互的 `sudo` 权限；不要把密码或令牌写入 Git、聊天或操作记录。

## 1. 传输与上线前检查

在本机 PowerShell 中，从 Flutter 仓库根目录传输补丁：

```powershell
scp -P 400 .\deploy\video-player-backend.patch www.leisure.xin:/home/pell/video-player-backend.patch
scp -P 400 .\deploy\video-dependency-security.patch www.leisure.xin:/home/pell/video-dependency-security.patch
ssh -p 400 www.leisure.xin
```

以下命令在服务器执行。先确认工作区干净、运行环境和剩余磁盘空间：

```sh
cd /var/www/treehole-nest
git -c safe.directory=/var/www/treehole-nest status --short
git -c safe.directory=/var/www/treehole-nest rev-parse --short HEAD
node --version
ffmpeg -version | head -n 1
ffprobe -version | head -n 1
df -h /var/www/img
PM2_HOME=/var/www/.pm2 pm2 list
git -c safe.directory=/var/www/treehole-nest apply --check /home/pell/video-player-backend.patch
```

`status --short` 应为空，`apply --check` 应无输出且退出码为 0。核对后端当前运行状态，确认 `/var/www/img` 有足够空间；转码会临时存放 360p、720p 两套分片。若 Git 工作区已有改动，或补丁检查失败，先查明差异，不要强行应用。

## 2. 应用后端代码、安装依赖并构建

```sh
cd /var/www/treehole-nest
git -c safe.directory=/var/www/treehole-nest apply /home/pell/video-player-backend.patch
git -c safe.directory=/var/www/treehole-nest apply --check /home/pell/video-dependency-security.patch
git -c safe.directory=/var/www/treehole-nest apply /home/pell/video-dependency-security.patch
sudo install -d -o www-data -g www-data -m 700 /var/tmp/treehole-npm-cache
sudo -H -u www-data npm ci --cache /var/tmp/treehole-npm-cache
npm audit --omit=dev
npm test -- --runInBand
npm run build
```

`npm audit --omit=dev` 应输出 `found 0 vulnerabilities`。完整 `npm audit` 仍可能报告仅影响开发工具的告警；本次依赖补丁没有使用 `--force`，也没有升级 NestJS 到 12。以上命令会更新后端工作区和 `node_modules`、`dist`，但尚未重启服务。若文件权限阻止安装或构建，由有权限的操作人处理对应目录权限；不要对整个 `/var/www` 递归改权限。

## 3. 执行一次性数据库迁移

迁移创建 `videos`、`video_danmaku` 两张表，不修改现有表。脚本读取后端 `.env` 中的 `DB_HOST`、`DB_PORT`、`DB_USERNAME`、`DB_PASSWORD`、`DB_NAME`，不会在终端打印数据库密码。服务器已核对为 Node `v20.20.0`，支持 `--env-file`。

先按现有数据库备份流程备份生产数据库，然后执行：

```sh
cd /var/www/treehole-nest
sudo -u www-data -- node --env-file=.env scripts/apply-video-migration.cjs
```

首次成功输出 `Video migration applied.`；再次运行输出 `Video tables already exist; migration skipped.`。若只建成其中一张表，脚本会停止并提示人工检查，此时不要直接重跑 SQL。可用有权限的数据库账号核对表结构：

```sql
SHOW CREATE TABLE videos;
SHOW CREATE TABLE video_danmaku;
```

## 4. 配置管理员令牌

`VIDEO_ADMIN_TOKEN` 是登记、查看转码状态和重试任务的管理员令牌；至少 32 个字符。先检查 `.env` 中是否已有同名项，不显示其值：

```sh
sudo grep -q '^VIDEO_ADMIN_TOKEN=' /var/www/treehole-nest/.env
echo $?
```

输出 `0` 表示已有令牌，应由操作人安全地取用或轮换；输出 `1` 表示没有。若没有，生成随机令牌并追加，命令本身不会把令牌打印在屏幕上：

```sh
sudo -u www-data -- sh -c 'umask 077; printf "\nVIDEO_ADMIN_TOKEN=%s\n" "$(openssl rand -hex 32)" >> /var/www/treehole-nest/.env'
```

如使用其他密钥管理方式，也可以将 `VIDEO_ADMIN_TOKEN` 注入 PM2 进程环境，但重启时须保留。默认媒体配置无需写入 `.env`：`VIDEO_MEDIA_ROOT=/var/www/img`，`VIDEO_PUBLIC_BASE=https://www.leisure.xin:33433`。若修改，应确保 API 返回的 HLS 和封面 URL 仍可通过 HTTPS 访问。

## 5. 重启与基础验证

```sh
cd /var/www/treehole-nest
PM2_HOME=/var/www/.pm2 pm2 reload treehole-nest --update-env
PM2_HOME=/var/www/.pm2 pm2 list
PM2_HOME=/var/www/.pm2 pm2 logs treehole-nest --lines 80 --nostream
curl -i https://tree.leisure.xin/node/videos
```

预期 PM2 进程为 `online`；视频列表返回 HTTP 200 和 `[]`（如果还没登记视频）。若服务启动报表不存在，回到第 3 步检查迁移；若连接 Redis 失败，检查现有 `REDIS_HOST`、`REDIS_PORT`、`REDIS_PASSWORD` 配置。不要把含敏感信息的完整日志公开。

## 6. 登记一条较短的现有视频作验证

服务器上已确认 `/var/www/img/teacher-day.mp4` 和 `/var/www/img/2.jpg` 存在。先用这条视频验证；不要先登记多 GB 的电影文件。以下命令在服务器的交互式 shell 中执行。输入令牌时终端不回显，也不进入 shell 历史：

```sh
read -r -s -p 'VIDEO_ADMIN_TOKEN: ' VIDEO_ADMIN_TOKEN; echo
curl -fsS -X POST 'https://tree.leisure.xin/node/videos/admin/register' \
  -H "x-video-admin-token: $VIDEO_ADMIN_TOKEN" \
  -H 'Content-Type: application/json' \
  --data '{"title":"教师节测试视频","source_path":"teacher-day.mp4","cover_path":"2.jpg"}'
```

记下返回的整数 `id`，把下面的 `VIDEO_ID` 改成该数值：

```sh
VIDEO_ID=1
curl -fsS "https://tree.leisure.xin/node/videos/admin/$VIDEO_ID/status" \
  -H "x-video-admin-token: $VIDEO_ADMIN_TOKEN"
```

状态依次可能为 `pending`、`processing`、`ready`。只有 `ready` 才出现在公开列表。完成后检查主播放列表和公开详情：

```sh
curl -i "https://www.leisure.xin:33433/video-hls/$VIDEO_ID/master.m3u8"
curl -fsS "https://tree.leisure.xin/node/videos/$VIDEO_ID"
curl -fsS 'https://tree.leisure.xin/node/videos'
unset VIDEO_ADMIN_TOKEN
```

主播放列表应返回 HTTP 200，且包含 `360p/playlist.m3u8`、`720p/playlist.m3u8`。若状态为 `failed`，先用管理员状态接口读 `error_message`，修复原因后再重试：

```sh
read -r -s -p 'VIDEO_ADMIN_TOKEN: ' VIDEO_ADMIN_TOKEN; echo
curl -fsS -X POST "https://tree.leisure.xin/node/videos/admin/$VIDEO_ID/retry" \
  -H "x-video-admin-token: $VIDEO_ADMIN_TOKEN"
unset VIDEO_ADMIN_TOKEN
```

登记接口使用服务器内现有文件相对于 `/var/www/img` 的路径；不要提交根目录外路径。`video-hls` 由工作进程在媒体目录下创建。若 HLS URL 返回 404，核对输出文件、`www-data` 目录权限及 OpenResty 的 HTTPS 映射。

## 7. App 验收

分别在 Android 和 iOS 真机安装包含本次 Flutter 改动的构建。确认封面列表和详情可见；自动/手动清晰度、横屏全屏和返回、进度拖动、倍速、双击、水平滑动、长按临时倍速均可用；后台返回后的播放状态正常。验证弹幕随暂停、拖动和跳转同步。访客只能观看，发送时进入登录流程；登录用户发送后立即可见。服务器若未完成第 2–6 步，App 视频页会处于加载/错误或空列表状态。

## 8. 回退

先停止新增视频登记。若只是转码文件有问题，可保持服务运行，检查失败状态并修复后通过管理员重试接口重新转码。

若新后端版本导致服务故障，且应用补丁后没有其他代码改动，可回退代码并重建：

```sh
cd /var/www/treehole-nest
git -c safe.directory=/var/www/treehole-nest apply --check -R --exclude=package.json --exclude=package-lock.json /home/pell/video-player-backend.patch
git -c safe.directory=/var/www/treehole-nest apply -R --exclude=package.json --exclude=package-lock.json /home/pell/video-player-backend.patch
npm run build
PM2_HOME=/var/www/.pm2 pm2 reload treehole-nest --update-env
```

新建的两张数据库表与 `/var/www/img/video-hls` 输出文件先保留，避免误删数据；待确认备份和影响后再单独决定清理。已安装到用户设备上的新版 App 无法靠服务器代码回退消除视频入口，需要通过 App 发布流程处理。
