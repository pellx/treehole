# 举报与自动隐藏部署

## 已确定的规则

- 帖子和回复使用同一规则：3 个不同登录用户举报同一内容后自动隐藏。
- 以 users.user_id 区分用户；同账号换设备、重复点击、请求重试均只记一次。
- 前两次登记举报，第三次隐藏；结果不是人工认定违规。
- 帖子隐藏后，其回复也不对外展示，且不允许继续回复；单独隐藏回复不隐藏整篇帖子。
- 新增 posts.is_hidden、comments.is_hidden，0 表示显示、1 表示隐藏。原文保留在服务端数据库，不物理删除。
- 达到阈值后，三名举报者及可识别的作者收到“审核与举报”通知。匿名作者仍可通过内部 user_id 接收通知，但身份和举报者名单不向其他用户公开。
- 举报成功提示、重复提示及加载信息使用底部小提示。回复长按弹出复制、举报、收藏菜单，收藏仍为占位。

## 上线前由你执行的 SQL

助手没有连接 MySQL 或执行迁移，也没有重启后端。先备份数据库，完成此前私信和系统消息迁移，再使用管理账号连接应用 DB_NAME 对应的数据库：

    mysql -u 你的管理账号 -p 你的实际数据库名

检查：

    SELECT DATABASE();
    SHOW COLUMNS FROM posts LIKE 'is_hidden';
    SHOW COLUMNS FROM comments LIKE 'is_hidden';
    SHOW TABLES LIKE 'content_reports';
    SHOW TABLES LIKE 'system_messages';

两个字段和 content_reports 应尚不存在，system_messages 应已存在。满足条件后：

    SOURCE /var/www/treehole-nest/database/migrations/20260928_add_content_reports.sql;

脚本分别执行两条 ALTER TABLE 和一条 CREATE TABLE。MySQL DDL 不整体回滚；如果中途失败，检查已完成的部分，只补剩下的操作，不要直接重跑全部脚本。

运行账号授权（将“实际数据库名”替换成 DB_NAME，账号如已调整也相应替换）：

    GRANT SELECT, INSERT ON `实际数据库名`.`content_reports` TO 'submit-post'@'localhost';
    GRANT SELECT, UPDATE ON `实际数据库名`.`posts` TO 'submit-post'@'localhost';
    GRANT SELECT, UPDATE ON `实际数据库名`.`comments` TO 'submit-post'@'localhost';
    GRANT SELECT, INSERT, UPDATE ON `实际数据库名`.`system_messages` TO 'submit-post'@'localhost';

保留既有发帖/回复 INSERT 权限及其他业务权限。新增 system_messages.UPDATE 用于清除通知中已隐藏回复的正文快照。

检查：

    SHOW CREATE TABLE content_reports;
    SHOW COLUMNS FROM posts LIKE 'is_hidden';
    SHOW COLUMNS FROM comments LIKE 'is_hidden';

然后由你按现有部署方式启用已编译后端：

    cd /var/www/treehole-nest
    npm run build
    sudo -H -u www-data env PM2_HOME=/var/www/.pm2 pm2 restart treehole-nest
    sudo -H -u www-data env PM2_HOME=/var/www/.pm2 pm2 logs treehole-nest --lines 80 --nostream

这些命令供你阅读执行；助手不会执行重启命令。请确认实际 PM2 配置与上述一致。需重新编译安装 Flutter App；无新依赖或令牌配置。

远程修改前备份：/home/pell/reports-before-20260928.tar.gz。

## 接口

### POST /node/posts/reports

使用现有 SessionGuard 请求头 x-session-id、x-session-secret。用户 ID 从认证会话获取，不从请求正文获取。

    {"target_type":"post","target_id":123,"reason":"举报原因"}

target_type 支持 post / comment；reason 为去除首尾空白后的 1–500 字。返回：

    {"duplicate":false,"hidden":false,"post_id":123}

duplicate 表示此前已举报；hidden 表示当前内容已隐藏。不向用户返回其他举报人身份。对已隐藏内容再次请求返回隐藏状态，不追加举报。

锁定目标帖；回复举报还锁定回复。数据库唯一约束 (target_type,target_id,reporter_id) 去重。阈值、隐藏、通知写入在同一事务完成；实时提示只在提交后发送。回复创建也先锁帖子，防止隐藏提交后又插入回复。

### 公开读取与隐藏标记

- idList、idListv2、作者列表及搜索最终 MySQL 查询均过滤隐藏帖；搜索索引中即使还有旧 ID，也不返回隐藏正文。
- GET /node/posts/:id 和 /node/posts/v2/:id 对隐藏帖返回：

      {"id":123,"hidden":true}

- GET /node/posts/comment/:id 对隐藏回复或隐藏帖下面的回复返回：

      {"id":456,"post_id":123,"hidden":true}

- 正常单帖响应的 comments 只包含未隐藏回复 ID，hidden_comment_ids 提供隐藏回复 ID，便于刷新单帖时清缓存。
- idListUpdate 中隐藏项返回对应 ID 的隐藏标记，不返回原文。
- 已有“帖子回复”系统消息中的相关正文快照在隐藏事务中替换为“关联内容已隐藏，原文不再展示”。

### POST /node/posts/visibility

公开内容可见性批量查询；每种 ID 最多 200 个，不返回正文：

    {"post_ids":[123],"comment_ids":[456]}
    {"hidden_posts":[123],"hidden_comments":[456]}

App 更新列表时批量核对已缓存内容，避免“隐藏内容不在新列表里，所以旧正文一直留在缓存”的问题。

## 缓存行为与范围

- 收到明确隐藏标记后删除 Hive 帖子/回复、帖子对应回复和列表引用，并清理相关帖子缩略图、应用 PNG 缓存和回复草稿。
- 保存最小隐藏 ID 标记，防止晚到请求重新写入已隐藏内容；断网或 500 错误不会被当成隐藏。
- 当前可见卡片同步移除，回复长按菜单复用原有帖子操作菜单。
- App 处于离线时无法预知服务端刚发生的隐藏；再次联网刷新、搜索或读取单帖后同步处理。
- 本轮没有管理员恢复/申诉流程；恢复显示需要后续同时设计服务端恢复与客户端隐藏标记撤销，不能只手动把字段改成 0 就视作完整恢复。
- 隐藏限制的是业务内容 API 和 App 缓存；已被用户另存的文件、现有公共媒体 URL 不属于本次撤回范围。
- “三人”实现为三个不同账号，不能据此证明三个账号一定属于三个自然人；更复杂的反恶意举报策略留待管理员阶段。

## 验收

1. 三个账号 A/B/C 举报同一帖子：A、B 后仍显示，C 后隐藏；A 重复举报不计数。
2. 多设备使用 A 账号仍只算一次。并发举报时最多写入每账号一条，阈值只触发一次通知。
3. 对回复做同样操作：回复消失，父帖仍显示；隐藏父帖后所有回复 GET 也只返回隐藏标记。
4. 第四个客户端先缓存帖子/回复，再由其他账号触发隐藏。分别通过列表刷新、单帖刷新检查缓存和页面内容消失；重启 App 后不复活。
5. 保留一个延迟的旧 GET 响应，先处理隐藏标记，再让旧响应返回，验证不能写回或展示。
6. 原始 GET、v2 GET、作者列表、搜索和系统回复通知均不泄露隐藏正文或附件元数据。
7. 隐藏帖无法继续发布回复，举报结果通知可读并清除未读；未登录举报被拒绝。
8. 回复长按显示复制、举报、收藏；复制行为正确，收藏仍提示占位。

所有自动测试均不连接生产数据库；真实 SQL 迁移、三账号操作和 Android/iOS 真机验证由你启用后进行。


## 本轮验证记录

- 服务器 npm run build 通过；举报、读取隔离、回复事务及消息回归共 36 项无数据库测试通过。
- Flutter 举报缓存和菜单、API 契约及消息回归共 30 项测试通过。相关源码静态分析通过。
- 未执行数据库迁移、未重启进程，尚未进行生产三账号或 Android/iOS 真机验收。
