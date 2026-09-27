# 私信与消息系统：部署记录

最新置顶和系统栏目部署请先阅读 [SYSTEM_INBOX_DEPLOY.md](SYSTEM_INBOX_DEPLOY.md)。下文按开发时间记录，最新补充优先。

## 本次范围

新增 dm_conversations（一对一会话）和 dm_messages（文本私信）实体，注册 MessagesModule。现已补齐创建会话、会话列表、历史消息和发送文字四个接口，并接入 Flutter App 的消息页面。已读状态、系统通知和管理员功能暂未实现。

源码位于服务器 /var/www/treehole-nest/src/messages/。SQL 位于 /var/www/treehole-nest/database/migrations/20260928_create_dm_tables.sql。

synchronize 继续为 false，注册实体不会自动建表。本次不需要新增令牌、环境变量或 npm 依赖。助手不执行 MySQL，不重启服务。

## 由你手动执行数据库操作

1. 先按现有流程备份数据库。
2. 使用有建表权限的数据库账号进入应用实际使用的数据库（名称取现有 DB_NAME，密码在终端交互输入，不粘贴到聊天中）：

   mysql -u 你的数据库账号 -p 你的数据库名

3. 在 MySQL 客户端检查：

   SELECT DATABASE();
   SHOW CREATE TABLE users;
   SHOW TABLES LIKE 'dm_conversations';
   SHOW TABLES LIKE 'dm_messages';

   确认 users 是 InnoDB，user_id 为有符号 INT 主键，且两张新表均不存在。实体源码使用有符号 INT，但助手没有查询线上实际表结构；如果类型不同，请先停止并调整新增外键字段，不要改动现有用户主键来迁就 SQL。

4. 满足前提后，在 MySQL 客户端执行：

   SOURCE /var/www/treehole-nest/database/migrations/20260928_create_dm_tables.sql;

5. 检查结果：

   SHOW CREATE TABLE dm_conversations;
   SHOW CREATE TABLE dm_messages;

SQL 只创建新表，不修改 users，不插入数据。没有使用 IF NOT EXISTS，以免把已存在但结构不一致的表误判为迁移成功。MySQL 建表不是一个可整体回滚的事务；若第一张成功、第二张失败，请保留错误信息，确认已存在表结构后仅处理未完成部分，不要盲目删除或重跑。

## 字段与约束

### dm_conversations

- id：会话主键，无符号 INT，自增。
- user_low_id / user_high_id：两名参与者的 users.user_id。后续创建接口必须先排序，保证 low < high，禁止与自己聊天。联合唯一索引防止同一有序组合重复；当前 SQL 未使用 CHECK，排序和禁止自聊必须在服务层实现，不能依赖唯一索引处理反向组合。
- last_seq：该会话最后一条消息序号，初始为 0。
- created_at：创建时间，毫秒精度。
- updated_at：会话行最后更新时间；发送时更新 last_seq 会同步更新时间。后续若增加会话配置等更新，列表排序应另增 last_message_at，避免配置修改改变消息时间。
- 两个用户分别有会话列表索引。查询某用户会话时可分两侧查询并合并排序。

### dm_messages

- id：消息主键，无符号 INT，自增。
- conversation_id：所属会话。
- seq：会话内从 1 开始递增的序号；与 conversation_id 联合唯一，支持按序号分页。
- sender_id：发送者 users.user_id。
- client_message_id：客户端生成的 UUID，重试时保持不变；与 sender_id 联合唯一，用于后续发送接口避免重复落库。
- content：纯文本正文，使用 utf8mb4 支持中文及 emoji。
- created_at：创建时间，毫秒精度。

外键确保用户和会话存在，删除/修改被引用的主键采用 RESTRICT，避免连带删除私信。实体关联不启用 eager 或 cascade。

## 已实现的接口规则

本次最小验证接口已实现以下规则：

- 登录鉴权、会话参与者校验，sender_id 必须取登录身份。
- 创建会话时用户 ID 排序并禁止自聊；唯一冲突时复用已有会话。
- 发送者必须是该会话两名参与者之一；外键本身不验证这项关系。
- 锁定会话行，在同一个事务中分配 seq、写入消息、更新 last_seq。失败整体回滚。
- UUID 格式校验、重复请求核对会话与内容，避免错误地复用不同消息。
- 正文非空及长度上限、发送频率限制；TEXT 类型本身不执行产品层长度规则。
- 私信接口不能直接序列化用户实体，防止带出用户令牌、手机号等字段。

消息为服务端可读取的正文存储，并非端到端加密。审核规则待后续讨论，当前没有接入第三方审核。

## 构建与运行

可以在服务器项目目录运行 npm run build 检查编译。build 不建表、不重启正在运行的进程。两张表的实际创建与线上运行效果，需要你完成数据库操作并启用新版后端后验证。已建好这两张表的服务器，本轮无需新增 SQL 或依赖。
## App 内验证流程（2026-09-28）

本次是现有 Flutter App 的功能，入口为底栏“消息”，不是网页。

### 启用后端（由你操作）

1. 如果两张表尚未创建，先完成上面的 SQL 操作。已创建则不要重复执行。
2. 源码已同步到 /var/www/treehole-nest/src/messages/，构建通过。按你现有部署流程重启 treehole-nest，使新接口生效。助手未执行重启。
3. 重新运行更新后的 Flutter App。没有新增 npm 或 Flutter 依赖，也不需要新的令牌配置。

### 用两个测试账号验证

1. A、B 各自登录 App，进入“消息”，标题会显示各自的用户 ID（users.user_id，不是昵称或令牌）。
2. A 点击右上角“发起私信”，输入 B 的 ID，进入聊天页。
3. A 发送文字；成功后消息出现在右侧，输入框清空。
4. B 在消息列表点击刷新，打开与 A 的会话，查看文字并回复。
5. A 在聊天页自动看到回复。现在通过 Socket.IO 自动通知并读取新消息；刷新按钮保留用于手动重试。
6. 退出会话再进入，验证历史消息仍存在。超过 50 条可加载更早消息；会话列表每页 30 个，按会话创建 ID 倒序展示。
7. 断网发送，确认草稿保留且底部出现小提示；恢复网络后保持正文不变再次发送，沿用同一个 UUID，防止同一请求重复落库。
8. 切换账号后重新进入消息页，确认列表属于新账号。访客可通过登录按钮进入原有登录流程。

正在获取、发送和错误信息均通过底部小提示显示，不向列表或输入区插入加载文本。只有输入接收人 ID 使用中央对话框。颜色使用 App 主题。

### 最小接口

统一前缀 /node/messages/dm，均使用现有 SessionGuard，凭证通过 x-session-id 与 x-session-secret 请求头发送：

- POST /conversations：正文 peer_user_id，创建或复用唯一会话。
- GET /conversations：可选 before_id，返回 user_id、items、next_before_id。
- GET /conversations/:id/messages：可选 before_seq，返回 user_id、items、next_before_seq，消息按 seq 倒序。
- POST /conversations/:id/messages：正文 content、client_message_id（UUID v4），返回已保存消息；相同 UUID 和内容重复发送返回原消息。

仅参与者可读取或发送。正文去除两端空白后不能为空，服务层限制 2000 个 UTF-16 单元；单个用户新消息间隔至少 1 秒。发送在同一数据库事务中锁定用户和会话、写入消息、更新 last_seq。重试返回原消息不占用新序号；同一 UUID 换正文或会话返回冲突。

### 本次验证与限制

- 服务器 npm run build 通过。
- 7 项后端 mock 单元测试通过（不连接数据库）；覆盖越权读写、重复发送、冲突、序号、限频和空正文。
- Flutter 聊天页 widget 测试通过，覆盖失败保留草稿、沿用 UUID 重试及成功显示消息。
- 尚未执行双账号真机端到端验证，也未验证实际数据库并发；需要你启用新版服务后按上述步骤操作。
- 当前支持文字与前台实时通知，没有已读、未读角标、附件或系统离线推送。失败草稿和 UUID 只保留在当前聊天页内，离开页面后不保存。
- 审核策略仍待讨论，本轮没有接入第三方文本审核。
## 建表后授予运行账号权限（2026-09-28 补充）

线上错误确认运行账号 submit-post@localhost 缺少新表的 SELECT 权限。建表账号与运行账号不同，建表不会自动向运行账号授权。

由你使用有 GRANT 权限的管理员账号执行以下 SQL。先将“实际数据库名”替换为应用 DB_NAME；不要原样执行占位符：

GRANT SELECT, INSERT, UPDATE ON `实际数据库名`.`dm_conversations` TO 'submit-post'@'localhost';
GRANT SELECT, INSERT ON `实际数据库名`.`dm_messages` TO 'submit-post'@'localhost';

这两条只授予私信所需的表权限，不授予 DELETE 或整个数据库权限。完成后在 App 点击重试。助手未执行这些 SQL。

前端已修正：消息接口或网络失败显示重试，不再因未取得 user_id 就显示登录按钮；明确需要登录时才显示登录入口。
## 实时私信更新（2026-09-28）

- 复用现有 /node/socket.io，通过 session_id 和 session_secret 鉴权；无需新端口、表或依赖。
- 消息事务提交后向双方在线设备发送 dm.changed，负载只包含 conversation_id。推送前重新校验会话有效性。
- App 收到通知后使用原有鉴权 HTTP 接口读取最新 50 条，自动更新聊天页和可见会话列表。读取期间收到新通知会合并为后续一次补拉。
- 服务端完成用户房间加入后发送 session.ready；客户端据此在初次连接或重连后补拉，避免连接建立期间漏消息。
- App 返回前台会恢复连接并补拉；离线期间保留数据库消息，上线后加载。未接入 APNs/FCM，不保证 App 被系统挂起或关闭时后台即时提醒。
- 消息刷新不显示加载弹窗，手动刷新仍保留用于故障重试。实时刷新展示最新一页，更早消息通过历史分页查看。
- 本轮后端源码已同步，需要你按原流程启用新版进程。助手不重启、不运行 SQL。
- 验证：两账号同时打开同一会话，发送后对端应自动出现；断网期间发送，恢复网络后应自动补拉；退出页面和切换账号后不会继续消费旧页面事件。
## 头像、消息免打扰与黑名单（2026-09-28）

本轮需要新增一张 user_message_preferences 表，不能直接启用新版后端而跳过迁移。

### 由你执行

1. 备份数据库，使用管理员账号进入应用数据库，检查：

   SHOW TABLES LIKE 'user_message_preferences';

2. 确认不存在后执行：

   SOURCE /var/www/treehole-nest/database/migrations/20260928_create_message_preferences.sql;

3. 将下面“实际数据库名”替换为应用数据库名，再授予后端运行账号权限：

   GRANT SELECT, INSERT, UPDATE ON `实际数据库名`.`user_message_preferences` TO 'submit-post'@'localhost';

4. 检查 SHOW CREATE TABLE user_message_preferences;，然后按现有流程启用新版后端并更新 App。之前两张私信表和 users 表无需改结构。助手未执行 SQL 或重启。

### 行为

- 会话列表及每条消息使用 users 中已审核的 avatar_filename，按 IMG_BASE_URL 生成头像 URL；无头像或下载失败回退默认图。API 只返回用户 ID、显示名、头像文件名和 URL，不返回手机号或令牌。
- 聊天页右上角“聊天设置”提供开启/关闭免打扰、加入/移出黑名单。
- 偏好按 user_id + peer_user_id 联合主键保存，跨设备有效。muted 和 blocked 均默认为 false。
- 免打扰保留实时内容同步，关闭收到新私信的底部提示。正在查看对应聊天时本来就不弹新消息提示；App 关闭后的系统通知尚未接入。
- 黑名单目前作用于私信，不屏蔽帖子或评论。任意一方拉黑后双方都不能发送新私信；历史消息保留。可从现有会话进入并解除自己设置的黑名单。
- 另一方的具体黑名单字段不返回，只通过 can_send 表示当前是否可以发送，失败使用统一提示。
- 设置修改与发送都锁定同一会话行串行执行，防止拉黑成功后仍有未检查的发送落库。拉黑之前已经提交的消息保留。
- 设置接口：POST /node/messages/dm/conversations/:id/preferences，正文为 muted 或 blocked 布尔值，可只传一个；沿用会话鉴权与参与者校验。
- 查询会话列表/消息历史新增 peer、self、muted、blocked、can_send 字段。
- 实时事件新增 notify：为 false 时仍刷新内容但不提示。设置变更也通过静默事件同步双方设备。

### 验证

A、B 分别开启 App：查看双方头像；A 对 B 开启免打扰，B 发送后 A 消息仍更新但无底部新消息提示；关闭后恢复提示。A 拉黑 B，双方发送都应失败，历史保留；A 解除后恢复。重新进入页面或换设备验证设置保留。
## 未读数量、已读记录与系统通知权限（2026-09-28）

### 数据库操作（你执行）

本轮在 user_message_preferences 新增 last_read_seq。请先完成之前的私信两表和偏好表迁移；不要重跑旧脚本。备份后在应用数据库中确认列不存在：

SHOW COLUMNS FROM user_message_preferences LIKE 'last_read_seq';

若不存在，再执行：

SOURCE /var/www/treehole-nest/database/migrations/20260928_add_dm_read_cursor.sql;

已有 user_message_preferences 的 SELECT、INSERT、UPDATE 授权无需变化。执行后再启用新版后端。本次助手未运行任何 MySQL 命令、未重启服务。

### 未读规则与接口

- 后端保存每个用户对该会话读到的 last_read_seq，以对方消息中 seq 大于游标的记录数计算未读。自己发送的消息不计入。
- GET /node/messages/dm/unread 返回 unread_count；会话列表每项也返回 unread_count。
- POST /node/messages/dm/conversations/:id/read 接收 last_read_seq，校验参与者，游标只前进、不超过当前会话最大序号。已读变更同步自己其他在线设备。
- 首次迁移时游标为 0，旧的对方消息会显示为未读，进入对应聊天后清除。
- App 底栏“消息”和每个会话显示数字，大于 99 显示 99+。进入聊天、处于前台且位于最新消息附近时回写已读；后台拉取不自动标记已读。
- 免打扰仍计入未读数，仅关闭提醒。黑名单不删除历史未读。

### 通知权限和行为

- 使用 flutter_local_notifications 19.5.0，Android 配置 POST_NOTIFICATIONS、通知图标及 desugaring；iOS 配置通知代理。
- 首次成功打开消息列表时请求系统通知权限；拒绝后不自动重复请求。消息页右上角铃铛可手动再次申请，系统不再弹窗时需到系统设置开启。
- Socket.IO 收到新的私信通知且不是正在前台查看的会话时显示本地系统通知；免打扰和黑名单规则沿用服务端判断。
- 通知仅显示“你收到了一条私信，点击查看”，不在锁屏暴露正文。点击打开消息列表，读取后取消该会话的本地通知。
- 这是实时连接收到事件后发出的本地通知。App 被系统挂起、强制结束或完全关闭时，Socket.IO 不保证运行，不能保证离线送达系统提醒。
- 项目尚未配置 APNs/FCM 或国内厂商推送。本轮没有伪装实现离线推送；完整离线推送还需选定服务、配置应用身份与服务器凭据，并增加设备推送令牌注册和投递流程。
- 前端依赖变更需重新编译安装，热重载不足以启用原生通知插件。iOS 构建需在 macOS 上完成，按现有 Flutter 流程安装 Pods。

### 验证步骤

1. A 不进入与 B 的聊天，B 连发两条：A 会话和底栏显示 2；A 自己发送的消息不增加自己的未读。
2. A 打开聊天并处于最新消息位置：未读清除；另一台登录 A 的设备同步清除。
3. A 拒绝通知权限：消息和未读依旧正常；开启权限后，B 发新消息应有系统通知（A 未正在看该会话）。
4. 开启免打扰：消息照常更新并累计未读，但不提示；关闭后恢复。
5. 退出/切换账号检查角标与通知清理，断线重连后从后端重新获取未读。
6. Android 13+ 和 iOS 真机分别验证权限弹窗、拒绝、系统设置中重新授权及通知点击；模拟测试不能代替系统权限实测。

插件配置依据：https://pub.dev/packages/flutter_local_notifications/versions/19.5.0
### 本轮验证记录

- 后端 npm run build 通过，17 项私信/通知 mock 测试通过；未连接数据库执行测试。
- 4 项 Flutter widget 测试通过，覆盖设置、实时更新、已读回写、发送重试与角标显示。新增通知服务、页面和角标静态检查通过。
- Android 完整 debug APK 构建已尝试，但长时间未完成；检查时机器可用物理内存约 200 MB，随后停止本次构建。因此本轮不宣称完整原生打包通过。
- iOS 无 macOS 构建环境，Android/iOS 系统通知权限弹窗和通知显示仍需真机验证。
## 通知数量与免打扰角标补充（2026-09-28）

- 新增 GET /node/messages/dm/conversations/:id/unread，校验参与者后返回该会话 unread_count、muted、blocked。通知按该会话实际未读显示“你收到了{num}条私信，点击查看”；不会累加事件次数。
- 通知并发查询只采用最新结果，已读/切号清理后丢弃旧结果；免打扰/拉黑或未读为 0 时取消该会话通知。
- GET /unread 的 unread_count 现在只统计非免打扰会话，新增 total_unread_count 保留全部未读数。
- 单个免打扰会话显示无数字红点；底栏仅有免打扰未读时显示红点，存在正常未读时显示正常会话未读总数。
- 本次两项调整无需额外 SQL，仍要求之前 last_read_seq 迁移已经完成。后端新接口与统计代码需要由用户启用新版进程。
## 置顶与三个系统栏目（2026-09-28）

本轮需要新的数据库迁移及授权。以 [SYSTEM_INBOX_DEPLOY.md](SYSTEM_INBOX_DEPLOY.md) 的步骤为准，包含 pinned、新系统消息表、已读表、接口和验收。早期章节的“官方通知未实现”及只统计私信的说明已被该补充更新。
