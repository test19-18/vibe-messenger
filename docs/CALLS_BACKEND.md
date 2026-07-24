# Vibe Messenger — Calls Backend (LiveKit Cloud)

Backend-контур личных звонков 1:1 для LiveKit Cloud. Включает Postgres-схему,
RLS, security-definer RPC/helper-функции и Deno Supabase Edge Functions.

## 1. Обзор архитектуры

```
┌──────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Flutter App │────▶│  Supabase Edge   │────▶│  Postgres       │
│  (caller)    │     │  Functions       │     │  (calls schema) │
└──────────────┘     │                  │     └─────────────────┘
                     │  create-call     │
                     │  issue-token     │     ┌─────────────────┐
                     │  call-action     │────▶│  LiveKit Cloud  │
                     │  send-call-push  │     │  (SFU/WebRTC)   │
                     │  expire-stale    │     └─────────────────┘
                     └────────┬─────────┘
                              │
                     ┌────────▼─────────┐
                     │  Firebase FCM    │
                     │  (push to callee)│
                     └──────────────────┘
```

**Поток звонка:**
1. Caller → `create-call` (body: `{calleeId, mediaKind, conversationId?}`) → создаёт запись `calls` (state `created`), проверяет membership/blocks/privacy. Возвращает `{callId, roomName, state, conversationId}`.
2. Caller → `call-action` (body: `{callId, action: "ringing"}`) → переводит звонок в `ringing`.
3. Caller → `issue-livekit-token` (body: `{callId, roomName}`) → получает JWT `{token, url}` для подключения к LiveKit room.
4. Caller → `send-call-push` → отправляет push callee (через FCM или возвращает backend-ready response).
5. Callee получает push / видит realtime изменение → `call-action` (action: `accept`) → `issue-livekit-token` → подключается к room.
6. Оба → `call-action` (ringing → accept → connect → end) для state machine.

**Токен LiveKit:** выдаётся ТОЛЬКО через `issue-livekit-token`, никогда не хранится в таблице `calls` и не логируется. Flutter клиент вызывает `create-call`, затем `issue-livekit-token` когда caller/callee подключается к комнате.

**conversation_id:** Принимается опционально в `create-call`. Если указан, функция проверяет что это direct-диалог, и что оба (caller и callee) являются его участниками.

## 2. Схема базы данных

Миграция: `supabase/migrations/202607240004_calls.sql` (идемпотентная, не изменяет существующие миграции).

### Таблицы

| Таблица              | Назначение                                              |
|----------------------|---------------------------------------------------------|
| `calls`              | Основная запись звонка (caller, callee, state, timing) |
| `call_participants`  | Участники звонка (direction, joined_at, left_at)        |
| `call_events`        | Append-only журнал событий звонка                       |
| `call_devices`       | FCM/VoIP device tokens для call push routing            |
| `call_preferences`   | Per-user настройки приватности звонков                  |
| `call_rate_limits`   | Sliding-window rate limiting для outbound calls         |

### Enum типы

| Тип                  | Значения                                                                         |
|----------------------|----------------------------------------------------------------------------------|
| `call_state`         | created, ringing, accepted, connected, declined, cancelled, missed, busy, ended, failed, expired |
| `call_media_kind`    | audio, video                                                                     |
| `call_event_type`    | created, ringing, accepted, connected, declined, cancelled, missed, busy, ended, failed, expired, participant_joined, participant_left |
| `call_direction`     | outgoing, incoming                                                               |

### State Machine

```
created ──ringing──▶ ringing
   │                   │
   │              ┌────┼────┬────────┬────────┐
   │              │    │    │        │        │
   │          accept  decline cancel missed  expired
   │              │    │        │
   │              ▼    ▼        ▼
   │          accepted          cancelled
   │              │
   │         connect
   │              │
   │              ▼
   │         connected
   │              │
   │         end/fail
   │              │
   ▼              ▼
cancelled      ended/failed
```

### RLS и Grants

- RLS включён на всех 6 таблицах.
- `calls`: caller/callee видят и обновляют свои звонки.
- `call_participants`: participant видит свои записи и записи участников своих звонков.
- `call_events`: call parties видят события своих звонков; INSERT только через service_role (edge functions).
- `call_devices`: self only (select/insert/update/delete).
- `call_preferences`: self only (select/insert/update).
- `call_rate_limits`: нет direct access для authenticated (управляется только RPC).
- Все SECURITY DEFINER функции имеют фиксированный `search_path = public, pg_temp`.
- `EXECUTE` отозван у PUBLIC по умолчанию; только allow-list функций открыт для authenticated.

### SECURITY DEFINER функции

| Функция                      | Доступ        | Назначение                                    |
|------------------------------|---------------|-----------------------------------------------|
| `can_call_user(a, b)`        | authenticated | Проверка membership + blocks + privacy        |
| `is_call_participant(id)`    | authenticated | Является ли пользователь участником звонка    |
| `is_call_party(id)`          | authenticated | Является ли пользователь caller/callee        |
| `user_has_active_call(id)`   | authenticated | Есть ли у пользователя активный звонок (busy) |
| `register_call_device(...)`  | authenticated | Регистрация FCM/VoIP token                    |
| `set_call_preferences(...)`  | authenticated | Настройка приватности звонков                 |
| `check_call_rate_limit(id)`  | service_role  | Проверка и инкремент rate limit               |
| `get_call_rate_limit()`      | service_role  | Получение лимита (30 calls / 5 min)           |
| `expire_stale_calls()`       | service_role  | Экспайр зависших звонков                      |
| `guard_call_write()`         | trigger-only  | Валидация state transitions и timestamps      |
| `guard_call_participant_write()` | trigger-only | Валидация participant writes             |
| `guard_call_event_write()`   | trigger-only  | Установка event_at                            |
| `guard_call_preferences_write()` | trigger-only | Валидация preferences writes             |
| `guard_call_device_write()`  | trigger-only  | Валидация device writes                       |
| `ensure_call_preferences()`  | trigger-only  | Создание preferences для нового profile       |

### Realtime

Таблицы `calls`, `call_participants`, `call_events`, `call_preferences` добавлены в `supabase_realtime` publication с `REPLICA IDENTITY FULL`.

### pg_cron

Если pg_cron доступен, миграция устанавливает job:
```
vibe-expire-stale-calls  * * * * *  →  select public.expire_stale_calls();
```

## 3. Edge Functions

| Function              | Method | Auth        | Назначение                          |
|-----------------------|--------|-------------|-------------------------------------|
| `create-call`         | POST   | user JWT    | Создание звонка                     |
| `issue-livekit-token` | POST   | user JWT    | Выдача LiveKit JWT                  |
| `call-action`         | POST   | user JWT    | State transition (accept/decline…)  |
| `send-call-push`      | POST   | user JWT    | Push notification callee            |
| `expire-stale-calls`  | GET/POST | CRON_SECRET | Экспайр зависших звонков          |

## 4. Secrets (точный список)

### Обязательные для Supabase Edge Functions

```bash
supabase secrets set SUPABASE_URL=https://your-project.supabase.co
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
supabase secrets set SUPABASE_ANON_KEY=your-anon-key
```

> **Legacy alias:** `SUPABASE_SERVICE_KEY` принимается как fallback если
> `SUPABASE_SERVICE_ROLE_KEY` не установлен. Новые deployment должны
> использовать стандартное имя `SUPABASE_SERVICE_ROLE_KEY`.

### Обязательные для LiveKit

```bash
supabase secrets set LIVEKIT_URL=wss://your-project.livekit.cloud
supabase secrets set LIVEKIT_API_KEY=your-livekit-api-key
supabase secrets set LIVEKIT_API_SECRET=your-livekit-api-secret
```

> **Критично:** `LIVEKIT_API_SECRET` используется только server-side для подписи JWT (HS256).
> Никогда не встраивайте secret в клиентский код и не коммитьте в репозиторий.

### Обязательные для Firebase FCM (push delivery)

Вариант 1 — единый JSON:

```bash
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON='{ "project_id": "...", "client_email": "...", "private_key": "-----BEGIN PRIVATE KEY-----\n..." }'
```

Вариант 2 — раздельные поля:

```bash
supabase secrets set FIREBASE_PROJECT_ID=your-firebase-project-id
supabase secrets set FIREBASE_CLIENT_EMAIL=firebase-adminsdk@your-project.iam.gserviceaccount.com
supabase secrets set FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\nMIIE...\n-----END PRIVATE KEY-----\n"
```

> До настройки Firebase `send-call-push` возвращает `delivered: false, reason: "firebase_not_configured"`
> без фейковой доставки.

### Опциональные

```bash
supabase secrets set CRON_SECRET=your-cron-protection-secret
```

Защищает `expire-stale-calls` endpoint. Если установлен, запросы должны включать
header `X-Cron-Secret: <secret>`.

## 5. Команды деплоя

### Установка Supabase CLI (если не установлен)

```bash
npm install -g supabase
```

### Логин и линк проекта

```bash
supabase login
supabase link --project-ref your-project-ref
```

### Применение миграции базы данных

```bash
# Из корня проекта
supabase db push

# Или вручную через SQL Editor в Supabase dashboard:
# Скопировать содержимое supabase/migrations/202607240004_calls.sql
# и выполнить в SQL Editor.
```

### Установка secrets

```bash
# Supabase
supabase secrets set SUPABASE_URL=https://your-project.supabase.co
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=eyJhbGci...
supabase secrets set SUPABASE_ANON_KEY=eyJhbGci...

# LiveKit
supabase secrets set LIVEKIT_URL=wss://your-project.livekit.cloud
supabase secrets set LIVEKIT_API_KEY=APIxxxxxxxxxxxx
supabase secrets set LIVEKIT_API_SECRET=secretxxxxxxxxxxxx

# Firebase (вариант 1 — JSON)
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON='{...}'

# Или Firebase (вариант 2 — раздельные)
supabase secrets set FIREBASE_PROJECT_ID=your-project
supabase secrets set FIREBASE_CLIENT_EMAIL=admin@your-project.iam.gserviceaccount.com
supabase secrets set FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"

# Опционально
supabase secrets set CRON_SECRET=your-random-secret
```

### Деплой Edge Functions

```bash
# Деплой всех call functions одной командой
supabase functions deploy create-call
supabase functions deploy issue-livekit-token
supabase functions deploy call-action
supabase functions deploy send-call-push
supabase functions deploy expire-stale-calls

# Или деплой всех функций сразу
supabase functions deploy
```

### Проверка после деплоя

```bash
# 1. Выполнить verification SQL
psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f supabase/verification_calls.sql

# Или через Supabase SQL Editor: скопировать verification_calls.sql и выполнить.

# 2. Проверить, что secrets установлены
supabase secrets list
# Должны быть: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_ANON_KEY,
#              LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET
#              (опционально: FIREBASE_*, CRON_SECRET)
#              (legacy alias: SUPABASE_SERVICE_KEY принимается как fallback)

# 3. Тест create-call (требует валидный JWT)
curl -X POST https://your-project.supabase.co/functions/v1/create-call \
  -H "Authorization: Bearer <user_jwt>" \
  -H "Content-Type: application/json" \
  -d '{"calleeId": "<target_user_uuid>", "mediaKind": "audio", "conversationId": "<direct_conversation_uuid>"}'
# Должен вернуть { "callId": "uuid", "roomName": "call-<uuid>", "state": "created", "conversationId": "uuid-or-null" }

# 4. Тест issue-livekit-token
curl -X POST https://your-project.supabase.co/functions/v1/issue-livekit-token \
  -H "Authorization: Bearer <user_jwt>" \
  -H "Content-Type: application/json" \
  -d '{"callId": "<call_uuid>", "roomName": "call-<uuid>"}'
# Должен вернуть { "token": "eyJ...", "url": "wss://..." }

# 5. Тест expire-stale-calls
curl -X POST https://your-project.supabase.co/functions/v1/expire-stale-calls \
  -H "X-Cron-Secret: <your_secret>"
# Должен вернуть { "expired": 0, ... }
```

### Настройка scheduled function для expire-stale-calls (если pg_cron недоступен)

В Supabase Dashboard → Edge Functions → Schedule:
- Function: `expire-stale-calls`
- Schedule: `* * * * *` (every minute)
- Headers: `X-Cron-Secret: <your_secret>` (if configured)

## 6. Структура файлов

```
supabase/
├── migrations/
│   └── 202607240004_calls.sql          # Calls schema migration
├── functions/
│   ├── create-call/
│   │   ├── index.ts                     # Edge function
│   │   └── README.md                    # Function docs
│   ├── issue-livekit-token/
│   │   ├── index.ts
│   │   └── README.md
│   ├── call-action/
│   │   ├── index.ts
│   │   └── README.md
│   ├── send-call-push/
│   │   ├── index.ts
│   │   └── README.md
│   └── expire-stale-calls/
│       ├── index.ts
│       └── README.md
└── verification_calls.sql               # Post-migration verification
docs/
└── CALLS_BACKEND.md                     # This file
```

## 7. Rate Limiting

- Лимит: **30 outbound calls per 5 minutes** per user.
- Реализация: `call_rate_limits` table + `check_call_rate_limit()` RPC.
- При превышении `create-call` возвращает HTTP 429.

## 8. Timeout Handling

| State     | Timeout | Экспайр в состояние | Причина            |
|-----------|---------|---------------------|--------------------|
| `ringing` | 45s     | `expired`           | `ringing_timeout`  |
| `created` | 90s     | `expired`           | `created_timeout`  |

Экспайр выполняется pg_cron job (каждую минуту) или edge function `expire-stale-calls`.

## 9. Безопасность

- **LiveKit API Secret**: используется только в `issue-livekit-token` для подписи JWT (HS256). Не хранится в БД, не логируется.
- **Firebase Service Account**: server secret only. Не встраивается в клиент.
- **JWT токены LiveKit**: TTL 2 часа, содержат VideoGrant с `roomJoin`, `canPublish`, `canSubscribe`.
- **State transitions**: валидируются в DB trigger `guard_call_write`. Authenticated users могут только: cancel (created), decline (ringing), accept (ringing), connect (accepted), end (connected/accepted). Остальные transitions — только service_role.
- **Privacy**: `can_call_user()` проверяет blocks (bidirectional), contacts, DND, и `allow_calls_from` (everyone/contacts/nobody).
- **RLS**: все таблицы имеют RLS; `call_events` INSERT доступен только service_role; `call_rate_limits` не имеет authenticated policy.
