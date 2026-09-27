-- Execute manually after existing message/system inbox migrations.
ALTER TABLE posts ADD COLUMN is_hidden TINYINT(1) NOT NULL DEFAULT 0;
ALTER TABLE comments ADD COLUMN is_hidden TINYINT(1) NOT NULL DEFAULT 0;
CREATE TABLE content_reports (
 id INT NOT NULL AUTO_INCREMENT,
 target_type VARCHAR(10) NOT NULL,
 target_id INT NOT NULL,
 reporter_id INT NOT NULL,
 reason VARCHAR(500) NOT NULL,
 created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
 PRIMARY KEY(id),
 UNIQUE KEY uk_content_report(target_type,target_id,reporter_id),
 KEY idx_reporter(reporter_id),
 CONSTRAINT fk_reporter FOREIGN KEY(reporter_id) REFERENCES users(user_id) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
