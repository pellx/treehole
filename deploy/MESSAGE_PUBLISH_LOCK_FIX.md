# 补齐消息写入锁表（2026-09-29）

## 原因与范围

当前消息功能需要 message_publish_lock，用户提供的 treehole_post 表列表缺少它。该表只有 id=1 的一行，用于在事务中串行创建系统消息和新私信会话，避免增量同步漏掉晚提交的旧编号记录。

直接引用位于后端 src/system-inbox/system-inbox.store.ts 的 write() 和 src/messages/dm.service.ts 的 create()。回复其他用户的帖子时，写入“帖子回复”通知也会经过 write()；锁表缺失或权限不足会使回复事务回滚。

这是补充迁移，仅增加锁表和固定锁行。已有 user_controls、user_violation_history 等表沿用当前结构。视频功能继续保存在 codex/video-player-paused 分支。

## 手动执行

助手没有执行数据库命令或重启服务。由数据库管理账号执行以下操作。

1. 核对后端配置的 DB_NAME 确实为 treehole_post；若不同，替换下列数据库名。
2. 进入 MySQL 管理会话，执行：

~~~sql
USE treehole_post;

SOURCE /var/www/treehole-nest/database/migrations/20260929_add_message_publish_lock.sql;

GRANT SELECT, UPDATE
ON treehole_post.message_publish_lock
TO 'submit-post'@'localhost';

SHOW CREATE TABLE treehole_post.message_publish_lock;
SELECT id FROM treehole_post.message_publish_lock;
SHOW GRANTS FOR 'submit-post'@'localhost';
~~~

锁表应为 InnoDB、id 为主键，查询结果应有 id=1。不要清空或删除此行。脚本可重复执行；已有表的结构仍需用 SHOW CREATE TABLE 核对。

前端仓库中同一 SQL 位于 deploy/sql/20260929_add_message_publish_lock.sql。此脚本没有账号密码，也不需要重新执行旧的私信建表或更名迁移。

3. 授权后在 App 重新发送回复，确认成功且帖主收到“帖子回复”通知。如仍失败，保留具体错误提示和发送时间用于核对日志。

## 视频暂停与部署

本次将服务器遗留视频源代码保存到后端 codex/video-player-paused 分支，并返回 master。主分支源码不引入 VideosModule。

Git 分支切换不会停止正在运行的进程，也不会自动替换旧 dist。本次不执行服务重启。若运行服务仍使用包含视频模块的旧构建，后续由你按原部署流程安装依赖、构建主分支并重启；暂停视频期间不需要新建 videos 或 video_danmaku 表。
