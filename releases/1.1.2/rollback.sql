-- 仅可在执行 apply 的同一个 MySQL 连接、且已经 COMMIT 后使用。
-- 若 apply 尚未 COMMIT，直接 ROLLBACK; 即可。
-- 先确认临时备份仍存在且 captured=1；断线后禁止继续，使用持久备份恢复。
SELECT COUNT(*) AS captured FROM release_112_capture;
SELECT * FROM release_112_backup;
START TRANSACTION;
DELETE FROM versions WHERE version_number='1.1.2' AND platform='android' AND EXISTS (SELECT 1 FROM release_112_capture);
INSERT INTO versions SELECT * FROM release_112_backup;
SELECT id,version_number FROM versions WHERE platform='android' ORDER BY id DESC LIMIT 1;
-- 检查后手动 COMMIT; 或 ROLLBACK;
