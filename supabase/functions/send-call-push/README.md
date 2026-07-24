# send-call-push

Sends a VoIP/call push notification to a callee's registered devices via Firebase Cloud Messaging (FCM).

## Endpoint

```
POST /functions/v1/send-call-push
```

## Authentication

Requires a valid Supabase user JWT in the `Authorization` header (the caller's token).

## Request Body

| Field        | Type   | Required | Description                          |
|--------------|--------|----------|--------------------------------------|
| `callId`     | string | Yes      | UUID of the call                     |
| `calleeId`   | string | Yes      | UUID of the callee                   |
| `roomName`   | string | Yes      | LiveKit room name                    |
| `callerName` | string | No       | Display name of the caller           |
| `mediaKind`  | string | No       | `"audio"` (default) or `"video"`    |

## Response

### Firebase configured — delivery attempted

```json
{
  "delivered": true,
  "deviceCount": 2,
  "successCount": 2,
  "results": [
    { "deviceId": "uuid", "success": true },
    { "deviceId": "uuid", "success": true }
  ]
}
```

### Firebase NOT configured — backend-ready response (no fake delivery)

```json
{
  "delivered": false,
  "reason": "firebase_not_configured",
  "message": "Push notification backend is ready but Firebase is not configured. ...",
  "deviceCount": 2,
  "payload": { "call_id": "...", "room_name": "...", "type": "incoming_call" }
}
```

### No registered devices

```json
{
  "delivered": false,
  "reason": "no_devices",
  "message": "Callee has no registered call devices. Push not sent.",
  "deviceCount": 0
}
```

## Environment Variables

### Required (Supabase)

| Variable                    | Description                          |
|-----------------------------|--------------------------------------|
| `SUPABASE_URL`              | Supabase project URL                 |
| `SUPABASE_SERVICE_ROLE_KEY` | Service-role key (standard name)     |
| `SUPABASE_SERVICE_KEY`      | Legacy alias for service-role key (fallback) |
| `SUPABASE_ANON_KEY`         | Anon/publishable key                 |

### Required for Firebase delivery (server secrets only)

Either set a single JSON blob:

| Variable                          | Description                                    |
|-----------------------------------|------------------------------------------------|
| `FIREBASE_SERVICE_ACCOUNT_JSON`   | Full Firebase service account JSON as string   |

Or set the three component fields:

| Variable                   | Description                              |
|----------------------------|------------------------------------------|
| `FIREBASE_PROJECT_ID`      | Firebase project ID                      |
| `FIREBASE_CLIENT_EMAIL`    | Service account client email             |
| `FIREBASE_PRIVATE_KEY`     | Service account private key (PEM format) |

**Never** put Firebase credentials in the client app or commit them to the repository.

## Behavior when Firebase is not configured

When `FIREBASE_SERVICE_ACCOUNT_JSON` (or `FIREBASE_PROJECT_ID`) is absent, the function:
1. Still queries the callee's registered `call_devices`.
2. Returns a **200** with `delivered: false` and `reason: "firebase_not_configured"`.
3. Does **NOT** fake a successful delivery.
4. Includes the prepared push payload in the response so the caller knows what would have been sent.

This allows the system to function end-to-end (call creation, state machine, LiveKit tokens)
while push delivery is pending Firebase configuration.

## FCM message format

Messages are sent via the **FCM HTTP v1 API** (`POST /v1/projects/{id}/messages:send`).

- **Android**: high priority, `CALL_INVITE` click action, `call_notifications` channel.
- **iOS**: APNs priority 10, `time-sensitive` interruption level, `content-available: true`
  for VoIP background delivery.
- **Data payload**: `call_id`, `room_name`, `caller_name`, `media_kind`, `type: "incoming_call"`.

Invalid FCM tokens (404/400 response) are automatically disabled in `call_devices`.
