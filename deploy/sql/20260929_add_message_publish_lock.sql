-- Run manually with a database administrator in the configured DB_NAME.
-- Only adds the shared message publication lock and its singleton row.
CREATE TABLE IF NOT EXISTS message_publish_lock (
  id INT NOT NULL,
  PRIMARY KEY (id)
) ENGINE=InnoDB;

INSERT INTO message_publish_lock (id)
VALUES (1)
ON DUPLICATE KEY UPDATE id = 1;
