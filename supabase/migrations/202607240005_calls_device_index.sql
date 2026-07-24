-- Complements 202607240004_calls.sql with the active device routing index
-- used by call push delivery and verification.

begin;

create index if not exists call_devices_user_active_idx
  on public.call_devices (user_id, last_seen_at desc)
  where disabled_at is null;

commit;
