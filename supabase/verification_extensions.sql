-- Verification for 202607240002_product_extensions.sql.
-- Safe to execute repeatedly; it does not mutate application data.

do $$
declare
  missing text[] := array[]::text[];
begin
  if to_regclass('public.message_user_deletions') is null then
    missing := array_append(missing, 'message_user_deletions');
  end if;
  if to_regclass('public.conversation_member_tags') is null then
    missing := array_append(missing, 'conversation_member_tags');
  end if;
  if to_regclass('public.scheduled_messages') is null then
    missing := array_append(missing, 'scheduled_messages');
  end if;
  if array_length(missing, 1) is not null then
    raise exception 'Missing extension tables: %', array_to_string(missing, ', ');
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'conversation_user_settings'
      and column_name = 'auto_delete_seconds'
  ) then
    raise exception 'Missing conversation_user_settings.auto_delete_seconds';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'conversation_user_settings'
      and column_name = 'protected_content'
  ) then
    raise exception 'Missing conversation_user_settings.protected_content';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'messages'
      and column_name = 'expires_at'
  ) then
    raise exception 'Missing messages.expires_at';
  end if;

  if to_regprocedure('public.create_scheduled_message(uuid,timestamp with time zone,public.message_kind,text,jsonb,uuid,boolean)') is null then
    raise exception 'Missing create_scheduled_message RPC';
  end if;
  if to_regprocedure('public.cancel_scheduled_message(uuid)') is null then
    raise exception 'Missing cancel_scheduled_message RPC';
  end if;
  if to_regprocedure('public.process_due_scheduled_messages(integer)') is null then
    raise exception 'Missing process_due_scheduled_messages RPC';
  end if;
  if to_regprocedure('public.cleanup_expired_messages(integer)') is null then
    raise exception 'Missing cleanup_expired_messages RPC';
  end if;
end
$$;

do $$
declare
  rel text;
begin
  foreach rel in array array[
    'message_user_deletions',
    'conversation_member_tags',
    'scheduled_messages'
  ] loop
    if not exists (
      select 1 from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = rel and c.relrowsecurity
    ) then
      raise exception 'RLS is not enabled for public.%', rel;
    end if;
    if not exists (
      select 1 from pg_policies
      where schemaname = 'public' and tablename = rel
    ) then
      raise exception 'No RLS policies found for public.%', rel;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = rel
    ) then
      raise exception 'public.% is not in supabase_realtime', rel;
    end if;
  end loop;
end
$$;

select
  c.relname as relation,
  c.relrowsecurity as rls_enabled,
  count(p.policyname) as policy_count
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
left join pg_policies p on p.schemaname = n.nspname and p.tablename = c.relname
where n.nspname = 'public'
  and c.relname in ('message_user_deletions', 'conversation_member_tags', 'scheduled_messages')
group by c.relname, c.relrowsecurity
order by c.relname;
