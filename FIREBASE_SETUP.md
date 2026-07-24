# Firebase Cloud Messaging — Server-Side Setup

This guide explains how to configure Firebase Cloud Messaging (FCM) for Vibe
Messenger. The client-side integration is already implemented; this covers the
**server-side credentials** and the **Android build secret**.

## Architecture overview

```
┌──────────────┐     FCM data message      ┌─────────────────┐
│  Supabase    │ ──────────────────────────▶ │  Android device  │
│  Edge Func   │   (FCM v1 HTTP API)        │  (Flutter client) │
│  send-call-  │                             │                   │
│  push        │ ◀────────────────────────── │  FCM token reg.   │
└──────────────┘   register_call_device RPC  └─────────────────┘
       │
       │  FIREBASE_SERVICE_ACCOUNT_JSON
       │  (Supabase Edge Function secret)
       ▼
┌──────────────┐
│  Firebase    │
│  Project     │
│  (FCM v1)    │
└──────────────┘
```

The client:
1. Initializes Firebase safely (pending state if `google-services.json` absent).
2. Acquires an FCM registration token.
3. Registers the token in `call_devices` via the `register_call_device` RPC
   under existing Supabase RLS.
4. Listens for foreground FCM data messages and shows local notifications.
5. Has a top-level background handler (`@pragma('vm:entry-point')`) with no
   UI access.

The server (Supabase Edge Function `send-call-push`):
1. Looks up the callee's active `call_devices` rows.
2. Sends FCM v1 data messages to each token.
3. Uses the service account JSON to obtain an OAuth2 access token.

## Step 1: Create a Firebase project

1. Go to the [Firebase Console](https://console.firebase.google.com/).
2. Create a new project (or use an existing one).
3. Add an Android app with package name `ru.vibe.vibe_messenger`.
4. Download `google-services.json`.

## Step 2: Add `google-services.json` as a build secret

**Never commit `google-services.json` to git.** It is already in `.gitignore`.

Place the file at:
```
android/app/google-services.json
```

The `com.google.gms.google-services` Gradle plugin (already configured in
`android/app/build.gradle.kts`) reads this file during the build and injects
the Firebase app configuration (API key, project ID, etc.) into the Android
manifest merger. The Flutter client calls `Firebase.initializeApp()` without
passing `FirebaseOptions` from Dart — the native config is the source of truth.

### CI/CD

For CI builds, provide `google-services.json` as a secure environment variable
or secret, and write it to `android/app/google-services.json` before building.
The GitHub Actions workflow should use a repository secret (base64-encoded)
and decode it in a pre-build step.

## Step 3: Add the Firebase service account JSON as a Supabase secret

**This is the only manual secret step.** The service account JSON is used by
the `send-call-push` Edge Function to authenticate with the FCM v1 HTTP API.

### 3a. Download the service account key

1. In the Firebase Console, go to **Project Settings → Service Accounts**.
2. Click **Generate new private key**.
3. A JSON file downloads — this is your service account key.

### 3b. Set the Supabase Edge Function secret

```bash
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON='{ "type": "service_account", "project_id": "...", ... }'
```

Or, if you prefer to pipe the file:

```bash
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON < path/to/service-account.json
```

**Never commit the service account JSON file to the repository.** Add it to
`.gitignore` (it is not tracked by default, but keep it outside the repo).

### 3c. Verify

```bash
supabase secrets list
# Should show FIREBASE_SERVICE_ACCOUNT_JSON
```

The `send-call-push` Edge Function reads this secret via
`Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")` and parses it to obtain an
OAuth2 access token for the FCM v1 API.

## What the client does NOT contain

- **No service-account credentials.** The client only uses the public Firebase
  app configuration from `google-services.json` (API key, project ID). These
  are public client values; authorization is enforced by Firebase and Supabase
  RLS.
- **No `FIREBASE_SERVICE_ACCOUNT_JSON` anywhere in Flutter code.**
- **No LiveKit API secrets.** LiveKit tokens are issued per-call by the
  `issue-livekit-token` Edge Function.

## FCM data payload contract

The server sends **data-only** messages (not notification messages) so the
client retains full control over UI and call lifecycle. The `type` field
identifies the payload:

### `incoming_call`

```json
{
  "type": "incoming_call",
  "call_id": "<uuid>",
  "room_name": "<string>",
  "caller_name": "<string>",
  "caller_id": "<uuid>",
  "media_kind": "audio|video",
  "conversation_id": "<uuid>"
}
```

### `call_cancelled`

```json
{
  "type": "call_cancelled",
  "call_id": "<uuid>"
}
```

### `message`

```json
{
  "type": "message",
  "conversation_id": "<uuid>",
  "message_id": "<uuid>",
  "sender_id": "<uuid>",
  "sender_name": "<string>",
  "body_preview": "<string>",
  "is_group": "true|false"
}
```

The client parses these via `FcmPayload.fromData()` in
`lib/features/notifications/domain/fcm_payload.dart`.

## Android notification channels

Two channels are created by `LocalNotificationsService`:

| Channel ID             | Name             | Importance | Purpose                          |
|------------------------|------------------|------------|----------------------------------|
| `vibe_messages`        | Сообщения         | High       | Chat message notifications       |
| `vibe_incoming_calls`  | Входящие звонки   | Max        | Incoming call (full-screen)      |

The `send-call-push` Edge Function sets `channel_id: "vibe_incoming_calls"`
in the FCM v1 `android.notification` block so background notifications appear
on the correct channel.

## What happens when Firebase is not configured?

If `google-services.json` is absent:

1. `Firebase.initializeApp()` throws `[core/no-options]`.
2. `initializeFirebase()` catches this and returns
   `FirebaseInitResult.pending()`.
3. The app starts normally without push.
4. The settings UI shows "Firebase ожидает настройки" (Firebase pending setup).
5. The push toggle is disabled (grayed out) with an explanatory subtitle.
6. No crash, no fake success.

If the `FIREBASE_SERVICE_ACCOUNT_JSON` Supabase secret is not set:

1. The `send-call-push` Edge Function returns
   `{ "delivered": false, "reason": "firebase_not_configured" }`.
2. The caller sees a clear message that push was not delivered.
3. The callee's `call_devices` row exists (registered by the client), but no
   FCM message is sent until the server secret is configured.

## Constraints

- **Do not commit `google-services.json`** — it is gitignored.
- **Do not commit the service account JSON** — it is a server secret only.
- **Do not embed service-account credentials in the Flutter client.**
- **Do not modify `google-services.json` contents** — it is generated by the
  Firebase Console.
- **Do not modify database migrations** — the `call_devices` table and
  `register_call_device` RPC already exist in
  `202607240004_calls.sql`.
- The `send-call-push` Edge Function is deployed. It remains intentionally
  inactive for real delivery until `FIREBASE_SERVICE_ACCOUNT_JSON` is added as
  a Supabase Edge Function secret.
