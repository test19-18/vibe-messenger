# Вайб

Flutter-мессенджер с Supabase backend и отдельным визуальным языком: почти чёрный фон, графитовые поверхности и электрик-синий акцент. Текущий клиент рассчитан на Flutter **3.44.8 / Dart 3.12**, Riverpod 2.6.1, go_router 14.8.1 и supabase_flutter 2.16.0, использует ручные mapper-модели и не требует codegen.

> Клиент синхронизирован с `supabase/migrations/202607240001_initial_schema.sql` и расширением `202607240002_product_extensions.sql`; SQL в этой итерации не менялся. Он использует только public URL и publishable key. **Service-role key запрещён в mobile build.**

## Реализовано в клиенте

- email sign-up/sign-in/reset, реактивный auth guard и безопасный unconfigured-backend режим;
- профиль: имя, username, bio, upload аватара в приватный `avatars`, signed URL и QR-ссылка;
- каталог пользователей, заявки контактов, accept/decline/cancel/remove, block/unblock и жалобы;
- lifecycle presence heartbeat, typing TTL, настройки видимости last seen/typing/read receipts;
- direct chat через идемпотентный RPC;
- список чатов: unread, pin, mute, archive, draft, папки и фильтры; channel rows намеренно скрыты;
- сообщения: reply, edit, глобальный soft-delete, delete-only-for-self через `message_user_deletions`, reactions, read markers, search, selection, copy и пересылка text/location/contact;
- hidden/expired messages фильтруются в realtime-ленте клиента; для `expires_at` показывается срок действия;
- отложенные text-сообщения: date/time picker, `silent`, realtime list и cancel через `create_scheduled_message` / `cancel_scheduled_message`;
- простое форматирование `**bold**`, `_italic_`, `` `code` ``;
- изображения/документы/аудио через приватные `chat-media`, voice через `voice-messages`, signed preview/download;
- location/contact JSON payloads, запись `record` и воспроизведение `just_audio`;
- groups: create/edit/avatar, owner/admin/member, moderation, targeted/link invites, join requests, ownership transfer;
- личные member tags синхронизируются сервером через `conversation_member_tags` и видны только создавшему их участнику;
- per-chat `auto_delete_seconds` и `protected_content` доступны в меню беседы; новые сообщения получают server-derived `expires_at`;
- polls: create RPC, vote/unvote и агрегированные результаты RPC;
- настройки: system/light/dark, RU/EN для основной навигации и новых экранов, text scale, animations/power-saving;
- локальный PIN hash и biometric gate через `shared_preferences` + `local_auth`;
- `user_devices` repository/UI и notification preferences;
- FCM push-уведомления: safe Firebase init (pending state без `google-services.json`), FCM token registration в `call_devices` через `register_call_device` RPC, foreground handling через `flutter_local_notifications` с отдельными каналами для сообщений и входящих звонков, background handler top-level без UI доступа, push→router и push→call event bus.

Полная честная матрица статусов и ограничений: [`docs/FEATURE_STATUS.md`](docs/FEATURE_STATUS.md).

## Локальный запуск

Android-папка может отсутствовать. Создайте platform template отдельно, чтобы не перезаписать исходники:

```bash
flutter create --platforms=android --org=ru.vibe \
  --project-name=vibe_messenger /tmp/vibe_flutter_platform
cp -R /tmp/vibe_flutter_platform/android ./android
python3 tool/configure_android.py .
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_PUBLIC_PUBLISHABLE_KEY
```

Без `--dart-define` приложение подключается к выделенному тестовому Supabase-проекту через встроенные публичные client-параметры. Для другой среды URL и publishable key переопределяются через `--dart-define`; fake-success и service-role ключи не используются.

### Нативная настройка Android

`tool/configure_android.py` добавляет `RECORD_AUDIO`/`USE_BIOMETRIC`, переводит `MainActivity` на `FlutterFragmentActivity`, настраивает AppCompat launch theme, регистрирует схему ссылок `vibe://` и создаёт native MethodChannel `vibe/screen_protection`. Обработчик включает или снимает Android `FLAG_SECURE`, поэтому защищённые чаты блокируют активные системные screenshots; Dart lifecycle-cover остаётся дополнительной защитой. На реальном Android-устройстве всё равно проверяются runtime permissions, biometric dialog, voice codec и `open_filex` intents.

### Email confirmation и password recovery

Мобильный callback URL: `ru.vibe.messenger://auth/callback`. Он передаётся в sign-up, повторную отправку confirmation email и password reset. В Supabase Dashboard необходимо добавить этот URI в **Authentication → URL Configuration → Additional Redirect URLs**. Если письмо по-прежнему ведёт на localhost, запросите новое письмо из актуального APK: старые ссылки не меняются.

### Firebase Cloud Messaging (push-уведомления)

Android-конфигурация Firebase (`google-services.json`) — gitignored, предоставляется как build secret. Без неё приложение запускается в безопасном Firebase-pending режиме: UI показывает честный статус, push не работает, crash-нет. Полная инструкция по server-side FCM credentials: [`FIREBASE_SETUP.md`](FIREBASE_SETUP.md).

Клиент не содержит service-account credentials. Service account JSON добавляется **только** как Supabase Edge Function secret `FIREBASE_SERVICE_ACCOUNT_JSON` и никогда не коммитится.

## Проверки

```bash
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub --fatal-infos --fatal-warnings
flutter test --no-pub
flutter build apk --debug --no-pub
```

Workflow `.github/workflows/android.yml` закреплён на Flutter 3.44.8, при необходимости создаёт Android template, выполняет format/analyze/test/build, публикует debug APK с SHA-256 как Actions artifact и обновляет публичный prerelease `latest-debug`.

## Supabase contract

Клиент использует audited schema из [`docs/DATABASE.md`](docs/DATABASE.md):

- identity/social: `profiles`, `contacts`, `user_blocks`, `reports`, `user_presence`, `user_settings`, `user_devices`;
- chats: `conversations`, `conversation_members`, `conversation_user_settings` (`auto_delete_seconds`, `protected_content`), `chat_folders`, `chat_folder_conversations`;
- messaging: `messages` (`expires_at`), `message_user_deletions`, `scheduled_messages`, `message_attachments`, `message_reactions`, `conversation_read_receipts`, `conversation_typing`, `message_pins`;
- groups: `group_invitations`, `group_join_requests`, `conversation_member_tags` и group RPC;
- scheduled/expiry RPC: `create_scheduled_message`, `cancel_scheduled_message`; Supabase Cron ежеминутно доставляет scheduled messages и каждые 5 минут очищает истёкшие сообщения;
- polls: `polls`, `poll_options`, `poll_votes`, `create_poll`, `get_poll_results`;
- private buckets: `avatars`, `chat-media`, `voice-messages`.

Клиент не создаёт channels и не содержит UI публичной ленты. Контур личных 1:1 audio/video calls добавлен в исходный код, но требует применения `202607240004_calls.sql` и развёртывания Edge Functions до реального соединения. Group calls, screen share, E2EE, stories, bots, AI, payments и другие исключённые продуктовые области отсутствуют.

## Структура

```text
lib/
  core/                 # public config, router, localization helper, theme/widgets
  features/
    auth/               # Supabase Auth
    profile/            # profile edit/avatar/QR
    contacts/           # directory, requests, block/report
    chats/              # chat list, settings, folders, filters
    chat/               # realtime messages/media/voice/polls
    groups/             # roles, members, invites, requests, moderation
    security/           # local PIN/biometric gate
    settings/           # preferences, presence, devices, detail screens
    notifications/      # FCM push: services, repository, providers, payload parsing
```

Архитектура: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). Правила изменений: [`CONTRIBUTING.md`](CONTRIBUTING.md). Firebase server-side FCM setup: [`FIREBASE_SETUP.md`](FIREBASE_SETUP.md).
