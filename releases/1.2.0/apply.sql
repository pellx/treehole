-- 在目标数据库中手动执行，单操作者；不要同时发布多个版本。
-- 先持久备份原行。临时备份仅在当前 MySQL 连接中存在，断开后需用持久备份回滚。
SET NAMES utf8mb4;
CREATE TEMPORARY TABLE IF NOT EXISTS release_120_backup LIKE versions;
CREATE TEMPORARY TABLE IF NOT EXISTS release_120_capture (id INT PRIMARY KEY);
START TRANSACTION;
INSERT INTO release_120_backup SELECT * FROM versions WHERE version_number='1.2.0' AND platform='android' AND NOT EXISTS (SELECT 1 FROM release_120_capture);
INSERT IGNORE INTO release_120_capture VALUES (1);
SET @release_title='私信、消息中心与内容治理';
SET @release_log='新增：一对一私信与消息中心、官方系统消息与公告、内容举报与自动隐藏、统一内容安全与分级处罚、头像上传审核与原生裁剪
优化：消息本地加密缓存与增量同步、广场首帧与启动路径、消息页与底栏视觉、加载反馈统一为底部小提示
修复：Android 升级版本号单调性、通用包 ABI 兜底、消息页首帧与启动画面、工具栏图标跳动、消息列表间距';
SET @release_description='1.2.0：
一，私信与消息中心：
1. 新增一对一私信：会话列表、聊天页、乐观发送、失败重试、已读游标、置顶、免打扰与黑名单
2. 消息页提供回复、公告、审核三个入口，底栏未读角标与一键清空未读
3. 消息本地加密缓存按账号隔离，支持增量同步与离线查看
4. 实时连接通过 Socket.IO 刷新会话，前台新私信展示本地通知
5. 首次启动引导开启通知权限，帖子作者菜单可直接发起私信
二，举报与内容隐藏：
1. 帖子和回复支持按原因举报
2. 同一内容被 3 个不同账号举报后自动隐藏
3. 客户端持久化隐藏标记并清理缓存、缩略图与草稿
4. 刷新时批量核对可见性，迟到响应不会复活已隐藏内容
三，内容安全与账号处罚：
1. 发帖、回复、私信、上传、改名统一走内容安全校验
2. 违规记录统一归档，处罚按 1 天、1 周、30 天、永久逐级升级
3. 审核拒绝不保存正文，封禁账号在发布入口直接提示
4. 发布请求携带请求标识，避免重复提交绕过限制
四，头像与个人资料：
1. 头像改为相册选择后原生 1:1 裁剪，再上传由服务端审核
2. 仅展示审核通过的头像，审核期间保留旧头像
3. 裁剪页支持主题配色，iOS 使用主题化裁剪控制器
五，启动与广场性能：
1. 启动阶段预取广场首页并在首帧展示缓存快照
2. 广场优先使用缓存，失败时回退到上次的帖子列表
3. 加载过程不再插入占位条目，减少首屏跳动
4. 消息页切换标签时保留状态
六，界面与交互：
1. 统一底部小提示与确认弹窗，加载状态不再占用页面布局
2. 消息页顶栏、底栏、角标与底部菜单样式集中到主题配置
3. 调整帖子卡片与消息列表的间距、图标与菜单顺序
七，发布与兼容：
1. Android versionCode 改为 build 号乘 10000 加 ABI 偏移
2. 版本号校验范围限制为 1 到 210000
3. 裁剪插件改为仓库内 fork，锁定 iOS 裁剪组件版本
4. 本版本依赖后端新接口与新表，需先完成服务端部署与数据库迁移';
SET @release_url='https://www.leisure.xin:33433/flutter_app_version/v1.2.0/';
UPDATE versions SET title=@release_title, log=@release_log, description=@release_description, download_url=@release_url WHERE version_number='1.2.0' AND platform='android';
INSERT INTO versions (version_number,platform,title,log,description,download_url,release_date)
SELECT '1.2.0','android',@release_title,@release_log,@release_description,@release_url,NOW()
WHERE NOT EXISTS (SELECT 1 FROM versions WHERE version_number='1.2.0' AND platform='android');
SELECT * FROM versions WHERE version_number='1.2.0' AND platform='android';
SELECT id,version_number FROM versions WHERE platform='android' ORDER BY id DESC LIMIT 1;
-- 确认只有一条 1.2.0 且 latest 为 1.2.0 后，手动执行 COMMIT;
-- 否则手动执行 ROLLBACK; 此文件不自动提交。
