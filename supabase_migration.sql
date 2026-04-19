-- =====================================================
-- Миграция для мессенджера Бубоглазики
-- Выполните в Supabase Dashboard → SQL Editor
-- =====================================================

-- Таблица messages: нужные колонки (выполнялось ранее)
ALTER TABLE messages DROP COLUMN IF EXISTS reply_to_id;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS deleted_for text[] DEFAULT '{}';
ALTER TABLE messages ADD COLUMN IF NOT EXISTS reply_to_id bigint REFERENCES messages(id) ON DELETE SET NULL;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS reply_to_content text;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS reply_to_sender_name text;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS forwarded_from_name text;

-- Таблица profiles: добавляем поле bio (о себе / статус)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS bio text DEFAULT '';
