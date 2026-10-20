-- Run manually in the existing application database.
-- Prerequisites: users uses InnoDB and users.user_id is INT SIGNED.
-- Do not rerun blindly after a partial failure: MySQL DDL is not transactional.
CREATE TABLE dm_conversations (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_low_id INT NOT NULL,
  user_high_id INT NOT NULL,
  last_seq INT UNSIGNED NOT NULL DEFAULT 0,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  updated_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_dm_pair (user_low_id, user_high_id),
  KEY idx_dm_high_activity (user_high_id, updated_at, id),
  KEY idx_dm_low_activity (user_low_id, updated_at, id),
  CONSTRAINT fk_dm_low_user FOREIGN KEY (user_low_id)
    REFERENCES users (user_id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_dm_high_user FOREIGN KEY (user_high_id)
    REFERENCES users (user_id) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE dm_messages (
  id INT UNSIGNED NOT NULL AUTO_INCREMENT,
  conversation_id INT UNSIGNED NOT NULL,
  seq INT UNSIGNED NOT NULL,
  sender_id INT NOT NULL,
  client_message_id CHAR(36) NOT NULL,
  content TEXT NOT NULL,
  created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (id),
  UNIQUE KEY uk_dm_seq (conversation_id, seq),
  UNIQUE KEY uk_dm_client_message (sender_id, client_message_id),
  CONSTRAINT fk_dm_message_conversation FOREIGN KEY (conversation_id)
    REFERENCES dm_conversations (id) ON DELETE RESTRICT ON UPDATE RESTRICT,
  CONSTRAINT fk_dm_message_sender FOREIGN KEY (sender_id)
    REFERENCES users (user_id) ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
