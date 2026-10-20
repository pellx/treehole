# 1.2.0 数据库迁移清单

本版本自 1.1.2 起新增 10 条迁移，SQL 全部镜像在本目录，与后端仓库 `database/migrations/` 同名。
MySQL 的 DDL 不能回滚，执行前先做持久备份；整个迁移过程保持单一操作者并停止写入。

## 执行顺序

按依赖排序，已执行过的条目跳过；每条执行完先用下方语句校验，再进入下一条。

| 顺序 | 文件 | 作用 | 依赖 |
| --- | --- | --- | --- |
| 1 | `20260927_add_user_avatar.sql` | `users` 增加 `avatar_filename`，保存审核通过的头像文件名 | 无 |
| 2 | `20260928_create_dm_tables.sql` | 新建 `dm_conversations`、`dm_messages`，私信会话与消息主体 | 无 |
| 3 | `20260928_create_message_preferences.sql` | 新建 `user_message_preferences`，会话置顶、免打扰等偏好 | 无 |
| 4 | `20260928_add_dm_read_cursor.sql` | 为消息偏好表补充已读游标字段 | 必须先执行 3 |
| 5 | `20260928_add_pinned_and_system_inbox.sql` | 偏好表增加 `pinned`，新建 `system_messages`、`system_message_reads` | 必须先执行 3 |
| 6 | `20260928_add_content_reports.sql` | `posts`、`comments` 增加 `is_hidden`，新建 `content_reports` | 无 |
| 7 | `20260928_add_dm_moderation.sql` | 新建 `dm_user_controls`、`dm_rejections`、`message_publish_lock` | 无 |
| 8 | `20260928_generalize_user_safety.sql` | 将 7 的两张表重命名为 `user_controls`、`user_violation_history` 并扩展处罚字段 | 必须在 7 之后 |
| 9 | `20260929_add_message_publish_lock.sql` | 以 `IF NOT EXISTS` 和 `ON DUPLICATE KEY UPDATE` 补建发布锁表，可重复执行 | 建议最后执行，可与 7 共存 |
| 10 | `20261020_add_dm_conversation_requests.sql` | `dm_conversations` 增加 `status`/`requested_by`/`requested_at`/`accepted_at`/`rejected_at`，支持陌生人私信先请求后接受 | 必须先执行 2（会话表存在） |

## 执行后校验

```sql
SHOW COLUMNS FROM users LIKE 'avatar_filename';
SHOW TABLES LIKE 'dm_conversations';
SHOW TABLES LIKE 'dm_messages';
SHOW COLUMNS FROM user_message_preferences LIKE 'pinned';
SHOW COLUMNS FROM posts LIKE 'is_hidden';
SHOW COLUMNS FROM comments LIKE 'is_hidden';
SHOW TABLES LIKE 'content_reports';
SHOW COLUMNS FROM user_controls LIKE 'penalty_level';
SHOW COLUMNS FROM user_violation_history LIKE 'source';
SELECT COUNT(*) FROM message_publish_lock;  -- 期望 1
SHOW COLUMNS FROM dm_conversations LIKE 'status';
SELECT status, COUNT(*) FROM dm_conversations GROUP BY status;  -- 老会话应为 accepted
```

## 授权

迁移只改表结构，不会自动给应用账号加权限。第 8 条 `RENAME TABLE` 之后旧授权也会失效，因此必须单独补授权：

1. 用有 GRANT 权限的账号执行 `releases/1.2.0/grants.sql`（默认数据库名 `treehole_post`，账号 `submit-post`@`localhost`；DB_NAME 不同就先整体替换）。
2. 执行后复核，应能看到各新表权限且不再出现 `command denied`：

```sql
SHOW GRANTS FOR 'submit-post'@'localhost';
```

3. 权限只在授权语句执行失败时才需要排查（常见原因：表不存在，说明对应迁移没跑）。

> 现状（2026-10-20 核对生产库）：9 张新表均已存在，`submit-post`@`localhost` 已具备所需权限，本次发版无需执行授权。第 10 条新增的 5 列**尚未执行**（生产库仍是请求功能上线前的结构），发版前必须补跑。
> 本步骤保留给新环境或重建库。

## 已知约束

- 第 8 条使用 `RENAME TABLE`，MySQL 的表级授权不会随表名迁移；执行后需要重新确认后端账号对新表名的权限，备份脚本里的旧表名也要同步修改。
- 第 7 条直接 `CREATE TABLE message_publish_lock`，如果该表已由第 9 条或其他途径建好，会报“表已存在”。遇到这种情况跳过第 7 条的建表与插入语句即可，其余语句不受影响。
- 第 8 条会把迁移时仍处于 `send_disabled=1` 的账号转成 24 小时封禁（`penalty_level=1`），随后删除 `send_disabled` 列；历史违规记录只改写说明文字，不重建处罚快照。
- 迁移只改结构，不删除帖文、评论和私信内容；但第 8 条之前的备份请保留到验证完成。
- 私信、系统消息、举报、头像相关接口依赖上述表和列，迁移完成并重启后端进程后才可用。
- 第 10 条把 `status` 默认值设为 `accepted`：升级前已有的会话不受影响；只有上线后新建的会话才是 `pending`。
- 第 10 条与客户端 1.2.0 及以后版本配套：旧客户端没有同意/拒绝入口，若服务端先上线，旧客户端新发起的会话会停在 `pending` 且无法接受，因此建议服务端与客户端**同批发版**。

## 关联文档

- 私信与消息表：`DM_DEPLOY.md`
- 审核拒绝与封禁：`MESSAGE_CACHE_MODERATION_DEPLOY.md`、`CONTENT_SAFETY_DEPLOY.md`
- 读游标与已读全部：`MESSAGE_READ_ALL_DEPLOY.md`
- 置顶与系统消息：`SYSTEM_INBOX_DEPLOY.md`
- 举报与隐藏：`REPORTS_DEPLOY.md`
- 头像：`AVATAR_DEPLOY.md`
- 发布锁：`MESSAGE_PUBLISH_LOCK_FIX.md`
