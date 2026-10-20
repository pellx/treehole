-- 私信请求（陌生人先请求，对方接受后才能发送）
-- Run manually in the existing application database. MySQL DDL is not transactional.
-- 现有会话全部视为已接受，避免上线后老会话被锁死。
ALTER TABLE dm_conversations
  ADD COLUMN status ENUM('pending','accepted','rejected') NOT NULL DEFAULT 'accepted' AFTER last_seq,
  ADD COLUMN requested_by INT NULL AFTER status,
  ADD COLUMN requested_at DATETIME(3) NULL AFTER requested_by,
  ADD COLUMN accepted_at DATETIME(3) NULL AFTER requested_at,
  ADD COLUMN rejected_at DATETIME(3) NULL AFTER accepted_at,
  ADD KEY idx_dm_status (status);

-- 校验
SHOW COLUMNS FROM dm_conversations LIKE 'status';
SHOW COLUMNS FROM dm_conversations LIKE 'requested_by';
SELECT status, COUNT(*) FROM dm_conversations GROUP BY status;
