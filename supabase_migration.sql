-- =====================================================
-- Миграция для мессенджера Бубоглазики
-- Выполните в Supabase Dashboard → SQL Editor
-- =====================================================

-- 1. Добавляем deleted_for (массив UUID пользователей, у которых скрыто сообщение)
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS deleted_for text[] DEFAULT '{}';

-- 2. Добавляем reply_to_id (ссылка на сообщение, на которое отвечаем)
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS reply_to_id uuid REFERENCES messages(id) ON DELETE SET NULL;

-- Также нужен reply_to_content и reply_to_sender для отображения цитаты без доп. запросов
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS reply_to_content text;

ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS reply_to_sender_name text;

-- 3. Добавляем forwarded_from_name (имя отправителя оригинала при пересылке)
ALTER TABLE messages
  ADD COLUMN IF NOT EXISTS forwarded_from_name text;
