# 消息本地缓存、增量同步与私信审核

## 功能与决定

- 消息会话列表、已加载私信、三个系统栏目和分类未读摘要在本机缓存。使用 Hive 加密存储，密钥放在现有安全存储；按账号令牌的 SHA-256 摘要隔离缓存，不把令牌或会话密钥写入缓存。
- 进入页面先显示本账号缓存，然后同步。断网保留缓存；未加载过的历史需联网获取。首次登录其他账号不会读取上一个账号的缓存。服务端确认会话失效后清理该账号消息缓存。
- 刷新发送最后确认收到的消息时间 after_time，并带 after_seq（私信）或 after_id（系统消息/会话）。服务端以稳定序号/ID 为准，避免同一毫秒多条消息或时间回拨导致漏收，不能仅使用 created_at > 时间。
- 私信每页最多 50 条，系统消息/新会话每页最多 30 条；补齐新增内容时自动继续下一页。只有成功合并并落盘后推进游标。发送成功的本地消息会缓存，但不提前推进同步游标，以免跳过尚未收到的对方消息。
- 向上查看旧历史沿用 before_seq / before_id，保留独立分页位置，不改变最新同步游标。
- 旧消息已读、隐藏后的正文替换、头像、置顶、免打扰、拉黑等不是新消息；每批最多 200 条发送 ID + sync_hash 做轻量状态核对，只返回改变或失去访问权的记录。置顶 ID 查询补发现其他设备新置顶的旧会话。
- 系统消息及新会话创建使用 message_publish_lock 的单行事务锁，让 ID 分配顺序与提交顺序一致，避免较旧事务迟提交而被增量游标跨过。所有受支持的业务写入路径均遵守该锁；不要绕过它直接插入新系统消息。
- 没有新增 npm 或 Flutter 依赖。

## 私信审核规则

- 所有新文字私信必须经过现有阿里云文本审核，审核通过后才保存和发送给对方。
- 同一用户跨会话累计连续审核拒绝；第 3 次拒绝后 send_disabled=1，后端关闭发送功能。仍能阅读历史、接收别人发送的私信。
- 中间一次新消息审核通过且成功发送，连续失败计数清零。重放以前已发送成功的 UUID 不会清除后来的失败记录。
- 相同 client_message_id 的失败重试只记一次。相同 UUID 改成其他内容/会话会被拒绝；修改草稿会生成新的 UUID。
- 未通过内容不写入 dm_messages，也不会发送给对方。拒绝记录保存内容摘要与审核原因，不保存被拒绝的私信正文。
- 配置未启用、缺凭据、结果结构异常、调用失败或超过 8 秒：拒绝这次发送，但不增加也不清零连续拒绝数。
- 审核消息和三次后的关闭通知写入“审核与举报”。第三次关闭与拒绝记录同一事务提交，通知在提交后发出。
- 暂无管理员恢复接口、自动到期或申诉入口；以后在管理员端统一实现。当前发送关闭持续保留。

## 数据库操作：由你执行

助手没有运行 SQL，也不会重启后端。先备份数据库，确认此前私信、系统消息、举报迁移均完成。

使用管理账号连接实际 DB_NAME：

    mysql -u 你的管理账号 -p 你的实际数据库名

检查三张新表尚不存在：

    SHOW TABLES LIKE 'dm_user_controls';
    SHOW TABLES LIKE 'dm_rejections';
    SHOW TABLES LIKE 'message_publish_lock';

执行：

    SOURCE /var/www/treehole-nest/database/migrations/20260928_add_dm_moderation.sql;

脚本创建：
- dm_user_controls：用户连续拒绝计数、发送禁用状态。
- dm_rejections：用户 + 消息 UUID 主键，内容摘要、拒绝原因及时间，用于重试去重。
- message_publish_lock：只有 id=1 的同步锁行。不要删除或清空。

MySQL DDL 不构成可整体回滚的事务；中途失败时检查已成功部分，仅补剩余操作，不要直接重跑整份脚本。

授予运行账号必要权限（替换实际数据库名和有变化的运行账号）：

    GRANT SELECT, INSERT, UPDATE ON `实际数据库名`.`dm_user_controls` TO 'submit-post'@'localhost';
    GRANT SELECT, INSERT ON `实际数据库名`.`dm_rejections` TO 'submit-post'@'localhost';
    GRANT SELECT, UPDATE ON `实际数据库名`.`message_publish_lock` TO 'submit-post'@'localhost';

保留此前消息表、用户表、系统消息表所需权限。确认锁行存在：

    SELECT id FROM message_publish_lock;
    SHOW CREATE TABLE dm_user_controls;
    SHOW CREATE TABLE dm_rejections;

## 审核配置：由你核对

服务器 .env 对 SSH 账号不可读，助手没有读取密钥，也未确认生产审核配置是否启用。部署前请自行确认：

- MODERATION_ENABLED=true。
- ALIBABA_CLOUD_ACCESS_KEY_ID、ALIBABA_CLOUD_ACCESS_KEY_SECRET 已配置，当前账号能够调用 comment_detection_pro。
- 原有帖子/头像审核配置可复用，不需要把密钥发送给助手。
- 若审核未配置，新版私信会拒绝发送并提示服务不可用，但不会因此累计违规次数。

## 启用后端：由你执行

数据库迁移和授权完成后：

    cd /var/www/treehole-nest
    npm run build
    sudo -H -u www-data env PM2_HOME=/var/www/.pm2 pm2 restart treehole-nest
    sudo -H -u www-data env PM2_HOME=/var/www/.pm2 pm2 logs treehole-nest --lines 80 --nostream

先确认实际 PM2 用户与路径一致。助手只同步源码和构建，不执行这些重启操作。App 需重新编译安装。

修改前源码备份：
- /home/pell/message-cache-before-20260928.tar.gz
- /home/pell/message-moderation-before-20260928.tar.gz

## API 增量协议

- GET /node/messages/dm/conversations/:id/messages?after_seq=最后序号&after_time=末条服务端时间
- GET /node/messages/system?category=reply&after_id=最后ID&after_time=末条服务端时间
- GET /node/messages/dm/conversations?after_id=最后ID&after_time=末条服务端时间

after_time 使用 ISO8601，URL 编码。before 与 after 不能同时使用。增量结果按序号/ID升序返回；has_more=true 表示继续补拉。客户端显示时按倒序合并、按 ID 去重。初次加载和旧历史分页接口保持兼容。

状态核对：

    POST /node/messages/dm/conversations/state
    {"known":[{"id":8,"hash":"上次返回的64位sync_hash"}]}

    POST /node/messages/system/state
    {"category":"reply","known":[{"id":10,"hash":"上次返回的64位sync_hash"}]}

返回 items 只有变动的完整记录，removed_ids 指出不可再访问的缓存记录。系统摘要仍通过 summary 查询；GET /messages/dm/pinned 只返回置顶会话 ID，避免重传正文。

私信发送错误：
- 403 + DM_MODERATION_REJECTED：本次审核未通过。
- 403 + DM_SEND_DISABLED：发送功能已关闭。
- 503：审核服务不可用/超时，不计违规。

HTTP 鉴权继续使用已有会话请求头。

## 手工公告注意事项

之前文档直接 INSERT 的方式在启用增量同步后需要加锁，以保持提交顺序：

    START TRANSACTION;
    SELECT id FROM message_publish_lock WHERE id=1 FOR UPDATE;
    INSERT INTO system_messages(recipient_id,category,event_key,title,content)
    VALUES(NULL,'announcement','manual-unique-event-key','标题','正文');
    COMMIT;

正常管理员内部发布方法已经自动处理锁。手工 SQL 不发实时事件，用户下一次刷新可见。

## 验收与边界

1. 登录 A，加载会话和历史后断网再进入，应先显示缓存。切换 B 不应看到 A 的内容。
2. 同一毫秒产生多条私信、离线期间超过 50 条：联网后补齐且无重复；抓包确认正常刷新携带 after_time/序号，只返回新增正文。
3. 读旧历史后再刷新，旧记录和分页位置保留；自己发送时恰有未收取的对方消息，游标不能跳过它。
4. 另一设备修改已读、置顶、免打扰，或举报触发旧系统消息正文隐藏，本机刷新后更新相应状态。
5. 连续三条不同 UUID 的明确审核拒绝关闭发送；同一 UUID 重试不加次数；失败→通过→失败计为一次。
6. 模拟审核配置关闭、网络异常和超时，多次操作不能误关闭账号；关闭账号的新 UUID 也不能绕过后端限制。
7. 接收消息、阅读历史和通知在关闭发送后仍可用。

缓存是普通本机历史缓存，不是端到端加密或离线推送。远程管理员恢复发送权限的业务流程尚未实现；不要仅通过重新安装 App 试图解除服务端限制。

## 本次自动验证

- 服务器 npm run build 通过。
- 后端 9 组、52 项相关测试通过，包含审核计数、重试去重、服务故障、增量分页和既有消息/举报/头像回归。
- Flutter 10 项相关测试通过，包含缓存账号隔离、增量游标、旧消息状态修正与现有消息界面。
- 尚未执行数据库迁移、生产重启或真机验收；真实审核配置需要按上文核对。
