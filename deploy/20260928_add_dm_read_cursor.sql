-- Execute after user_message_preferences has been created.
ALTER TABLE user_message_preferences
  ADD COLUMN last_read_seq INT UNSIGNED NOT NULL DEFAULT 0;
-- Existing incoming messages become unread until the conversation is opened.