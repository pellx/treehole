-- Execute manually AFTER 20260928_add_dm_moderation.sql. Back up first.
-- No application process should write during migration. DDL is not atomic.
RENAME TABLE dm_user_controls TO user_controls,
             dm_rejections TO user_violation_history;
ALTER TABLE user_controls
 ADD COLUMN penalty_level INT NOT NULL DEFAULT 0,
 ADD COLUMN banned_at DATETIME(3) NULL,
 ADD COLUMN banned_until DATETIME(3) NULL,
 ADD COLUMN permanent TINYINT(1) NOT NULL DEFAULT 0;
-- Old disabled accounts begin the first 24-hour account ban at migration time.
UPDATE user_controls SET penalty_level=1, banned_at=CURRENT_TIMESTAMP(3),
 banned_until=DATE_ADD(CURRENT_TIMESTAMP(3), INTERVAL 1 DAY), consecutive_failures=0
 WHERE send_disabled=1;
ALTER TABLE user_controls DROP COLUMN send_disabled;
ALTER TABLE user_violation_history
 DROP PRIMARY KEY,
 ADD COLUMN id INT NOT NULL AUTO_INCREMENT PRIMARY KEY FIRST,
 CHANGE COLUMN client_message_id request_key VARCHAR(100) NOT NULL,
 ADD COLUMN source VARCHAR(32) NOT NULL DEFAULT 'dm_text',
 ADD COLUMN target_id INT NULL,
 ADD COLUMN reviewer_id INT NULL,
 ADD COLUMN penalty_level INT NOT NULL DEFAULT 0,
 ADD COLUMN banned_until DATETIME(3) NULL,
 ADD COLUMN permanent TINYINT(1) NOT NULL DEFAULT 0,
 DROP COLUMN content_hash,
 DROP INDEX idx_dm_rejection_time,
 ADD UNIQUE KEY uk_user_violation(user_id,source,request_key),
 ADD KEY idx_user_violation_time(user_id,created_at);
UPDATE user_violation_history SET reason='历史私信审核拒绝（旧记录未保存处罚快照）';
-- Snapshot fields on old rows are unknown/default; do not reconstruct them as new violations.
