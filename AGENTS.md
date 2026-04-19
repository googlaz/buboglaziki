# Buboglaziki — Project Rules for AI Agents

## Стек проекта
- **Платформа:** Flutter (Dart), Android
- **Backend:** Supabase (PostgreSQL + realtime + storage)
- **Push:** Firebase Cloud Messaging
- **Звонки:** Jitsi Meet через WebView

## КРИТИЧЕСКИ ВАЖНО

1. **Это Flutter-проект, НЕ React/Vue/Node.js.** Весь UI пишется в Dart-виджетах в папке `lib/`.
2. **Нет XML, HTML, JSX, CSS.** Только Dart-код.
3. **Никогда не давай примеры на других стеках** (React, Vue, Node, Express). Только Flutter/Dart.

## Структура проекта

```
lib/
├── main.dart                       — точка входа
├── theme/app_theme.dart            — цвета и темы
├── screens/
│   ├── chat_screen.dart            — экран чата (пузыри сообщений уже в Telegram-стиле)
│   ├── chat_list_screen.dart       — список чатов
│   ├── call_screen.dart            — активный звонок
│   ├── incoming_call_screen.dart   — входящий звонок
│   ├── outgoing_call_screen.dart   — исходящий звонок
│   ├── login_code_screen.dart      — вход по коду
│   └── profile_selection_screen.dart — выбор профиля
└── services/
    ├── fcm_sender.dart             — отправка push-уведомлений
    ├── fcm_service.dart            — приём push-уведомлений
    └── jitsi_service.dart          — генерация Jitsi-ссылок
```

## Supabase — структура БД

```
profiles
├── id (int, PK)
├── display_name (text)
├── avatar_url (text)
└── fcm_token (text)

messages
├── id (int, PK)
├── chat_id (text)
├── sender_id (int)  ← ВАЖНО: int, не string!
├── content (text)
├── image_url (text)
└── created_at (timestamptz)

calls
├── id (int, PK)
├── caller_id (int)
├── receiver_id (int)
└── status (text: 'ringing' | 'accepted' | 'rejected' | 'ended')
```

## Правила работы с временем

- В БД `created_at` хранится в UTC (Supabase по умолчанию)
- При отображении в UI использовать `.toLocal()` — это автоматически даст время пользователя
- Сейчас в `chat_screen.dart:307` уже есть `DateTime.parse(...).toLocal()` — это правильно

## Правила работы с sender_id

- В БД `sender_id` — это `int`
- В UI `currentUserId` — это `String`
- **Всегда приводить оба к одному типу перед сравнением:**
  ```dart
  final senderId = (msg['sender_id'] ?? '').toString();
  final isMe = senderId == widget.currentUserId;
  ```

## Что уже реализовано

- ✅ Telegram-стиль пузырей сообщений (мои справа/зелёные, чужие слева/белые)
- ✅ Имена отправителей в групповом чате (`_senderNames` cache в `chat_screen.dart`)
- ✅ Время внутри пузыря, не перекрывает текст
- ✅ Галочки прочтения для моих сообщений
- ✅ Голосовые/видео-звонки через Jitsi
- ✅ Push-уведомления через FCM
- ✅ Группа "Вся семья" + личные чаты

## Что ещё нужно сделать (из задач пользователя)

1. **Долгое нажатие на сообщение** → контекстное меню (Ответить / Переслать / Удалить)
2. **Удалить** → диалог "Удалить у меня" или "Удалить у всех"
3. **Для этого в Supabase нужна миграция:**
   ```sql
   ALTER TABLE messages ADD COLUMN deleted_for jsonb DEFAULT '[]'::jsonb;
   -- массив user_id, которые удалили сообщение у себя
   -- если пусто — сообщение видно всем
   -- если удалено у всех — запись удаляется полностью из БД
   ```

## Как запускать изменения

- Сборка APK — через GitHub Actions (`.github/workflows/`)
- Локально Flutter не установлен — **не пытайся запускать `flutter build`**
- После изменений: `git add`, `git commit`, `git push` — CI сам соберёт APK

## Стиль кода

- Отступы: 2 пробела
- Константы цветов — в `lib/theme/app_theme.dart`
- Тексты UI — на русском
- Имена переменных — на английском
- Никаких emoji в коде, только в UI-строках (если нужно)
