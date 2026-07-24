# call-action

Handles state transitions for a call (ringing, accept, connect, decline, cancel, end, missed, fail).

## Endpoint

```
POST /functions/v1/call-action
```

## Authentication

Requires a valid Supabase user JWT in the `Authorization` header.

## Request Body

| Field    | Type   | Required | Description                                                        |
|----------|--------|----------|--------------------------------------------------------------------|
| `callId` | string | Yes      | UUID of the call                                                   |
| `action` | string | Yes      | One of: `ringing`, `accept`, `connect`, `decline`, `cancel`, `end`, `missed`, `fail` |

## Actions

| Action    | Target State  | Allowed Party | Valid From States                          |
|-----------|---------------|---------------|--------------------------------------------|
| `ringing` | `ringing`     | caller        | `created`                                  |
| `accept`  | `accepted`    | callee        | `ringing`                                  |
| `connect` | `connected`   | either        | `accepted`                                 |
| `decline` | `declined`    | callee        | `ringing`                                  |
| `cancel`  | `cancelled`   | caller        | `created`, `ringing`                       |
| `end`     | `ended`       | either        | `accepted`, `connected`                    |
| `missed`  | `missed`      | callee        | `ringing`                                  |
| `fail`    | `failed`      | either        | `accepted`, `connected`                    |

## Response

### Success (200)

```json
{
  "callId": "uuid",
  "state": "connected",
  "durationSeconds": null
}
```

### Errors

| Status | Description                                         |
|--------|-----------------------------------------------------|
| 400    | Missing `callId`/`action` or invalid action         |
| 401    | Authentication required                             |
| 403    | Not authorized (not a call party or wrong party)    |
| 404    | Call not found                                      |
| 409    | Invalid state transition                            |
| 500    | Server error                                        |

## Environment Variables

| Variable                    | Description                          |
|-----------------------------|--------------------------------------|
| `SUPABASE_URL`              | Supabase project URL                 |
| `SUPABASE_SERVICE_ROLE_KEY` | Service-role key (standard name)     |
| `SUPABASE_SERVICE_KEY`      | Legacy alias for service-role key (fallback) |
| `SUPABASE_ANON_KEY`         | Anon/publishable key                 |

## Flow

1. Authenticates the user via JWT.
2. Fetches the call record and verifies the user is a party.
3. Validates the action is allowed for the user's role (caller/callee).
4. Validates the state transition is legal.
5. Updates the call state — the DB trigger `guard_call_write` sets timestamps
   (`ringing_at`, `accepted_at`, `connected_at`, `ended_at`) and computes
   `duration_seconds` on `ended`.
6. Logs the event in `call_events`.
7. On `connect`, sets the participant's `joined_at`; on `end`, sets `left_at`.
