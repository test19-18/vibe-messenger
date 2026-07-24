-- Vibe Messenger post-migration verification.
-- Run after 202607240001_initial_schema.sql in Supabase SQL Editor or with:
--   psql -v ON_ERROR_STOP=1 "$DATABASE_URL" -f supabase/verification.sql
-- The script is read-only and raises on a missing/unsafe schema object.

begin;

-- 1. Tables, columns, enums and RLS -------------------------------------------
do $$
declare
  _expected_tables constant text[] := array[
    'profiles', 'contacts', 'user_blocks', 'conversations',
    'conversation_members', 'messages', 'message_attachments',
    'message_reactions', 'conversation_read_receipts', 'conversation_typing',
    'message_pins', 'conversation_user_settings', 'chat_folders',
    'chat_folder_conversations', 'user_settings', 'user_presence',
    'user_devices', 'reports', 'group_invitations', 'group_join_requests',
    'polls', 'poll_options', 'poll_votes'
  ];
  _table text;
  _column text;
  _enum_values text[];
begin
  if to_regprocedure('extensions.digest(text,text)') is null
     or to_regprocedure('extensions.gen_random_bytes(integer)') is null then
    raise exception 'pgcrypto is not available in schema extensions';
  end if;

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
    ) then
      raise exception 'No RLS policy found for public.%', _table;
    end if;

    if exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = _table and column_name = 'updated_at'
    ) and not exists (
      select 1
      from pg_trigger t
      where t.tgrelid = format('public.%I', _table)::regclass
        and t.tgname = 'set_updated_at'
        and not t.tgisinternal
        and t.tgenabled <> 'D'
    ) then
      raise exception 'set_updated_at trigger is missing on public.%', _table;
    end if;
  end loop;

  foreach _column in array array[
    'id', 'username', 'display_name', 'avatar_path', 'bio',
    'created_at', 'updated_at'
  ] loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'profiles' and column_name = _column
    ) then
      raise exception 'Flutter contract column profiles.% is missing', _column;
    end if;
  end loop;

  foreach _column in array array['user_id', 'last_seen_at', 'online_until'] loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'user_presence' and column_name = _column
    ) then
      raise exception 'Flutter presence column user_presence.% is missing', _column;
    end if;
  end loop;

  foreach _column in array array[
    'id', 'conversation_id', 'sender_id', 'body', 'reply_to_message_id',
    'edited_at', 'deleted_at', 'created_at'
  ] loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema = 'public' and table_name = 'messages' and column_name = _column
    ) then
      raise exception 'Flutter contract column messages.% is missing', _column;
    end if;
  end loop;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.conversation_members'::regclass
      and conname = 'conversation_members_user_id_fkey'
      and contype = 'f'
  ) then
    raise exception 'Expected PostgREST relation conversation_members_user_id_fkey is missing';
  end if;

  select array_agg(e.enumlabel order by e.enumsortorder)
    into _enum_values
  from pg_type t
  join pg_namespace n on n.oid = t.typnamespace
  join pg_enum e on e.enumtypid = t.oid
  where n.nspname = 'public' and t.typname = 'conversation_kind';

  if _enum_values is distinct from array['direct', 'group', 'channel']::text[] then
    raise exception 'Unexpected conversation_kind values: %', _enum_values;
  end if;
end
$$;

-- 2. Critical FK/check constraints and triggers -------------------------------
do $$
declare
  _constraint text;
  _trigger_spec text;
  _schema_name text;
  _table_name text;
  _trigger_name text;
begin
  foreach _constraint in array array[
    'conversations.conversations_shape',
    'conversations.conversations_last_message_fk',
    'conversation_members.conversation_members_left_at',
    'messages.messages_reply_conversation_fk',
    'message_attachments.message_attachments_message_conversation_fk',
    'conversation_read_receipts.conversation_read_receipts_message_fk',
    'message_pins.message_pins_message_conversation_fk',
    'reports.reports_at_most_one_target',
    'reports.reports_resolution_shape',
    'group_invitations.group_invitations_response_shape',
    'group_join_requests.group_join_requests_response_shape',
    'polls.polls_message_conversation_fk',
    'poll_options.poll_options_poll_conversation_fk',
    'poll_votes.poll_votes_poll_conversation_fk',
    'poll_votes.poll_votes_option_poll_conversation_fk'
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

  foreach _trigger_spec in array array[
    'public.profiles.guard_profile_write',
    'public.profiles.profile_deletion_cleanup',
    'public.contacts.guard_contact_write',
    'public.conversations.guard_conversation_write',
    'public.conversations.validate_conversation_shape_from_conversation',
    'public.conversation_members.guard_conversation_member_write',
    'public.conversation_members.validate_conversation_shape_from_member',
    'public.messages.guard_message_write',
    'public.messages.sync_conversation_last_message',
    'public.messages.validate_poll_message_from_message',
    'public.message_attachments.guard_attachment_write',
    'public.message_reactions.guard_reaction_write',
    'public.conversation_read_receipts.guard_read_receipt_write',
    'public.conversation_typing.guard_typing_write',
    'public.user_presence.guard_presence_write',
    'public.user_devices.guard_device_write',
    'public.conversation_user_settings.guard_conversation_user_settings_write',
    'public.user_settings.guard_user_settings_write',
    'public.chat_folders.guard_chat_folder_write',
    'public.chat_folder_conversations.guard_folder_conversation_write',
    'public.reports.guard_report_write',
    'public.group_invitations.guard_invitation_write',
    'public.group_invitations.apply_accepted_invitation',
    'public.group_join_requests.guard_join_request_write',
    'public.group_join_requests.apply_approved_join_request',
    'public.polls.guard_poll_write',
    'public.polls.validate_poll_message_from_poll',
    'public.polls.validate_poll_options_from_poll',
    'public.poll_options.guard_poll_option_write',
    'public.poll_options.validate_poll_options_from_option',
    'public.poll_votes.guard_poll_vote_write',
    'public.poll_votes.sync_poll_vote_count',
    'auth.users.on_auth_user_created'
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

-- 3. RPC surface and grants ----------------------------------------------------
do $$
declare
  _table text;
  _function regprocedure;
  _internal_function regprocedure;
  _expected_tables constant text[] := array[
    'profiles', 'contacts', 'user_blocks', 'conversations',
    'conversation_members', 'messages', 'message_attachments',
    'message_reactions', 'conversation_read_receipts', 'conversation_typing',
    'message_pins', 'conversation_user_settings', 'chat_folders',
    'chat_folder_conversations', 'user_settings', 'user_presence',
    'user_devices', 'reports', 'group_invitations', 'group_join_requests',
    'polls', 'poll_options', 'poll_votes'
  ];
begin
  if has_schema_privilege('anon', 'public', 'USAGE') then
    raise exception 'anon unexpectedly has USAGE on schema public';
  end if;
  if not has_schema_privilege('authenticated', 'public', 'USAGE') then
    raise exception 'authenticated lacks USAGE on schema public';
  end if;
  if has_schema_privilege('authenticated', 'public', 'CREATE')
     or has_schema_privilege('service_role', 'public', 'CREATE') then
    raise exception 'An API role unexpectedly has CREATE on schema public';
  end if;

  foreach _table in array _expected_tables loop
    if has_table_privilege('anon', format('public.%I', _table), 'SELECT,INSERT,UPDATE,DELETE') then
      raise exception 'anon unexpectedly has table privileges on public.%', _table;
    end if;
    if not has_table_privilege('authenticated', format('public.%I', _table), 'SELECT') then
      raise exception 'authenticated lacks SELECT on public.%', _table;
    end if;
  end loop;

  if has_table_privilege('authenticated', 'public.conversations', 'INSERT')
     or has_table_privilege('authenticated', 'public.conversation_members', 'INSERT')
     or has_table_privilege('authenticated', 'public.polls', 'INSERT')
     or has_table_privilege('authenticated', 'public.poll_options', 'INSERT') then
    raise exception 'RPC-only tables expose direct INSERT to authenticated';
  end if;
  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'conversation_members'
      and cmd = 'INSERT'
  ) then
    raise exception 'conversation_members must not expose an INSERT policy';
  end if;

  if has_table_privilege('authenticated', 'public.messages', 'DELETE') then
    raise exception 'messages must use soft-delete; authenticated has DELETE';
  end if;
  if has_table_privilege('authenticated', 'public.conversation_read_receipts', 'DELETE') then
    raise exception 'Read-receipt monotonicity can be bypassed through DELETE';
  end if;

  if not has_column_privilege('authenticated', 'public.messages', 'body', 'UPDATE')
     or has_column_privilege('authenticated', 'public.messages', 'sender_id', 'UPDATE') then
    raise exception 'Unexpected messages column UPDATE grants';
  end if;

  foreach _function in array array[
    'public.register_device(public.device_platform,text,text,text)'::regprocedure,
    'public.create_direct_conversation(uuid)'::regprocedure,
    'public.create_group_conversation(text,text)'::regprocedure,
    'public.transfer_conversation_ownership(uuid,uuid)'::regprocedure,
    'public.create_group_invite_link(uuid,timestamptz,integer)'::regprocedure,
    'public.accept_group_invite_token(text)'::regprocedure,
    'public.accept_group_invitation(uuid)'::regprocedure,
    'public.review_group_join_request(uuid,boolean)'::regprocedure,
    'public.create_poll(uuid,text,text[],boolean,smallint,boolean,timestamptz)'::regprocedure,
    'public.get_poll_results(uuid)'::regprocedure
  ] loop
    if not has_function_privilege('authenticated', _function, 'EXECUTE') then
      raise exception 'authenticated lacks EXECUTE on %', _function;
    end if;
    if has_function_privilege('anon', _function, 'EXECUTE') then
      raise exception 'anon unexpectedly has EXECUTE on %', _function;
    end if;
  end loop;

  if to_regprocedure('public.create_group_conversation(text,text,public.conversation_kind)') is not null
     or exists (
       select 1 from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname ~* 'create.*channel|channel.*create'
     ) then
    raise exception 'A user-facing channel creation function must not exist';
  end if;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prorettype = 'pg_catalog.trigger'::regtype
      and (
        has_function_privilege('authenticated', p.oid, 'EXECUTE')
        or has_function_privilege('anon', p.oid, 'EXECUTE')
      )
  ) then
    raise exception 'A public trigger function is executable by an API role';
  end if;

  foreach _internal_function in array array[
    'public.set_updated_at()'::regprocedure,
    'public.guard_profile_write()'::regprocedure,
    'public.guard_conversation_write()'::regprocedure,
    'public.guard_conversation_member_write()'::regprocedure,
    'public.guard_message_write()'::regprocedure,
    'public.guard_attachment_write()'::regprocedure,
    'public.guard_reaction_write()'::regprocedure,
    'public.guard_conversation_user_settings_write()'::regprocedure,
    'public.guard_user_settings_write()'::regprocedure,
    'public.guard_report_write()'::regprocedure,
    'public.guard_poll_vote_write()'::regprocedure,
    'public.handle_new_auth_user()'::regprocedure
  ] loop
    if has_function_privilege('authenticated', _internal_function, 'EXECUTE')
       or has_function_privilege('anon', _internal_function, 'EXECUTE') then
      raise exception 'Internal function % is executable by an API role', _internal_function;
    end if;
  end loop;

  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and not exists (
        select 1 from unnest(coalesce(p.proconfig, array[]::text[])) cfg
        where cfg like 'search_path=%'
      )
  ) then
    raise exception 'A SECURITY DEFINER helper/RPC lacks a fixed search_path';
  end if;
end
$$;

-- 4. Storage ------------------------------------------------------------------
do $$
declare
  _bucket text;
  _policy text;
begin
  foreach _bucket in array array['avatars', 'chat-media', 'voice-messages'] loop
    if not exists (
      select 1 from storage.buckets b
      where b.id = _bucket
        and b.name = _bucket
        and not b.public
        and b.file_size_limit = case _bucket
          when 'avatars' then 10485760
          when 'chat-media' then 104857600
          when 'voice-messages' then 52428800
        end
        and cardinality(b.allowed_mime_types) > 0
    ) then
      raise exception 'Missing or misconfigured private Storage bucket %', _bucket;
    end if;
  end loop;

  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'storage' and c.relname = 'objects' and c.relrowsecurity
  ) then
    raise exception 'RLS is not enabled on storage.objects';
  end if;

  foreach _policy in array array[
    'storage_avatars_select_visible', 'storage_avatars_insert_self',
    'storage_avatars_update_self', 'storage_avatars_delete_self',
    'storage_chat_select_member', 'storage_chat_insert_member',
    'storage_chat_update_uploader', 'storage_chat_delete_uploader'
  ] loop
    if not exists (
      select 1 from pg_policies
      where schemaname = 'storage' and tablename = 'objects' and policyname = _policy
    ) then
      raise exception 'Missing Storage policy %', _policy;
    end if;
  end loop;

  if not public.is_profile_avatar_path(
    '11111111-1111-1111-1111-111111111111/avatar.webp',
    '11111111-1111-1111-1111-111111111111'::uuid
  ) then
    raise exception 'Profile avatar path helper rejected a valid path';
  end if;

  if public.is_profile_avatar_path(
    '11111111-1111-1111-1111-111111111111/..',
    '11111111-1111-1111-1111-111111111111'::uuid
  ) then
    raise exception 'Profile avatar path helper accepted traversal';
  end if;

  if not public.is_conversation_object_path(
    '11111111-1111-1111-1111-111111111111/22222222-2222-2222-2222-222222222222/file.bin',
    '11111111-1111-1111-1111-111111111111'::uuid,
    '22222222-2222-2222-2222-222222222222'::uuid
  ) then
    raise exception 'Conversation object path helper rejected a valid path';
  end if;
end
$$;

-- 5. Realtime publication -----------------------------------------------------
do $$
declare
  _table text;
  _expected_realtime constant text[] := array[
    'conversations', 'conversation_members', 'messages', 'message_attachments', 'message_reactions',
    'conversation_read_receipts', 'conversation_typing', 'message_pins',
    'conversation_user_settings', 'user_presence', 'group_invitations',
    'group_join_requests', 'polls', 'poll_options', 'poll_votes'
  ];
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    raise exception 'Publication supabase_realtime is missing';
  end if;

  foreach _table in array _expected_realtime loop
    if not exists (
      select 1 from pg_publication_tables
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

-- 6. Stored-data invariants (also useful after production incidents) ----------
do $$
begin
  if exists (
    select 1
    from public.conversations c
    left join public.conversation_members cm on cm.conversation_id = c.id
    where c.kind = 'direct'
    group by c.id, c.direct_user_low, c.direct_user_high
    having count(*) filter (where cm.status = 'active') <> 2
       or count(*) filter (where cm.status = 'active' and cm.role = 'owner') <> 0
       or bool_or(
         cm.user_id not in (c.direct_user_low, c.direct_user_high)
         or cm.status <> 'active'
         or cm.role <> 'member'
       )
  ) then
    raise exception 'Invalid direct-conversation membership shape found';
  end if;

  if exists (
    select 1
    from public.conversations c
    left join public.conversation_members cm on cm.conversation_id = c.id
    where c.kind <> 'direct'
    group by c.id
    having count(*) filter (where cm.status = 'active' and cm.role = 'owner') <> 1
  ) then
    raise exception 'A group/channel without exactly one active owner exists';
  end if;

  if exists (
    select 1
    from public.conversations c
    left join lateral (
      select m.id, m.created_at
      from public.messages m
      where m.conversation_id = c.id and m.deleted_at is null
      order by m.created_at desc, m.id desc
      limit 1
    ) latest on true
    where c.last_message_id is distinct from latest.id
       or c.last_message_at is distinct from latest.created_at
  ) then
    raise exception 'Stale or invalid conversations last-message cache found';
  end if;

  if exists (
    select 1 from public.message_attachments a
    join public.messages m on m.id = a.message_id
    where a.conversation_id <> m.conversation_id
  ) then
    raise exception 'Attachment/message conversation mismatch found';
  end if;

  if exists (
    select 1 from public.conversation_read_receipts r
    join public.messages m on m.id = r.last_read_message_id
    where r.conversation_id <> m.conversation_id
  ) then
    raise exception 'Read receipt points at a message in another conversation';
  end if;

  if exists (
    select 1 from public.chat_folder_conversations fc
    join public.chat_folders f on f.id = fc.folder_id
    where fc.user_id <> f.user_id
  ) then
    raise exception 'Folder-conversation ownership mismatch found';
  end if;

  if exists (
    select 1
    from public.messages m
    left join public.polls p on p.message_id = m.id
    where m.deleted_at is null
    group by m.id, m.kind, m.body
    having (
         m.kind = 'poll'
         and (count(p.id) <> 1 or m.body is distinct from min(p.question))
       )
       or (m.kind <> 'poll' and count(p.id) <> 0)
  ) then
    raise exception 'Live poll message/poll one-to-one invariant is broken';
  end if;

  if exists (
    select 1
    from public.polls p
    left join public.poll_options po on po.poll_id = p.id
    group by p.id, p.max_selections
    having count(po.id) not between 2 and 20
       or p.max_selections > count(po.id)
       or min(po.position) <> 0
       or max(po.position) <> count(po.id) - 1
  ) then
    raise exception 'Invalid poll option shape found';
  end if;

  if exists (
    select 1
    from public.poll_options po
    left join public.poll_votes pv on pv.option_id = po.id
    group by po.id, po.vote_count
    having po.vote_count <> count(pv.option_id)
  ) then
    raise exception 'Cached poll_options.vote_count differs from poll_votes';
  end if;
end
$$;

-- 7. RLS planning/recursion smoke test under an authenticated JWT -------------
select set_config('request.jwt.claim.sub', gen_random_uuid()::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;

-- Explicit helper calls force policy helper queries even on an empty database.
select public.is_conversation_member(gen_random_uuid()) as member_smoke,
       public.can_view_conversation(gen_random_uuid()) as conversation_smoke,
       public.can_view_profile(gen_random_uuid()) as profile_smoke,
       public.message_is_visible(gen_random_uuid()) as message_smoke,
       public.poll_is_visible(gen_random_uuid()) as poll_smoke,
       public.can_read_chat_object(
         'chat-media',
         gen_random_uuid()::text || '/' || gen_random_uuid()::text || '/smoke.bin'
       ) as storage_smoke;

select 'profiles' as relation, count(*) as visible_rows from public.profiles
union all select 'contacts', count(*) from public.contacts
union all select 'user_blocks', count(*) from public.user_blocks
union all select 'conversations', count(*) from public.conversations
union all select 'conversation_members', count(*) from public.conversation_members
union all select 'messages', count(*) from public.messages
union all select 'message_attachments', count(*) from public.message_attachments
union all select 'message_reactions', count(*) from public.message_reactions
union all select 'conversation_read_receipts', count(*) from public.conversation_read_receipts
union all select 'conversation_typing', count(*) from public.conversation_typing
union all select 'message_pins', count(*) from public.message_pins
union all select 'conversation_user_settings', count(*) from public.conversation_user_settings
union all select 'chat_folders', count(*) from public.chat_folders
union all select 'chat_folder_conversations', count(*) from public.chat_folder_conversations
union all select 'user_settings', count(*) from public.user_settings
union all select 'user_presence', count(*) from public.user_presence
union all select 'user_devices', count(*) from public.user_devices
union all select 'reports', count(*) from public.reports
union all select 'group_invitations', count(*) from public.group_invitations
union all select 'group_join_requests', count(*) from public.group_join_requests
union all select 'polls', count(*) from public.polls
union all select 'poll_options', count(*) from public.poll_options
union all select 'poll_votes', count(*) from public.poll_votes
union all select 'storage.objects', count(*) from storage.objects;

reset role;
rollback;

-- Success means every assertion completed and the transaction was rolled back.
