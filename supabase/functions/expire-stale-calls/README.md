# expire-stale-calls

Expires calls stuck in `created` or `ringing` state beyond their timeout thresholds.

## Endpoint

```
GET  /functions/v1/expire-stale-calls
POST /functions/v1/expire-stale-calls
```

## Authentication

No user JWT required. Optionally protected by `CRON_SECRET`:

```
X-Cron-Secret: <secret>
```

If `CRON_SECRET` is set as an environment variable, requests must include the
matching `X-Cron-Secret` header. If not set, the endpoint is open (use Supabase
Edge Function restrictions or API gateway rules to protect it).

## Response

### Success (200)

```json
{
  "expired": 3,
  "ringingExpired": 2,
  "createdExpired": 1,
  "callIds": ["uuid1", "uuid2", "uuid3"],
  "timestamp": "2026-07-24T12:00:00.000Z"
}
```

## Environment Variables

| Variable                    | Description                                         |
|-----------------------------|-----------------------------------------------------|
| `SUPABASE_URL`              | Supabase project URL                                |
| `SUPABASE_SERVICE_ROLE_KEY` | Service-role key (standard name)                    |
| `SUPABASE_SERVICE_KEY`      | Legacy alias for service-role key (fallback)        |
| `CRON_SECRET`               | Optional secret for protecting the endpoint         |

## Timeouts

| State     | Timeout | Reason             |
|-----------|---------|--------------------|
| `ringing` | 45s     | `ringing_timeout`  |
| `created` | 90s     | `created_timeout`  |

## Scheduling

This function can be triggered by:

1. **pg_cron** (configured in the migration): runs `public.expire_stale_calls()`
   every minute via a Postgres RPC. This is the preferred method.
2. **Supabase scheduled functions**: configure in the Supabase dashboard to
   call this endpoint every minute.
3. **External cron**: any HTTP-based cron service (GitHub Actions, cron-job.org,
   etc.) can call this endpoint.

Both the pg_cron RPC and this edge function are safe to run concurrently —
they use optimistic locking (`eq("state", ...)` in the update WHERE clause)
so there are no double-expiry conflicts.

## Flow

1. Fetches calls in `ringing` state older than 45 seconds (limit 200).
2. Expires each to `expired` with `end_reason = "ringing_timeout"`.
3. Logs an `expired` event in `call_events`.
4. Fetches calls in `created` state older than 90 seconds (limit 200).
5. Expires each to `expired` with `end_reason = "created_timeout"`.
6. Logs an `expired` event in `call_events`.
7. Returns a summary of expired calls.
