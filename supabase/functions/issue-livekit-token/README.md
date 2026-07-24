# issue-livekit-token

Issues a LiveKit access token (JWT) for a call participant to join a room.

## Endpoint

```
POST /functions/v1/issue-livekit-token
```

## Authentication

Requires a valid Supabase user JWT in the `Authorization` header:

```
Authorization: Bearer <access_token>
```

## Request Body

| Field      | Type   | Required | Description                    |
|------------|--------|----------|--------------------------------|
| `callId`   | string | Yes      | UUID of the call               |
| `roomName` | string | Yes      | LiveKit room name from create-call |

## Response

### Success (200)

```json
{
  "token": "<LiveKit JWT>",
  "url": "wss://your-project.livekit.cloud"
}
```

### Errors

| Status | Description                                          |
|--------|------------------------------------------------------|
| 400    | Missing `callId` or `roomName`, invalid format      |
| 401    | Authentication required                              |
| 403    | User is not a party to this call                     |
| 404    | Call not found or not in an active state             |
| 503    | LiveKit credentials not configured                   |
| 500    | Token generation failure                             |

## Environment Variables

| Variable                    | Description                                      |
|-----------------------------|--------------------------------------------------|
| `LIVEKIT_URL`               | LiveKit Cloud URL (e.g. `wss://proj.livekit.cloud`) |
| `LIVEKIT_API_KEY`           | LiveKit API key                                  |
| `LIVEKIT_API_SECRET`        | LiveKit API secret (signs JWT, never sent client)|
| `SUPABASE_URL`              | Supabase project URL                             |
| `SUPABASE_SERVICE_ROLE_KEY` | Service-role key (standard name)                 |
| `SUPABASE_SERVICE_KEY`      | Legacy alias for service-role key (fallback)     |
| `SUPABASE_ANON_KEY`         | Anon/publishable key                             |

## Security

- **Never** embed `LIVEKIT_API_SECRET` in client code or commit it to the repository.
- The secret is used **only** server-side to sign the JWT via HMAC-SHA256.
- The generated token is returned to the client but is never stored in the database.
- The token contains a `VideoGrant` with `roomJoin`, `canPublish`, `canSubscribe`,
  `canPublishData`, and `canUpdateOwnMetadata` set to `true`.
- Token TTL is 2 hours (7200 seconds). Calls that exceed this duration will need
  a fresh token (re-issue via this endpoint).

## JWT Structure

The token is a standard JWT with:

```json
{
  "iss": "<LIVEKIT_API_KEY>",
  "sub": "<user_uuid>",
  "iat": <issued_at_unix>,
  "exp": <expiry_unix>,
  "nbf": <not_before_unix>,
  "video": {
    "roomJoin": true,
    "room": "<room_name>",
    "canPublish": true,
    "canPublishData": true,
    "canSubscribe": true,
    "canUpdateOwnMetadata": true
  }
}
```

Signed with `HS256` using `LIVEKIT_API_SECRET` as the HMAC key.
