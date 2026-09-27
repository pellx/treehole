-- Manual migration only. Existing DM and system inbox tables are required.
CREATE TABLE dm_user_controls (
 user_id INT NOT NULL PRIMARY KEY,
 consecutive_failures INT NOT NULL DEFAULT 0,
 send_disabled TINYINT(1) NOT NULL DEFAULT 0,
 CONSTRAINT fk_dm_control_user FOREIGN KEY(user_id) REFERENCES users(user_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE dm_rejections (
 user_id INT NOT NULL,
 client_message_id CHAR(36) NOT NULL,
 content_hash CHAR(64) NOT NULL,
 reason VARCHAR(500) NOT NULL,
 created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
 PRIMARY KEY(user_id,client_message_id),
 KEY idx_dm_rejection_time(user_id,created_at),
 CONSTRAINT fk_dm_rejection_user FOREIGN KEY(user_id) REFERENCES users(user_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Serializes creation/commit of system messages and new conversations.
CREATE TABLE message_publish_lock (id INT NOT NULL PRIMARY KEY) ENGINE=InnoDB;
INSERT INTO message_publish_lock(id) VALUES (1);
