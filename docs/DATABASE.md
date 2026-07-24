# База данных Vibe Messenger

Актуальный источник схемы — одна миграция:

- `supabase/migrations/202607240001_initial_schema.sql`
- постпроверки — `supabase/verification.sql`

Миграция рассчитана на чистый Supabase Postgres и выполняется одной транзакцией. Она создаёт типы, таблицы и FK, затем helper/trigger/RPC-функции, RLS, явные grants, приватные Storage buckets/policies и состав publication `supabase_realtime`.

## 1. Основные сущности

### Пользователи и социальные связи

- `profiles` — профиль `auth.users`; создаётся auth-trigger-ом, содержит `username`, `display_name`, `bio`, `avatar_path`, discoverability/onboarding flags.
- `user_settings` — приватные настройки пользователя.
- `user_presence` — `last_seen_at` и `online_until`. Presence хранится отдельно от `profiles` и читается Flutter-клиентом как вложенная one-to-one relation.
- `user_devices` — FCM-токены и сведения об устройствах; `register_device(...)` атомарно регистрирует или переносит токен текущему пользователю.
- `contacts` — одна unordered-пара пользователей с workflow `pending → accepted/declined/cancelled`.
- `user_blocks` — направленная блокировка. При блокировке контакт пары удаляется, а отправка в существующий direct chat запрещается.

### Разговоры

- `conversations` — `direct`, `group` или зарезервированный enum-вариант `channel`.
- `conversation_members` — роль (`owner/admin/member`) и состояние (`active/left/removed/banned`).
- `conversation_user_settings` — персональные archive/pin/mute/notification/draft настройки.
- `chat_folders`, `chat_folder_conversations` — пользовательские папки; composite FK гарантирует, что строка папки принадлежит тому же `user_id`.

Direct chat создаётся только RPC `create_direct_conversation(_other_user_id)`. RPC нормализует UUID-пару, берёт advisory lock, проверяет профиль/блокировку, создаёт ровно двух активных `member` и является идемпотентным.

Group создаётся только RPC `create_group_conversation(_title, _description)`, который создаёт одного активного `owner`. В enum оставлен `channel`, но **клиентской функции создания channels нет**; пользователь не имеет прямого `INSERT` на `conversations` или `conversation_members`.

Отложенные constraint triggers проверяют в конце транзакции:

- direct содержит ровно двух заданных активных участников без owner;
- group/channel содержит ровно одного активного owner;
- kind/direct pair и identity-поля нельзя менять после создания.

### Сообщения и состояние чата

- `messages` — текст, media kinds, poll/system, reply, soft-delete и idempotency nonce.
- `message_attachments` — метаданные объектов Storage; composite FK не допускает несовпадение message/conversation.
- `message_reactions` — уникальная реакция пользователя на сообщение.
- `conversation_read_receipts` — монотонный message marker и серверное `last_read_at`.
- `conversation_typing` — короткоживущий typing state, TTL ограничен trigger-ом.
- `message_pins` — pinned message с проверкой той же беседы.

`last_message_id/last_message_at` в `conversations` поддерживаются trigger-ом. Composite FK не позволяет кэшировать сообщение другой беседы. Сообщения удаляются логически: trigger очищает body/metadata и записывает `deleted_by`; физический `DELETE` клиенту не выдан.

Для media message kind должен соответствовать attachment kind. Объект сначала загружается в Storage, затем клиент создаёт `message_attachments`; чтение чужого объекта возможно только после появления metadata row и только активному участнику.

### Инвайты и заявки

- `group_invitations` поддерживает targeted invite (`invitee_id`) и link invite (`token_hash`). В БД хранится только SHA-256 hash токена.
- `group_join_requests` поддерживает `pending → approved/rejected/cancelled`.
- `accept_group_invitation`, `accept_group_invite_token` и `review_group_join_request` выполняют status transition и membership change атомарно.
- Expired invite нельзя принять; banned user не может принять invite или быть одобрен.
- Membership `INSERT` закрыт для API и выполняется только trusted trigger/RPC-путём.

### Опросы

- `polls` связан один-к-одному с live `messages(kind = 'poll')`.
- `poll_options` содержит 2–20 уникальных по регистронезависимому тексту опций с непрерывными позициями от 0.
- `poll_votes` composite FK связывает vote одновременно с правильными poll, option и conversation.
- RPC `create_poll(...)` создаёт message, poll и options атомарно.
- Голосования сериализуются row lock-ом poll; лимит выбора проверяется до insert, `vote_count` поддерживается trigger-ом.
- После первого голоса нельзя менять multiple-choice rules/anonymity или редактировать набор/текст опций. Закрытый/истёкший poll не принимает голоса.
- Для anonymous poll RLS показывает пользователю только его собственные vote rows; агрегаты выдаёт `get_poll_results(...)`.

### Жалобы

`reports` хранит ровно одну цель при создании: user, conversation или message. После удаления цели FK использует `SET NULL`, чтобы moderation history сохранилась. API-пользователь может только создать и читать собственную жалобу; status меняется только trusted backend/service-role путём.

## 2. RLS и права

RLS включён на всех 23 таблицах `public`. Политики на membership-heavy таблицах используют `SECURITY DEFINER` helpers (`is_conversation_member`, `is_conversation_admin`, `can_view_profile` и др.), поэтому они не читают защищаемую таблицу через её же policy и не создают RLS recursion.

Все definer-функции имеют фиксированный `search_path = public, pg_temp` (или явно добавляют `extensions` для pgcrypto). `CREATE` на schema `public` отозван у API-ролей. PostgreSQL default `EXECUTE TO PUBLIC` отозван для функций миграции; trigger/internal-функции остаются owner-only. Для `authenticated` выдан явный allow-list helper/RPC-функций.

Табличные grants также явные:

- `anon` не имеет доступа к application tables/functions;
- `authenticated` получает `SELECT` с RLS;
- изменения выдаются на минимальный набор таблиц и, где нужно, только на конкретные columns;
- прямого `INSERT` на conversations/members/polls/options и прямого `DELETE` messages нет;
- service-role остаётся доверенной серверной ролью и должен использоваться только вне клиента.

## 3. Supabase Storage

Все buckets приватные:

| Bucket | Лимит | Путь |
|---|---:|---|
| `avatars` | 10 MiB | профиль: `<user_uuid>/<file>`; группа: `<conversation_uuid>/<uploader_uuid>/<file>` |
| `chat-media` | 100 MiB | `<conversation_uuid>/<uploader_uuid>/<file>` |
| `voice-messages` | 50 MiB | `<conversation_uuid>/<uploader_uuid>/<file>` |

Path helpers требуют точное число непустых сегментов, валидные UUID, отсутствие `.`/`..`, двойных/краевых slash и backslash. Upload/update/delete разрешены только владельцу path и, для conversation objects, активному участнику или group admin. Download chat media дополнительно требует live `message_attachments` row.

Удаление DB metadata и Storage object не является одной транзакцией между сервисами. Клиент/backend должен удалять metadata и object с retry/cleanup для orphan-файлов.

## 4. Realtime

Миграция создаёт publication `supabase_realtime`, если её нет, выставляет `REPLICA IDENTITY FULL` и идемпотентно добавляет:

- `conversations`, `conversation_members`;
- `messages`, `message_attachments`, `message_reactions`;
- `conversation_read_receipts`, `conversation_typing`, `message_pins`;
- `conversation_user_settings`, `user_presence`;
- `group_invitations`, `group_join_requests`;
- `polls`, `poll_options`, `poll_votes`.

`profiles`, `contacts`, `reports`, `user_devices`, `chat_folders`, `chat_folder_conversations` и `user_settings` намеренно не публикуются: текущий Flutter-клиент читает их запросами, а лишний WAL fan-out и old-row surface не нужны. Realtime всё равно фильтруется RLS текущей JWT-роли.

## 5. Контракт Flutter

Flutter-клиент 0.2 использует ручные defensive mapper-модели без codegen и следующий schema surface:

- `profiles` + nested `user_presence`; FK relation `conversation_members_user_id_fkey` для embedded profile;
- `contacts`, `user_blocks`, `reports` для request/block/report workflow;
- `conversations`, `conversation_members`, `conversation_user_settings` с `auto_delete_seconds`/`protected_content`, `chat_folders`, `chat_folder_conversations`;
- `messages` включая `kind`, `metadata`, `client_nonce`, reply/edit/delete fields и `expires_at`;
- `message_user_deletions`, `scheduled_messages`, `message_attachments`, `message_reactions`, `conversation_read_receipts`, `conversation_typing`, `message_pins`;
- `group_invitations`, `group_join_requests`, `conversation_member_tags`, group role/status updates;
- `polls`, `poll_options`, `poll_votes`;
- `user_settings`, `user_devices`;
- RPC `create_direct_conversation`, `create_group_conversation`, ownership/invite/join RPC, `create_poll`, `get_poll_results`, `register_device`, scheduled delivery и expiry cleanup;
- private buckets `avatars`, `chat-media`, `voice-messages` и короткие signed URLs/download.

Клиент фильтрует reserved `channel` rows и не содержит channel creation/UI. `user_presence` остаётся canonical presence source. Миграции 002–003 добавляют delete-for-self, server member tags, scheduled messages, auto-delete и protected content; два активных Supabase Cron job выполняют доставку и очистку.

## 6. Применение и проверка

Для нового проекта:

```bash
supabase db reset
# либо штатный deploy миграций
supabase db push
```

После миграций выполните `supabase/verification.sql` и `supabase/verification_extensions.sql` в SQL Editor или через `psql -v ON_ERROR_STOP=1`. Скрипты:

1. падает при отсутствии таблиц, PK/FK/check constraints, triggers или RLS policies;
2. проверяет grants и закрытый function surface;
3. проверяет private buckets и Storage policies;
4. проверяет publication и replica identity;
5. выполняет smoke-SELECT всех application tables под ролью `authenticated` с фиктивным JWT, чтобы обнаружить RLS recursion.

## 7. Эксплуатационные риски

- Нет E2E encryption: plaintext message body и metadata доступны доверенному DB/service-role контуру.
- Presence/typing/read receipts раскрываются согласно user settings и RLS, но продукт должен явно документировать privacy semantics.
- FCM-токены и invite links требуют server-side rotation/revocation и log redaction.
- Signed URL является capability-ссылкой и остаётся действительным до истечения TTL даже после block/leave; клиент сейчас запрашивает URL на один час.
- Expired invitations/typing rows и orphan Storage objects требуют периодической cleanup-задачи.
- `vote_count` защищён trigger-ами, но после аварийного ручного вмешательства service-role его следует сверять с `count(poll_votes)` через verification query.
- Миграция использует column-specific `ON DELETE SET NULL`, поддерживаемый актуальным Supabase PostgreSQL (15+).
- Любые новые таблицы/functions не наследуют автоматически текущий client allow-list: для них отдельно нужны RLS, grants, function revoke и решение по Realtime.
