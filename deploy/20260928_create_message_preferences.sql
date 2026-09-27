-- Execute manually after the two DM tables exist. users.user_id must be INT SIGNED.
CREATE TABLE user_message_preferences (
  user_id INT NOT NULL,
  peer_user_id INT NOT NULL,
  muted TINYINT NOT NULL DEFAULT 0,
  blocked TINYINT NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, peer_user_id),
  CONSTRAINT fk_message_preferences_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE RESTRICT,
  CONSTRAINT fk_message_preferences_peer FOREIGN KEY (peer_user_id) REFERENCES users(user_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
