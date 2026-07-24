-- Verification for 202607240004_calls.sql (calls backend).
-- Safe to execute repeatedly; read-only, does not mutate application data.
-- Run after applying the calls migration:
--   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f supabase/verification_calls.sql
-- Or via Supabase SQL Editor.

begin;

-- 1. Tables, enums, and RLS ----------------------------------------------------
do $$
declare
  _expected_tables constant text[] := array[
    'calls', 'call_participants', 'call_events',
    'call_devices', 'call_preferences', 'call_rate_limits'
  ];
  _table text;
  _enum_values text[];
begin
  foreach _table in array _expected_tables loop
    if to_regclass(format('public.%I', _table)) is null then
      raise exception 'Missing table public.%', _table;
    end if;

    if not exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = _table
        and c.relkind in ('r', 'p')
        and c.relrowsecurity
    ) then
      raise exception 'RLS is not enabled on public.%', _table;
    end if;

    if not exists (
      select 1
      from pg_policies p
      where p.schemaname = 'public' and p.tablename = _table
    ) and _table <> 'call_rate_limits' then
      raise exception 'No RLS policy found for public.%', _table;
    end if;
  end loop;

  -- call_rate_limits should have RLS enabled but NO policy (no direct access)
  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'call_rate_limits'
      and c.relrowsecurity
  ) then
    raise exception 'RLS is not enabled on public.call_rate_limits';
  end if;

  if exists (
    select 1
    from pg_policies p
    where p.schemaname = 'public' and p.tablename = 'call_rate_limits'
  ) then
    raise exception 'call_rate_limits must not expose any RLS policy (RPC-only access)';
  end if;

  -- Verify call_state enum values
  select array_agg(e.enumlabel order by e.enumsortorder)
    into _enum_values
  from pg_type t
  join pg_namespace n on n.oid = t.typnamespace
  join pg_enum e on e.enumtypid = t.oid
  where n.nspname = 'public' and t.typname = 'call_state';

  if _enum_values is distinct from array[
    'created', 'ringing', 'accepted', 'connected',
    'declined', 'cancelled', 'missed', 'busy',
    'ended', 'failed', 'expired'
  ]::text[] then
    raise exception 'Unexpected call_state values: %', _enum_values;
  end if;

  -- Verify call_media_kind enum
  select array_agg(e.enumlabel order by e.enumsortorder)
    into _enum_values
  from pg_type t
  join pg_namespace n on n.oid = t.typnamespace
  join pg_enum e on e.enumtypid = t.oid
  where n.nspname = 'public' and t.typname = 'call_media_kind';

  if _enum_values is distinct from array['audio', 'video']::text[] then
    raise exception 'Unexpected call_media_kind values: %', _enum_values;
  end if;

  -- Verify call_event_type enum
  select array_agg(e.enumlabel order by e.enumsortorder)
    into _enum_values
  from pg_type t
  join pg_namespace n on n.oid = t.typnamespace
  join pg_enum e on e.enumtypid = t.oid
  where n.nspname = 'public' and t.typname = 'call_event_type';

  if _enum_values is distinct from array[
    'created', 'ringing', 'accepted', 'connected',
    'declined', 'cancelled', 'missed', 'busy',
    'ended', 'failed', 'expired',
    'participant_joined', 'participant_left'
  ]::text[] then
    raise exception 'Unexpected call_event_type values: %', _enum_values;
  end if;

  -- Verify call_direction enum
  select array_agg(e.enumlabel order by e.enumsortorder)
    into _enum_values
  from pg_type t
  join pg_namespace n on n.oid = t.typnamespace
  join pg_enum e on e.enumtypid = t.oid
  where n.nspname = 'public' and t.typname = 'call_direction';

  if _enum_values is distinct from array['outgoing', 'incoming']::text[] then
    raise exception 'Unexpected call_direction values: %', _enum_values;
  end if;
end
$$;

-- 2. Critical constraints ------------------------------------------------------
do $$
declare
  _constraint text;
  _table_name text;
begin
  foreach _constraint in array array[
    'calls.calls_no_self',
    'calls.calls_room_name_length',
    'calls.calls_metadata_object',
    'calls.calls_duration_nonneg',
    'calls.calls_ring_after_create',
    'calls.calls_accept_after_ring',
    'calls.calls_connect_after_accept',
    'calls.calls_end_after_create',
    'calls.calls_ringing_has_time',
    'calls.calls_accepted_has_time',
    'calls.calls_connected_has_time',
    'calls.calls_ended_has_time',
    'calls.calls_duration_only_ended',
    'call_participants.call_participants_left_after_join',
    'call_devices.call_devices_token_length'
  ] loop
    _table_name := split_part(_constraint, '.', 1);
    if not exists (
      select 1 from pg_constraint c
      where c.conrelid = format('public.%I', _table_name)::regclass
        and c.conname = split_part(_constraint, '.', 2)
        and c.convalidated
    ) then
      raise exception 'Missing or unvalidated constraint public.%', _constraint;
    end if;
  end loop;
end
$$;

-- 3. Indexes -------------------------------------------------------------------
do $$
declare
  _index text;
  _table_name text;
begin
  foreach _index in array array[
    'calls.calls_caller_state_idx',
    'calls.calls_callee_state_idx',
    'calls.calls_room_uidx',
    'calls.calls_conversation_idx',
    'calls.calls_expire_idx',
    'calls.calls_active_pair_uidx',
    'call_participants.call_participants_user_idx',
    'call_events.call_events_call_timeline_idx',
    'call_events.call_events_actor_idx',
    'call_devices.call_devices_user_active_idx'
  ] loop
    _table_name := split_part(_index, '.', 1);
    if not exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = split_part(_index, '.', 2)
        and c.relkind in ('i', 'I')
    ) then
      raise exception 'Missing index %', _index;
    end if;
  end loop;

  -- Verify call_devices unique constraint on fcm_token
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.call_devices'::regclass
      and contype = 'u'
  ) then
    raise exception 'call_devices missing unique constraint on fcm_token';
  end if;
end
$$;

-- 4. Triggers ------------------------------------------------------------------
do $$
declare
  _trigger_spec text;
  _schema_name text;
  _table_name text;
  _trigger_name text;
begin
  foreach _trigger_spec in array array[
    'public.calls.guard_call_write',
    'public.calls.set_updated_at',
    'public.call_participants.guard_call_participant_write',
    'public.call_participants.set_updated_at',
    'public.call_events.guard_call_event_write',
    'public.call_devices.guard_call_device_write',
    'public.call_devices.set_updated_at',
    'public.call_preferences.guard_call_preferences_write',
    'public.call_preferences.set_updated_at',
    'public.profiles.ensure_call_preferences'
  ] loop
    _schema_name := split_part(_trigger_spec, '.', 1);
    _table_name := split_part(_trigger_spec, '.', 2);
    _trigger_name := split_part(_trigger_spec, '.', 3);
    if not exists (
      select 1
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = _schema_name
        and c.relname = _table_name
        and t.tgname = _trigger_name
        and not t.tgisinternal
        and t.tgenabled <> 'D'
    ) then
      raise exception 'Missing or disabled trigger %.%.%', _schema_name, _table_name, _trigger_name;
    end if;
  end loop;
end
$$;

-- 5. RPC surface and grants ----------------------------------------------------
do $$
declare
  _function regprocedure;
  _internal_function regprocedure;
begin
  -- Functions that authenticated should have EXECUTE on
  foreach _function in array array[
    'public.can_call_user(uuid,uuid)'::regprocedure,
    'public.is_call_participant(uuid)'::regprocedure,
    'public.is_call_party(uuid)'::regprocedure,
    'public.user_has_active_call(uuid)'::regprocedure,
    'public.register_call_device(public.device_platform,text,text,text,text)'::regprocedure,
    'public.set_call_preferences(boolean,text,boolean,boolean,timestamptz)'::regprocedure
  ] loop
    if not has_function_privilege('authenticated', _function, 'EXECUTE') then
      raise exception 'authenticated lacks EXECUTE on %', _function;
    end if;
    if has_function_privilege('anon', _function, 'EXECUTE') then
      raise exception 'anon unexpectedly has EXECUTE on %', _function;
    end if;
  end loop;

  -- Functions that only service_role should have EXECUTE on
  foreach _function in array array[
    'public.check_call_rate_limit(uuid)'::regprocedure,
    'public.get_call_rate_limit()'::regprocedure,
    'public.expire_stale_calls()'::regprocedure
  ] loop
    if not has_function_privilege('service_role', _function, 'EXECUTE') then
      raise exception 'service_role lacks EXECUTE on %', _function;
    end if;
    if has_function_privilege('authenticated', _function, 'EXECUTE') then
      raise exception 'authenticated unexpectedly has EXECUTE on service-only %', _function;
    end if;
  end loop;

  -- Trigger / internal functions must NOT be executable by API roles
  foreach _internal_function in array array[
    'public.guard_call_write()'::regprocedure,
    'public.guard_call_participant_write()'::regprocedure,
    'public.guard_call_event_write()'::regprocedure,
    'public.guard_call_preferences_write()'::regprocedure,
    'public.guard_call_device_write()'::regprocedure,
    'public.ensure_call_preferences()'::regprocedure
  ] loop
    if has_function_privilege('authenticated', _internal_function, 'EXECUTE')
       or has_function_privilege('anon', _internal_function, 'EXECUTE') then
      raise exception 'Internal function % is executable by an API role', _internal_function;
    end if;
  end loop;

  -- All SECURITY DEFINER functions must have a fixed search_path
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and p.proname ~ '^can_call_user|^is_call|^user_has_active|^check_call_rate|^get_call_rate|^register_call_device|^set_call_preferences|^ensure_call_preferences|^expire_stale_calls|^guard_call'
      and not exists (
        select 1 from unnest(coalesce(p.proconfig, array[]::text[])) cfg
        where cfg like 'search_path=%'
      )
  ) then
    raise exception 'A SECURITY DEFINER call function lacks a fixed search_path';
  end if;
end
$$;

-- 6. Table grants --------------------------------------------------------------
do $$
declare
  _table text;
begin
  foreach _table in array array[
    'calls', 'call_participants', 'call_events',
    'call_devices', 'call_preferences'
  ] loop
    if has_table_privilege('anon', format('public.%I', _table), 'SELECT') then
      raise exception 'anon unexpectedly has SELECT on public.%', _table;
    end if;
    if not has_table_privilege('authenticated', format('public.%I', _table), 'SELECT') then
      raise exception 'authenticated lacks SELECT on public.%', _table;
    end if;
  end loop;

  -- call_events should NOT have INSERT/UPDATE/DELETE for authenticated (service-only)
  if has_table_privilege('authenticated', 'public.call_events', 'INSERT') then
    raise exception 'authenticated should not have INSERT on call_events (service-only)';
  end if;
  if has_table_privilege('authenticated', 'public.call_events', 'UPDATE') then
    raise exception 'authenticated should not have UPDATE on call_events';
  end if;

  -- call_rate_limits should have NO direct access for authenticated
  if has_table_privilege('authenticated', 'public.call_rate_limits', 'SELECT') then
    raise exception 'authenticated should not have SELECT on call_rate_limits (RPC-only)';
  end if;
end
$$;

-- 7. Realtime publication ------------------------------------------------------
do $$
declare
  _table text;
  _expected_realtime constant text[] := array[
    'calls', 'call_participants', 'call_events', 'call_preferences'
  ];
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise exception 'Publication supabase_realtime is missing';
  end if;

  foreach _table in array _expected_realtime loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = _table
    ) then
      raise exception 'public.% is missing from supabase_realtime', _table;
    end if;

    if not exists (
      select 1
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname = _table
        and c.relreplident = 'f'
    ) then
      raise exception 'public.% does not use REPLICA IDENTITY FULL', _table;
    end if;
  end loop;
end
$$;

-- 8. pg_cron job (if pg_cron is available) -------------------------------------
do $$
begin
  if to_regprocedure('cron.schedule(text,text,text)') is not null then
    if not exists (
      select 1
      from cron.job
      where jobname = 'vibe-expire-stale-calls'
    ) then
      raise exception 'pg_cron job vibe-expire-stale-calls is missing';
    end if;
  else
    raise notice 'pg_cron is unavailable; external scheduling of expire_stale_calls is required';
  end if;
end
$$;

-- 9. Summary report ------------------------------------------------------------
select
  c.relname as relation,
  c.relrowsecurity as rls_enabled,
  count(p.policyname) as policy_count
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_policies p on p.schemaname = n.nspname and p.tablename = c.relname
where n.nspname = 'public'
  and c.relname in ('calls', 'call_participants', 'call_events',
                    'call_devices', 'call_preferences', 'call_rate_limits')
  and c.relkind = 'r'
group by c.relname, c.relrowsecurity
order by c.relname;

commit;
