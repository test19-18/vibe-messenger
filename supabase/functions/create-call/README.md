# create-call

Creates a 1:1 personal call record in the database.

## Endpoint

```
POST /functions/v1/create-call
```

## Authentication

Requires a valid Supabase user JWT in the `Authorization` header:

```
Authorization: Bearer <access_token>
```

## Request Body

| Field             | Type   | Required | Description                                    |
|-------------------|--------|----------|------------------------------------------------|
| `calleeId`        | string | Yes      | UUID of the user to call                       |
| `mediaKind`       | string | No       | `"audio"` (default) or `"video"`              |
| `conversationId`  | string | No       | UUID of a direct conversation (verified)       |

## Response

### Success (200)

```json
{
  "callId": "uuid",
  "roomName": "call-<uuid>",
  "state": "created",
  "conversationId": "uuid-or-null"
}
```

### Errors

| Status | Code    | Description                                      |
|--------|---------|--------------------------------------------------|
| 400    |         | Missing/invalid `calleeId` or self-call          |
| 401    |         | Authentication required                          |
| 403    |         | Cannot call user (blocked/privacy/contacts-only) |
| 409    | busy    | Callee is in another active call                 |
| 409    | duplicate | An active call already exists between users    |
| 429    |         | Rate limit exceeded                              |
| 500    |         | Server error                                     |

## Environment Variables

| Variable                    | Description                                      |
|-----------------------------|--------------------------------------------------|
| `SUPABASE_URL`              | Supabase project URL                             |
| `SUPABASE_SERVICE_ROLE_KEY` | Service-role key (server only, standard name)    |
| `SUPABASE_SERVICE_KEY`      | Legacy alias for service-role key (fallback)     |
| `SUPABASE_ANON_KEY`         | Anon/publishable key                             |

## Flow

1. Verifies caller authentication via JWT.
2. Checks `can_call_user(caller, callee)` — validates blocks, privacy, contacts.
3. Checks `user_has_active_call(callee)` — busy detection.
4. Checks for existing active call between the pair.
5. Checks rate limit via `check_call_rate_limit`.
6. Inserts call record (state `created`), participant records, and a `created` event.
7. Returns `callId` and `roomName` for the client to use with `issue-livekit-token`.
