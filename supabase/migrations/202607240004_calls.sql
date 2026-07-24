-- Vibe Messenger: 1:1 personal calls backend (LiveKit Cloud).
-- Depends on 202607240001_initial_schema.sql.
-- Idempotent: safe to re-apply.

begin;

-- Domain enums -----------------------------------------------------------------
do $$ begin
  create type public.call_state as enum (
    'created', 'ringing', 'accepted', 'connected',
    'declined', 'cancelled', 'missed', 'busy',
    'ended', 'failed', 'expired'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.call_media_kind as enum ('audio', 'video');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.call_event_type as enum (
    'created', 'ringing', 'accepted', 'connected',
    'declined', 'cancelled', 'missed', 'busy',
    'ended', 'failed', 'expired',
    'participant_joined', 'participant_left'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.call_direction as enum ('outgoing', 'incoming');
exception when duplicate_object then null; end $$;

-- Tables ------------------------------------------------------------------------

-- call_preferences: per-user call privacy settings (1:1 only, DND, etc.)
create table if not exists public.call_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  allow_calls boolean not null default true,
  allow_calls_from text not null default 'contacts'  -- 'everyone' | 'contacts' | 'nobody'
    check (allow_calls_from in ('everyone', 'contacts', 'nobody')),
  include_in_call_history boolean not null default true,
  ringtone_enabled boolean not null default true,
  vibrate_enabled boolean not null default true,
  do_not_disturb_until timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- call_devices: FCM device tokens specifically for call push routing
-- (separate from user_devices to allow independent token lifecycle for VoIP)
create table if not exists public.call_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform public.device_platform not null,
  fcm_token text not null,
  voip_token text,  -- APNs VoIP token for iOS; null on Android
  device_name text,
  app_version text,
  last_seen_at timestamptz not null default now(),
  disabled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (fcm_token),
  constraint call_devices_token_length check (
    char_length(fcm_token) between 16 and 4096 and fcm_token !~ '\s'
  ),
  constraint call_devices_voip_token_length check (
    voip_token is null
    or (char_length(voip_token) between 16 and 4096 and voip_token !~ '\s')
  ),
  constraint call_devices_text_lengths check (
    (device_name is null or char_length(device_name) <= 200)
    and (app_version is null or char_length(app_version) <= 100)
  )
);

-- call_rate_limits: per-user sliding-window rate limiting for outbound calls
create table if not exists public.call_rate_limits (
  user_id uuid not null references public.profiles(id) on delete cascade,
  window_start timestamptz not null default now(),
  call_count integer not null default 0,
  primary key (user_id)
);

-- calls: the core call record
create table if not exists public.calls (
  id uuid primary key default gen_random_uuid(),
  room_name text not null,  -- LiveKit room identifier
  caller_id uuid not null references public.profiles(id) on delete cascade,
  callee_id uuid not null references public.profiles(id) on delete cascade,
  state public.call_state not null default 'created',
  media_kind public.call_media_kind not null default 'audio',
  conversation_id uuid references public.conversations(id) on delete set null,
  -- timing
  created_at timestamptz not null default now(),
  ringing_at timestamptz,
  accepted_at timestamptz,
  connected_at timestamptz,
  ended_at timestamptz,
  -- duration in seconds, set when state → ended
  duration_seconds integer,
  -- why the call ended (if available)
  end_reason text,
  -- metadata
  metadata jsonb not null default '{}'::jsonb,
  constraint calls_no_self check (caller_id <> callee_id),
  constraint calls_room_name_length check (
    char_length(room_name) between 1 and 200 and room_name ~ '^[a-zA-Z0-9_\-]+$'
  ),
  constraint calls_end_reason_length check (
    end_reason is null or char_length(end_reason) <= 200
  ),
  constraint calls_metadata_object check (
    jsonb_typeof(metadata) = 'object' and octet_length(metadata::text) <= 65536
  ),
  constraint calls_duration_nonneg check (
    duration_seconds is null or duration_seconds >= 0
  ),
  -- timing consistency
  constraint calls_ring_after_create check (
    ringing_at is null or ringing_at >= created_at
  ),
  constraint calls_accept_after_ring check (
    accepted_at is null or (ringing_at is not null and accepted_at >= ringing_at)
  ),
  constraint calls_connect_after_accept check (
    connected_at is null or (accepted_at is not null and connected_at >= accepted_at)
  ),
  constraint calls_end_after_create check (
    ended_at is null or ended_at >= created_at
  ),
  -- state-timing consistency
  -- States that necessarily passed through 'ringing' must have ringing_at.
  -- 'cancelled' and 'declined' can be reached from either 'created' or 'ringing',
  -- so ringing_at is optional for them (NOT condition OR requirement).
  constraint calls_ringing_has_time check (
    (state not in ('ringing','accepted','connected','ended','missed','busy','declined')
     or ringing_at is not null)
    and (state not in ('created','failed')
     or ringing_at is null)
    -- 'expired', 'cancelled' can be reached from either 'created' or 'ringing'
  ),
  constraint calls_accepted_has_time check (
    (state not in ('accepted','connected')
     or accepted_at is not null)
    and (state not in ('created','ringing','missed','busy','cancelled','declined','expired')
     or accepted_at is null)
    -- 'ended' and 'failed' may or may not have accepted_at depending on path
  ),
  constraint calls_connected_has_time check (
    (state <> 'connected' or connected_at is not null)
    and (connected_at is null or accepted_at is not null)
    and (state not in ('created','ringing','accepted','missed','busy','cancelled','declined','expired')
     or connected_at is null)
    -- 'ended' and 'failed' may or may not have connected_at depending on path
  ),
  constraint calls_ended_has_time check (
    (state in ('ended','failed','expired','missed','busy','cancelled','declined'))
    = (ended_at is not null)
  ),
  constraint calls_duration_only_ended check (
    duration_seconds is null or state = 'ended'
  )
);

create index if not exists calls_caller_state_idx
  on public.calls (caller_id, state, created_at desc);
create index if not exists calls_callee_state_idx
  on public.calls (callee_id, state, created_at desc);
create index if not exists calls_room_uidx
  on public.calls (room_name) where state not in ('ended', 'failed', 'expired');
create index if not exists calls_conversation_idx
  on public.calls (conversation_id, created_at desc) where conversation_id is not null;
create index if not exists calls_expire_idx
  on public.calls (created_at, state) where state in ('created', 'ringing');
create unique index if not exists calls_active_pair_uidx
  on public.calls (caller_id, callee_id)
  where state in ('created', 'ringing', 'accepted', 'connected');

-- call_participants: per-participant state within a call
create table if not exists public.call_participants (
  call_id uuid not null references public.calls(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  direction public.call_direction not null,
  joined_at timestamptz,
  left_at timestamptz,
  -- LiveKit-specific
  participant_identity text not null,  -- maps to LiveKit participant identity
  -- tracking
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (call_id, user_id),
  constraint call_participants_identity_length check (
    char_length(participant_identity) between 1 and 200
  ),
  constraint call_participants_left_after_join check (
    left_at is null or (joined_at is not null and left_at >= joined_at)
  )
);

create index if not exists call_participants_user_idx
  on public.call_participants (user_id, created_at desc);

-- call_events: append-only event log for audit and debugging
create table if not exists public.call_events (
  id uuid primary key default gen_random_uuid(),
  call_id uuid not null references public.calls(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  event_type public.call_event_type not null,
  event_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  constraint call_events_metadata_object check (
    jsonb_typeof(metadata) = 'object' and octet_length(metadata::text) <= 65536
  )
);

create index if not exists call_events_call_timeline_idx
  on public.call_events (call_id, event_at, id);
create index if not exists call_events_actor_idx
  on public.call_events (actor_id, event_at desc) where actor_id is not null;

-- Realtime replica identity ----------------------------------------------------
alter table public.calls replica identity full;
alter table public.call_participants replica identity full;
alter table public.call_events replica identity full;
alter table public.call_preferences replica identity full;

-- Realtime publication ---------------------------------------------------------
do $$
declare
  _table text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  foreach _table in array array[
    'calls', 'call_participants', 'call_events', 'call_preferences'
  ] loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = _table
    ) then
      execute format('alter publication supabase_realtime add table public.%I', _table);
    end if;
  end loop;
end
$$;

-- =============================================================================
-- SECURITY DEFINER helper functions
-- =============================================================================

-- Check if user A can call user B (membership + blocks + privacy)
create or replace function public.can_call_user(_caller_id uuid, _callee_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  _prefs public.call_preferences%rowtype;
  _is_contact boolean;
begin
  if _caller_id is null or _callee_id is null or _caller_id = _callee_id then
    return false;
  end if;

  -- Block check (bidirectional)
  if public.is_blocked_pair(_caller_id, _callee_id) then
    return false;
  end if;

  -- Callee exists and is visible
  if not exists (select 1 from public.profiles p where p.id = _callee_id) then
    return false;
  end if;

  -- Callee preferences
  select * into _prefs from public.call_preferences cp where cp.user_id = _callee_id;
  if not found then
    -- No preferences row → default: allow from everyone
    return true;
  end if;

  if not _prefs.allow_calls then
    return false;
  end if;

  -- Do not disturb
  if _prefs.do_not_disturb_until is not null and _prefs.do_not_disturb_until > now() then
    return false;
  end if;

  -- Privacy level
  case _prefs.allow_calls_from
    when 'nobody' then
      return false;
    when 'everyone' then
      return true;
    when 'contacts' then
      _is_contact := exists (
        select 1
        from public.contacts c
        where c.status = 'accepted'
          and (
            (c.requester_id = _caller_id and c.addressee_id = _callee_id)
            or (c.requester_id = _callee_id and c.addressee_id = _caller_id)
          )
      );
      return _is_contact;
    else
      return false;
  end case;
end;
$$;

-- Check if a user is a participant in a call
create or replace function public.is_call_participant(_call_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(exists (
    select 1
    from public.call_participants cp
    where cp.call_id = _call_id
      and cp.user_id = (select auth.uid())
  ), false);
$$;

-- Check if a user is either caller or callee of a call
create or replace function public.is_call_party(_call_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(exists (
    select 1
    from public.calls c
    where c.id = _call_id
      and (c.caller_id = (select auth.uid()) or c.callee_id = (select auth.uid()))
  ), false);
$$;

-- Check if callee has an active call (for busy detection)
create or replace function public.user_has_active_call(_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(exists (
    select 1
    from public.calls c
    where (c.caller_id = _user_id or c.callee_id = _user_id)
      and c.state in ('ringing', 'accepted', 'connected')
  ), false);
$$;

-- Get call rate limit (max calls per window)
create or replace function public.get_call_rate_limit()
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$ select 30; $$;  -- 30 calls per 5-minute window

-- Check and increment rate limit for outbound calls
create or replace function public.check_call_rate_limit(_caller_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _max_calls integer := public.get_call_rate_limit();
  _window_seconds integer := 300;  -- 5 minutes
  _row public.call_rate_limits%rowtype;
begin
  if _caller_id is null then
    return false;
  end if;

  select * into _row
  from public.call_rate_limits
  where user_id = _caller_id
  for update;

  if not found then
    insert into public.call_rate_limits (user_id, window_start, call_count)
    values (_caller_id, now(), 1)
    on conflict (user_id) do update
      set call_count = public.call_rate_limits.call_count + 1,
          window_start = now()
    where public.call_rate_limits.user_id = _caller_id;
    return true;
  end if;

  -- Check if window has elapsed
  if _row.window_start < now() - (_window_seconds || ' seconds')::interval then
    -- Reset window
    update public.call_rate_limits
    set window_start = now(), call_count = 1
    where user_id = _caller_id;
    return true;
  end if;

  -- Within window — check limit
  if _row.call_count >= _max_calls then
    return false;
  end if;

  -- Increment
  update public.call_rate_limits
  set call_count = call_count + 1
  where user_id = _caller_id;

  return true;
end;
$$;

-- Register a call device token (FCM + optional VoIP)
create or replace function public.register_call_device(
  _platform public.device_platform,
  _fcm_token text,
  _voip_token text default null,
  _device_name text default null,
  _app_version text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _me uuid := auth.uid();
  _device_id uuid;
begin
  if _me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if _fcm_token is null or btrim(_fcm_token) = '' then
    raise exception 'FCM token is required' using errcode = '22004';
  end if;

  insert into public.call_devices (
    user_id, platform, fcm_token, voip_token, device_name, app_version, last_seen_at, disabled_at
  ) values (
    _me, _platform, btrim(_fcm_token),
    case when _voip_token is not null then btrim(_voip_token) else null end,
    nullif(btrim(_device_name), ''), nullif(btrim(_app_version), ''),
    now(), null
  )
  on conflict (fcm_token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        voip_token = excluded.voip_token,
        device_name = excluded.device_name,
        app_version = excluded.app_version,
        last_seen_at = now(),
        disabled_at = null
  returning id into _device_id;

  return _device_id;
end;
$$;

-- Set call preferences (upsert)
create or replace function public.set_call_preferences(
  _allow_calls boolean default null,
  _allow_calls_from text default null,
  _ringtone_enabled boolean default null,
  _vibrate_enabled boolean default null,
  _do_not_disturb_until timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _me uuid := auth.uid();
begin
  if _me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if _allow_calls_from is not null and _allow_calls_from not in ('everyone', 'contacts', 'nobody') then
    raise exception 'allow_calls_from must be one of: everyone, contacts, nobody' using errcode = '22023';
  end if;

  insert into public.call_preferences (user_id, allow_calls, allow_calls_from, ringtone_enabled, vibrate_enabled, do_not_disturb_until)
  values (_me,
    coalesce(_allow_calls, true),
    coalesce(_allow_calls_from, 'contacts'),
    coalesce(_ringtone_enabled, true),
    coalesce(_vibrate_enabled, true),
    _do_not_disturb_until
  )
  on conflict (user_id) do update
    set allow_calls = coalesce(_allow_calls, public.call_preferences.allow_calls),
        allow_calls_from = coalesce(_allow_calls_from, public.call_preferences.allow_calls_from),
        ringtone_enabled = coalesce(_ringtone_enabled, public.call_preferences.ringtone_enabled),
        vibrate_enabled = coalesce(_vibrate_enabled, public.call_preferences.vibrate_enabled),
        do_not_disturb_until = _do_not_disturb_until,
        updated_at = now();
end;
$$;

-- Ensure call_preferences row exists for a user (trigger on profiles insert)
create or replace function public.ensure_call_preferences()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.call_preferences (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

-- =============================================================================
-- TRIGGER functions (guard writes)
-- =============================================================================

create or replace function public.guard_call_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _actor uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    -- Caller must be the authenticated user
    if _actor is not null then
      new.caller_id := _actor;
    end if;
    new.created_at := now();
    new.state := 'created';

    -- No self-call
    if new.caller_id = new.callee_id then
      raise exception 'Cannot call yourself' using errcode = '22023';
    end if;

    -- Rate limit
    if not public.check_call_rate_limit(new.caller_id) then
      raise exception 'Call rate limit exceeded' using errcode = '42901';
    end if;

  elsif tg_op = 'UPDATE' then
    -- Identity fields immutable
    if new.id <> old.id
       or new.caller_id <> old.caller_id
       or new.callee_id <> old.callee_id
       or new.room_name <> old.room_name
       or new.created_at <> old.created_at then
      raise exception 'Call identity fields are immutable' using errcode = '42501';
    end if;

    -- Only caller or callee can update
    if _actor is not null and _actor <> new.caller_id and _actor <> new.callee_id then
      raise exception 'Only call parties can update call state' using errcode = '42501';
    end if;

    -- State transition validation
    if new.state <> old.state then
      -- Only service_role or trigger can make these transitions
      -- (Edge functions use service_role key)
      if current_setting('role', true) <> 'service_role'
         and _actor is not null then
        -- Authenticated users can only: cancel (created→cancelled),
        -- decline (ringing→declined), accept (ringing→accepted)
        if not (
          (old.state = 'created' and new.state = 'cancelled')
          or (old.state in ('created','ringing') and new.state = 'declined')
          or (old.state = 'ringing' and new.state = 'accepted')
          or (old.state = 'accepted' and new.state = 'connected')
          or (old.state in ('connected','accepted') and new.state = 'ended')
        ) then
          raise exception 'Invalid state transition from % to %',
            old.state::text, new.state::text using errcode = '42501';
        end if;
      end if;

      -- Set timestamps based on transition
      if new.state = 'ringing' and old.state = 'created' then
        new.ringing_at := now();
      elsif new.state = 'accepted' and old.state = 'ringing' then
        new.accepted_at := now();
      elsif new.state = 'connected' and old.state = 'accepted' then
        new.connected_at := now();
      elsif new.state in ('ended','failed','expired') then
        new.ended_at := now();
        if new.connected_at is not null then
          new.duration_seconds := extract(epoch from (now() - new.connected_at))::integer;
        end if;
      elsif new.state = 'missed' then
        new.ended_at := now();
      elsif new.state = 'busy' then
        new.ended_at := now();
      elsif new.state = 'cancelled' then
        new.ended_at := now();
      elsif new.state = 'declined' then
        new.ended_at := now();
      end if;
    end if;
  end if;

  return new;
end;
$$;

create or replace function public.guard_call_participant_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _actor uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    -- User must be a party to the call
    if _actor is not null then
      new.user_id := _actor;
    end if;
    if not exists (
      select 1 from public.calls c
      where c.id = new.call_id
        and (c.caller_id = new.user_id or c.callee_id = new.user_id)
    ) then
      raise exception 'Participant must be a call party' using errcode = '42501';
    end if;
    new.created_at := now();
  elsif tg_op = 'UPDATE' then
    if new.call_id <> old.call_id or new.user_id <> old.user_id
       or new.participant_identity <> old.participant_identity
       or new.direction <> old.direction then
      raise exception 'Call participant identity fields are immutable' using errcode = '42501';
    end if;
    if _actor is not null and new.user_id <> _actor
       and current_setting('role', true) <> 'service_role' then
      raise exception 'Only the participant or service role can update' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.guard_call_event_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    new.event_at := now();
  end if;
  return new;
end;
$$;

create or replace function public.guard_call_preferences_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _actor uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    if _actor is not null then
      new.user_id := _actor;
    end if;
    new.created_at := now();
  elsif tg_op = 'UPDATE' then
    if new.user_id <> old.user_id or new.created_at <> old.created_at then
      raise exception 'Call preferences identity fields are immutable' using errcode = '42501';
    end if;
    if _actor is not null and new.user_id <> _actor
       and current_setting('role', true) <> 'service_role' then
      raise exception 'Can only update own call preferences' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.guard_call_device_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _actor uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    if _actor is not null then
      new.user_id := _actor;
    end if;
    new.created_at := now();
  elsif tg_op = 'UPDATE' then
    if new.id <> old.id or new.created_at <> old.created_at then
      raise exception 'Call device identity fields are immutable' using errcode = '42501';
    end if;
    if new.user_id <> old.user_id
       and (_actor is null or new.user_id <> _actor or new.fcm_token <> old.fcm_token) then
      raise exception 'A call device token may only be reassigned to the authenticated user' using errcode = '42501';
    end if;
  end if;

  new.fcm_token := btrim(new.fcm_token);
  new.voip_token := case when new.voip_token is not null then btrim(new.voip_token) else null end;
  new.device_name := nullif(btrim(new.device_name), '');
  new.app_version := nullif(btrim(new.app_version), '');
  new.last_seen_at := now();
  if tg_op = 'UPDATE' and new.disabled_at is not null and old.disabled_at is null then
    new.disabled_at := now();
  end if;
  return new;
end;
$$;

-- =============================================================================
-- TRIGGER installation
-- =============================================================================
drop trigger if exists set_updated_at on public.call_preferences;
create trigger set_updated_at
before insert or update on public.call_preferences
for each row execute function public.set_updated_at();

drop trigger if exists guard_call_preferences_write on public.call_preferences;
create trigger guard_call_preferences_write
before insert or update on public.call_preferences
for each row execute function public.guard_call_preferences_write();

drop trigger if exists set_updated_at on public.call_devices;
create trigger set_updated_at
before insert or update on public.call_devices
for each row execute function public.set_updated_at();

drop trigger if exists guard_call_device_write on public.call_devices;
create trigger guard_call_device_write
before insert or update on public.call_devices
for each row execute function public.guard_call_device_write();

drop trigger if exists set_updated_at on public.calls;
create trigger set_updated_at
before insert or update on public.calls
for each row execute function public.set_updated_at();

drop trigger if exists guard_call_write on public.calls;
create trigger guard_call_write
before insert or update on public.calls
for each row execute function public.guard_call_write();

drop trigger if exists set_updated_at on public.call_participants;
create trigger set_updated_at
before insert or update on public.call_participants
for each row execute function public.set_updated_at();

drop trigger if exists guard_call_participant_write on public.call_participants;
create trigger guard_call_participant_write
before insert or update on public.call_participants
for each row execute function public.guard_call_participant_write();

drop trigger if exists guard_call_event_write on public.call_events;
create trigger guard_call_event_write
before insert on public.call_events
for each row execute function public.guard_call_event_write();

-- Ensure call_preferences for new profiles
drop trigger if exists ensure_call_preferences on public.profiles;
create trigger ensure_call_preferences
after insert on public.profiles
for each row execute function public.ensure_call_preferences();

-- =============================================================================
-- RLS
-- =============================================================================
alter table public.calls enable row level security;
alter table public.call_participants enable row level security;
alter table public.call_events enable row level security;
alter table public.call_devices enable row level security;
alter table public.call_preferences enable row level security;
alter table public.call_rate_limits enable row level security;

-- calls: caller or callee can see their calls
drop policy if exists calls_select_party on public.calls;
create policy calls_select_party on public.calls
for select to authenticated
using (caller_id = (select auth.uid()) or callee_id = (select auth.uid()));

drop policy if exists calls_insert_caller on public.calls;
create policy calls_insert_caller on public.calls
for insert to authenticated
with check (caller_id = (select auth.uid()));

drop policy if exists calls_update_party on public.calls;
create policy calls_update_party on public.calls
for update to authenticated
using (caller_id = (select auth.uid()) or callee_id = (select auth.uid()))
with check (caller_id = (select auth.uid()) or callee_id = (select auth.uid()));

-- call_participants: participant can see their rows
drop policy if exists call_participants_select_party on public.call_participants;
create policy call_participants_select_party on public.call_participants
for select to authenticated
using (
  user_id = (select auth.uid())
  or exists (
    select 1 from public.calls c
    where c.id = call_id
      and (c.caller_id = (select auth.uid()) or c.callee_id = (select auth.uid()))
  )
);

drop policy if exists call_participants_insert_self on public.call_participants;
create policy call_participants_insert_self on public.call_participants
for insert to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists call_participants_update_self on public.call_participants;
create policy call_participants_update_self on public.call_participants
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

-- call_events: call parties can read events for their calls
drop policy if exists call_events_select_party on public.call_events;
create policy call_events_select_party on public.call_events
for select to authenticated
using (
  actor_id = (select auth.uid())
  or exists (
    select 1 from public.calls c
    where c.id = call_id
      and (c.caller_id = (select auth.uid()) or c.callee_id = (select auth.uid()))
  )
);

-- call_events insert: only service_role (edge functions)
-- (no authenticated INSERT policy — events are written by edge functions with service key)

-- call_devices: self only
drop policy if exists call_devices_select_self on public.call_devices;
create policy call_devices_select_self on public.call_devices
for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists call_devices_insert_self on public.call_devices;
create policy call_devices_insert_self on public.call_devices
for insert to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists call_devices_update_self on public.call_devices;
create policy call_devices_update_self on public.call_devices
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists call_devices_delete_self on public.call_devices;
create policy call_devices_delete_self on public.call_devices
for delete to authenticated
using (user_id = (select auth.uid()));

-- call_preferences: self only
drop policy if exists call_preferences_select_self on public.call_preferences;
create policy call_preferences_select_self on public.call_preferences
for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists call_preferences_insert_self on public.call_preferences;
create policy call_preferences_insert_self on public.call_preferences
for insert to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists call_preferences_update_self on public.call_preferences;
create policy call_preferences_update_self on public.call_preferences
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

-- call_rate_limits: no direct access for authenticated (managed by RPC only)
-- (RLS enabled but no policy = no access for authenticated)

-- =============================================================================
-- GRANTS
-- =============================================================================
revoke all on
  public.calls, public.call_participants, public.call_events,
  public.call_devices, public.call_preferences, public.call_rate_limits
from public, anon, authenticated;

grant all on
  public.calls, public.call_participants, public.call_events,
  public.call_devices, public.call_preferences, public.call_rate_limits
to service_role;

grant select on
  public.calls, public.call_participants, public.call_events,
  public.call_devices, public.call_preferences
to authenticated, service_role;

grant insert on
  public.calls, public.call_participants, public.call_devices, public.call_preferences
to authenticated, service_role;

grant update on
  public.calls, public.call_participants, public.call_devices, public.call_preferences
to authenticated, service_role;

grant delete on
  public.call_devices
to authenticated, service_role;

-- Function grants
-- Start closed (revoke default EXECUTE)
do $$
declare
  _function regprocedure;
begin
  for _function in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname::text = any (array[
        'can_call_user', 'is_call_participant', 'is_call_party',
        'user_has_active_call', 'get_call_rate_limit', 'check_call_rate_limit',
        'register_call_device', 'set_call_preferences',
        'ensure_call_preferences',
        'guard_call_write', 'guard_call_participant_write',
        'guard_call_event_write', 'guard_call_preferences_write',
        'guard_call_device_write'
      ]::text[])
  loop
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      _function
    );
  end loop;
end $$;

-- Allow-list: public helpers callable by authenticated
grant execute on function public.can_call_user(uuid, uuid) to authenticated, service_role;
grant execute on function public.is_call_participant(uuid) to authenticated, service_role;
grant execute on function public.is_call_party(uuid) to authenticated, service_role;
grant execute on function public.user_has_active_call(uuid) to authenticated, service_role;
grant execute on function public.register_call_device(public.device_platform, text, text, text, text) to authenticated, service_role;
grant execute on function public.set_call_preferences(boolean, text, boolean, boolean, timestamptz) to authenticated, service_role;

-- Service-only functions (edge functions use service_role key)
grant execute on function public.check_call_rate_limit(uuid) to service_role;
grant execute on function public.get_call_rate_limit() to service_role;

-- =============================================================================
-- expire_stale_calls RPC (service-role callable)
-- Defined before pg_cron scheduling so the function exists when the job is
-- registered within the same transaction.
-- =============================================================================
create or replace function public.expire_stale_calls()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _expired integer := 0;
  _ringing_timeout_seconds integer := 45;  -- call rings for max 45s
  _created_timeout_seconds integer := 90;  -- created but not ringing within 90s
begin
  -- Expire calls stuck in 'ringing' beyond timeout
  with stale as (
    select c.id
    from public.calls c
    where c.state = 'ringing'
      and c.ringing_at < now() - (_ringing_timeout_seconds || ' seconds')::interval
    order by c.ringing_at, c.id
    for update skip locked
    limit 200
  )
  update public.calls c
  set state = 'expired', ended_at = now(), end_reason = 'ringing_timeout'
  from stale
  where c.id = stale.id;

  get diagnostics _expired = row_count;

  -- Expire calls stuck in 'created' beyond timeout
  with stale as (
    select c.id
    from public.calls c
    where c.state = 'created'
      and c.created_at < now() - (_created_timeout_seconds || ' seconds')::interval
    order by c.created_at, c.id
    for update skip locked
    limit 200
  )
  update public.calls c
  set state = 'expired', ended_at = now(), end_reason = 'created_timeout'
  from stale
  where c.id = stale.id;

  get diagnostics _expired = row_count;

  return _expired;
end;
$$;

-- Revoke default EXECUTE and grant to service_role only
revoke all on function public.expire_stale_calls() from public, anon, authenticated;
grant execute on function public.expire_stale_calls() to service_role;

-- =============================================================================
-- Optional pg_cron: expire stale calls every minute
-- =============================================================================
do $$
begin
  if to_regprocedure('cron.schedule(text,text,text)') is not null then
    execute 'select cron.schedule($1, $2, $3)'
      using
        'vibe-expire-stale-calls',
        '* * * * *',
        'select public.expire_stale_calls();';
  else
    raise notice 'pg_cron is unavailable; external scheduling of expire_stale_calls is required';
  end if;
exception when others then
  raise notice 'pg_cron job for stale calls not installed (%); external scheduling is required', sqlerrm;
end
$$;

commit;
