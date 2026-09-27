# 置顶聊天与系统消息部署（2026-09-28）

## 当前状态

后端源码已同步到 /var/www/treehole-nest，并通过 npm run build 和 34 项无数据库单元测试。App 新增三个栏目及置顶功能，5 项 widget 测试和相关源码静态检查通过。

助手没有执行 MySQL、没有重启或 reload 后端。新代码尚需你完成下述数据库操作并启用。没有新增 npm 依赖、令牌或环境变量。Android/iOS 的最终界面和双账号实时操作仍需安装新 App 验证。

修改前源码备份：
/home/pell/system-inbox.Oplw7VDO/before.tar.gz
/home/pell/system-inbox.Oplw7VDO/avatar-before.tar.gz

## 1. 数据库操作（由你执行）

先备份应用数据库，确认此前私信三表和 last_read_seq 迁移已完成。使用现有管理账号连接 DB_NAME 对应的数据库：

    mysql -u 你的管理账号 -p 你的实际数据库名

在 MySQL 客户端检查：

    SELECT DATABASE();
    SHOW COLUMNS FROM user_message_preferences;
    SHOW TABLES LIKE 'system_messages';
    SHOW TABLES LIKE 'system_message_reads';

确认 user_message_preferences 已有 last_read_seq、尚无 pinned，并且两张 system 表不存在。满足条件后执行：

    SOURCE /var/www/treehole-nest/database/migrations/20260928_add_pinned_and_system_inbox.sql;

此脚本包含三项操作：
- 增加 pinned，默认 0，每个用户独立保存自己的置顶设置。
- 创建 system_messages，存储公告、审核与举报结果、帖子回复通知。recipient_id 为 NULL 的公告面向所有登录用户，包括以后注册的用户；私人通知有明确收件人。event_key 唯一，用于业务事件重试去重。
- 创建 system_message_reads，主键为消息 ID + 用户 ID，保存每个人的已读记录。读公告不会清除其他用户的未读。
- post_id/comment_id 只是关联线索，不加级联外键；原帖删除后仍保留通知快照。通知不公开匿名回复者的实际用户 ID 或昵称。

MySQL DDL 不构成可整体回滚的事务。脚本没有 IF NOT EXISTS；中途出错时检查哪些操作已完成，只处理缺失项，不要直接重跑或删表。

使用有授权权限的管理账号执行以下 SQL。把“实际数据库名”替换成 DB_NAME；若运行账号已经变化，也替换账号名：

    GRANT SELECT, INSERT ON `实际数据库名`.`system_messages` TO 'submit-post'@'localhost';
    GRANT SELECT, INSERT ON `实际数据库名`.`system_message_reads` TO 'submit-post'@'localhost';

保留既有 user_message_preferences 的 SELECT、INSERT、UPDATE 权限。

    SHOW CREATE TABLE system_messages;
    SHOW CREATE TABLE system_message_reads;
    SHOW COLUMNS FROM user_message_preferences LIKE 'pinned';

## 2. 启用新版后端（由你执行）

SQL 和授权完成后，在你准备好的维护时间使用现有部署流程启用新代码。助手已经编译，但没有操作进程；如需重新构建：

    cd /var/www/treehole-nest
    npm run build

按照此前运行用户 www-data、PM2_HOME=/var/www/.pm2 的配置，重启命令为：

    sudo -H -u www-data env PM2_HOME=/var/www/.pm2 pm2 restart treehole-nest
    sudo -H -u www-data env PM2_HOME=/var/www/.pm2 pm2 logs treehole-nest --lines 80 --nostream

先确认 PM2 实际配置与上述一致。不要在 SQL 或授权未完成时启用新进程：未读统计和回复入库会使用新表。

重新编译安装 Flutter App。此次未新增原生插件配置。

## 3. 接口与行为

沿用 SessionGuard 的 x-session-id / x-session-secret，不使用新令牌。

- POST /node/messages/dm/conversations/:id/preferences 支持 {"pinned":true} 或 false；与免打扰/黑名单分别保存。
- GET /node/messages/dm/conversations 返回 pinned；置顶会话排在前面，同组延续原来的 ID 倒序。下一页同时传 next_before_id 和 next_before_pinned 对应的 before_id / before_pinned。切换置顶后刷新列表。
- GET /node/messages/system/summary 返回 announcement、moderation、reply 的未读数。
- GET /node/messages/system?category=announcement（或 moderation/reply），可带 before_id。
- POST /node/messages/system/:id/read，正文 {}。只允许收件人或全体公告读者操作，可重复调用。
- 系统消息只在打开具体详情后标记已读；进入栏目或后台刷新不会自动清空未读。
- 系统消息未读计入底栏数字；免打扰私信仍只显示无数字红点。私信系统通知文案的数量仍只取对应私信会话。
- system.changed 仅通知客户端重新拉取，不携带正文；私密消息推送前验证会话。其他设备的已读状态也同步。
- 本次系统栏目没有新增手机系统通知或离线推送通道。

## 4. 已接入和预留的来源

已接入：
- 新的帖子文本审核未通过：保存提交标题和审核返回原因。尚未生成帖子 ID，因此不会伪造违规帖链接。审核服务异常也可能导致不通过，提示不等同于人工判定违规。
- 新的头像审核未通过：保存审核原因。
- 新的帖子回复：给帖子归属用户写入通知，与回复同一事务提交；自己回复自己不通知。网页旧帖若 user_id 为 NULL，无法归属用户，不生成个人通知。
- 详情展示通知正文、时间和关联帖子编号；目前不提供从通知跳转帖子页面。

预留：
- 公告存储、阅读已完成，后端 SystemInboxStore.publishAnnouncement 为可信内部发布方法。按此前决定，管理员登录、发布接口和管理 App 仍未设计。
- 举报按钮目前是占位入口，没有真实举报提交/裁决流程。SystemInboxStore.recordReportResult 是未来处理流程的内部写入方法，普通用户不能调用 HTTP 接口伪造审核或举报结果。此时“审核与举报”里可以收到审核消息，但不会凭空产生举报结果。
- 已发布帖被删除/判违规的通知尚无对应管理流程；以后在该流程调用系统消息写入方法。
- 不回填历史审核和回复记录。

若你需要先人工发布一条公告，可由管理账号在应用数据库执行（修改内容，每次用不同 event_key）：

    INSERT INTO system_messages (recipient_id, category, event_key, title, content)
    VALUES (NULL, 'announcement', 'manual-announcement-20260928-001', '公告标题', '公告正文');

SQL 手工插入不会发出 Socket.IO 事件，用户刷新消息或下次进入后可见。以后管理员调用内部发布方法可同步通知在线设备。

## 5. 验收

1. A、B 登录，A 将与 B 的聊天置顶，退出重进仍置顶；B 的设置不受影响。取消置顶恢复同组 ID 排序，免打扰和黑名单不被改动。
2. 会话超过 30 条时，验证置顶分组跨页无重复、无遗漏。
3. 发布公告：两个账号各自收到 1 条未读；A 读详情后 B 仍未读。
4. B 回复 A 的帖子：A 的帖子回复栏目和底栏更新；A 查看后多设备未读同步清除；自己回复自己不产生通知。
5. 触发实际审核未通过，确认审核原因进入相应用户栏目；另一账号不能获取或标记该私人通知已读。
6. 新消息与免打扰私信同时存在时，数字仅合计系统消息和非免打扰私信；只有免打扰私信未读时为纯红点。
7. 断网、重连、切号及前后台切换验证数据补拉，不串账号。

单元测试使用 mock，不代表已执行真实 MySQL 迁移或线上接口联调。


## 后续更新：举报已接入

上述“举报仍占位”的阶段描述已更新。举报提交、三人阈值自动隐藏与结果通知已实现；新的迁移和授权见 [REPORTS_DEPLOY.md](REPORTS_DEPLOY.md)。管理员裁决、恢复和申诉仍待后续实现。
