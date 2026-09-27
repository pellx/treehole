# 统一违规记录与账号封禁部署

本说明替代 MESSAGE_CACHE_MODERATION_DEPLOY.md 中的私信专用处罚规则。消息缓存、增量同步及 message_publish_lock 保持不变。

## 已实现的规则

- 内容安全模块 src/moderation 统一维护用户违规历史和封禁状态。
- 来源：dm_text（私信文本）、post_text（帖子标题和正文）、reply_text（回复文本）、image_upload（图片预上传）、avatar_image（头像图片）、reported_post / reported_reply（被举报后明确认定违规）。
- 审核拒绝不保存正文、图片、内容摘要、风险词。历史只保存原因类别、来源、关联对象、请求标识、审核者和处罚快照。图片审核所需临时文件在失败或异常后清理；不建立违规图片档案。
- 首次跨来源连续 3 次明确违规封 24 小时；解禁后每次新的违规依次封 7 天、30 天、永久。通过审核并成功完成发布清零初始连续次数，但不降低处罚等级。
- 审核服务未配置、返回异常、请求故障或超时不是违规，拦截发送但不计罚。文本与图片发布均要求真实审核可用。
- 被封禁账号禁止发帖、回复、私信、上传任何附件/图片、上传头像和修改公开用户名；浏览、登录、接收/阅读消息、已读标记及个人会话设置继续可用。
- 截止时间由后端判断，无需定时 SQL 或后台解封任务；发送与发布提交前再次校验。已经成功发送的私信重试仅返回旧记录，不产生新发布。
- 同一账号、来源、请求标识唯一；重复审核失败不重复计罚。私信沿用 client_message_id；其他发布支持 x-publish-id UUID 请求头。App 对同一会话相同内容的重试在当前进程内复用该标识，修改内容会生成新标识。客户端重启或切换会话后的再次提交属于新请求；后端不存内容摘要，因此不做相同正文全局去重。

## 两张表

### user_controls：当前状态，每个用户一行

- user_id：users 主键。
- consecutive_failures：首次处罚前连续违规计数。
- penalty_level：0 无处罚，1 一天，2 一周，3 三十天，4 永久；正常发布不降低等级。
- banned_at / banned_until：最近一次封禁开始/截止时间。
- permanent：永久封禁。到期后保留历史字段，生效状态按时间计算。

### user_violation_history：每个违规事件一行

- id、user_id、source、request_key、reason、created_at。
- target_id：私信违规时为会话 ID；举报认定为帖子或回复 ID；尚未发布的内容为 NULL。
- reviewer_id：人工认定审核者，自动审核为 NULL。
- penalty_level、banned_until、permanent：本次处罚结果快照，保留历次封禁情况。
- UNIQUE(user_id, source, request_key) 防重；用户与时间索引便于查询历史。

## 举报认定边界

三名不同用户举报仍只触发隐藏，绝不因此直接记违规或封禁。

内容安全服务新增内部方法：

    confirmReportedViolation(type, targetId, reviewerId, reasonCode)

- type 为 post / comment。
- reasonCode 为 spam / abuse / sexual / violence / illegal / privacy / other；不接受自由输入原文作为记录原因。
- 原子完成：确认存在举报、定位真实作者、隐藏内容、更新帖子变更时间、替换旧回复通知正文、记录违规与处罚、给举报者发送最终结果。
- 同一对象只处罚一次；更多举报或重复点击认定不能追加次数。
- 既有隐藏信号和消息状态同步会清理/替换前端缓存。
- 尚无管理员 HTTP 接口或管理页面。此方法只能由未来经过管理员权限验证的调用方调用，绝不可直接暴露给普通用户。reviewerId 不是身份鉴权。
- 没有 user_id 的历史匿名内容不能可靠归属账号，该方法拒绝处罚；继续沿用举报隐藏机制。
- 对已封禁账号后来认定的其他独立违规仍记录并升级处罚；有未结束的临时封禁时从现有截止时间追加时长。
- 已经发布后再被认定违规的帖子/回复按既有逻辑隐藏，原业务表保留；违规历史表不复制正文。不包含申诉、撤销和人工解封接口。

## 接口兼容性变化

旧 POST /posts 和 POST /posts/comment 无登录身份，无法执行账号封禁，现返回 410；使用登录后的 /posts/v2 和 /posts/v2/comment。

POST /file-processor/upload 必须携带 x-session-id / x-session-secret；App 已接入。其余发布入口保留原鉴权。multipart 的身份和请求标识放请求头，避免增加表单 parts。

封禁返回 403 + ACCOUNT_BANNED、message、banned_until、permanent。单次审核违规返回 CONTENT_REJECTED。前端使用现有底部小提示，不新增文档流信息。

## 数据库迁移：仅由你执行

助手没有运行 MySQL，也没有重启后端。先备份数据库并安排停止写入窗口。不要在新旧进程同时写入时更名表。

1. 若上次的 20260928_add_dm_moderation.sql 尚未执行，先按旧说明完成它（包括 message_publish_lock），再运行本次迁移。此前私信、系统通知、举报相关迁移也必须已完成。
2. 查看实际表结构：

       SHOW CREATE TABLE dm_user_controls;
       SHOW CREATE TABLE dm_rejections;

3. 执行本次脚本：

       SOURCE /var/www/treehole-nest/database/migrations/20260928_generalize_user_safety.sql;

   它把原两张表更名，删除内容摘要列，保留旧计数和请求标识。旧版已永久禁发的用户改为从迁移时起封禁一天，处罚等级 1。旧历史无法还原当时处罚快照，标记为历史审核拒绝，快照字段保留默认值。

4. 为实际运行账号授予新表权限（替换数据库名及账号）：

       GRANT SELECT, INSERT, UPDATE ON `实际数据库名`.`user_controls` TO 'submit-post'@'localhost';
       GRANT SELECT, INSERT ON `实际数据库名`.`user_violation_history` TO 'submit-post'@'localhost';

   原系统消息、用户、帖子、回复、举报表权限以及 message_publish_lock 权限继续需要。表更名不自动迁移原表名对应的授权。

5. 核对结果：

       SHOW CREATE TABLE user_controls;
       SHOW CREATE TABLE user_violation_history;
       SELECT user_id, penalty_level, banned_at, banned_until, permanent FROM user_controls;

DDL 不能整体事务回滚，迁移非幂等；中途失败需根据实际结构补剩余步骤，不能盲目重跑。使用与应用现有 DATETIME 配置一致的数据库时区执行；截止时间 API 输出 ISO8601。

## 配置与启用：仅由你执行

- 核对 MODERATION_ENABLED=true 与原有阿里云文本/图片审核凭据及权限。助手未读取生产密钥。
- 完成迁移授权后 npm run build，再由你按现有 PM2 方式重启 treehole-nest。需要重新安装新版 App；旧客户端无身份预上传会收到 401。
- 暂缓的视频模块不在本次改动中，重新启用它时需将弹幕等新发布入口接入同一 ContentSafetyService，不能绕开统一封禁。
- 源码备份：/home/pell/content-safety-before-20260928.tar.gz。

## 验证

自动测试覆盖递进期限及永久封禁、解禁后等级保留、违规去重、审核故障不计罚、私信与回复审核、图片以附件类型上传仍审核、头像清理、举报认定幂等与隐藏、发布路由鉴权。

部署后需用测试账号验证真实审核返回、跨入口禁发、截止时间及客户端提示。没有执行生产迁移、重启或真实违规内容测试。

自动验证结果：服务器 npm run build 通过；后端 10 组共 65 项相关测试通过；前端 10 项测试通过；修改涉及的 Dart 文件静态检查无问题。
