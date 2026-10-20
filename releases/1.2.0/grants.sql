-- 1.2.0 数据库授权（私信 / 系统消息 / 举报 / 处罚 / 发布锁 / 版本）
-- 由有 GRANT 权限的管理员账号执行；应用账号为 'submit-post'@'localhost'。
-- 默认数据库名 treehole_post；若后端 DB_NAME 不同，请先整体替换再执行。
-- 执行前提：1.2.0 的全部迁移已按 deploy/MIGRATIONS_1.2.0.md 执行完毕，否则 GRANT 会报 1146 表不存在。
-- 执行后立即生效，无需重启后端。
--
-- 现状（2026-10-20 核对生产库 treehole_post）：
--   9 张新表均已存在，'submit-post'@'localhost' 已具备下列全部权限，本次发版无需执行本文件。
--   GRANT 语句幂等，重复执行也无副作用；保留本文件用于新环境或重建库。

-- 0) 先查看现状（只读，把结果发回即可确认是否已授权）
SHOW GRANTS FOR 'submit-post'@'localhost';

-- 1) 私信会话与消息
GRANT SELECT, INSERT, UPDATE ON treehole_post.dm_conversations TO 'submit-post'@'localhost';
GRANT SELECT, INSERT ON treehole_post.dm_messages TO 'submit-post'@'localhost';

-- 2) 会话偏好（置顶 / 免打扰 / 拉黑 / 已读游标）
GRANT SELECT, INSERT, UPDATE ON treehole_post.user_message_preferences TO 'submit-post'@'localhost';

-- 3) 系统消息与已读状态
GRANT SELECT, INSERT, UPDATE ON treehole_post.system_messages TO 'submit-post'@'localhost';
GRANT SELECT, INSERT ON treehole_post.system_message_reads TO 'submit-post'@'localhost';

-- 4) 举报与内容隐藏（posts / comments 只补 UPDATE，其余权限应已存在）
GRANT SELECT, INSERT ON treehole_post.content_reports TO 'submit-post'@'localhost';
GRANT SELECT, UPDATE ON treehole_post.posts TO 'submit-post'@'localhost';
GRANT SELECT, UPDATE ON treehole_post.comments TO 'submit-post'@'localhost';

-- 5) 账号处罚（generalize_user_safety 之后的表名）
GRANT SELECT, INSERT, UPDATE ON treehole_post.user_controls TO 'submit-post'@'localhost';
GRANT SELECT, INSERT ON treehole_post.user_violation_history TO 'submit-post'@'localhost';

-- 6) 消息发布串行锁
GRANT SELECT, UPDATE ON treehole_post.message_publish_lock TO 'submit-post'@'localhost';

-- 7) 版本表（客户端检查更新只读；写入仍由运维手工执行）
GRANT SELECT ON treehole_post.versions TO 'submit-post'@'localhost';

-- 8) 复核：以下查询应能正常返回，不再出现 command denied
SELECT COUNT(*) AS lock_rows FROM treehole_post.message_publish_lock;
SELECT COUNT(*) AS dm_conversations FROM treehole_post.dm_conversations;
SELECT COUNT(*) AS content_reports FROM treehole_post.content_reports;
