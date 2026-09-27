# 头像存储与审核：服务器操作说明

本次头像功能在 Flutter main 上开发，后端补丁基于原后端 master，不包含搁置的视频功能。已按授权于 2026-09-28 将头像源码同步到 www.leisure.xin 的 /var/www/treehole-nest。未执行数据库迁移、修改密钥、生成部署文件或重启服务。

## 功能与接口

- 登录用户上传头像：POST /node/user/avatar，multipart 表单只有一个 file 字段，使用 x-session-id、x-session-secret 请求头鉴权。用户 ID 从有效会话取得。
- 上传文件最大 5MB，只接受真实且可完整解码的 512×512 JPEG。App 使用 image_cropper 的原生裁剪页面固定正方形，前端将大小图统一为 512×512 JPEG 并清除元数据；后端用 libvips 只校验格式、尺寸与可解码性，不缩放或转码。
- 复用阿里云 baselineCheck 及项目现有图片审核规则。审核未启用、缺少密钥、调用失败、结果异常或超过 45 秒均拒绝更新。
- 用户原图留在手机；上传的裁剪结果在操作系统私有临时目录进行解码校验。待审核的 JPEG 暂存在 /var/www/img/pre-upload/avatar-review/，用于阿里云通过 HTTPS 拉取；文件名随机，接口不返回该地址，审核结束后清理。
- 审核通过的头像存入 /var/www/img/user-icon/<随机 UUID>.jpg；users.avatar_filename 保存文件名。数据库更新成功后清理旧头像；拒绝或更新失败时保留旧头像。
- POST /node/user/profile 增加 avatar_url 字段，无头像为 null。Flutter 在登录或切号后读取该字段。
- 每个账号每 10 秒最多发起一次上传。原来的手机本地头像不会自动上传；更新 App 后重新选择一次即可同步到服务器。

## 当前服务器同步状态（2026-09-28）

- 当前服务器已完成源码同步，不需要再执行第 1 节上传和应用补丁。该节仅供其他未同步环境使用。
- TypeScript 无输出类型检查及 11 项头像单元测试通过。
- 原始源码备份：/home/pell/avatar-sync.nPxhh9G4/source-before.tar.gz。同步前已有源码差异另存于同目录 existing-changes.patch。
- 数据库迁移、媒体目录与审核配置、正式构建及重启仍由你按后续步骤检查执行。

## 1. 上传补丁

在本机 Flutter 仓库目录的 PowerShell 执行：

```powershell
scp -P 400 .\deploy\avatar-backend.patch www.leisure.xin:/home/pell/avatar-backend.patch
ssh -p 400 www.leisure.xin
```

以下命令在服务器执行：

```bash
cd /var/www/treehole-nest
git -c safe.directory=/var/www/treehole-nest status --short
git -c safe.directory=/var/www/treehole-nest apply --check /home/pell/avatar-backend.patch
```

先保存服务器已有的源码修改。补丁检查成功后再应用；若检查报冲突，停止并核对差异，不要强制覆盖。

```bash
git -c safe.directory=/var/www/treehole-nest apply /home/pell/avatar-backend.patch
```

本补丁不修改 package.json 或锁文件，不需要因头像功能重新安装依赖。使用服务器已有依赖构建。

## 2. 媒体与审核配置

确认现有服务账号 www-data 可读写头像和审核目录，并且 libvips 已安装：

```bash
sudo install -d -o www-data -g www-data -m 755 /var/www/img/user-icon
sudo install -d -o www-data -g www-data -m 755 /var/www/img/pre-upload/avatar-review
vips --version
vipsheader --version
```

后端 .env 使用项目已有审核配置：

```dotenv
MODERATION_ENABLED=true
ALIBABA_CLOUD_ACCESS_KEY_ID=已有的阿里云密钥ID
ALIBABA_CLOUD_ACCESS_KEY_SECRET=已有的阿里云密钥
IMG_BASE_URL=https://www.leisure.xin:33433
```

上面是配置项说明，不要把示例文字当作密钥覆盖现有配置。由有权限的操作人编辑 .env，保持 www-data 可读和现有 600 权限。本功能不需要额外管理员令牌。

OpenResty 应继续将媒体 HTTPS 根路径映射到 /var/www/img；阿里云必须能够访问 /pre-upload/avatar-review/ 中待审核的文件。关闭目录列表。/user-icon/ 的 .jpg 应以 image/jpeg 提供头像；已有 .webp 继续提供 image/webp。反向代理请求体限制至少 5MB（建议 8M），上传接口读取超时至少 90 秒。审核目录的临时文件在请求完成后会删除；若进程异常终止，可在确认没有审核任务运行后清理残留。

## 3. 数据库迁移（必须在启动新代码之前完成）

先按你的数据库备份流程完成备份。迁移仅在 users 表新增可空的 avatar_filename VARCHAR(64)，现有用户默认 null。

```bash
cd /var/www/treehole-nest
sudo -u www-data -- node --env-file=.env scripts/apply-avatar-migration.cjs
```

脚本使用已有 DB_HOST、DB_PORT、DB_USERNAME、DB_PASSWORD、DB_NAME。Node 20.20.0 支持 --env-file；执行时不需要把数据库密码写入命令。
首次成功输出 Avatar migration applied.；已存在且类型兼容时跳过。若同名列类型不符则停止，不会覆盖已有字段。

可用数据库管理工具确认：

```sql
SHOW COLUMNS FROM users LIKE 'avatar_filename';
```

## 4. 构建与重启

```bash
cd /var/www/treehole-nest
npm run build
npm test -- --runInBand user-avatar.service.spec.ts avatar-image.processor.spec.ts avatar-upload.options.spec.ts
```

确认构建和测试成功后：

```bash
PM2_HOME=/var/www/.pm2 pm2 reload treehole-nest --update-env
PM2_HOME=/var/www/.pm2 pm2 list
PM2_HOME=/var/www/.pm2 pm2 logs treehole-nest --lines 80 --nostream
```

若构建失败，不要执行后面的重启命令。若运行后提示 Unknown column avatar_filename，检查第 3 步是否针对实际生产数据库完成。

## 5. App 验收

1. 安装包含头像改动的 App，登录后点击头像，选择图片进入现成裁剪页面，可移动、缩放和旋转，固定正方形。取消时不上传；确认后通过底部小 Toast 显示上传审核进度及结果，个人页面布局不变，通过后头像更新。分别验证小图和大图输出均为 512×512 JPEG。
2. 在另一台设备登录同一账号，确认显示相同头像；切换账号后不应显示上一账号头像。
3. 直接向接口上传超过 5MB、非 JPEG、错误尺寸或损坏图片，后端应拒绝。原图大小不等于上传大小：App 上传的是裁剪压缩结果。
4. 在测试环境模拟审核拒绝、审核服务不可用及数据库更新失败，确认旧头像保留，待审核文件清理；生产环境不要为了验证而停用全站审核。
5. 用未登录会话访问头像上传接口，应返回 401。成功后用户资料的 avatar_url 应指向 /user-icon/，该 URL 可通过 HTTPS 读取。
6. 服务器 libvips 校验、阿里云真实审核和手机原生裁剪上传的联调需要在实际部署后验证。本地测试使用模拟审核和图片校验器验证发布与失败清理逻辑；前端另测小图放大、大图缩小及无效图片。原生 Android/iOS 裁剪需真机验收。

## 6. 回退

如果应用补丁后没有其他相关源码修改，可以回退代码：

```bash
cd /var/www/treehole-nest
git -c safe.directory=/var/www/treehole-nest apply --check -R /home/pell/avatar-backend.patch
git -c safe.directory=/var/www/treehole-nest apply -R /home/pell/avatar-backend.patch
npm run build
```

仅在回退构建成功后重启：

```bash
PM2_HOME=/var/www/.pm2 pm2 reload treehole-nest --update-env
```

先保留 users.avatar_filename 和 user-icon 目录中的已审核头像，便于恢复。旧版服务不使用新增列；无需通过删列或删文件来回退代码。

## 更新已有头像补丁的说明

本文件配套的 avatar-backend.patch 是基于原 master 的完整补丁，不要重复叠加到已经应用旧版头像补丁的代码上。若服务器已应用旧版，请先保留旧版补丁并检查工作区，再撤回旧版源码补丁后应用新版；有其他源码修改时先核对差异。已经增加 avatar_filename 的数据库不需要再次改表，迁移脚本会检查后跳过。新版保留已有 WebP 头像的读取，新上传统一为 JPEG。

## iOS 裁剪主题构建

App 通过 third_party/image_cropper 本地插件扩展 iOS 配色，需将该目录随源码一起保存。flutter pub get 后需完整重编译 App（热重载无法更新原生代码）；底层 TOCropViewController 固定为 2.8.0。iOS 需要在 macOS/Xcode 编译并验证深浅主题、系统主题与 App 主题不同、旋转、取消和上传。当前 Windows 环境只完成 Flutter 侧参数桥接测试，未进行 iOS 编译或真机验收。

## 2026-09-28 multipart 修复

已远程修复 Too many parts：移除 parts: 1，继续限制单文件、无额外字段和 5MB。源码及构建产物已更新，未重启服务、未运行 MySQL。需要用户自行重启后端后让修复生效。新版前端采用底部小 Toast 显示上传审核进度及结果，需更新 App 才能看到。

## 2026-09-28 审核响应兼容修复

严格审核允许阿里云 nonLabel 结果不携带 confidence；其他风险标签仍检查置信度，畸形结果仍拦截。已同步服务器、npm run build 成功、22 项头像测试通过。未重启或运行 MySQL。前端改为底部小 Toast，上传完成自动关闭进度提示并展示结果，页面布局不变。
