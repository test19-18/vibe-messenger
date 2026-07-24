# Архитектура «Вайб», клиент 0.2

## 1. Слои

Приложение организовано по feature-first схеме.

- **Presentation** — Flutter widgets и локальное состояние форм.
- **Providers** — ручная Riverpod-композиция зависимостей и async state.
- **Services** — сценарии сообщений, typing, voice recording, local app lock и lifecycle presence.
- **Repositories** — изолированные вызовы Supabase Auth/PostgREST/Realtime/Storage/RPC и SharedPreferences.
- **Domain** — неизменяемые модели с defensive parsing, без codegen.
- **Core** — environment config, backend status, тема, router, общие состояния.

UI не знает о PostgREST-таблицах. Nullable `SupabaseClient` позволяет безопасно запустить сборку без environment-конфигурации.

## 2. Конфигурация и безопасность

`SUPABASE_URL` и `SUPABASE_ANON_KEY` читаются через `String.fromEnvironment`. Для автоматической тестовой сборки задан URL проекта и современный `sb_publishable_…` client key по умолчанию; оба значения являются публичной конфигурацией мобильного клиента. При необходимости их можно переопределить через `--dart-define`.

Publishable key безопасен только вместе с корректным RLS. Service-role key полностью обходит RLS, поэтому он запрещён в коде, CI artifact и mobile build.

`AppConfig.initializeBackend()` возвращает `ready`, `unconfigured` или `failed`; ошибка старта становится видимым banner/state, а не необработанным исключением.

## 3. Навигация и auth guard

`GoRouter` получает refresh-события из `AuthRepository.sessionChanges()`; `authSessionProvider` предоставляет ту же сессию остальному UI.

- Неавторизованный пользователь перенаправляется на `/login`.
- `/register` и `/reset-password` остаются публичными.
- После сессии пользователь попадает на исходный `from` или `/chats`.
- Главные четыре раздела находятся в `StatefulShellRoute.indexedStack`, поэтому их состояние сохраняется.
- `/conversation/:id`, `/group/:id`, `/groups/new`, `/group-access`, `/profile/qr` и detail routes настроек находятся над shell.
- Все новые функции достижимы из chat FAB, conversation menu, profile actions или settings hub; channel route/UI отсутствуют.

## 4. Контракт Supabase

Миграции поддерживаются отдельно от Flutter-клиента; этот этап их не изменяет. Код синхронизирован со следующим минимальным контрактом (snake_case).

### `profiles`

| Поле | Тип | Использование клиента |
|---|---|---|
| `id` | uuid PK/FK auth.users | текущий пользователь/контакт |
| `username` | text nullable/unique | публичный handle |
| `display_name` | text not null | отображаемое имя |
| `avatar_path` | text nullable | путь в приватном bucket `avatars`; UI получает signed URL |
| `bio` | text nullable | описание |
| `created_at`, `updated_at` | timestamptz | служебные даты |

Auth trigger создаёт профиль из `raw_user_meta_data.full_name`, поэтому sign-up передаёт именно `full_name`.

### `conversations` и `conversation_members`

| Таблица | Ключевые поля |
|---|---|
| `conversations` | `id`, `kind` (`direct/group/channel`), `title`, `avatar_path`, `created_by`, `last_message_at`, timestamps |
| `conversation_members` | `(conversation_id, user_id)` PK, `role`, `status`, `joined_at` |

Direct chat создаётся только атомарным idempotent RPC `create_direct_conversation(_other_user_id)`. Клиент не пытается самостоятельно вставлять пару membership rows.

### `messages`

| Поле | Тип |
|---|---|
| `id` | uuid PK, default gen_random_uuid() |
| `conversation_id` | uuid FK |
| `sender_id` | uuid nullable FK (может стать null после удаления профиля) |
| `kind` | `text/image/video/file/audio/voice/location/contact/poll/system` |
| `body` | text nullable |
| `metadata` | jsonb для location/contact/forward provenance и небольших payload |
| `client_nonce` | idempotency token клиента |
| `reply_to_message_id` | uuid nullable self-FK |
| `edited_at`, `deleted_at`, `deleted_by`, `created_at`, `updated_at` | timestamps/uuid |

Редактирование меняет только `body`; trigger выставляет `edited_at`. Soft-delete выставляет `deleted_at`; trigger очищает содержимое и записывает автора удаления. RLS допускает чтение/отправку только участникам, редактирование — автору (групповой admin может удалить).

### Read и typing state

| Таблица | Назначение |
|---|---|
| `conversation_read_receipts` | `(conversation_id, user_id)`, `last_read_message_id`, `last_read_at` |
| `conversation_typing` | `(conversation_id, user_id)`, `is_typing`, `expires_at` |
| `user_presence` | `user_id`, `last_seen_at`, `online_until`; читается вложенно из `profiles` |

Из-за column-level grants клиент сначала обновляет разрешённые state-поля, а при отсутствии строки делает insert; typing=false удаляет собственную строку. `expires_at` ограничивает зависший typing state. `PresenceHeartbeat` пишет best-effort heartbeat раз в минуту и обновляет offline state по lifecycle; visibility всё равно определяется `user_settings` и RLS.

## 5. Realtime

- Сообщения: `stream(primaryKey: ['id'])`, фильтр по `conversation_id`, дополнительная сортировка на клиенте.
- Typing: realtime stream таблицы `conversation_typing`; UI делает debounce, backend ограничивает TTL, локальный таймер скрывает просроченные строки.
- Read state: monotonic `last_read_message_id` + timestamp upsert при открытии/получении сообщений.
- Reactions, pins, read receipts, polls и presence читаются через опубликованные таблицы; attachments/polls дополнительно получают signed/RPC данные.
- `message_reactions` не содержит `conversation_id`, поэтому realtime stream проходит RLS и затем фильтруется клиентом по UUID сообщения.

Для production дополнительно нужны retry/backoff, cursor pagination и серверная агрегация unread count.

## 6. Состояния и ошибки

`AsyncStateView` унифицирует progress/empty/error/content. Ошибки Auth переводятся в русские сообщения; transport/schema/RLS errors показываются пользователю без раскрытия секретов. Unconfigured backend отображается через `BackendStatusBanner`.

## 7. Известные границы клиента 0.2

- Нет локальной БД/offline queue и cursor pagination; message stream загружает доступный realtime snapshot.
- Unread вычисляется клиентом максимум по 500 загруженным сообщениям; для production нужен view/RPC.
- Signed URLs живут один час; долгоживущие media screens должны обновлять capability URL после expiry.
- Media upload выполняет Storage → message → attachment с cleanup/soft-delete на ошибке, но DB и Storage не имеют общей транзакции; orphan cleanup остаётся эксплуатационной задачей.
- Forward media/poll требует copy RPC/storage policy и намеренно отклоняется, text/location/contact пересылаются новым message с provenance metadata.
- Scheduled/auto-delete backend отсутствует: UI показывает local placeholder без fake success.
- Member tags — явно local-only SharedPreferences, потому что schema не содержит поля.
- RU/EN покрывает основную навигацию и новые экраны; legacy auth/profile copy преимущественно RU.
- Push delivery/FCM token acquisition ожидают Firebase SDK; service-role и Firebase config в код не добавлены.
- Поля и RLS должны оставаться синхронизированы с миграцией; отсутствующая таблица даст управляемый error state, но не данные.

## 8. CI

Workflow ставит Flutter 3.44.8 из stable-канала, согласованный с `pubspec.lock`. Если `android/` отсутствует, он вызывает `flutter create` во временной директории и копирует только Android platform, чтобы не перезаписать исходники. Затем выполняются format check, analyze, tests и debug APK build. Сборка использует только публичные Supabase URL/publishable key, публикует APK как Actions artifact и обновляет prerelease `latest-debug`; секретных backend-ключей в workflow нет.

## 9. Новые feature-модули

### Chat organization

`ConversationRepository` объединяет membership, conversation, latest messages, receipts, personal settings и folder mapping. `filteredConversationsProvider` применяет all/unread/direct/group/archive/folder filters. Channel rows исключаются до построения UI.

### Media

`MessageRepository.uploadAttachment` проверяет kind/size, формирует разрешённый path `<conversation>/<uploader>/<file>`, загружает объект в private bucket и только затем создаёт message/attachment metadata. На ошибке message soft-delete и Storage remove выполняются best effort. Документ скачивается только через authenticated Storage download, изображение/voice получают короткий signed URL.

### Groups/polls

Group creation, ownership, invite tokens, invitation acceptance, join review и poll creation вызывают только audited RPC. Обычные role/status updates идут через RLS-protected tables. `GroupDetails.fromMap` отвергает `channel`, чтобы reserved enum не превратился в неутверждённый UI.

### Local settings/security

`AppPreferences` разделяет canonical backend columns и дополнительные значения внутри `user_settings.settings`; SharedPreferences даёт local-first запуск. PIN хранится как salted SHA-256 hash, а не plaintext, но SharedPreferences не является hardware-backed keystore. `local_auth`, microphone recorder и file intents требуют нативной platform/device проверки.

Точная продуктовая матрица: [`FEATURE_STATUS.md`](FEATURE_STATUS.md).
