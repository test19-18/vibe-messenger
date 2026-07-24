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

Миграции поддерживаются отдельно от Flutter-клиента; этот этап их не изменяет. Код синхронизирован с initial schema и `202607240002_product_extensions.sql` (snake_case).

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
| `expires_at` | timestamptz nullable, server-derived из sender `auto_delete_seconds` |
| `edited_at`, `deleted_at`, `deleted_by`, `created_at`, `updated_at` | timestamps/uuid |

Редактирование меняет только `body`; trigger выставляет `edited_at`. Soft-delete выставляет `deleted_at`; trigger очищает содержимое и записывает автора удаления. RLS допускает чтение/отправку только участникам, редактирование — автору (групповой admin может удалить).

### Product extensions

| Контракт | Использование клиента |
|---|---|
| `message_user_deletions` | insert delete-only-for-self; отдельный realtime stream hidden IDs объединяется с message stream до выдачи UI |
| `conversation_member_tags` | личные метки участников; list/update-or-insert/delete под self-only RLS, без SharedPreferences |
| `scheduled_messages` | realtime list по беседе; создание только через `create_scheduled_message`, отмена через `cancel_scheduled_message` |
| `conversation_user_settings.auto_delete_seconds` | nullable 1…31536000; влияет только на новые сообщения отправителя, `expires_at` задаёт trigger |
| `conversation_user_settings.protected_content` | per-user настройка UI/platform screen protection |

`ScheduledMessage` и `ConversationUserSettings` — defensive pure-Dart domain models. Клиент не вызывает service-role delivery/cleanup RPC: `process_due_scheduled_messages` и `cleanup_expired_messages` принадлежат trusted scheduler/pg_cron.

### Read и typing state

| Таблица | Назначение |
|---|---|
| `conversation_read_receipts` | `(conversation_id, user_id)`, `last_read_message_id`, `last_read_at` |
| `conversation_typing` | `(conversation_id, user_id)`, `is_typing`, `expires_at` |
| `user_presence` | `user_id`, `last_seen_at`, `online_until`; читается вложенно из `profiles` |

Из-за column-level grants клиент сначала обновляет разрешённые state-поля, а при отсутствии строки делает insert; typing=false удаляет собственную строку. `expires_at` ограничивает зависший typing state. `PresenceHeartbeat` пишет best-effort heartbeat раз в минуту и обновляет offline state по lifecycle; visibility всё равно определяется `user_settings` и RLS.

## 5. Realtime

- Сообщения: stream `messages` объединяется со stream `message_user_deletions` по `conversation_id`; UI получает только rows без hidden ID и с будущим/null `expires_at`. До первого snapshot обоих streams список не выдаётся, чтобы скрытая row не мелькнула. Timer переэмитит список в момент ближайшего expiry.
- Typing: realtime stream таблицы `conversation_typing`; UI делает debounce, backend ограничивает TTL, локальный таймер скрывает просроченные строки.
- Read state: monotonic `last_read_message_id` + timestamp upsert при открытии/получении сообщений.
- Reactions, pins, read receipts, polls, scheduled messages, member tags, per-chat settings и presence читаются через опубликованные таблицы; attachments/polls дополнительно получают signed/RPC данные.
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
- Scheduled delivery выполняют два активных Supabase Cron job: due messages каждую минуту и cleanup истёкших сообщений каждые 5 минут. Мобильный клиент не получает service-role.
- Auto-delete server-authoritative для новых сообщений отправителя; клиентский timer своевременно скрывает уже полученный `expires_at`, а Cron выполняет backend cleanup.
- `protected_content` вызывает `ScreenProtectionApi` через channel `vibe/screen_protection`. CI-скрипт генерирует Android handler с `WindowManager.LayoutParams.FLAG_SECURE`; Dart lifecycle-cover остаётся дополнительным fallback.
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

Group creation, ownership, invite tokens, invitation acceptance, join review и poll creation вызывают только audited RPC. Обычные role/status updates идут через RLS-protected tables. Личные member tags загружаются из `conversation_member_tags` вместе со списком участников и после mutation инвалидируют provider. `GroupDetails.fromMap` отвергает `channel`, чтобы reserved enum не превратился в неутверждённый UI.

### Local settings/security

`AppPreferences` разделяет canonical backend columns и дополнительные значения внутри `user_settings.settings`; SharedPreferences даёт local-first запуск только глобальным app preferences/PIN, но не member tags. PIN хранится как salted SHA-256 hash, а не plaintext, но SharedPreferences не является hardware-backed keystore. `local_auth`, microphone recorder и file intents требуют нативной platform/device проверки.

`ScreenProtectionService` зависит от абстракции `ScreenProtectionApi`. После `flutter create` скрипт `tool/configure_android.py` переписывает Kotlin `MainActivity`, регистрирует `MethodChannel("vibe/screen_protection")`, обрабатывает `setProtectedContent(enabled)` и add/clear `WindowManager.LayoutParams.FLAG_SECURE`. Он также добавляет `vibe://` intent-filter; lifecycle privacy cover остаётся дополнительной защитой.

### Calls (1:1 audio/video)

Контур личных звонков построен на LiveKit Flutter client 2.8.1 и Supabase Edge Functions. Клиент никогда не содержит LiveKit API secret — токен выдаётся сервером per-call через Edge Function и short-lived. Подключение к комнате происходит только после получения серверного токена (`CallSession.canConnectRoom`).

**Слои:**
- **Domain:** `CallStatus` (enum с wire values), `CallType`, `CallSession`, `CallRecord`, `CallSessionTransition` (pure state machine с validated transitions). Все модели immutable с defensive parsing, без codegen.
- **Data:** `CallRepository` — Supabase Edge Functions (`create-call`, `issue-livekit-token`, `call-action`), `calls` table reads/streams. Token выдаётся только через `issue-livekit-token`, не хранится в БД и не логируется. Realtime subscription на incoming calls (`callee_id = me`, `state = ringing/created`). DB columns `state`/`media_kind` маппятся в UI `CallStatus`/`CallType` defensively.
- **Services:** `CallRoomService` — LiveKit `Room` lifecycle, `LocalParticipant` track control (mute/camera/switch), `AudioManager` speaker routing, `VideoTrack` retrieval для rendering. `TelecomApi` — абстракция native Core-Telecom (`MethodChannel("vibe/telecom")`), `isAvailable` возвращает false до native реализации.
- **Providers:** `activeCallProvider` (StateNotifier, single active call), `callInitiationProvider`, `incomingCallActionProvider`, `callHistoryProvider`, `incomingCallsProvider`/`latestIncomingCallProvider` (realtime watcher).
- **Presentation:** `CallScreen` (full-screen active call с audio/video layout, `VideoTrackRenderer`), `IncomingCallOverlay` (foreground incoming call с accept/decline), `CallHistoryScreen`.

**State machine:** `idle → ringingOutgoing/ringingIncoming → connecting → accepted → completed`. Terminal states: `completed`, `missed`, `declined`, `cancelled`, `busy`, `failed`. `accepted → reconnecting → accepted` для временной потери связи. Все transitions валидируются через `CallSessionTransition.canTransition`.

**UI reachability:** Кнопки audio/video call в `AppBar` conversation screen (только для direct chats, не group). Call history в Settings Hub. Incoming call overlay повёрнут над `AppLockGate` в `app.dart`. Route `/call` — full-screen, `/call-history` — с optional `conversationId` filter.

**Firebase pending:** Foreground realtime watcher работает (Supabase Realtime). Background push для incoming calls требует Firebase SDK — намеренно не добавлен. UI честно показывает, что background push не работает.

**Native telecom:** Android manifest добавил логически нужные permissions (camera, microphone, bluetooth, MODIFY_AUDIO_SETTINGS, BIND_TELECOM_CONNECTION_SERVICE, MANAGE_OWN_CALLS, POST_NOTIFICATIONS). `MainActivity.kt` регистрирует `MethodChannel("vibe/telecom")` с `isAvailable = false` — documented interface, не full implementation. `minSdk` поднят до 24 (требование `livekit_client`).

Точная продуктовая матрица: [`FEATURE_STATUS.md`](FEATURE_STATUS.md).
