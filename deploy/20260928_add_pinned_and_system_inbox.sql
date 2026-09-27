-- Run manually in the application database; prior DM migrations are required.
ALTER TABLE user_message_preferences ADD COLUMN pinned TINYINT NOT NULL DEFAULT 0;

CREATE TABLE system_messages (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  recipient_id INT NULL,
  category VARCHAR(20) NOT NULL,
  event_key VARCHAR(128) NOT NULL,
  title VARCHAR(255) NOT NULL,
  content TEXT NOT NULL,
  post_id INT NULL,
  comment_id INT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_system_event (event_key),
  KEY idx_system_recipient_category (recipient_id, category, id),
  CONSTRAINT fk_system_recipient FOREIGN KEY (recipient_id) REFERENCES users(user_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE system_message_reads (
  message_id INT UNSIGNED NOT NULL,
  user_id INT NOT NULL,
  read_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (message_id, user_id),
  KEY idx_system_reads_user (user_id, message_id),
  CONSTRAINT fk_system_read_message FOREIGN KEY (message_id) REFERENCES system_messages(id) ON DELETE RESTRICT,
  CONSTRAINT fk_system_read_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
