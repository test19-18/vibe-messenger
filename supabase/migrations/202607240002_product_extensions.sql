-- Vibe Messenger product extensions.
-- Depends on 202607240001_initial_schema.sql and is safe to re-apply.

begin;

-- Domain enum -----------------------------------------------------------------
do $$
begin
  create type public.scheduled_message_status as enum (
    'pending', 'cancelled', 'delivered', 'failed'
  );
exception when duplicate_object then
  null;
end
$$;

-- Per-user message deletion ----------------------------------------------------
create table if not exists public.message_user_deletions (
  message_id uuid not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  deleted_at timestamptz not null default now(),
  primary key (message_id, user_id),
  constraint message_user_deletions_message_conversation_fk
    foreign key (conversation_id, message_id)
    references public.messages(conversation_id, id) on delete cascade
);

create index if not exists message_user_deletions_user_conversation_idx
  on public.message_user_deletions (user_id, conversation_id, deleted_at desc);
create index if not exists message_user_deletions_message_idx
  on public.message_user_deletions (message_id, conversation_id);

-- Personal server-backed member labels. A label belongs to the user who created
-- it; it is not a shared moderation label.
create table if not exists public.conversation_member_tags (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null,
  member_id uuid not null,
  tag text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (conversation_id, user_id, member_id),
  constraint conversation_member_tags_owner_membership_fk
    foreign key (conversation_id, user_id)
    references public.conversation_members(conversation_id, user_id) on delete cascade,
  constraint conversation_member_tags_target_membership_fk
    foreign key (conversation_id, member_id)
    references public.conversation_members(conversation_id, user_id) on delete cascade,
  constraint conversation_member_tags_tag_length
    check (char_length(btrim(tag)) between 1 and 64)
);

create index if not exists conversation_member_tags_user_idx
  on public.conversation_member_tags (user_id, updated_at desc);
create index if not exists conversation_member_tags_target_idx
  on public.conversation_member_tags (conversation_id, member_id, user_id);

-- Per-user product preferences and message expiration --------------------------
alter table public.conversation_user_settings
  add column if not exists auto_delete_seconds integer,
  add column if not exists protected_content boolean not null default false;

alter table public.messages
  add column if not exists expires_at timestamptz;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.conversation_user_settings'::regclass
      and conname = 'conversation_user_settings_auto_delete_range'
  ) then
    alter table public.conversation_user_settings
      add constraint conversation_user_settings_auto_delete_range
      check (auto_delete_seconds is null or auto_delete_seconds between 1 and 31536000);
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conrelid = 'public.messages'::regclass
      and conname = 'messages_expiry_after_creation'
  ) then
    alter table public.messages
      add constraint messages_expiry_after_creation
      check (expires_at is null or expires_at >= created_at);
  end if;
end
$$;

create index if not exists messages_expiry_cleanup_idx
  on public.messages (expires_at, id)
  where expires_at is not null and deleted_at is null;

-- Scheduled messages -----------------------------------------------------------
create table if not exists public.scheduled_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  kind public.message_kind not null default 'text',
  body text,
  metadata jsonb not null default '{}'::jsonb,
  reply_to uuid,
  scheduled_for timestamptz not null,
  silent boolean not null default false,
  status public.scheduled_message_status not null default 'pending',
  delivered_message_id uuid references public.messages(id) on delete set null,
  cancelled_at timestamptz,
  delivered_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint scheduled_messages_body_length
    check (body is null or char_length(body) <= 50000),
  constraint scheduled_messages_supported_kind
    check (kind not in ('poll', 'system')),
  constraint scheduled_messages_text_has_body
    check (kind <> 'text' or nullif(btrim(body), '') is not null),
  constraint scheduled_messages_metadata_object
    check (
      jsonb_typeof(metadata) = 'object'
      and octet_length(
        (
          metadata || jsonb_build_object(
            'silent', silent,
            'scheduled_message_id', id
          )
        )::text
      ) <= 262144
    ),
  constraint scheduled_messages_status_shape
    check (
      (
        status = 'pending'
        and cancelled_at is null
        and delivered_at is null
        and failed_at is null
        and delivered_message_id is null
      )
      or (
        status = 'cancelled'
        and cancelled_at is not null
        and delivered_at is null
        and failed_at is null
        and delivered_message_id is null
      )
      or (
        status = 'delivered'
        and cancelled_at is null
        and delivered_at is not null
        and failed_at is null
        and delivered_message_id is not null
      )
      or (
        status = 'failed'
        and cancelled_at is null
        and delivered_at is null
        and failed_at is not null
        and delivered_message_id is null
      )
    ),
  constraint scheduled_messages_reply_conversation_fk
    foreign key (conversation_id, reply_to)
    references public.messages(conversation_id, id)
    on delete set null (reply_to)
);

create index if not exists scheduled_messages_sender_status_idx
  on public.scheduled_messages (sender_id, status, scheduled_for, id);
create index if not exists scheduled_messages_due_idx
  on public.scheduled_messages (scheduled_for, id)
  where status = 'pending';
create index if not exists scheduled_messages_reply_idx
  on public.scheduled_messages (reply_to)
  where reply_to is not null;

-- Security-definer authorization helpers --------------------------------------
create or replace function public.is_active_conversation_member(
  _conversation_id uuid,
  _user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select _user_id is not null and coalesce(exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id = _conversation_id
      and cm.user_id = _user_id
      and cm.status = 'active'
  ), false);
$$;

create or replace function public.can_user_send_to_conversation(
  _conversation_id uuid,
  _user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select _user_id is not null and coalesce(exists (
    select 1
    from public.conversations c
    join public.conversation_members cm
      on cm.conversation_id = c.id
     and cm.user_id = _user_id
     and cm.status = 'active'
    where c.id = _conversation_id
      and (not c.is_locked or cm.role in ('owner', 'admin'))
      and (
        c.kind <> 'direct'
        or not public.is_blocked_pair(c.direct_user_low, c.direct_user_high)
      )
  ), false);
$$;

-- Preserve the existing authenticated helper while making the actor explicit for
-- trusted scheduled-delivery jobs.
create or replace function public.can_send_to_conversation(_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.can_user_send_to_conversation(
    _conversation_id,
    (select auth.uid())
  );
$$;

create or replace function public.message_is_deleted_for_user(
  _message_id uuid,
  _user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select _user_id is not null and coalesce(exists (
    select 1
    from public.message_user_deletions d
    where d.message_id = _message_id
      and d.user_id = _user_id
  ), false);
$$;

create or replace function public.message_is_deleted_for_me(_message_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.message_is_deleted_for_user(
    _message_id,
    (select auth.uid())
  );
$$;

create or replace function public.can_manage_conversation_member_tag(
  _conversation_id uuid,
  _member_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_active_conversation_member(
           _conversation_id,
           (select auth.uid())
         )
     and public.is_active_conversation_member(_conversation_id, _member_id);
$$;

-- Live child resources inherit both per-user deletion and expiration visibility.
create or replace function public.message_is_visible(_message_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(exists (
    select 1
    from public.messages m
    join public.conversation_members cm
      on cm.conversation_id = m.conversation_id
     and cm.user_id = (select auth.uid())
     and cm.status = 'active'
    where m.id = _message_id
      and m.deleted_at is null
      and (m.expires_at is null or m.expires_at > now())
      and not public.message_is_deleted_for_user(m.id, (select auth.uid()))
  ), false);
$$;

create or replace function public.poll_is_visible(_poll_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(exists (
    select 1
    from public.polls p
    join public.messages m
      on m.id = p.message_id
     and m.conversation_id = p.conversation_id
     and m.deleted_at is null
     and (m.expires_at is null or m.expires_at > now())
    join public.conversation_members cm
      on cm.conversation_id = p.conversation_id
     and cm.user_id = (select auth.uid())
     and cm.status = 'active'
    where p.id = _poll_id
      and not public.message_is_deleted_for_user(m.id, (select auth.uid()))
  ), false);
$$;

create or replace function public.can_read_attachment(_attachment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(exists (
    select 1
    from public.message_attachments a
    join public.messages m
      on m.id = a.message_id
     and m.deleted_at is null
     and (m.expires_at is null or m.expires_at > now())
    join public.conversation_members cm
      on cm.conversation_id = a.conversation_id
     and cm.user_id = (select auth.uid())
     and cm.status = 'active'
    where a.id = _attachment_id
      and not public.message_is_deleted_for_user(m.id, (select auth.uid()))
  ), false);
$$;

create or replace function public.can_read_chat_object(_bucket text, _name text)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(exists (
    select 1
    from public.message_attachments a
    join public.messages m
      on m.id = a.message_id
     and m.deleted_at is null
     and (m.expires_at is null or m.expires_at > now())
    join public.conversation_members cm
      on cm.conversation_id = a.conversation_id
     and cm.user_id = (select auth.uid())
     and cm.status = 'active'
    where (
      (a.storage_bucket = _bucket and a.storage_path = _name)
      or (_bucket = 'chat-media' and a.thumbnail_path = _name)
    )
      and not public.message_is_deleted_for_user(m.id, (select auth.uid()))
  ), false);
$$;

-- Guard functions --------------------------------------------------------------
create or replace function public.guard_message_user_deletion_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _actor uuid := auth.uid();
  _conversation_id uuid;
begin
  if _actor is not null then
    new.user_id := _actor;
  elsif new.user_id is null then
    raise exception 'A deletion owner is required' using errcode = '23502';
  end if;

  select m.conversation_id into _conversation_id
  from public.messages m
  where m.id = new.message_id
    and m.deleted_at is null
    and (m.expires_at is null or m.expires_at > now());

  if _conversation_id is null then
    raise exception 'Only a live message can be deleted for a user' using errcode = '23514';
  end if;

  new.conversation_id := _conversation_id;
  new.deleted_at := now();
  return new;
end;
$$;

create or replace function public.guard_conversation_member_tag_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    if auth.uid() is not null then
      new.user_id := auth.uid();
    end if;
    new.created_at := now();
  elsif new.conversation_id <> old.conversation_id
        or new.user_id <> old.user_id
        or new.member_id <> old.member_id
        or new.created_at <> old.created_at then
    raise exception 'Member-tag identity fields are immutable' using errcode = '42501';
  end if;

  new.tag := btrim(new.tag);
  return new;
end;
$$;

-- This trigger runs after guard_message_write by trigger-name order. It derives
-- expiration from the sender's current conversation_user_settings row and keeps
-- expires_at immutable afterwards.
create or replace function public.set_message_expiration()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _auto_delete_seconds integer;
begin
  if tg_op = 'UPDATE' then
    if new.expires_at is distinct from old.expires_at then
      raise exception 'Message expiration is immutable' using errcode = '42501';
    end if;
    return new;
  end if;

  if new.reply_to_message_id is not null and (
    not exists (
      select 1
      from public.messages reply
      where reply.id = new.reply_to_message_id
        and reply.deleted_at is null
        and (reply.expires_at is null or reply.expires_at > now())
    )
    or public.message_is_deleted_for_user(new.reply_to_message_id, new.sender_id)
  ) then
    raise exception 'Reply target is unavailable to the sender' using errcode = '23514';
  end if;

  select settings.auto_delete_seconds into _auto_delete_seconds
  from public.conversation_user_settings settings
  where settings.conversation_id = new.conversation_id
    and settings.user_id = new.sender_id;

  new.expires_at := case
    when _auto_delete_seconds is null then null
    else new.created_at + make_interval(secs => _auto_delete_seconds)
  end;
  return new;
end;
$$;

-- Scheduled-message RPCs -------------------------------------------------------
create or replace function public.create_scheduled_message(
  _conversation_id uuid,
  _scheduled_for timestamptz,
  _kind public.message_kind default 'text',
  _body text default null,
  _metadata jsonb default '{}'::jsonb,
  _reply_to uuid default null,
  _silent boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _me uuid := auth.uid();
  _scheduled_id uuid;
begin
  if _me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not public.can_user_send_to_conversation(_conversation_id, _me) then
    raise exception 'Not allowed to schedule a message in this conversation' using errcode = '42501';
  end if;
  if _scheduled_for is null or _scheduled_for <= now() then
    raise exception 'scheduled_for must be in the future' using errcode = '22023';
  end if;
  if _kind in ('poll', 'system') then
    raise exception 'Poll and system messages cannot be scheduled' using errcode = '22023';
  end if;
  if _reply_to is not null and not exists (
    select 1
    from public.messages m
    where m.id = _reply_to
      and m.conversation_id = _conversation_id
      and m.deleted_at is null
      and (m.expires_at is null or m.expires_at > now())
      and not public.message_is_deleted_for_user(m.id, _me)
  ) then
    raise exception 'Reply target is unavailable' using errcode = '23514';
  end if;

  insert into public.scheduled_messages (
    conversation_id,
    sender_id,
    kind,
    body,
    metadata,
    reply_to,
    scheduled_for,
    silent
  ) values (
    _conversation_id,
    _me,
    _kind,
    _body,
    coalesce(_metadata, '{}'::jsonb),
    _reply_to,
    _scheduled_for,
    coalesce(_silent, false)
  )
  returning id into _scheduled_id;

  return _scheduled_id;
end;
$$;

create or replace function public.cancel_scheduled_message(_scheduled_message_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _me uuid := auth.uid();
  _status public.scheduled_message_status;
begin
  if _me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  select sm.status into _status
  from public.scheduled_messages sm
  where sm.id = _scheduled_message_id
    and sm.sender_id = _me
  for update;

  if not found then
    raise exception 'Scheduled message not found' using errcode = 'P0002';
  end if;
  if _status = 'cancelled' then
    return true;
  end if;
  if _status <> 'pending' then
    return false;
  end if;

  update public.scheduled_messages
  set status = 'cancelled',
      cancelled_at = now()
  where id = _scheduled_message_id;
  return true;
end;
$$;

create or replace function public.deliver_scheduled_message(_scheduled_message_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _scheduled public.scheduled_messages%rowtype;
  _message_id uuid;
begin
  select * into _scheduled
  from public.scheduled_messages sm
  where sm.id = _scheduled_message_id
  for update;

  if not found then
    return null;
  end if;
  if _scheduled.status = 'delivered' then
    return _scheduled.delivered_message_id;
  end if;
  if _scheduled.status <> 'pending' or _scheduled.scheduled_for > now() then
    return null;
  end if;

  if not public.can_user_send_to_conversation(
    _scheduled.conversation_id,
    _scheduled.sender_id
  ) then
    update public.scheduled_messages
    set status = 'failed', failed_at = now()
    where id = _scheduled.id;
    return null;
  end if;

  if _scheduled.reply_to is not null and not exists (
    select 1
    from public.messages m
    where m.id = _scheduled.reply_to
      and m.conversation_id = _scheduled.conversation_id
      and m.deleted_at is null
      and (m.expires_at is null or m.expires_at > now())
      and not public.message_is_deleted_for_user(m.id, _scheduled.sender_id)
  ) then
    update public.scheduled_messages
    set status = 'failed', failed_at = now()
    where id = _scheduled.id;
    return null;
  end if;

  begin
    insert into public.messages (
      conversation_id,
      sender_id,
      kind,
      body,
      metadata,
      reply_to_message_id
    ) values (
      _scheduled.conversation_id,
      _scheduled.sender_id,
      _scheduled.kind,
      _scheduled.body,
      _scheduled.metadata || jsonb_build_object(
        'silent', _scheduled.silent,
        'scheduled_message_id', _scheduled.id
      ),
      _scheduled.reply_to
    )
    returning id into _message_id;
  exception when others then
    update public.scheduled_messages
    set status = 'failed', failed_at = now()
    where id = _scheduled.id;
    return null;
  end;

  update public.scheduled_messages
  set status = 'delivered',
      delivered_message_id = _message_id,
      delivered_at = now()
  where id = _scheduled.id;

  return _message_id;
end;
$$;

create or replace function public.process_due_scheduled_messages(_limit integer default 100)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _scheduled_message_id uuid;
  _processed integer := 0;
begin
  if _limit is null or _limit not between 1 and 1000 then
    raise exception 'limit must be between 1 and 1000' using errcode = '22023';
  end if;

  for _scheduled_message_id in
    select sm.id
    from public.scheduled_messages sm
    where sm.status = 'pending'
      and sm.scheduled_for <= now()
    order by sm.scheduled_for, sm.id
    for update skip locked
    limit _limit
  loop
    perform public.deliver_scheduled_message(_scheduled_message_id);
    _processed := _processed + 1;
  end loop;

  return _processed;
end;
$$;

create or replace function public.cleanup_expired_messages(_limit integer default 1000)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _cleaned integer;
begin
  if _limit is null or _limit not between 1 and 10000 then
    raise exception 'limit must be between 1 and 10000' using errcode = '22023';
  end if;

  with expired as (
    select m.id
    from public.messages m
    where m.deleted_at is null
      and m.expires_at is not null
      and m.expires_at <= now()
    order by m.expires_at, m.id
    for update skip locked
    limit _limit
  )
  update public.messages m
  set deleted_at = now()
  from expired
  where m.id = expired.id;

  get diagnostics _cleaned = row_count;
  return _cleaned;
end;
$$;

-- Trigger installation ---------------------------------------------------------
drop trigger if exists guard_message_user_deletion_write on public.message_user_deletions;
create trigger guard_message_user_deletion_write
before insert on public.message_user_deletions
for each row execute function public.guard_message_user_deletion_write();

drop trigger if exists set_updated_at on public.conversation_member_tags;
create trigger set_updated_at
before insert or update on public.conversation_member_tags
for each row execute function public.set_updated_at();

drop trigger if exists guard_conversation_member_tag_write on public.conversation_member_tags;
create trigger guard_conversation_member_tag_write
before insert or update on public.conversation_member_tags
for each row execute function public.guard_conversation_member_tag_write();

drop trigger if exists set_updated_at on public.scheduled_messages;
create trigger set_updated_at
before insert or update on public.scheduled_messages
for each row execute function public.set_updated_at();

drop trigger if exists set_message_expiration on public.messages;
create trigger set_message_expiration
before insert or update on public.messages
for each row execute function public.set_message_expiration();

-- RLS -------------------------------------------------------------------------
alter table public.message_user_deletions enable row level security;
alter table public.conversation_member_tags enable row level security;
alter table public.scheduled_messages enable row level security;

drop policy if exists message_user_deletions_select_self on public.message_user_deletions;
create policy message_user_deletions_select_self on public.message_user_deletions
for select to authenticated
using (
  user_id = (select auth.uid())
  and public.is_conversation_member(conversation_id)
);

drop policy if exists message_user_deletions_insert_self on public.message_user_deletions;
create policy message_user_deletions_insert_self on public.message_user_deletions
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and public.message_is_visible(message_id)
);

drop policy if exists conversation_member_tags_select_self on public.conversation_member_tags;
create policy conversation_member_tags_select_self on public.conversation_member_tags
for select to authenticated
using (
  user_id = (select auth.uid())
  and public.is_conversation_member(conversation_id)
);

drop policy if exists conversation_member_tags_insert_self on public.conversation_member_tags;
create policy conversation_member_tags_insert_self on public.conversation_member_tags
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and public.can_manage_conversation_member_tag(conversation_id, member_id)
);

drop policy if exists conversation_member_tags_update_self on public.conversation_member_tags;
create policy conversation_member_tags_update_self on public.conversation_member_tags
for update to authenticated
using (
  user_id = (select auth.uid())
  and public.is_conversation_member(conversation_id)
)
with check (
  user_id = (select auth.uid())
  and public.can_manage_conversation_member_tag(conversation_id, member_id)
);

drop policy if exists conversation_member_tags_delete_self on public.conversation_member_tags;
create policy conversation_member_tags_delete_self on public.conversation_member_tags
for delete to authenticated
using (
  user_id = (select auth.uid())
  and public.is_conversation_member(conversation_id)
);

drop policy if exists scheduled_messages_select_self on public.scheduled_messages;
create policy scheduled_messages_select_self on public.scheduled_messages
for select to authenticated
using (sender_id = (select auth.uid()));

-- A user's deletion marker and an elapsed expires_at remove the message from that
-- user's normal timeline query. Existing global soft-delete tombstones remain
-- readable unless they have expired or were deleted only for that user.
drop policy if exists messages_select_member on public.messages;
create policy messages_select_member on public.messages
for select to authenticated
using (
  public.is_conversation_member(conversation_id)
  and not public.message_is_deleted_for_me(id)
  and (expires_at is null or expires_at > now())
);

-- Explicit grants --------------------------------------------------------------
revoke all on
  public.message_user_deletions,
  public.conversation_member_tags,
  public.scheduled_messages
from public, anon, authenticated;

grant all on
  public.message_user_deletions,
  public.conversation_member_tags,
  public.scheduled_messages
  to service_role;

grant select on
  public.message_user_deletions,
  public.conversation_member_tags,
  public.scheduled_messages
  to authenticated, service_role;

grant insert on public.message_user_deletions to authenticated, service_role;
grant insert on public.conversation_member_tags to authenticated, service_role;
grant update (tag) on public.conversation_member_tags to authenticated, service_role;
grant delete on public.conversation_member_tags to authenticated, service_role;

grant update (auto_delete_seconds, protected_content)
  on public.conversation_user_settings to authenticated, service_role;

-- New functions start closed. Internal actor-explicit helpers and trigger
-- functions remain owner-only; only the public helper/RPC allow-list is opened.
revoke all on function public.is_active_conversation_member(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.can_user_send_to_conversation(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.message_is_deleted_for_user(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.message_is_deleted_for_me(uuid)
  from public, anon, authenticated;
revoke all on function public.can_manage_conversation_member_tag(uuid, uuid)
  from public, anon, authenticated;
revoke all on function public.guard_message_user_deletion_write()
  from public, anon, authenticated;
revoke all on function public.guard_conversation_member_tag_write()
  from public, anon, authenticated;
revoke all on function public.set_message_expiration()
  from public, anon, authenticated;
revoke all on function public.create_scheduled_message(
  uuid, timestamptz, public.message_kind, text, jsonb, uuid, boolean
) from public, anon, authenticated;
revoke all on function public.cancel_scheduled_message(uuid)
  from public, anon, authenticated;
revoke all on function public.deliver_scheduled_message(uuid)
  from public, anon, authenticated;
revoke all on function public.process_due_scheduled_messages(integer)
  from public, anon, authenticated;
revoke all on function public.cleanup_expired_messages(integer)
  from public, anon, authenticated;

-- Re-assert the ACL of replaced helpers.
revoke all on function public.can_send_to_conversation(uuid) from public, anon;
revoke all on function public.message_is_visible(uuid) from public, anon;
revoke all on function public.poll_is_visible(uuid) from public, anon;
revoke all on function public.can_read_attachment(uuid) from public, anon;
revoke all on function public.can_read_chat_object(text, text) from public, anon;

grant execute on function public.message_is_deleted_for_me(uuid)
  to authenticated, service_role;
grant execute on function public.can_manage_conversation_member_tag(uuid, uuid)
  to authenticated, service_role;
grant execute on function public.can_send_to_conversation(uuid)
  to authenticated, service_role;
grant execute on function public.message_is_visible(uuid)
  to authenticated, service_role;
grant execute on function public.poll_is_visible(uuid)
  to authenticated, service_role;
grant execute on function public.can_read_attachment(uuid)
  to authenticated, service_role;
grant execute on function public.can_read_chat_object(text, text)
  to authenticated, service_role;

grant execute on function public.create_scheduled_message(
  uuid, timestamptz, public.message_kind, text, jsonb, uuid, boolean
) to authenticated, service_role;
grant execute on function public.cancel_scheduled_message(uuid)
  to authenticated, service_role;

grant execute on function public.deliver_scheduled_message(uuid)
  to service_role;
grant execute on function public.process_due_scheduled_messages(integer)
  to service_role;
grant execute on function public.cleanup_expired_messages(integer)
  to service_role;

-- Realtime --------------------------------------------------------------------
alter table public.message_user_deletions replica identity full;
alter table public.conversation_member_tags replica identity full;
alter table public.scheduled_messages replica identity full;

do $$
declare
  _table text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  foreach _table in array array[
    'message_user_deletions',
    'conversation_member_tags',
    'scheduled_messages'
  ] loop
    if not exists (
      select 1
      from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = _table
    ) then
      execute format(
        'alter publication supabase_realtime add table public.%I',
        _table
      );
    end if;
  end loop;
end
$$;

-- Optional pg_cron integration. Named jobs are updated instead of duplicated.
-- If pg_cron is absent, not initialized, or the migration role cannot schedule
-- jobs, the migration still succeeds; an external trusted caller must invoke the
-- process/cleanup RPCs.
do $$
begin
  if to_regprocedure('cron.schedule(text,text,text)') is not null then
    execute 'select cron.schedule($1, $2, $3)'
      using
        'vibe-deliver-scheduled-messages',
        '* * * * *',
        'select public.process_due_scheduled_messages(200);';

    execute 'select cron.schedule($1, $2, $3)'
      using
        'vibe-cleanup-expired-messages',
        '*/5 * * * *',
        'select public.cleanup_expired_messages(2000);';
  else
    raise notice 'pg_cron is unavailable; external scheduling is required';
  end if;
exception when others then
  raise notice 'pg_cron jobs were not installed (%); external scheduling is required', sqlerrm;
end
$$;

commit;
