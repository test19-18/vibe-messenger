# Feature status — Vibe 0.2

Легенда:

- **Implemented** — есть достижимый UI и клиентская операция; требуется обычная интеграционная проверка с deployed migration.
- **Backend-ready** — repository/schema contract готов, но внешний/native production-контур ещё не подключён или не подтверждён.
- **Local placeholder** — UI честно сообщает, что серверного контракта нет; fake success не используется.
- **Firebase-pending** — намеренно нет Firebase SDK/google-services.json.
- **Excluded** — вне утверждённого scope.

## Аккаунт, профиль и социальный граф

| Функция | Статус | Примечание |
|---|---|---|
| Email auth/reset/auth guard | Implemented | Supabase Auth PKCE |
| Имя/username/bio | Implemented | `profiles`, server normalization/checks |
| Avatar upload/view | Implemented | private `avatars`, signed URL, 10 MiB client guard |
| QR профиля | Implemented | `vibe://profile/<uuid>`; universal/app links не настраивались |
| Каталог discoverable profiles | Implemented | RLS authoritative |
| Contact request accept/decline/cancel/remove | Implemented | `contacts` workflow |
| Block/unblock | Implemented | `user_blocks`; blocked profile name скрывается RLS |
| User/message/conversation reports | Implemented | client может создавать/читать только собственные reports |
| Presence heartbeat | Implemented | foreground 60 s + lifecycle offline; best effort |
| Visibility: last seen/typing/read | Implemented | `user_settings` + RLS helpers |

## Чаты и сообщения

| Функция | Статус | Примечание |
|---|---|---|
| Direct chat creation | Implemented | `create_direct_conversation` RPC |
| Chat unread | Implemented | client aggregation максимум по 500 messages; production RPC/view desirable |
| Pin/mute/archive/draft | Implemented | `conversation_user_settings` |
| Folders and filters | Implemented | create/assign/filter; repository также поддерживает delete |
| Text/reply/edit | Implemented | sender/RLS checks |
| Delete for everyone | Implemented | единственная schema semantics — global soft-delete |
| Delete only for self | Implemented | insert в `message_user_deletions`; realtime hidden-id stream сразу фильтрует локальную ленту |
| Reactions | Implemented | realtime stream; current table lacks `conversation_id`, so stream is RLS-wide then filtered by message id |
| Read receipts | Implemented | monotonic `last_read_message_id`; timestamp fallback |
| Typing | Implemented | realtime + TTL, privacy toggle |
| Search in conversation | Implemented | PostgREST `ilike`, limit 100; no FTS/ranking |
| Selection/copy | Implemented | local UI state |
| Forward text/location/contact | Implemented | new message + provenance metadata |
| Forward media/poll | Backend-ready | blocked with explicit error until copy RPC/storage strategy exists |
| Message pin/unpin | Implemented | direct members or group admins per RLS |
| Simple formatting | Implemented | bold/italic/code parser; not Markdown/HTML |
| Image preview | Implemented | private object signed URL + fullscreen `InteractiveViewer` |
| Document download/open | Implemented | private download to temp + `open_filex`; native verification required |
| Location/contact payload | Implemented | validated JSON metadata; location copies coordinates, no map SDK |
| Voice record/play | Implemented | `record` + `just_audio`; native permission/codec verification required |
| Scheduled messages | Implemented | text create через RPC, realtime list, cancel RPC, date/time picker и `silent`; Supabase Cron доставляет due messages каждую минуту |
| Auto-delete timer / `expires_at` | Implemented | per-user `auto_delete_seconds`; срок новых сообщений выводится в bubble, expired rows дополнительно скрываются локальным timer |
| Protected chat content | Implemented | `protected_content` синхронизирован; CI генерирует Android MethodChannel и включает `FLAG_SECURE`, lifecycle-cover остаётся дополнительной защитой |
| Offline queue/database | Not implemented | online-first client |

## Groups and polls

| Функция | Статус | Примечание |
|---|---|---|
| Create/edit group/avatar | Implemented | RPC + admin update/private avatar |
| Roles/members/leave | Implemented | owner/admin/member and state transitions enforced by DB |
| Promote/demote/remove/ban | Implemented | UI exposes operation; RLS/trigger remains authoritative |
| Ownership transfer | Implemented | RPC |
| Targeted invitation | Implemented | admin insert + invitee accept/decline UI |
| Link invitation | Implemented | token returned once, copied as `vibe://`; deep-link native wiring pending |
| Join request/create/review | Implemented | direct table insert + review RPC |
| Member tags | Implemented | личные server-backed метки в `conversation_member_tags`; RLS показывает только метки текущего пользователя |
| Poll create | Implemented | atomic `create_poll` RPC |
| Poll vote/unvote/results | Implemented | DB limits/locks + `get_poll_results` RPC |
| Poll advanced editing/close UI | Backend-ready | schema supports parts; dedicated editor not included |
| Channels/public feed | Excluded | enum remains reserved; Flutter hides channel rows and has no creation UI |

## Settings, devices and notifications

| Функция | Статус | Примечание |
|---|---|---|
| System/light/dark | Implemented | local-first + `user_settings.theme` |
| RU/EN | Implemented (partial catalog) | primary navigation/new screens switch; legacy auth/profile copy remains predominantly RU |
| Text size | Implemented | 0.85–1.35 `TextScaler` |
| Animations/power-saving | Implemented | reduced ticker activity; not OS battery API |
| Media auto-download preference | Backend-ready | saved, but network/cellular policy engine is placeholder |
| Media cache toggle/clear | Local placeholder | no offline cache index/database yet |
| Local PIN lock | Implemented | salted SHA-256 hash in SharedPreferences; not a secure keystore |
| Biometric lock | Implemented | `local_auth`; native/device verification required |
| Registered devices UI | Implemented | list/disable/remove `user_devices` |
| Device token repository | Backend-ready | `register_device` RPC implemented |
| Push preference | Implemented | `user_settings` fields |
| FCM token acquisition/delivery | Firebase-pending | no Firebase SDK, no `google-services.json` |
| All Supabase Auth sessions list/revoke | Backend-ready/server-required | mobile client shows current session only; admin/session management needs trusted backend |

## Explicitly excluded

Screen share, E2EE/secret chats, channels/public feed UI, stories/live, bot platform, Wear OS, AI, payments, gifts and blockchain are not implemented and no placeholder claims success for them.

## Звонки (1:1 audio/video)

| Функция | Статус | Примечание |
|---|---|---|
| 1:1 audio call (outgoing) | Backend-ready | LiveKit Flutter client 2.8.1; `create-call` + `issue-livekit-token` + `call-action` Edge Functions |
| 1:1 video call (outgoing) | Backend-ready | `VideoTrackRenderer` для local/remote; camera on/off/switch |
| Incoming call route (foreground) | Backend-ready | Realtime subscription на `calls` table где `callee_id = me` и `state = ringing/created`; `IncomingCallOverlay` показывается над текущим UI |
| Incoming call (background push) | Firebase-pending | Нет Firebase SDK/google-services.json; foreground realtime watcher работает, background push — нет |
| Ringing/accept/decline/cancel | Implemented (client) | `CallSessionTransition` pure state machine; все transitions unit-tested |
| Busy/missed/ended states | Backend-ready | Client обрабатывает terminal states из realtime; server timeout/edge function не деплоилась |
| LiveKit room connect (after server token) | Implemented (client) | `CallRoomService.connect()` требует `canConnectRoom == true` (token + url + roomName); API secret никогда не в client |
| Mute/speaker/camera on/off/switch | Implemented (client) | `LocalParticipant.setMicrophoneEnabled/setCameraEnabled`; `AudioManager.setSpeakerOutputPreferred`; `VideoTrack.switchCamera` |
| Reconnect UI | Implemented (client) | `RoomReconnectingEvent` → `CallStatus.reconnecting` → UI overlay "Переподключение…" |
| Call duration (live + history) | Implemented (client) | Timer с `acceptedAt`; `CallRecord.displayDurationSeconds` |
| Call history UI | Backend-ready | `CallHistoryScreen` с `listCallHistory`; batch-resolve peer names; reachable из settings hub и conversation |
| Native Telecom/ConnectionService | Local placeholder | `TelecomApi` abstraction + `MethodChannel("vibe/telecom")`; `isAvailable` возвращает false; native handler не реализован |
| Group calls | Excluded | UI отклоняет с explicit message |
| API secret in client | Excluded | Токен выдаётся Edge Function per-call, short-lived; service-role/LiveKit API secret не в коде |

## Verification state

- `dart format --output=none --set-exit-if-changed lib test`: проходит на Dart 3.12.2.
- `flutter analyze --no-pub --fatal-infos --fatal-warnings`: проходит на Flutter 3.44.8.
- `flutter test --no-pub`: 76 tests проходят, включая email redirect и pure-domain tests звонков.
- Миграция `202607240004_calls.sql` и Edge Function source подготовлены, но не применены/развёрнуты: Supabase MCP connection отключена.
- Миграции 001–003 применены к выделенному Supabase-проекту, RLS/realtime extensions проверены, а два Supabase Cron job активны. Android `FLAG_SECURE` host генерируется CI; microphone/biometric/file intents, Firebase push, deployed call backend и реальные calls требуют проверки на устройствах.
