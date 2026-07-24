-- Vibe messenger: initial Supabase/Postgres schema.
-- Apply as one migration to a clean Supabase project.

begin;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- Domain enums ----------------------------------------------------------------
do $$ begin
  create type public.contact_status as enum ('pending', 'accepted', 'declined', 'cancelled');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.conversation_kind as enum ('direct', 'group', 'channel');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.conversation_member_role as enum ('owner', 'admin', 'member');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.conversation_member_status as enum ('active', 'left', 'removed', 'banned');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.message_kind as enum (
    'text', 'image', 'video', 'file', 'audio', 'voice',
    'location', 'contact', 'poll', 'system'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.attachment_kind as enum ('image', 'video', 'file', 'audio', 'voice');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.notification_level as enum ('all', 'mentions', 'none');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.device_platform as enum ('android', 'ios', 'web', 'desktop');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.report_status as enum ('open', 'in_review', 'resolved', 'rejected');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.invitation_status as enum ('pending', 'accepted', 'declined', 'revoked', 'expired');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.join_request_status as enum ('pending', 'approved', 'rejected', 'cancelled');
exception when duplicate_object then null; end $$;

-- Core identities --------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text,
  display_name text not null default '',
  bio text,
  avatar_path text,
  is_discoverable boolean not null default true,
  onboarding_completed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_format check (
    username is null or (
      username = lower(username)
      and username ~ '^[a-z0-9_][a-z0-9_.]{2,31}$'
    )
  ),
  constraint profiles_display_name_length check (char_length(display_name) <= 100),
  constraint profiles_bio_length check (bio is null or char_length(bio) <= 500),
  constraint profiles_avatar_path_length check (avatar_path is null or char_length(avatar_path) <= 1024)
);

create unique index if not exists profiles_username_lower_uidx
  on public.profiles (lower(username)) where username is not null;
create index if not exists profiles_display_name_lower_idx
  on public.profiles (lower(display_name));

create table if not exists public.contacts (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status public.contact_status not null default 'pending',
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint contacts_no_self check (requester_id <> addressee_id),
  constraint contacts_response_shape check (
    (status = 'pending' and responded_at is null)
    or (status <> 'pending' and responded_at is not null)
  )
);

create unique index if not exists contacts_unordered_pair_uidx
  on public.contacts (
    least(requester_id::text, addressee_id::text),
    greatest(requester_id::text, addressee_id::text)
  );
create index if not exists contacts_requester_status_idx
  on public.contacts (requester_id, status, updated_at desc);
create index if not exists contacts_addressee_status_idx
  on public.contacts (addressee_id, status, updated_at desc);

create table if not exists public.user_blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint user_blocks_no_self check (blocker_id <> blocked_id)
);

create index if not exists user_blocks_blocked_idx
  on public.user_blocks (blocked_id, blocker_id);

-- Conversations and membership -------------------------------------------------
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  kind public.conversation_kind not null,
  title text,
  description text,
  avatar_path text,
  created_by uuid references public.profiles(id) on delete set null,
  direct_user_low uuid references public.profiles(id) on delete cascade,
  direct_user_high uuid references public.profiles(id) on delete cascade,
  is_locked boolean not null default false,
  join_requests_enabled boolean not null default false,
  last_message_id uuid,
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint conversations_title_length check (title is null or char_length(title) between 1 and 120),
  constraint conversations_description_length check (description is null or char_length(description) <= 2000),
  constraint conversations_avatar_path_length check (avatar_path is null or char_length(avatar_path) <= 1024),
  constraint conversations_shape check (
    (
      kind = 'direct'
      and title is null
      and description is null
      and avatar_path is null
      and not is_locked
      and not join_requests_enabled
      and direct_user_low is not null
      and direct_user_high is not null
      and direct_user_low <> direct_user_high
      and direct_user_low::text < direct_user_high::text
    )
    or
    (
      kind <> 'direct'
      and title is not null
      and direct_user_low is null
      and direct_user_high is null
    )
  )
);

create unique index if not exists conversations_direct_pair_uidx
  on public.conversations (direct_user_low, direct_user_high)
  where kind = 'direct';
create index if not exists conversations_created_by_idx
  on public.conversations (created_by, created_at desc);
create index if not exists conversations_last_message_idx
  on public.conversations (last_message_at desc nulls last);

create table if not exists public.conversation_members (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null,
  role public.conversation_member_role not null default 'member',
  status public.conversation_member_status not null default 'active',
  invited_by uuid references public.profiles(id) on delete set null,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (conversation_id, user_id),
  constraint conversation_members_user_id_fkey
    foreign key (user_id) references public.profiles(id) on delete cascade,
  constraint conversation_members_left_at check (
    (status = 'active' and left_at is null)
    or (status <> 'active' and left_at is not null)
  )
);

create index if not exists conversation_members_user_active_idx
  on public.conversation_members (user_id, conversation_id)
  where status = 'active';
create index if not exists conversation_members_conversation_active_idx
  on public.conversation_members (conversation_id, role, joined_at)
  where status = 'active';

-- Messages --------------------------------------------------------------------
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid references public.profiles(id) on delete set null,
  kind public.message_kind not null default 'text',
  body text,
  reply_to_message_id uuid,
  client_nonce text,
  metadata jsonb not null default '{}'::jsonb,
  edited_at timestamptz,
  deleted_at timestamptz,
  deleted_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint messages_body_length check (body is null or char_length(body) <= 50000),
  constraint messages_client_nonce_length check (
    client_nonce is null or char_length(client_nonce) between 1 and 128
  ),
  constraint messages_text_has_body check (
    deleted_at is not null
    or kind <> 'text'
    or nullif(btrim(body), '') is not null
  ),
  constraint messages_delete_pair check (
    (deleted_at is null and deleted_by is null)
    or deleted_at is not null
  ),
  constraint messages_metadata_object check (
    jsonb_typeof(metadata) = 'object' and octet_length(metadata::text) <= 262144
  ),
  unique (conversation_id, id),
  constraint messages_reply_conversation_fk
    foreign key (conversation_id, reply_to_message_id)
    references public.messages(conversation_id, id)
    on delete set null (reply_to_message_id)
);

create index if not exists messages_conversation_timeline_idx
  on public.messages (conversation_id, created_at desc, id desc);
create index if not exists messages_conversation_live_timeline_idx
  on public.messages (conversation_id, created_at desc, id desc)
  where deleted_at is null;
create index if not exists messages_sender_idx
  on public.messages (sender_id, created_at desc) where sender_id is not null;
create index if not exists messages_reply_idx
  on public.messages (reply_to_message_id) where reply_to_message_id is not null;
create unique index if not exists messages_client_nonce_uidx
  on public.messages (conversation_id, sender_id, client_nonce)
  where sender_id is not null and client_nonce is not null;

-- The FK is added after messages exists because conversations caches the last message.
do $$ begin
  alter table public.conversations
    add constraint conversations_last_message_fk
    foreign key (id, last_message_id)
    references public.messages(conversation_id, id)
    on delete set null (last_message_id);
exception when duplicate_object then null; end $$;

create table if not exists public.message_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  uploaded_by uuid references public.profiles(id) on delete set null,
  kind public.attachment_kind not null,
  storage_bucket text not null,
  storage_path text not null,
  thumbnail_path text,
  file_name text,
  mime_type text,
  byte_size bigint,
  width integer,
  height integer,
  duration_ms integer,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint message_attachments_bucket check (storage_bucket in ('chat-media', 'voice-messages')),
  constraint message_attachments_path_length check (
    char_length(storage_path) between 1 and 1024
    and octet_length(storage_path) <= 1024
    and (
      thumbnail_path is null
      or (char_length(thumbnail_path) between 1 and 1024 and octet_length(thumbnail_path) <= 1024)
    )
  ),
  constraint message_attachments_file_fields_length check (
    (file_name is null or char_length(file_name) <= 512)
    and (mime_type is null or char_length(mime_type) <= 255)
  ),
  constraint message_attachments_size check (byte_size is null or byte_size > 0),
  constraint message_attachments_dimensions check (
    (width is null or width > 0) and (height is null or height > 0)
  ),
  constraint message_attachments_duration check (duration_ms is null or duration_ms >= 0),
  constraint message_attachments_metadata_object check (
    jsonb_typeof(metadata) = 'object' and octet_length(metadata::text) <= 65536
  ),
  constraint message_attachments_message_conversation_fk
    foreign key (conversation_id, message_id)
    references public.messages(conversation_id, id) on delete cascade,
  unique (storage_bucket, storage_path)
);

create index if not exists message_attachments_message_idx
  on public.message_attachments (message_id, created_at);
create index if not exists message_attachments_conversation_idx
  on public.message_attachments (conversation_id, created_at desc);
create index if not exists message_attachments_thumbnail_idx
  on public.message_attachments (thumbnail_path) where thumbnail_path is not null;

create table if not exists public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id, emoji),
  constraint message_reactions_emoji_length check (char_length(btrim(emoji)) between 1 and 32)
);

create index if not exists message_reactions_message_idx
  on public.message_reactions (message_id, created_at);
create index if not exists message_reactions_user_idx
  on public.message_reactions (user_id, created_at desc);

create table if not exists public.conversation_read_receipts (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  last_read_message_id uuid,
  last_read_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (conversation_id, user_id),
  constraint conversation_read_receipts_message_fk
    foreign key (conversation_id, last_read_message_id)
    references public.messages(conversation_id, id)
    on delete set null (last_read_message_id)
);

create index if not exists conversation_read_receipts_user_idx
  on public.conversation_read_receipts (user_id, updated_at desc);

create table if not exists public.conversation_typing (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  is_typing boolean not null default true,
  expires_at timestamptz not null default (now() + interval '12 seconds'),
  updated_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

create index if not exists conversation_typing_expiry_idx
  on public.conversation_typing (expires_at);

create table if not exists public.message_pins (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  message_id uuid not null,
  pinned_by uuid references public.profiles(id) on delete set null,
  pinned_at timestamptz not null default now(),
  primary key (conversation_id, message_id),
  constraint message_pins_message_conversation_fk
    foreign key (conversation_id, message_id)
    references public.messages(conversation_id, id) on delete cascade
);

create index if not exists message_pins_conversation_idx
  on public.message_pins (conversation_id, pinned_at desc);

-- Per-user chat organization and preferences ----------------------------------
create table if not exists public.conversation_user_settings (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  is_archived boolean not null default false,
  is_pinned boolean not null default false,
  mute_until timestamptz,
  notification_level public.notification_level not null default 'all',
  custom_title text,
  draft text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (conversation_id, user_id),
  constraint conversation_user_settings_title_length check (
    custom_title is null or char_length(custom_title) <= 120
  ),
  constraint conversation_user_settings_draft_length check (
    draft is null or char_length(draft) <= 10000
  )
);

create index if not exists conversation_user_settings_user_list_idx
  on public.conversation_user_settings (user_id, is_archived, is_pinned desc, updated_at desc);

create table if not exists public.chat_folders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  name text not null,
  color text,
  icon text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint chat_folders_name_length check (char_length(btrim(name)) between 1 and 60),
  constraint chat_folders_color_format check (color is null or color ~ '^#[0-9A-Fa-f]{6}$'),
  unique (id, user_id),
  unique (user_id, name)
);

create index if not exists chat_folders_user_sort_idx
  on public.chat_folders (user_id, sort_order, created_at);
create unique index if not exists chat_folders_user_name_lower_uidx
  on public.chat_folders (user_id, lower(btrim(name)));

create table if not exists public.chat_folder_conversations (
  folder_id uuid not null,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  sort_order integer not null default 0,
  added_at timestamptz not null default now(),
  primary key (folder_id, conversation_id),
  foreign key (folder_id, user_id)
    references public.chat_folders(id, user_id) on delete cascade
);

create index if not exists chat_folder_conversations_user_idx
  on public.chat_folder_conversations (user_id, folder_id, sort_order, added_at);
create index if not exists chat_folder_conversations_conversation_idx
  on public.chat_folder_conversations (conversation_id, user_id);

create table if not exists public.user_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  locale text not null default 'ru',
  theme text not null default 'system',
  send_read_receipts boolean not null default true,
  show_typing_status boolean not null default true,
  show_last_seen boolean not null default true,
  push_enabled boolean not null default true,
  push_message_preview boolean not null default true,
  auto_download_media boolean not null default true,
  settings jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_settings_locale_length check (char_length(locale) between 2 and 16),
  constraint user_settings_theme check (theme in ('system', 'light', 'dark')),
  constraint user_settings_json_object check (
    jsonb_typeof(settings) = 'object' and octet_length(settings::text) <= 65536
  )
);

create table if not exists public.user_presence (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  last_seen_at timestamptz not null default now(),
  online_until timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists user_presence_online_idx
  on public.user_presence (online_until desc) where online_until is not null;

create table if not exists public.user_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform public.device_platform not null,
  device_name text,
  fcm_token text not null,
  app_version text,
  last_seen_at timestamptz not null default now(),
  disabled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_devices_token_length check (
    char_length(fcm_token) between 16 and 2048 and fcm_token !~ '\s'
  ),
  constraint user_devices_text_lengths check (
    (device_name is null or char_length(device_name) <= 200)
    and (app_version is null or char_length(app_version) <= 100)
  ),
  unique (fcm_token)
);

create index if not exists user_devices_user_active_idx
  on public.user_devices (user_id, last_seen_at desc)
  where disabled_at is null;

-- Safety, invitations and membership requests ---------------------------------
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references public.profiles(id) on delete set null,
  reported_user_id uuid references public.profiles(id) on delete set null,
  reported_conversation_id uuid references public.conversations(id) on delete set null,
  reported_message_id uuid references public.messages(id) on delete set null,
  reason text not null,
  details text,
  evidence jsonb not null default '{}'::jsonb,
  status public.report_status not null default 'open',
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Targets use ON DELETE SET NULL so historical moderation rows survive account/
  -- message deletion; the write trigger still requires exactly one target on INSERT.
  constraint reports_at_most_one_target check (
    num_nonnulls(reported_user_id, reported_conversation_id, reported_message_id) <= 1
  ),
  constraint reports_not_self check (
    reported_user_id is null or reporter_id is null or reported_user_id <> reporter_id
  ),
  constraint reports_reason_length check (char_length(btrim(reason)) between 2 and 100),
  constraint reports_details_length check (details is null or char_length(details) <= 5000),
  constraint reports_resolution_shape check (
    (status in ('resolved', 'rejected') and resolved_at is not null)
    or (status in ('open', 'in_review') and resolved_at is null)
  ),
  constraint reports_evidence_object check (
    jsonb_typeof(evidence) = 'object' and octet_length(evidence::text) <= 524288
  )
);

create index if not exists reports_reporter_idx
  on public.reports (reporter_id, created_at desc) where reporter_id is not null;
create index if not exists reports_status_idx
  on public.reports (status, created_at);
create index if not exists reports_message_idx
  on public.reports (reported_message_id) where reported_message_id is not null;

create table if not exists public.group_invitations (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  inviter_id uuid references public.profiles(id) on delete set null,
  invitee_id uuid references public.profiles(id) on delete cascade,
  token_hash text,
  status public.invitation_status not null default 'pending',
  max_uses integer not null default 1,
  use_count integer not null default 0,
  expires_at timestamptz,
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint group_invitations_target check (
    (invitee_id is not null and token_hash is null and max_uses = 1)
    or (invitee_id is null and token_hash is not null)
  ),
  constraint group_invitations_usage check (
    max_uses between 1 and 10000 and use_count between 0 and max_uses
  ),
  constraint group_invitations_token_hash check (
    token_hash is null or token_hash ~ '^[0-9a-f]{64}$'
  ),
  constraint group_invitations_not_self check (
    invitee_id is null or inviter_id is null or invitee_id <> inviter_id
  ),
  constraint group_invitations_response_shape check (
    (status = 'pending' and responded_at is null)
    or (status <> 'pending' and responded_at is not null)
  )
);

create unique index if not exists group_invitations_token_uidx
  on public.group_invitations (token_hash) where token_hash is not null;
create unique index if not exists group_invitations_pending_invitee_uidx
  on public.group_invitations (conversation_id, invitee_id)
  where invitee_id is not null and status = 'pending';
create index if not exists group_invitations_invitee_idx
  on public.group_invitations (invitee_id, status, created_at desc)
  where invitee_id is not null;
create index if not exists group_invitations_conversation_idx
  on public.group_invitations (conversation_id, status, created_at desc);

create table if not exists public.group_join_requests (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  requester_id uuid not null references public.profiles(id) on delete cascade,
  message text,
  status public.join_request_status not null default 'pending',
  responded_by uuid references public.profiles(id) on delete set null,
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint group_join_requests_message_length check (message is null or char_length(message) <= 1000),
  constraint group_join_requests_response_shape check (
    (status = 'pending' and responded_by is null and responded_at is null)
    or (status = 'cancelled' and responded_by is null and responded_at is not null)
    or (status in ('approved', 'rejected') and responded_at is not null)
  )
);

create unique index if not exists group_join_requests_pending_uidx
  on public.group_join_requests (conversation_id, requester_id)
  where status = 'pending';
create index if not exists group_join_requests_requester_idx
  on public.group_join_requests (requester_id, status, created_at desc);
create index if not exists group_join_requests_conversation_idx
  on public.group_join_requests (conversation_id, status, created_at);

-- Polls -----------------------------------------------------------------------
create table if not exists public.polls (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null unique,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  creator_id uuid references public.profiles(id) on delete set null,
  question text not null,
  allow_multiple boolean not null default false,
  max_selections smallint not null default 1,
  is_anonymous boolean not null default false,
  closes_at timestamptz,
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint polls_question_length check (char_length(btrim(question)) between 1 and 1000),
  constraint polls_selection_shape check (
    (allow_multiple and max_selections between 1 and 20)
    or (not allow_multiple and max_selections = 1)
  ),
  constraint polls_close_shape check (
    (closes_at is null or closes_at > created_at)
    and (closed_at is null or closed_at >= created_at)
  ),
  constraint polls_message_conversation_fk
    foreign key (conversation_id, message_id)
    references public.messages(conversation_id, id) on delete cascade,
  unique (id, conversation_id)
);

create index if not exists polls_conversation_idx
  on public.polls (conversation_id, created_at desc);
create index if not exists polls_closes_at_idx
  on public.polls (closes_at) where closed_at is null and closes_at is not null;

create table if not exists public.poll_options (
  id uuid primary key default gen_random_uuid(),
  poll_id uuid not null,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  option_text text not null,
  position smallint not null,
  vote_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint poll_options_text_length check (char_length(btrim(option_text)) between 1 and 500),
  constraint poll_options_position check (position between 0 and 99),
  constraint poll_options_vote_count check (vote_count >= 0),
  constraint poll_options_poll_conversation_fk
    foreign key (poll_id, conversation_id)
    references public.polls(id, conversation_id) on delete cascade,
  unique (poll_id, position),
  unique (poll_id, id, conversation_id)
);

create index if not exists poll_options_poll_idx
  on public.poll_options (poll_id, position);
create unique index if not exists poll_options_text_lower_uidx
  on public.poll_options (poll_id, lower(option_text));

create table if not exists public.poll_votes (
  poll_id uuid not null,
  option_id uuid not null,
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  voter_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (poll_id, option_id, voter_id),
  constraint poll_votes_poll_conversation_fk
    foreign key (poll_id, conversation_id)
    references public.polls(id, conversation_id) on delete cascade,
  constraint poll_votes_option_poll_conversation_fk
    foreign key (poll_id, option_id, conversation_id)
    references public.poll_options(poll_id, id, conversation_id) on delete cascade
);

create index if not exists poll_votes_poll_voter_idx
  on public.poll_votes (poll_id, voter_id);
create index if not exists poll_votes_option_idx
  on public.poll_votes (option_id);
create index if not exists poll_votes_voter_idx
  on public.poll_votes (voter_id, created_at desc);

-- Generic utility and authorization helpers -----------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create or replace function public.object_path_conversation_id(_name text)
returns uuid
language plpgsql
immutable
strict
set search_path = public, pg_temp
as $$
declare
  _part text;
begin
  _part := split_part(_name, '/', 1);
  if _part !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  return _part::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

create or replace function public.object_path_owner_id(_name text, _segment integer default 1)
returns uuid
language plpgsql
immutable
strict
set search_path = public, pg_temp
as $$
declare
  _part text;
begin
  if _segment < 1 then
    return null;
  end if;
  _part := split_part(_name, '/', _segment);
  if _part !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  return _part::uuid;
exception when invalid_text_representation then
  return null;
end;
$$;

create or replace function public.is_safe_storage_path(_name text, _minimum_segments integer)
returns boolean
language sql
immutable
strict
set search_path = public, pg_temp
as $$
  select _minimum_segments >= 1
    and _name !~ '(^/|/$|//)'
    and _name !~ '(^|/)\.{1,2}(/|$)'
    and position(E'\\' in _name) = 0
    and cardinality(string_to_array(_name, '/')) >= _minimum_segments;
$$;

create or replace function public.is_profile_avatar_path(_name text, _owner_id uuid)
returns boolean
language sql
immutable
strict
set search_path = public, pg_temp
as $$
  select public.is_safe_storage_path(_name, 2)
    and cardinality(string_to_array(_name, '/')) = 2
    and public.object_path_owner_id(_name, 1) = _owner_id;
$$;

create or replace function public.is_conversation_object_path(
  _name text,
  _conversation_id uuid,
  _owner_id uuid
)
returns boolean
language sql
immutable
strict
set search_path = public, pg_temp
as $$
  select public.is_safe_storage_path(_name, 3)
    and cardinality(string_to_array(_name, '/')) = 3
    and public.object_path_conversation_id(_name) = _conversation_id
    and public.object_path_owner_id(_name, 2) = _owner_id;
$$;

create or replace function public.is_blocked_pair(_user_a uuid, _user_b uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(exists (
    select 1
    from public.user_blocks b
    where (b.blocker_id = _user_a and b.blocked_id = _user_b)
       or (b.blocker_id = _user_b and b.blocked_id = _user_a)
  ), false);
$$;

create or replace function public.is_conversation_member(_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(exists (
    select 1
    from public.conversation_members cm
    where cm.conversation_id = _conversation_id
      and cm.user_id = (select auth.uid())
      and cm.status = 'active'
  ), false);
$$;

create or replace function public.can_view_conversation(_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select (select auth.uid()) is not null and (
    public.is_conversation_member(_conversation_id)
    or exists (
      select 1
      from public.group_invitations gi
      where gi.conversation_id = _conversation_id
        and gi.invitee_id = (select auth.uid())
        and gi.status = 'pending'
        and (gi.expires_at is null or gi.expires_at > now())
    )
    or exists (
      select 1
      from public.group_join_requests r
      where r.conversation_id = _conversation_id
        and r.requester_id = (select auth.uid())
        and r.status = 'pending'
    )
  );
$$;

create or replace function public.is_conversation_admin(_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(exists (
    select 1
    from public.conversation_members cm
    join public.conversations c on c.id = cm.conversation_id
    where cm.conversation_id = _conversation_id
      and cm.user_id = (select auth.uid())
      and cm.status = 'active'
      and cm.role in ('owner', 'admin')
      and c.kind <> 'direct'
  ), false);
$$;

create or replace function public.is_conversation_owner(_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(exists (
    select 1
    from public.conversation_members cm
    join public.conversations c on c.id = cm.conversation_id
    where cm.conversation_id = _conversation_id
      and cm.user_id = (select auth.uid())
      and cm.status = 'active'
      and cm.role = 'owner'
      and c.kind <> 'direct'
  ), false);
$$;

create or replace function public.can_send_to_conversation(_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(exists (
    select 1
    from public.conversations c
    join public.conversation_members me
      on me.conversation_id = c.id
     and me.user_id = (select auth.uid())
     and me.status = 'active'
    where c.id = _conversation_id
      and (not c.is_locked or me.role in ('owner', 'admin'))
      and (
        c.kind <> 'direct'
        or not public.is_blocked_pair(c.direct_user_low, c.direct_user_high)
      )
  ), false);
$$;

create or replace function public.can_pin_messages(_conversation_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(exists (
    select 1
    from public.conversations c
    join public.conversation_members me
      on me.conversation_id = c.id
     and me.user_id = (select auth.uid())
     and me.status = 'active'
    where c.id = _conversation_id
      and (c.kind = 'direct' or me.role in ('owner', 'admin'))
  ), false);
$$;

create or replace function public.can_view_read_receipt(_conversation_id uuid, _subject_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_conversation_member(_conversation_id)
    and (
      _subject_user_id = (select auth.uid())
      or (
        not public.is_blocked_pair((select auth.uid()), _subject_user_id)
        and coalesce((
          select us.send_read_receipts
          from public.user_settings us
          where us.user_id = _subject_user_id
        ), true)
      )
    );
$$;

create or replace function public.can_view_typing_status(_conversation_id uuid, _subject_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_conversation_member(_conversation_id)
    and (
      _subject_user_id = (select auth.uid())
      or (
        not public.is_blocked_pair((select auth.uid()), _subject_user_id)
        and coalesce((
          select us.show_typing_status
          from public.user_settings us
          where us.user_id = _subject_user_id
        ), true)
      )
    );
$$;

create or replace function public.can_view_presence(_subject_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when (select auth.uid()) is null then false
    when _subject_user_id = (select auth.uid()) then true
    when not coalesce((
      select us.show_last_seen
      from public.user_settings us
      where us.user_id = _subject_user_id
    ), true) then false
    else not public.is_blocked_pair((select auth.uid()), _subject_user_id)
      and (
      exists (
        select 1
        from public.conversation_members mine
        join public.conversation_members theirs
          on theirs.conversation_id = mine.conversation_id
         and theirs.user_id = _subject_user_id
         and theirs.status = 'active'
        where mine.user_id = (select auth.uid())
          and mine.status = 'active'
      )
      or exists (
        select 1
        from public.contacts c
        where c.status = 'accepted'
          and (
            (c.requester_id = (select auth.uid()) and c.addressee_id = _subject_user_id)
            or (c.addressee_id = (select auth.uid()) and c.requester_id = _subject_user_id)
          )
      )
    )
  end;
$$;

create or replace function public.can_view_profile(_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select case
    when (select auth.uid()) is null then false
    when _profile_id = (select auth.uid()) then true
    when public.is_blocked_pair((select auth.uid()), _profile_id) then false
    when exists (
      select 1
      from public.conversation_members mine
      join public.conversation_members theirs
        on theirs.conversation_id = mine.conversation_id
       and theirs.user_id = _profile_id
       and theirs.status = 'active'
      where mine.user_id = (select auth.uid())
        and mine.status = 'active'
    ) then true
    when exists (
      select 1
      from public.contacts c
      where c.status in ('pending', 'accepted')
        and (
          (c.requester_id = (select auth.uid()) and c.addressee_id = _profile_id)
          or (c.addressee_id = (select auth.uid()) and c.requester_id = _profile_id)
        )
    ) then true
    when exists (
      select 1
      from public.group_invitations gi
      where gi.status = 'pending'
        and (
          (gi.invitee_id = (select auth.uid()) and gi.inviter_id = _profile_id)
          or (
            gi.invitee_id = _profile_id
            and (
              gi.inviter_id = (select auth.uid())
              or public.is_conversation_admin(gi.conversation_id)
            )
          )
        )
        and (gi.expires_at is null or gi.expires_at > now())
    ) then true
    when exists (
      select 1
      from public.group_join_requests r
      where r.requester_id = _profile_id
        and r.status = 'pending'
        and public.is_conversation_admin(r.conversation_id)
    ) then true
    else exists (
      select 1
      from public.profiles p
      where p.id = _profile_id
        and p.is_discoverable
        and not public.is_blocked_pair((select auth.uid()), _profile_id)
    )
  end;
$$;

create or replace function public.can_report_user(_profile_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select (select auth.uid()) is not null
    and _profile_id <> (select auth.uid())
    and exists (select 1 from public.profiles p where p.id = _profile_id)
    and (
      public.can_view_profile(_profile_id)
      or public.is_blocked_pair((select auth.uid()), _profile_id)
    );
$$;

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
    join public.conversation_members cm
      on cm.conversation_id = p.conversation_id
     and cm.user_id = (select auth.uid())
     and cm.status = 'active'
    where p.id = _poll_id
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
    join public.messages m on m.id = a.message_id and m.deleted_at is null
    join public.conversation_members cm
      on cm.conversation_id = a.conversation_id
     and cm.user_id = (select auth.uid())
     and cm.status = 'active'
    where a.id = _attachment_id
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
    join public.messages m on m.id = a.message_id and m.deleted_at is null
    join public.conversation_members cm
      on cm.conversation_id = a.conversation_id
     and cm.user_id = (select auth.uid())
     and cm.status = 'active'
    where (
      (a.storage_bucket = _bucket and a.storage_path = _name)
      or (_bucket = 'chat-media' and a.thumbnail_path = _name)
    )
  ), false);
$$;

-- Data-integrity triggers -------------------------------------------------------
create or replace function public.guard_profile_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _actor uuid := auth.uid();
begin
  if tg_op = 'INSERT' then
    if _actor is not null and new.id <> _actor then
      raise exception 'A profile may only be created for the authenticated user' using errcode = '42501';
    end if;
    new.created_at := now();
  else
    if new.id <> old.id or new.created_at <> old.created_at then
      raise exception 'Profile identity fields are immutable' using errcode = '42501';
    end if;
  end if;

  new.username := nullif(lower(btrim(new.username)), '');
  new.display_name := btrim(new.display_name);
  new.bio := nullif(btrim(new.bio), '');

  if new.avatar_path is not null
     and public.is_profile_avatar_path(new.avatar_path, new.id) is distinct from true then
    raise exception 'Avatar path must start with the profile UUID' using errcode = '22023';
  end if;
  return new;
end;
$$;

create or replace function public.lock_user_pair()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _a uuid;
  _b uuid;
begin
  if tg_op = 'DELETE' then
    _a := old.blocker_id;
    _b := old.blocked_id;
  else
    _a := new.blocker_id;
    _b := new.blocked_id;
  end if;
  perform pg_advisory_xact_lock(
    hashtextextended(least(_a::text, _b::text) || ':' || greatest(_a::text, _b::text), 0)
  );
  if tg_op = 'INSERT' then
    new.created_at := now();
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function public.cleanup_contacts_after_block()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  delete from public.contacts c
  where (c.requester_id = new.blocker_id and c.addressee_id = new.blocked_id)
     or (c.requester_id = new.blocked_id and c.addressee_id = new.blocker_id);
  return new;
end;
$$;

create or replace function public.guard_contact_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _actor uuid := auth.uid();
begin
  if tg_op = 'INSERT' and _actor is not null then
    new.requester_id := _actor;
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      least(new.requester_id::text, new.addressee_id::text)
      || ':' || greatest(new.requester_id::text, new.addressee_id::text),
      0
    )
  );

  if tg_op = 'INSERT' then
    new.status := 'pending';
    new.responded_at := null;
    new.created_at := now();
    if _actor is not null and not public.can_view_profile(new.addressee_id) then
      raise exception 'User not found or unavailable' using errcode = 'P0002';
    end if;
    if public.is_blocked_pair(new.requester_id, new.addressee_id) then
      raise exception 'A contact request is not allowed for blocked users' using errcode = '42501';
    end if;
    return new;
  end if;

  if new.requester_id <> old.requester_id
     or new.addressee_id <> old.addressee_id
     or new.created_at <> old.created_at then
    raise exception 'Contact identity fields are immutable' using errcode = '42501';
  end if;

  if _actor is not null then
    if _actor = old.requester_id then
      if not (old.status = 'pending' and new.status = 'cancelled') then
        raise exception 'The requester may only cancel a pending request' using errcode = '42501';
      end if;
    elsif _actor = old.addressee_id then
      if not (old.status = 'pending' and new.status in ('accepted', 'declined')) then
        raise exception 'The addressee may only accept or decline a pending request' using errcode = '42501';
      end if;
    else
      raise exception 'Not a participant in this contact request' using errcode = '42501';
    end if;
  end if;

  if new.status = 'accepted' and public.is_blocked_pair(new.requester_id, new.addressee_id) then
    raise exception 'Blocked users cannot become contacts' using errcode = '42501';
  end if;
  if new.status is distinct from old.status then
    new.responded_at := now();
  end if;
  return new;
end;
$$;

create or replace function public.guard_conversation_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _actor uuid := auth.uid();
begin
  if tg_op = 'UPDATE' and pg_trigger_depth() > 1 then
    return new;
  end if;

  if new.kind <> 'direct' then
    new.title := btrim(new.title);
    new.description := nullif(btrim(new.description), '');
  end if;

  if tg_op = 'INSERT' then
    if _actor is not null and new.created_by is distinct from _actor then
      raise exception 'created_by must be the authenticated user' using errcode = '42501';
    end if;
    if new.kind = 'direct' then
      perform pg_advisory_xact_lock(
        hashtextextended(new.direct_user_low::text || ':' || new.direct_user_high::text, 0)
      );
      if _actor is not null and _actor not in (new.direct_user_low, new.direct_user_high) then
        raise exception 'The creator must be a direct-conversation participant' using errcode = '42501';
      end if;
      if public.is_blocked_pair(new.direct_user_low, new.direct_user_high) then
        raise exception 'A direct conversation cannot be created between blocked users' using errcode = '42501';
      end if;
    elsif new.avatar_path is not null
          and public.is_conversation_object_path(new.avatar_path, new.id, new.created_by) is distinct from true then
      raise exception 'Conversation avatar path must be conversation_uuid/uploader_uuid/file' using errcode = '22023';
    end if;
    new.created_at := now();
    new.last_message_id := null;
    new.last_message_at := null;
    return new;
  end if;

  if new.id <> old.id
     or new.kind <> old.kind
     or new.direct_user_low is distinct from old.direct_user_low
     or new.direct_user_high is distinct from old.direct_user_high
     or new.created_at <> old.created_at then
    raise exception 'Conversation identity fields are immutable' using errcode = '42501';
  end if;
  if new.created_by is distinct from old.created_by then
    raise exception 'created_by is immutable' using errcode = '42501';
  end if;
  if new.avatar_path is distinct from old.avatar_path and new.avatar_path is not null then
    if new.kind = 'direct'
       or public.is_conversation_object_path(
         new.avatar_path,
         new.id,
         coalesce(_actor, public.object_path_owner_id(new.avatar_path, 2))
       ) is distinct from true then
      raise exception 'Conversation avatar path must be conversation_uuid/uploader_uuid/file' using errcode = '22023';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.guard_conversation_member_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _actor uuid := auth.uid();
  _kind public.conversation_kind;
  _creator uuid;
  _actor_role public.conversation_member_role;
  _actor_status public.conversation_member_status;
  _has_invitation boolean;
begin
  if pg_trigger_depth() > 1 then
    -- Trusted invitation/join-request triggers maintain membership atomically.
    return new;
  end if;

  select c.kind, c.created_by into _kind, _creator
  from public.conversations c
  where c.id = new.conversation_id;

  if _kind is null then
    raise exception 'Conversation not found' using errcode = '23503';
  end if;

  if tg_op = 'INSERT' then
    new.created_at := now();
    new.joined_at := coalesce(new.joined_at, now());
    new.left_at := case when new.status = 'active' then null else coalesce(new.left_at, now()) end;

    if _actor is null then
      return new;
    end if;

    if _kind = 'direct' then
      if _actor <> _creator
         or new.user_id not in (
           (select direct_user_low from public.conversations where id = new.conversation_id),
           (select direct_user_high from public.conversations where id = new.conversation_id)
         )
         or new.role <> 'member'
         or new.status <> 'active' then
        raise exception 'Invalid direct-conversation membership' using errcode = '42501';
      end if;
      return new;
    end if;

    if new.user_id = _actor then
      select exists (
        select 1
        from public.group_invitations gi
        where gi.conversation_id = new.conversation_id
          and gi.status in ('pending', 'accepted')
          and (gi.expires_at is null or gi.expires_at > now())
          and (gi.invitee_id = _actor or gi.token_hash is not null)
      ) into _has_invitation;

      if _creator = _actor
         and not exists (
           select 1 from public.conversation_members cm
           where cm.conversation_id = new.conversation_id
         ) then
        if new.role <> 'owner' or new.status <> 'active' then
          raise exception 'The first group member must be the active owner' using errcode = '42501';
        end if;
        return new;
      elsif _has_invitation and new.role = 'member' and new.status = 'active' then
        return new;
      end if;
    end if;

    select cm.role, cm.status into _actor_role, _actor_status
    from public.conversation_members cm
    where cm.conversation_id = new.conversation_id and cm.user_id = _actor;

    if _actor_status <> 'active' then
      raise exception 'Only active members may add members' using errcode = '42501';
    end if;
    if _actor_role = 'owner' and new.role in ('admin', 'member') and new.status = 'active' then
      return new;
    end if;
    if _actor_role = 'admin' and new.role = 'member' and new.status = 'active' then
      return new;
    end if;
    raise exception 'Insufficient membership role' using errcode = '42501';
  end if;

  if new.conversation_id <> old.conversation_id
     or new.user_id <> old.user_id
     or new.created_at <> old.created_at
     or new.joined_at <> old.joined_at then
    raise exception 'Membership identity fields are immutable' using errcode = '42501';
  end if;

  if new.status = 'active' then
    new.left_at := null;
  elsif new.status is distinct from old.status then
    new.left_at := now();
  end if;

  if _actor is null then
    return new;
  end if;

  if _kind = 'direct' and (new.role is distinct from old.role or new.status is distinct from old.status) then
    raise exception 'Direct-conversation membership is immutable; use archive settings instead' using errcode = '42501';
  end if;

  if _kind = 'direct' then
    return new;
  end if;

  if _actor = old.user_id then
    if old.role = 'owner' then
      if new.status not in ('active', 'left') or new.role not in ('owner', 'admin', 'member') then
        raise exception 'Invalid owner membership transition' using errcode = '42501';
      end if;
      return new;
    end if;
    if old.status = 'active' and new.status = 'left' and new.role = old.role then
      return new;
    end if;

    raise exception 'Members may only leave their own group membership' using errcode = '42501';
  end if;

  select cm.role, cm.status into _actor_role, _actor_status
  from public.conversation_members cm
  where cm.conversation_id = old.conversation_id and cm.user_id = _actor;

  if _actor_status <> 'active' then
    raise exception 'Only active members may manage membership' using errcode = '42501';
  end if;
  if _actor_role = 'owner' then
    return new;
  end if;
  if _actor_role = 'admin'
     and old.role = 'member'
     and new.role = 'member'
     and new.status in ('active', 'removed') then
    return new;
  end if;
  raise exception 'Insufficient membership role' using errcode = '42501';
end;
$$;

create or replace function public.validate_conversation_membership_shape()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _conversation_id uuid;
  _kind public.conversation_kind;
  _low uuid;
  _high uuid;
  _active_count integer;
  _owner_count integer;
begin
  _conversation_id := case
    when tg_table_name = 'conversations' then coalesce(new.id, old.id)
    else coalesce(new.conversation_id, old.conversation_id)
  end;

  select c.kind, c.direct_user_low, c.direct_user_high
    into _kind, _low, _high
  from public.conversations c
  where c.id = _conversation_id;

  if not found then
    return null;
  end if;

  select count(*) filter (where status = 'active'),
         count(*) filter (where status = 'active' and role = 'owner')
    into _active_count, _owner_count
  from public.conversation_members cm
  where cm.conversation_id = _conversation_id;

  if _kind = 'direct' then
    if _active_count <> 2 or _owner_count <> 0 or exists (
      select 1
      from public.conversation_members cm
      where cm.conversation_id = _conversation_id
        and (
          cm.user_id not in (_low, _high)
          or cm.status <> 'active'
          or cm.role <> 'member'
        )
    ) then
      raise exception 'A direct conversation must have exactly its two active member participants';
    end if;
  elsif _owner_count <> 1 then
    raise exception 'A group or channel must have exactly one active owner';
  end if;

  return null;
end;
$$;

create or replace function public.handle_profile_deletion()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _conversation record;
  _replacement uuid;
begin
  delete from public.conversations c
  where c.kind = 'direct'
    and old.id in (c.direct_user_low, c.direct_user_high);

  for _conversation in
    select cm.conversation_id
    from public.conversation_members cm
    join public.conversations c on c.id = cm.conversation_id
    where cm.user_id = old.id
      and cm.status = 'active'
      and cm.role = 'owner'
      and c.kind <> 'direct'
  loop
    select cm.user_id into _replacement
    from public.conversation_members cm
    where cm.conversation_id = _conversation.conversation_id
      and cm.user_id <> old.id
      and cm.status = 'active'
    order by case cm.role when 'admin' then 0 else 1 end, cm.joined_at
    limit 1;

    if _replacement is null then
      delete from public.conversations where id = _conversation.conversation_id;
    else
      update public.conversation_members
      set role = 'owner'
      where conversation_id = _conversation.conversation_id
        and user_id = _replacement;
    end if;
  end loop;
  return old;
end;
$$;

create or replace function public.guard_message_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _actor uuid := auth.uid();
  _reply_conversation uuid;
  _is_admin boolean;
begin
  if tg_op = 'INSERT' then
    if _actor is not null then
      new.sender_id := _actor;
    end if;
    if new.kind = 'system' then
      if _actor is not null then
        raise exception 'System messages cannot be forged by API users' using errcode = '42501';
      end if;
      new.sender_id := null;
    elsif new.sender_id is null then
      raise exception 'A message sender is required' using errcode = '23502';
    end if;
    new.created_at := now();
    new.edited_at := null;
    new.deleted_at := null;
    new.deleted_by := null;

    if new.reply_to_message_id is not null then
      select m.conversation_id into _reply_conversation
      from public.messages m
      where m.id = new.reply_to_message_id and m.deleted_at is null;
      if _reply_conversation is distinct from new.conversation_id then
        raise exception 'Reply target must be a live message in the same conversation' using errcode = '23514';
      end if;
    end if;
    return new;
  end if;

  if pg_trigger_depth() > 1 then
    return new;
  end if;

  if new.id <> old.id
     or new.conversation_id <> old.conversation_id
     or new.sender_id is distinct from old.sender_id
     or new.kind <> old.kind
     or new.reply_to_message_id is distinct from old.reply_to_message_id
     or new.client_nonce is distinct from old.client_nonce
     or new.created_at <> old.created_at then
    raise exception 'Message identity fields are immutable' using errcode = '42501';
  end if;

  if old.deleted_at is not null then
    raise exception 'A deleted message cannot be changed or restored' using errcode = '42501';
  end if;

  if _actor is not null
     and old.kind = 'poll'
     and new.deleted_at is null
     and (
       new.body is distinct from old.body
       or new.metadata is distinct from old.metadata
     ) then
    raise exception 'Poll messages must be edited through the polls table' using errcode = '42501';
  end if;

  if _actor is not null and _actor is distinct from old.sender_id then
    _is_admin := public.is_conversation_admin(old.conversation_id);
    if not _is_admin or new.deleted_at is null then
      raise exception 'Only the sender may edit a message; group admins may only delete it' using errcode = '42501';
    end if;
    if new.body is distinct from old.body or new.metadata is distinct from old.metadata then
      raise exception 'Group admins may not edit message content' using errcode = '42501';
    end if;
  end if;

  if new.deleted_at is not null then
    new.deleted_at := now();
    new.deleted_by := coalesce(_actor, old.sender_id);
    new.body := null;
    new.metadata := '{}'::jsonb;
  elsif new.body is distinct from old.body or new.metadata is distinct from old.metadata then
    new.edited_at := now();
  end if;
  return new;
end;
$$;

create or replace function public.sync_conversation_last_message()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _last_id uuid;
  _last_at timestamptz;
begin
  if tg_op = 'INSERT' and new.deleted_at is null then
    update public.conversations c
    set last_message_id = new.id,
        last_message_at = new.created_at
    where c.id = new.conversation_id
      and (c.last_message_at is null or (new.created_at, new.id) >= (c.last_message_at, coalesce(c.last_message_id, new.id)));
  elsif tg_op = 'UPDATE'
        and old.deleted_at is null
        and new.deleted_at is not null then
    select m.id, m.created_at into _last_id, _last_at
    from public.messages m
    where m.conversation_id = new.conversation_id
      and m.deleted_at is null
    order by m.created_at desc, m.id desc
    limit 1;

    update public.conversations
    set last_message_id = _last_id,
        last_message_at = _last_at
    where id = new.conversation_id
      and (last_message_id = new.id or _last_id is null or last_message_at <= old.created_at);
  elsif tg_op = 'DELETE' then
    select m.id, m.created_at into _last_id, _last_at
    from public.messages m
    where m.conversation_id = old.conversation_id
      and m.deleted_at is null
    order by m.created_at desc, m.id desc
    limit 1;

    update public.conversations
    set last_message_id = _last_id,
        last_message_at = _last_at
    where id = old.conversation_id;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;

create or replace function public.guard_attachment_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _actor uuid := auth.uid();
  _conversation_id uuid;
  _sender_id uuid;
  _message_kind public.message_kind;
begin
  if tg_op = 'UPDATE' and pg_trigger_depth() > 1 then
    return new;
  end if;

  if tg_op = 'INSERT' then
    select m.conversation_id, m.sender_id, m.kind
      into _conversation_id, _sender_id, _message_kind
    from public.messages m
    where m.id = new.message_id and m.deleted_at is null;

    if _conversation_id is null then
      raise exception 'Attachment message does not exist or is deleted' using errcode = '23503';
    end if;
    if _actor is not null and _sender_id is distinct from _actor then
      raise exception 'Attachments may only be added to your own message' using errcode = '42501';
    end if;
    if _message_kind::text not in ('image', 'video', 'file', 'audio', 'voice')
       or new.kind::text <> _message_kind::text then
      raise exception 'Attachment kind must match an attachment message kind' using errcode = '23514';
    end if;

    new.conversation_id := _conversation_id;
    new.uploaded_by := coalesce(_actor, new.uploaded_by);
    new.created_at := now();

    if public.is_conversation_object_path(
         new.storage_path,
         _conversation_id,
         new.uploaded_by
       ) is distinct from true then
      raise exception 'Attachment path must be conversation_uuid/uploader_uuid/file' using errcode = '22023';
    end if;
    if new.thumbnail_path is not null and public.is_conversation_object_path(
      new.thumbnail_path,
      _conversation_id,
      new.uploaded_by
    ) is distinct from true then
      raise exception 'Thumbnail path must be conversation_uuid/uploader_uuid/file' using errcode = '22023';
    end if;
    if new.kind = 'voice' and new.storage_bucket <> 'voice-messages' then
      raise exception 'Voice attachments belong in voice-messages' using errcode = '23514';
    elsif new.kind <> 'voice' and new.storage_bucket <> 'chat-media' then
      raise exception 'Non-voice attachments belong in chat-media' using errcode = '23514';
    end if;
    return new;
  end if;

  raise exception 'Attachment rows are immutable; delete and recreate them' using errcode = '42501';
end;
$$;

create or replace function public.guard_reaction_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not exists (
    select 1 from public.messages m
    where m.id = new.message_id and m.deleted_at is null
  ) then
    raise exception 'Reactions require a live message' using errcode = '23514';
  end if;
  if auth.uid() is not null then
    new.user_id := auth.uid();
  end if;
  new.emoji := btrim(new.emoji);
  new.created_at := now();
  return new;
end;
$$;

create or replace function public.guard_read_receipt_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _actor uuid := auth.uid();
  _message_conversation uuid;
  _message_created_at timestamptz;
  _old_message_created_at timestamptz;
begin
  if tg_op = 'UPDATE' and pg_trigger_depth() > 1 then
    -- Allow FK maintenance when the referenced message is physically deleted.
    return new;
  end if;

  if tg_op = 'INSERT' and _actor is not null then
    new.user_id := _actor;
    new.created_at := now();
  elsif tg_op = 'UPDATE' and (
    new.conversation_id <> old.conversation_id
    or new.user_id <> old.user_id
    or new.created_at <> old.created_at
  ) then
    raise exception 'Read-receipt identity fields are immutable' using errcode = '42501';
  end if;

  if new.last_read_message_id is not null then
    select m.conversation_id, m.created_at into _message_conversation, _message_created_at
    from public.messages m where m.id = new.last_read_message_id;
    if _message_conversation is distinct from new.conversation_id then
      raise exception 'Read marker must reference the same conversation' using errcode = '23514';
    end if;
  end if;

  if tg_op = 'UPDATE' and _actor is not null and old.last_read_message_id is not null then
    if new.last_read_message_id is null then
      raise exception 'Read receipts cannot move backwards' using errcode = '23514';
    end if;
    select m.created_at into _old_message_created_at
    from public.messages m where m.id = old.last_read_message_id;
    if (_message_created_at, new.last_read_message_id) < (_old_message_created_at, old.last_read_message_id) then
      raise exception 'Read receipts cannot move backwards' using errcode = '23514';
    end if;
  end if;

  new.last_read_at := now();
  return new;
end;
$$;

create or replace function public.guard_typing_write()
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
  elsif new.conversation_id <> old.conversation_id or new.user_id <> old.user_id then
    raise exception 'Typing identity fields are immutable' using errcode = '42501';
  end if;
  new.expires_at := least(coalesce(new.expires_at, now() + interval '12 seconds'), now() + interval '30 seconds');
  return new;
end;
$$;

create or replace function public.guard_presence_write()
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
  elsif new.user_id <> old.user_id then
    raise exception 'Presence identity fields are immutable' using errcode = '42501';
  end if;

  new.last_seen_at := now();
  if new.online_until is not null then
    new.online_until := least(new.online_until, now() + interval '5 minutes');
  end if;
  return new;
end;
$$;

create or replace function public.guard_device_write()
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
  elsif new.id <> old.id or new.created_at <> old.created_at then
    raise exception 'Device identity fields are immutable' using errcode = '42501';
  elsif new.user_id <> old.user_id
        and (_actor is null or new.user_id <> _actor or new.fcm_token <> old.fcm_token) then
    raise exception 'A device token may only be reassigned to the authenticated user' using errcode = '42501';
  end if;

  new.fcm_token := btrim(new.fcm_token);
  new.device_name := nullif(btrim(new.device_name), '');
  new.app_version := nullif(btrim(new.app_version), '');
  new.last_seen_at := now();
  if tg_op = 'UPDATE' and new.disabled_at is not null and old.disabled_at is null then
    new.disabled_at := now();
  end if;
  return new;
end;
$$;

create or replace function public.guard_message_pin_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _message_conversation uuid;
begin
  if tg_op = 'INSERT' then
    select m.conversation_id into _message_conversation
    from public.messages m where m.id = new.message_id and m.deleted_at is null;
    if _message_conversation is distinct from new.conversation_id then
      raise exception 'Pinned message must belong to the conversation' using errcode = '23514';
    end if;
    if auth.uid() is not null then
      new.pinned_by := auth.uid();
    end if;
    new.pinned_at := now();
  end if;
  return new;
end;
$$;

create or replace function public.guard_conversation_user_settings_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
  elsif new.conversation_id <> old.conversation_id
        or new.user_id <> old.user_id
        or new.created_at <> old.created_at then
    raise exception 'Conversation-setting identity fields are immutable' using errcode = '42501';
  end if;

  new.custom_title := nullif(btrim(new.custom_title), '');
  return new;
end;
$$;

create or replace function public.guard_user_settings_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
  elsif new.user_id <> old.user_id or new.created_at <> old.created_at then
    raise exception 'User-setting identity fields are immutable' using errcode = '42501';
  end if;
  new.locale := lower(btrim(new.locale));
  return new;
end;
$$;

create or replace function public.guard_chat_folder_write()
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
  elsif new.id <> old.id
        or new.user_id <> old.user_id
        or new.created_at <> old.created_at then
    raise exception 'Chat-folder identity fields are immutable' using errcode = '42501';
  end if;

  new.name := btrim(new.name);
  new.color := upper(nullif(btrim(new.color), ''));
  new.icon := nullif(btrim(new.icon), '');
  return new;
end;
$$;

create or replace function public.guard_folder_conversation_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _folder_user uuid;
begin
  if tg_op = 'UPDATE' and (
    new.folder_id <> old.folder_id
    or new.conversation_id <> old.conversation_id
    or new.user_id <> old.user_id
    or new.added_at <> old.added_at
  ) then
    raise exception 'Folder-conversation identity fields are immutable' using errcode = '42501';
  end if;

  select f.user_id into _folder_user from public.chat_folders f where f.id = new.folder_id;
  if _folder_user is null then
    raise exception 'Chat folder not found' using errcode = '23503';
  end if;
  new.user_id := _folder_user;
  if tg_op = 'INSERT' then
    new.added_at := now();
  end if;
  return new;
end;
$$;

create or replace function public.guard_report_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'UPDATE' and pg_trigger_depth() > 1 then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if auth.uid() is not null then
      new.reporter_id := auth.uid();
    end if;
    if num_nonnulls(new.reported_user_id, new.reported_conversation_id, new.reported_message_id) <> 1 then
      raise exception 'A report must have exactly one target' using errcode = '23514';
    end if;
    if new.reported_user_id is not null and new.reported_user_id = new.reporter_id then
      raise exception 'Users cannot report themselves' using errcode = '23514';
    end if;
    new.reason := btrim(new.reason);
    new.details := nullif(btrim(new.details), '');
    new.status := 'open';
    new.resolved_at := null;
    new.created_at := now();
    return new;
  end if;

  if auth.uid() is not null then
    raise exception 'Reports cannot be changed by API users' using errcode = '42501';
  end if;
  if new.status in ('resolved', 'rejected') and old.status not in ('resolved', 'rejected') then
    new.resolved_at := now();
  elsif new.status not in ('resolved', 'rejected') then
    new.resolved_at := null;
  end if;
  return new;
end;
$$;

create or replace function public.guard_invitation_write()
returns trigger
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  _kind public.conversation_kind;
  _actor uuid := auth.uid();
begin
  if tg_op = 'UPDATE' and pg_trigger_depth() > 1 then
    return new;
  end if;

  select kind into _kind from public.conversations where id = new.conversation_id;
  if _kind = 'direct' or _kind is null then
    raise exception 'Invitations are only valid for groups and channels' using errcode = '23514';
  end if;

  if tg_op = 'INSERT' then
    if _actor is not null then
      new.inviter_id := _actor;
    end if;
    new.status := 'pending';
    new.use_count := 0;
    new.created_at := now();
    if new.expires_at is not null and new.expires_at <= now() then
      raise exception 'Invitation expiration must be in the future' using errcode = '22023';
    end if;
    if _actor is not null
       and new.invitee_id is not null
       and not public.can_view_profile(new.invitee_id) then
      raise exception 'Invitee not found or unavailable' using errcode = 'P0002';
    end if;
    if new.invitee_id is not null and exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = new.conversation_id
        and cm.user_id = new.invitee_id
        and cm.status in ('active', 'banned')
    ) then
      raise exception 'The invitee is already active or banned' using errcode = '23514';
    end if;
    if new.invitee_id is not null and public.is_blocked_pair(new.inviter_id, new.invitee_id) then
      raise exception 'A targeted invitation is not allowed for blocked users' using errcode = '42501';
    end if;
    return new;
  end if;

  -- Link-invite consumption is performed only by accept_group_invite_token().
  -- API roles have no UPDATE privilege on use_count, so this exact transition
  -- cannot be forged through a regular table update.
  if old.invitee_id is null
     and old.token_hash is not null
     and old.status = 'pending'
     and new.id = old.id
     and new.conversation_id = old.conversation_id
     and new.inviter_id is not distinct from old.inviter_id
     and new.invitee_id is null
     and new.token_hash = old.token_hash
     and new.max_uses = old.max_uses
     and new.use_count = old.use_count + 1
     and new.use_count <= new.max_uses
     and new.expires_at is not distinct from old.expires_at
     and new.created_at = old.created_at
     and new.status = (
       case
         when new.use_count = new.max_uses then 'accepted'::public.invitation_status
         else 'pending'::public.invitation_status
       end
     ) then
    if old.expires_at is not null and old.expires_at <= now() then
      raise exception 'Invite token is expired' using errcode = '42501';
    end if;
    if new.status = 'accepted' then
      new.responded_at := now();
    end if;
    return new;
  end if;

  if new.id <> old.id
     or new.conversation_id <> old.conversation_id
     or new.inviter_id is distinct from old.inviter_id
     or new.invitee_id is distinct from old.invitee_id
     or new.token_hash is distinct from old.token_hash
     or new.max_uses <> old.max_uses
     or new.use_count <> old.use_count
     or new.expires_at is distinct from old.expires_at
     or new.created_at <> old.created_at then
    raise exception 'Invitation fields other than status are immutable to API users' using errcode = '42501';
  end if;

  if old.status <> 'pending' then
    raise exception 'Only pending invitations may be changed' using errcode = '23514';
  end if;
  if old.expires_at is not null
     and old.expires_at <= now()
     and new.status = 'accepted' then
    raise exception 'Expired invitations cannot be accepted' using errcode = '42501';
  end if;
  if _actor is not null and _actor = old.invitee_id then
    if new.status not in ('accepted', 'declined') then
      raise exception 'Invitees may only accept or decline' using errcode = '42501';
    end if;
  elsif _actor is not null and public.is_conversation_admin(old.conversation_id) then
    if new.status <> 'revoked' then
      raise exception 'Administrators may only revoke invitations directly' using errcode = '42501';
    end if;
  elsif _actor is not null then
    raise exception 'Not allowed to change this invitation' using errcode = '42501';
  end if;

  if new.status in ('accepted', 'declined', 'revoked', 'expired') then
    new.responded_at := now();
  end if;
  return new;
end;
$$;

create or replace function public.apply_accepted_invitation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'accepted' and old.status is distinct from new.status and new.invitee_id is not null then
    if exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = new.conversation_id
        and cm.user_id = new.invitee_id
        and cm.status = 'banned'
    ) then
      raise exception 'Banned users cannot accept invitations' using errcode = '42501';
    end if;

    insert into public.conversation_members (
      conversation_id, user_id, role, status, invited_by, joined_at
    ) values (
      new.conversation_id, new.invitee_id, 'member', 'active', new.inviter_id, now()
    )
    on conflict (conversation_id, user_id) do update
      set role = 'member', status = 'active', invited_by = excluded.invited_by,
          joined_at = now(), left_at = null;

    update public.group_join_requests
    set status = 'cancelled', responded_by = null, responded_at = now()
    where conversation_id = new.conversation_id
      and requester_id = new.invitee_id
      and status = 'pending';
  end if;
  return new;
end;
$$;

create or replace function public.guard_join_request_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _kind public.conversation_kind;
  _join_enabled boolean;
  _actor uuid := auth.uid();
begin
  if tg_op = 'UPDATE' and pg_trigger_depth() > 1 then
    return new;
  end if;

  select kind, join_requests_enabled into _kind, _join_enabled
  from public.conversations where id = new.conversation_id;
  if _kind = 'direct' or _kind is null then
    raise exception 'Join requests are only valid for groups and channels' using errcode = '23514';
  end if;

  if tg_op = 'INSERT' then
    if _actor is not null and not _join_enabled then
      raise exception 'Join requests are disabled for this conversation' using errcode = '42501';
    end if;
    if _actor is not null then
      new.requester_id := _actor;
    end if;
    if exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = new.conversation_id
        and cm.user_id = new.requester_id
        and cm.status in ('active', 'banned')
    ) then
      raise exception 'Active or banned users cannot request membership' using errcode = '23514';
    end if;
    new.message := nullif(btrim(new.message), '');
    new.status := 'pending';
    new.responded_by := null;
    new.responded_at := null;
    new.created_at := now();
    return new;
  end if;

  if new.id <> old.id
     or new.conversation_id <> old.conversation_id
     or new.requester_id <> old.requester_id
     or new.message is distinct from old.message
     or new.created_at <> old.created_at then
    raise exception 'Join-request identity fields are immutable' using errcode = '42501';
  end if;
  if old.status <> 'pending' then
    raise exception 'Only pending join requests may be changed' using errcode = '23514';
  end if;

  if _actor is not null and _actor = old.requester_id then
    if new.status <> 'cancelled' then
      raise exception 'Requesters may only cancel' using errcode = '42501';
    end if;
  elsif _actor is not null and public.is_conversation_admin(old.conversation_id) then
    if new.status not in ('approved', 'rejected') then
      raise exception 'Administrators may only approve or reject' using errcode = '42501';
    end if;
    new.responded_by := _actor;
  elsif _actor is not null then
    raise exception 'Not allowed to change this join request' using errcode = '42501';
  end if;

  new.responded_at := now();
  return new;
end;
$$;

create or replace function public.apply_approved_join_request()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'approved' and old.status is distinct from new.status then
    if exists (
      select 1 from public.conversation_members cm
      where cm.conversation_id = new.conversation_id
        and cm.user_id = new.requester_id
        and cm.status = 'banned'
    ) then
      raise exception 'Banned users cannot be approved' using errcode = '42501';
    end if;

    insert into public.conversation_members (
      conversation_id, user_id, role, status, invited_by, joined_at
    ) values (
      new.conversation_id, new.requester_id, 'member', 'active', new.responded_by, now()
    )
    on conflict (conversation_id, user_id) do update
      set role = 'member', status = 'active', invited_by = excluded.invited_by,
          joined_at = now(), left_at = null
      where public.conversation_members.status <> 'banned';

    update public.group_invitations
    set status = 'revoked', responded_at = now()
    where conversation_id = new.conversation_id
      and invitee_id = new.requester_id
      and status = 'pending';
  end if;
  return new;
end;
$$;

create or replace function public.guard_poll_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _message_conversation uuid;
  _message_sender uuid;
  _message_kind public.message_kind;
begin
  if tg_op = 'UPDATE' and pg_trigger_depth() > 1 then
    return new;
  end if;

  if tg_op = 'INSERT' then
    select m.conversation_id, m.sender_id, m.kind
      into _message_conversation, _message_sender, _message_kind
    from public.messages m where m.id = new.message_id and m.deleted_at is null;
    if _message_kind is distinct from 'poll' or _message_conversation is null then
      raise exception 'A poll must reference a live poll message' using errcode = '23514';
    end if;
    if auth.uid() is not null and _message_sender is distinct from auth.uid() then
      raise exception 'A poll may only be created for your own message' using errcode = '42501';
    end if;
    new.conversation_id := _message_conversation;
    new.creator_id := _message_sender;
    new.question := btrim(new.question);
    new.created_at := now();
    update public.messages
    set body = new.question, edited_at = null
    where id = new.message_id;
    return new;
  end if;

  if not exists (
    select 1 from public.messages m
    where m.id = old.message_id and m.deleted_at is null
  ) then
    raise exception 'A deleted poll message cannot be changed' using errcode = '23514';
  end if;

  if old.closed_at is null and old.closes_at is not null and old.closes_at <= now() then
    if new.closed_at is null
       or new.question is distinct from old.question
       or new.allow_multiple is distinct from old.allow_multiple
       or new.max_selections is distinct from old.max_selections
       or new.is_anonymous is distinct from old.is_anonymous
       or new.closes_at is distinct from old.closes_at then
      raise exception 'An expired poll may only be closed' using errcode = '23514';
    end if;
  end if;

  if new.id <> old.id
     or new.message_id <> old.message_id
     or new.conversation_id <> old.conversation_id
     or new.creator_id is distinct from old.creator_id
     or new.created_at <> old.created_at then
    raise exception 'Poll identity fields are immutable' using errcode = '42501';
  end if;
  if auth.uid() is not null and auth.uid() is distinct from old.creator_id
     and (
       new.question is distinct from old.question
       or new.allow_multiple is distinct from old.allow_multiple
       or new.max_selections is distinct from old.max_selections
       or new.is_anonymous is distinct from old.is_anonymous
       or new.closes_at is distinct from old.closes_at
       or new.closed_at is null
     ) then
    raise exception 'Group administrators may only close another user''s poll' using errcode = '42501';
  end if;
  if old.closed_at is not null and new is distinct from old then
    raise exception 'A closed poll cannot be edited' using errcode = '23514';
  end if;
  if exists (select 1 from public.poll_votes pv where pv.poll_id = old.id)
     and (
       new.allow_multiple is distinct from old.allow_multiple
       or new.max_selections is distinct from old.max_selections
       or new.is_anonymous is distinct from old.is_anonymous
     ) then
    raise exception 'Poll voting rules and anonymity are immutable after the first vote' using errcode = '23514';
  end if;
  if new.closed_at is not null and old.closed_at is null then
    new.closed_at := now();
  end if;
  new.question := btrim(new.question);
  if new.question is distinct from old.question then
    update public.messages
    set body = new.question, edited_at = now()
    where id = new.message_id;
  end if;
  return new;
end;
$$;

create or replace function public.guard_poll_option_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _conversation_id uuid;
  _closed boolean;
  _message_live boolean;
  _option_count integer;
begin
  if tg_op = 'UPDATE'
     and pg_trigger_depth() > 1
     and new.id = old.id
     and new.poll_id = old.poll_id
     and new.conversation_id = old.conversation_id
     and new.option_text = old.option_text
     and new.position = old.position
     and new.created_at = old.created_at then
    -- Internal maintenance by sync_poll_vote_count(), including FK cascades.
    return new;
  end if;

  select p.conversation_id,
         (p.closed_at is not null or (p.closes_at is not null and p.closes_at <= now())),
         exists (
           select 1 from public.messages m
           where m.id = p.message_id and m.deleted_at is null
         )
    into _conversation_id, _closed, _message_live
  from public.polls p where p.id = new.poll_id;
  if _conversation_id is null then
    raise exception 'Poll not found' using errcode = '23503';
  end if;
  if not _message_live then
    raise exception 'A deleted poll message cannot be changed' using errcode = '23514';
  end if;
  if _closed then
    raise exception 'A closed poll cannot be changed' using errcode = '23514';
  end if;

  if tg_op = 'INSERT' then
    select count(*) into _option_count
    from public.poll_options po
    where po.poll_id = new.poll_id;
    if _option_count >= 20 or new.position <> _option_count then
      raise exception 'Poll options must be appended contiguously from position zero' using errcode = '23514';
    end if;

    new.conversation_id := _conversation_id;
    new.option_text := btrim(new.option_text);
    new.vote_count := 0;
    new.created_at := now();
  elsif new.id <> old.id
        or new.poll_id <> old.poll_id
        or new.conversation_id <> old.conversation_id
        or new.vote_count <> old.vote_count
        or new.created_at <> old.created_at then
    raise exception 'Poll-option identity and vote count are immutable to API users' using errcode = '42501';
  else
    if exists (select 1 from public.poll_votes pv where pv.poll_id = old.poll_id)
       and (
         new.option_text is distinct from old.option_text
         or new.position is distinct from old.position
       ) then
      raise exception 'Poll options are immutable after the first vote' using errcode = '23514';
    end if;
    new.option_text := btrim(new.option_text);
  end if;
  return new;
end;
$$;

create or replace function public.guard_poll_vote_write()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _poll public.polls%rowtype;
  _selection_count integer;
begin
  if tg_op = 'DELETE' and pg_trigger_depth() > 1 then
    -- Allow FK cascades when a poll/message/conversation is removed.
    return old;
  end if;

  if tg_op = 'DELETE' then
    select * into _poll from public.polls where id = old.poll_id for update;
    if _poll.closed_at is not null or (_poll.closes_at is not null and _poll.closes_at <= now()) then
      raise exception 'Votes cannot be removed from a closed poll' using errcode = '23514';
    end if;
    return old;
  end if;

  select * into _poll from public.polls where id = new.poll_id for update;
  if not found then
    raise exception 'Poll not found' using errcode = '23503';
  end if;
  if not exists (
    select 1 from public.messages m
    where m.id = _poll.message_id and m.deleted_at is null
  ) then
    raise exception 'Votes cannot be changed on a deleted poll message' using errcode = '23514';
  end if;
  if _poll.closed_at is not null or (_poll.closes_at is not null and _poll.closes_at <= now()) then
    raise exception 'The poll is closed' using errcode = '23514';
  end if;
  if not exists (
    select 1 from public.poll_options po
    where po.id = new.option_id and po.poll_id = new.poll_id
  ) then
    raise exception 'The option does not belong to the poll' using errcode = '23514';
  end if;

  if auth.uid() is not null then
    new.voter_id := auth.uid();
  end if;
  new.conversation_id := _poll.conversation_id;
  new.created_at := now();

  select count(*) into _selection_count
  from public.poll_votes pv
  where pv.poll_id = new.poll_id and pv.voter_id = new.voter_id;

  if (not _poll.allow_multiple and _selection_count >= 1)
     or (_poll.allow_multiple and _selection_count >= _poll.max_selections) then
    raise exception 'Poll selection limit reached' using errcode = '23514';
  end if;
  return new;
end;
$$;

create or replace function public.sync_poll_vote_count()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    update public.poll_options set vote_count = vote_count + 1 where id = new.option_id;
    return new;
  else
    update public.poll_options set vote_count = greatest(vote_count - 1, 0) where id = old.option_id;
    return old;
  end if;
end;
$$;

create or replace function public.validate_poll_message_shape()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _message_id uuid;
  _kind public.message_kind;
  _body text;
  _deleted_at timestamptz;
  _poll_count integer;
  _poll_question text;
begin
  _message_id := case when tg_table_name = 'messages' then coalesce(new.id, old.id) else coalesce(new.message_id, old.message_id) end;
  select m.kind, m.body, m.deleted_at into _kind, _body, _deleted_at
  from public.messages m where m.id = _message_id;
  if not found then
    return null;
  end if;
  select count(*), min(p.question) into _poll_count, _poll_question
  from public.polls p where p.message_id = _message_id;
  if _deleted_at is null and (
    (_kind = 'poll' and (_poll_count <> 1 or _body is distinct from _poll_question))
    or (_kind <> 'poll' and _poll_count <> 0)
  ) then
    raise exception 'Live poll messages and poll rows must have a synchronized one-to-one relationship';
  end if;
  return null;
end;
$$;

create or replace function public.validate_poll_options_shape()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _poll_id uuid;
  _max_selections smallint;
  _option_count integer;
  _min_position smallint;
  _max_position smallint;
begin
  _poll_id := case
    when tg_table_name = 'polls' then coalesce(new.id, old.id)
    else coalesce(new.poll_id, old.poll_id)
  end;

  select p.max_selections into _max_selections
  from public.polls p
  where p.id = _poll_id;
  if not found then
    return null;
  end if;

  select count(*), min(po.position), max(po.position)
    into _option_count, _min_position, _max_position
  from public.poll_options po
  where po.poll_id = _poll_id;

  if _option_count not between 2 and 20 then
    raise exception 'A poll must have between 2 and 20 options';
  end if;
  if _max_selections > _option_count then
    raise exception 'max_selections cannot exceed the option count';
  end if;
  if _min_position <> 0 or _max_position <> _option_count - 1 then
    raise exception 'Poll option positions must be contiguous and start at zero';
  end if;
  return null;
end;
$$;

-- Trigger installation ---------------------------------------------------------
do $$
declare
  _table text;
begin
  foreach _table in array array[
    'profiles', 'contacts', 'conversations', 'conversation_members', 'messages',
    'message_attachments', 'conversation_read_receipts', 'conversation_typing',
    'conversation_user_settings', 'chat_folders', 'user_settings', 'user_presence', 'user_devices',
    'reports', 'group_invitations', 'group_join_requests', 'polls', 'poll_options'
  ] loop
    execute format('drop trigger if exists set_updated_at on public.%I', _table);
    execute format(
      'create trigger set_updated_at before insert or update on public.%I for each row execute function public.set_updated_at()',
      _table
    );
  end loop;
end $$;

drop trigger if exists guard_profile_write on public.profiles;
create trigger guard_profile_write
before insert or update on public.profiles
for each row execute function public.guard_profile_write();

drop trigger if exists profile_deletion_cleanup on public.profiles;
create trigger profile_deletion_cleanup
before delete on public.profiles
for each row execute function public.handle_profile_deletion();

drop trigger if exists lock_block_pair on public.user_blocks;
create trigger lock_block_pair
before insert or delete on public.user_blocks
for each row execute function public.lock_user_pair();

drop trigger if exists cleanup_contacts_after_block on public.user_blocks;
create trigger cleanup_contacts_after_block
after insert on public.user_blocks
for each row execute function public.cleanup_contacts_after_block();

drop trigger if exists guard_contact_write on public.contacts;
create trigger guard_contact_write
before insert or update on public.contacts
for each row execute function public.guard_contact_write();

drop trigger if exists guard_conversation_write on public.conversations;
create trigger guard_conversation_write
before insert or update on public.conversations
for each row execute function public.guard_conversation_write();

drop trigger if exists guard_conversation_member_write on public.conversation_members;
create trigger guard_conversation_member_write
before insert or update on public.conversation_members
for each row execute function public.guard_conversation_member_write();

drop trigger if exists validate_conversation_shape_from_conversation on public.conversations;
create constraint trigger validate_conversation_shape_from_conversation
after insert or update on public.conversations
deferrable initially deferred
for each row execute function public.validate_conversation_membership_shape();

drop trigger if exists validate_conversation_shape_from_member on public.conversation_members;
create constraint trigger validate_conversation_shape_from_member
after insert or update or delete on public.conversation_members
deferrable initially deferred
for each row execute function public.validate_conversation_membership_shape();

drop trigger if exists guard_message_write on public.messages;
create trigger guard_message_write
before insert or update on public.messages
for each row execute function public.guard_message_write();

drop trigger if exists sync_conversation_last_message on public.messages;
create trigger sync_conversation_last_message
after insert or delete or update of deleted_at on public.messages
for each row execute function public.sync_conversation_last_message();

drop trigger if exists validate_poll_message_from_message on public.messages;
create constraint trigger validate_poll_message_from_message
after insert or update on public.messages
deferrable initially deferred
for each row execute function public.validate_poll_message_shape();

drop trigger if exists guard_attachment_write on public.message_attachments;
create trigger guard_attachment_write
before insert or update on public.message_attachments
for each row execute function public.guard_attachment_write();

drop trigger if exists guard_reaction_write on public.message_reactions;
create trigger guard_reaction_write
before insert on public.message_reactions
for each row execute function public.guard_reaction_write();

drop trigger if exists guard_read_receipt_write on public.conversation_read_receipts;
create trigger guard_read_receipt_write
before insert or update on public.conversation_read_receipts
for each row execute function public.guard_read_receipt_write();

drop trigger if exists guard_typing_write on public.conversation_typing;
create trigger guard_typing_write
before insert or update on public.conversation_typing
for each row execute function public.guard_typing_write();

drop trigger if exists guard_presence_write on public.user_presence;
create trigger guard_presence_write
before insert or update on public.user_presence
for each row execute function public.guard_presence_write();

drop trigger if exists guard_device_write on public.user_devices;
create trigger guard_device_write
before insert or update on public.user_devices
for each row execute function public.guard_device_write();

drop trigger if exists guard_message_pin_write on public.message_pins;
create trigger guard_message_pin_write
before insert on public.message_pins
for each row execute function public.guard_message_pin_write();

drop trigger if exists guard_conversation_user_settings_write on public.conversation_user_settings;
create trigger guard_conversation_user_settings_write
before insert or update on public.conversation_user_settings
for each row execute function public.guard_conversation_user_settings_write();

drop trigger if exists guard_user_settings_write on public.user_settings;
create trigger guard_user_settings_write
before insert or update on public.user_settings
for each row execute function public.guard_user_settings_write();

drop trigger if exists guard_chat_folder_write on public.chat_folders;
create trigger guard_chat_folder_write
before insert or update on public.chat_folders
for each row execute function public.guard_chat_folder_write();

drop trigger if exists guard_folder_conversation_write on public.chat_folder_conversations;
create trigger guard_folder_conversation_write
before insert or update on public.chat_folder_conversations
for each row execute function public.guard_folder_conversation_write();

drop trigger if exists guard_report_write on public.reports;
create trigger guard_report_write
before insert or update on public.reports
for each row execute function public.guard_report_write();

drop trigger if exists guard_invitation_write on public.group_invitations;
create trigger guard_invitation_write
before insert or update on public.group_invitations
for each row execute function public.guard_invitation_write();

drop trigger if exists apply_accepted_invitation on public.group_invitations;
create trigger apply_accepted_invitation
after update of status on public.group_invitations
for each row execute function public.apply_accepted_invitation();

drop trigger if exists guard_join_request_write on public.group_join_requests;
create trigger guard_join_request_write
before insert or update on public.group_join_requests
for each row execute function public.guard_join_request_write();

drop trigger if exists apply_approved_join_request on public.group_join_requests;
create trigger apply_approved_join_request
after update of status on public.group_join_requests
for each row execute function public.apply_approved_join_request();

drop trigger if exists guard_poll_write on public.polls;
create trigger guard_poll_write
before insert or update on public.polls
for each row execute function public.guard_poll_write();

drop trigger if exists validate_poll_message_from_poll on public.polls;
create constraint trigger validate_poll_message_from_poll
after insert or update or delete on public.polls
deferrable initially deferred
for each row execute function public.validate_poll_message_shape();

drop trigger if exists validate_poll_options_from_poll on public.polls;
create constraint trigger validate_poll_options_from_poll
after insert or update on public.polls
deferrable initially deferred
for each row execute function public.validate_poll_options_shape();

drop trigger if exists guard_poll_option_write on public.poll_options;
create trigger guard_poll_option_write
before insert or update on public.poll_options
for each row execute function public.guard_poll_option_write();

drop trigger if exists validate_poll_options_from_option on public.poll_options;
create constraint trigger validate_poll_options_from_option
after insert or update or delete on public.poll_options
deferrable initially deferred
for each row execute function public.validate_poll_options_shape();

drop trigger if exists guard_poll_vote_write on public.poll_votes;
create trigger guard_poll_vote_write
before insert or delete on public.poll_votes
for each row execute function public.guard_poll_vote_write();

drop trigger if exists sync_poll_vote_count on public.poll_votes;
create trigger sync_poll_vote_count
after insert or delete on public.poll_votes
for each row execute function public.sync_poll_vote_count();

-- Atomic client RPCs ------------------------------------------------------------
create or replace function public.register_device(
  _platform public.device_platform,
  _fcm_token text,
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

  insert into public.user_devices (
    user_id, platform, device_name, fcm_token, app_version, last_seen_at, disabled_at
  ) values (
    _me, _platform, nullif(btrim(_device_name), ''), btrim(_fcm_token),
    nullif(btrim(_app_version), ''), now(), null
  )
  on conflict (fcm_token) do update
    set user_id = excluded.user_id,
        platform = excluded.platform,
        device_name = excluded.device_name,
        app_version = excluded.app_version,
        last_seen_at = now(),
        disabled_at = null
  returning id into _device_id;

  return _device_id;
end;
$$;

create or replace function public.create_direct_conversation(_other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _me uuid := auth.uid();
  _low uuid;
  _high uuid;
  _conversation_id uuid;
begin
  if _me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if _other_user_id is null or _other_user_id = _me then
    raise exception 'A different participant is required' using errcode = '22023';
  end if;
  if not public.can_view_profile(_other_user_id) then
    raise exception 'User not found or unavailable' using errcode = 'P0002';
  end if;

  _low := case when _me::text < _other_user_id::text then _me else _other_user_id end;
  _high := case when _me::text < _other_user_id::text then _other_user_id else _me end;

  perform pg_advisory_xact_lock(hashtextextended(_low::text || ':' || _high::text, 0));

  if public.is_blocked_pair(_me, _other_user_id) then
    raise exception 'A direct conversation is not allowed for blocked users' using errcode = '42501';
  end if;

  select c.id into _conversation_id
  from public.conversations c
  where c.kind = 'direct'
    and c.direct_user_low = _low
    and c.direct_user_high = _high;

  if _conversation_id is not null then
    return _conversation_id;
  end if;

  insert into public.conversations (
    kind, created_by, direct_user_low, direct_user_high
  ) values (
    'direct', _me, _low, _high
  ) returning id into _conversation_id;

  insert into public.conversation_members (conversation_id, user_id, role, status)
  values
    (_conversation_id, _low, 'member', 'active'),
    (_conversation_id, _high, 'member', 'active');

  insert into public.conversation_user_settings (conversation_id, user_id)
  values (_conversation_id, _low), (_conversation_id, _high)
  on conflict do nothing;

  return _conversation_id;
end;
$$;

-- Remove the historical overload that accepted conversation_kind and therefore
-- exposed channel creation to API callers.
drop function if exists public.create_group_conversation(text, text, public.conversation_kind);

create or replace function public.create_group_conversation(
  _title text,
  _description text default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _me uuid := auth.uid();
  _conversation_id uuid;
begin
  if _me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  insert into public.conversations (kind, title, description, created_by)
  values ('group', btrim(_title), nullif(btrim(_description), ''), _me)
  returning id into _conversation_id;

  insert into public.conversation_members (conversation_id, user_id, role, status)
  values (_conversation_id, _me, 'owner', 'active');

  insert into public.conversation_user_settings (conversation_id, user_id)
  values (_conversation_id, _me)
  on conflict do nothing;

  return _conversation_id;
end;
$$;

create or replace function public.transfer_conversation_ownership(
  _conversation_id uuid,
  _new_owner_id uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _me uuid := auth.uid();
begin
  if _me is null or not public.is_conversation_owner(_conversation_id) then
    raise exception 'Only the current owner may transfer ownership' using errcode = '42501';
  end if;
  if _new_owner_id = _me then
    return;
  end if;
  if not exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = _conversation_id
      and cm.user_id = _new_owner_id
      and cm.status = 'active'
  ) then
    raise exception 'The new owner must be an active member' using errcode = '23514';
  end if;

  update public.conversation_members
  set role = 'owner'
  where conversation_id = _conversation_id and user_id = _new_owner_id;

  update public.conversation_members
  set role = 'admin'
  where conversation_id = _conversation_id and user_id = _me;
end;
$$;

create or replace function public.create_group_invite_link(
  _conversation_id uuid,
  _expires_at timestamptz default (now() + interval '7 days'),
  _max_uses integer default 1
)
returns table (invitation_id uuid, token text)
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  _me uuid := auth.uid();
  _token text;
  _id uuid;
begin
  if _me is null or not public.is_conversation_admin(_conversation_id) then
    raise exception 'Group administrator role required' using errcode = '42501';
  end if;
  if _max_uses not between 1 and 10000 then
    raise exception 'max_uses must be between 1 and 10000' using errcode = '22023';
  end if;
  if _expires_at is not null and _expires_at <= now() then
    raise exception 'Expiration must be in the future' using errcode = '22023';
  end if;

  _token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.group_invitations (
    conversation_id, inviter_id, token_hash, max_uses, expires_at
  ) values (
    _conversation_id, _me, encode(extensions.digest(_token, 'sha256'), 'hex'), _max_uses, _expires_at
  ) returning id into _id;

  return query select _id, _token;
end;
$$;

create or replace function public.accept_group_invite_token(_token text)
returns uuid
language plpgsql
security definer
set search_path = public, extensions, pg_temp
as $$
declare
  _me uuid := auth.uid();
  _invite public.group_invitations%rowtype;
  _hash text;
begin
  if _me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if _token is null or char_length(_token) < 32 then
    raise exception 'Invalid invite token' using errcode = '22023';
  end if;

  _hash := encode(extensions.digest(_token, 'sha256'), 'hex');
  select * into _invite
  from public.group_invitations gi
  where gi.token_hash = _hash
    and gi.status = 'pending'
  for update;

  if not found
     or (_invite.expires_at is not null and _invite.expires_at <= now())
     or _invite.use_count >= _invite.max_uses then
    raise exception 'Invite token is invalid or expired' using errcode = '42501';
  end if;
  if exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = _invite.conversation_id
      and cm.user_id = _me
      and cm.status = 'banned'
  ) then
    raise exception 'Banned users cannot join this conversation' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.conversation_members cm
    where cm.conversation_id = _invite.conversation_id
      and cm.user_id = _me
      and cm.status = 'active'
  ) then
    return _invite.conversation_id;
  end if;

  delete from public.conversation_members cm
  where cm.conversation_id = _invite.conversation_id
    and cm.user_id = _me
    and cm.status <> 'banned';

  insert into public.conversation_members (
    conversation_id, user_id, role, status, invited_by, joined_at
  ) values (
    _invite.conversation_id, _me, 'member', 'active', _invite.inviter_id, now()
  );

  update public.group_join_requests
  set status = 'cancelled'
  where conversation_id = _invite.conversation_id
    and requester_id = _me
    and status = 'pending';

  update public.group_invitations
  set status = 'declined'
  where conversation_id = _invite.conversation_id
    and invitee_id = _me
    and status = 'pending';

  update public.group_invitations
  set use_count = use_count + 1,
      status = case when use_count + 1 >= max_uses then 'accepted'::public.invitation_status else status end,
      responded_at = case when use_count + 1 >= max_uses then now() else responded_at end
  where id = _invite.id;

  return _invite.conversation_id;
end;
$$;

create or replace function public.accept_group_invitation(_invitation_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _me uuid := auth.uid();
  _conversation_id uuid;
begin
  if _me is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  update public.group_invitations gi
  set status = 'accepted', responded_at = now()
  where gi.id = _invitation_id
    and gi.invitee_id = _me
    and gi.status = 'pending'
    and (gi.expires_at is null or gi.expires_at > now())
  returning gi.conversation_id into _conversation_id;

  if _conversation_id is null then
    raise exception 'Invitation not found or expired' using errcode = 'P0002';
  end if;
  return _conversation_id;
end;
$$;

create or replace function public.review_group_join_request(
  _request_id uuid,
  _approve boolean
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _conversation_id uuid;
  _requester_id uuid;
begin
  select r.conversation_id, r.requester_id
    into _conversation_id, _requester_id
  from public.group_join_requests r
  where r.id = _request_id and r.status = 'pending'
  for update;

  if _conversation_id is null then
    raise exception 'Pending join request not found' using errcode = 'P0002';
  end if;
  if not public.is_conversation_admin(_conversation_id) then
    raise exception 'Group administrator role required' using errcode = '42501';
  end if;

  update public.group_join_requests
  set status = case when _approve then 'approved'::public.join_request_status else 'rejected'::public.join_request_status end,
      responded_by = auth.uid(), responded_at = now()
  where id = _request_id;

  return _conversation_id;
end;
$$;

create or replace function public.create_poll(
  _conversation_id uuid,
  _question text,
  _options text[],
  _allow_multiple boolean default false,
  _max_selections smallint default 1,
  _is_anonymous boolean default false,
  _closes_at timestamptz default null
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _me uuid := auth.uid();
  _message_id uuid;
  _poll_id uuid;
  _option text;
  _position smallint := 0;
begin
  if _me is null or not public.can_send_to_conversation(_conversation_id) then
    raise exception 'Not allowed to create a poll in this conversation' using errcode = '42501';
  end if;
  if coalesce(array_length(_options, 1), 0) not between 2 and 20 then
    raise exception 'A poll requires 2 to 20 options' using errcode = '22023';
  end if;
  if not _allow_multiple and _max_selections <> 1 then
    raise exception 'Single-choice polls must have max_selections = 1' using errcode = '22023';
  end if;
  if _allow_multiple and _max_selections not between 1 and least(20, array_length(_options, 1)) then
    raise exception 'Invalid max_selections' using errcode = '22023';
  end if;
  if _closes_at is not null and _closes_at <= now() then
    raise exception 'Poll closing time must be in the future' using errcode = '22023';
  end if;

  insert into public.messages (conversation_id, sender_id, kind, body)
  values (_conversation_id, _me, 'poll', btrim(_question))
  returning id into _message_id;

  insert into public.polls (
    message_id, conversation_id, creator_id, question,
    allow_multiple, max_selections, is_anonymous, closes_at
  ) values (
    _message_id, _conversation_id, _me, btrim(_question),
    _allow_multiple, _max_selections, _is_anonymous, _closes_at
  ) returning id into _poll_id;

  foreach _option in array _options loop
    insert into public.poll_options (poll_id, conversation_id, option_text, position)
    values (_poll_id, _conversation_id, btrim(_option), _position);
    _position := _position + 1;
  end loop;

  return _poll_id;
end;
$$;

create or replace function public.get_poll_results(_poll_id uuid)
returns table (
  option_id uuid,
  option_text text,
  option_position smallint,
  vote_count integer,
  selected_by_me boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  _conversation_id uuid;
begin
  select p.conversation_id into _conversation_id from public.polls p where p.id = _poll_id;
  if _conversation_id is null or not public.poll_is_visible(_poll_id) then
    raise exception 'Poll is not visible' using errcode = '42501';
  end if;

  return query
  select po.id, po.option_text, po.position, po.vote_count,
         exists (
           select 1 from public.poll_votes pv
           where pv.poll_id = po.poll_id
             and pv.option_id = po.id
             and pv.voter_id = auth.uid()
         )
  from public.poll_options po
  where po.poll_id = _poll_id
  order by po.position;
end;
$$;

-- Automatic auth profile and default settings ---------------------------------
create or replace function public.ensure_profile_settings()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.user_settings (user_id) values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  _display_name text;
begin
  _display_name := coalesce(
    nullif(btrim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(btrim(new.raw_user_meta_data ->> 'name'), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Пользователь'
  );

  insert into public.profiles (id, display_name)
  values (new.id, left(_display_name, 100))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists ensure_profile_settings on public.profiles;
create trigger ensure_profile_settings
after insert on public.profiles
for each row execute function public.ensure_profile_settings();

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_auth_user();

insert into public.profiles (id, display_name)
select u.id,
       left(coalesce(
         nullif(btrim(u.raw_user_meta_data ->> 'full_name'), ''),
         nullif(btrim(u.raw_user_meta_data ->> 'name'), ''),
         nullif(split_part(coalesce(u.email, ''), '@', 1), ''),
         'Пользователь'
       ), 100)
from auth.users u
on conflict (id) do nothing;

insert into public.user_settings (user_id)
select p.id from public.profiles p
on conflict (user_id) do nothing;

-- RLS -------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.contacts enable row level security;
alter table public.user_blocks enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.messages enable row level security;
alter table public.message_attachments enable row level security;
alter table public.message_reactions enable row level security;
alter table public.conversation_read_receipts enable row level security;
alter table public.conversation_typing enable row level security;
alter table public.message_pins enable row level security;
alter table public.conversation_user_settings enable row level security;
alter table public.chat_folders enable row level security;
alter table public.chat_folder_conversations enable row level security;
alter table public.user_settings enable row level security;
alter table public.user_presence enable row level security;
alter table public.user_devices enable row level security;
alter table public.reports enable row level security;
alter table public.group_invitations enable row level security;
alter table public.group_join_requests enable row level security;
alter table public.polls enable row level security;
alter table public.poll_options enable row level security;
alter table public.poll_votes enable row level security;

-- Profiles
drop policy if exists profiles_select_visible on public.profiles;
create policy profiles_select_visible on public.profiles
for select to authenticated
using (public.can_view_profile(id));

drop policy if exists profiles_insert_self on public.profiles;
create policy profiles_insert_self on public.profiles
for insert to authenticated
with check (id = (select auth.uid()));

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles
for update to authenticated
using (id = (select auth.uid()))
with check (id = (select auth.uid()));

-- Contacts
drop policy if exists contacts_select_participant on public.contacts;
create policy contacts_select_participant on public.contacts
for select to authenticated
using ((select auth.uid()) in (requester_id, addressee_id));

drop policy if exists contacts_insert_requester on public.contacts;
create policy contacts_insert_requester on public.contacts
for insert to authenticated
with check (
  requester_id = (select auth.uid())
  and addressee_id <> (select auth.uid())
);

drop policy if exists contacts_update_participant on public.contacts;
create policy contacts_update_participant on public.contacts
for update to authenticated
using ((select auth.uid()) in (requester_id, addressee_id))
with check ((select auth.uid()) in (requester_id, addressee_id));

drop policy if exists contacts_delete_participant on public.contacts;
create policy contacts_delete_participant on public.contacts
for delete to authenticated
using ((select auth.uid()) in (requester_id, addressee_id));

-- Blocks
drop policy if exists blocks_select_owner on public.user_blocks;
create policy blocks_select_owner on public.user_blocks
for select to authenticated
using (blocker_id = (select auth.uid()));

drop policy if exists blocks_insert_owner on public.user_blocks;
create policy blocks_insert_owner on public.user_blocks
for insert to authenticated
with check (blocker_id = (select auth.uid()) and blocked_id <> (select auth.uid()));

drop policy if exists blocks_delete_owner on public.user_blocks;
create policy blocks_delete_owner on public.user_blocks
for delete to authenticated
using (blocker_id = (select auth.uid()));

-- Conversations and members
drop policy if exists conversations_select_member on public.conversations;
create policy conversations_select_member on public.conversations
for select to authenticated
using (public.can_view_conversation(id));

drop policy if exists conversations_update_admin on public.conversations;
create policy conversations_update_admin on public.conversations
for update to authenticated
using (kind <> 'direct' and public.is_conversation_admin(id))
with check (kind <> 'direct' and public.is_conversation_admin(id));

drop policy if exists members_select_member on public.conversation_members;
create policy members_select_member on public.conversation_members
for select to authenticated
using (public.is_conversation_member(conversation_id));

-- Membership INSERT is intentionally RPC/trigger-only. In particular, an
-- invitee cannot bypass invitation acceptance by inserting a membership row.
drop policy if exists members_insert_admin_or_invitee on public.conversation_members;

drop policy if exists members_update_self on public.conversation_members;
create policy members_update_self on public.conversation_members
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists members_update_admin on public.conversation_members;
create policy members_update_admin on public.conversation_members
for update to authenticated
using (public.is_conversation_admin(conversation_id))
with check (public.is_conversation_admin(conversation_id));

-- Messages and chat state
drop policy if exists messages_select_member on public.messages;
create policy messages_select_member on public.messages
for select to authenticated
using (public.is_conversation_member(conversation_id));

drop policy if exists messages_insert_sender on public.messages;
create policy messages_insert_sender on public.messages
for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and public.can_send_to_conversation(conversation_id)
);

drop policy if exists messages_update_sender_or_admin on public.messages;
create policy messages_update_sender_or_admin on public.messages
for update to authenticated
using (
  public.is_conversation_member(conversation_id)
  and (sender_id = (select auth.uid()) or public.is_conversation_admin(conversation_id))
)
with check (
  public.is_conversation_member(conversation_id)
  and (sender_id = (select auth.uid()) or public.is_conversation_admin(conversation_id))
);

drop policy if exists attachments_select_member on public.message_attachments;
create policy attachments_select_member on public.message_attachments
for select to authenticated
using (public.can_read_attachment(id));

drop policy if exists attachments_insert_sender on public.message_attachments;
create policy attachments_insert_sender on public.message_attachments
for insert to authenticated
with check (
  uploaded_by = (select auth.uid())
  and public.can_send_to_conversation(conversation_id)
  and exists (
    select 1 from public.messages m
    where m.id = message_id
      and m.conversation_id = message_attachments.conversation_id
      and m.sender_id = (select auth.uid())
      and m.deleted_at is null
  )
);

drop policy if exists attachments_delete_uploader on public.message_attachments;
create policy attachments_delete_uploader on public.message_attachments
for delete to authenticated
using (uploaded_by = (select auth.uid()) and public.is_conversation_member(conversation_id));

drop policy if exists reactions_select_member on public.message_reactions;
create policy reactions_select_member on public.message_reactions
for select to authenticated
using (public.message_is_visible(message_id));

drop policy if exists reactions_insert_self on public.message_reactions;
create policy reactions_insert_self on public.message_reactions
for insert to authenticated
with check (
  user_id = (select auth.uid())
  and exists (
    select 1 from public.messages m
    where m.id = message_id
      and m.deleted_at is null
      and public.can_send_to_conversation(m.conversation_id)
  )
);

drop policy if exists reactions_delete_self on public.message_reactions;
create policy reactions_delete_self on public.message_reactions
for delete to authenticated
using (user_id = (select auth.uid()));

drop policy if exists receipts_select_member on public.conversation_read_receipts;
create policy receipts_select_member on public.conversation_read_receipts
for select to authenticated
using (public.can_view_read_receipt(conversation_id, user_id));

drop policy if exists receipts_insert_self on public.conversation_read_receipts;
create policy receipts_insert_self on public.conversation_read_receipts
for insert to authenticated
with check (user_id = (select auth.uid()) and public.is_conversation_member(conversation_id));

drop policy if exists receipts_update_self on public.conversation_read_receipts;
create policy receipts_update_self on public.conversation_read_receipts
for update to authenticated
using (user_id = (select auth.uid()) and public.is_conversation_member(conversation_id))
with check (user_id = (select auth.uid()) and public.is_conversation_member(conversation_id));

drop policy if exists receipts_delete_self on public.conversation_read_receipts;
create policy receipts_delete_self on public.conversation_read_receipts
for delete to authenticated
using (user_id = (select auth.uid()));

drop policy if exists typing_select_member on public.conversation_typing;
create policy typing_select_member on public.conversation_typing
for select to authenticated
using (
  public.can_view_typing_status(conversation_id, user_id)
  and expires_at > now()
);

drop policy if exists typing_insert_self on public.conversation_typing;
create policy typing_insert_self on public.conversation_typing
for insert to authenticated
with check (user_id = (select auth.uid()) and public.can_send_to_conversation(conversation_id));

drop policy if exists typing_update_self on public.conversation_typing;
create policy typing_update_self on public.conversation_typing
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()) and public.can_send_to_conversation(conversation_id));

drop policy if exists typing_delete_self on public.conversation_typing;
create policy typing_delete_self on public.conversation_typing
for delete to authenticated
using (user_id = (select auth.uid()));

drop policy if exists pins_select_member on public.message_pins;
create policy pins_select_member on public.message_pins
for select to authenticated
using (
  public.is_conversation_member(conversation_id)
  and public.message_is_visible(message_id)
);

drop policy if exists pins_insert_moderator on public.message_pins;
create policy pins_insert_moderator on public.message_pins
for insert to authenticated
with check (pinned_by = (select auth.uid()) and public.can_pin_messages(conversation_id));

drop policy if exists pins_delete_moderator on public.message_pins;
create policy pins_delete_moderator on public.message_pins
for delete to authenticated
using (public.can_pin_messages(conversation_id));

-- Personal chat settings/folders
drop policy if exists conversation_settings_select_self on public.conversation_user_settings;
create policy conversation_settings_select_self on public.conversation_user_settings
for select to authenticated
using (user_id = (select auth.uid()) and public.is_conversation_member(conversation_id));

drop policy if exists conversation_settings_insert_self on public.conversation_user_settings;
create policy conversation_settings_insert_self on public.conversation_user_settings
for insert to authenticated
with check (user_id = (select auth.uid()) and public.is_conversation_member(conversation_id));

drop policy if exists conversation_settings_update_self on public.conversation_user_settings;
create policy conversation_settings_update_self on public.conversation_user_settings
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()) and public.is_conversation_member(conversation_id));

drop policy if exists conversation_settings_delete_self on public.conversation_user_settings;
create policy conversation_settings_delete_self on public.conversation_user_settings
for delete to authenticated
using (user_id = (select auth.uid()));

drop policy if exists folders_all_self on public.chat_folders;
create policy folders_all_self on public.chat_folders
for all to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists folder_conversations_select_self on public.chat_folder_conversations;
create policy folder_conversations_select_self on public.chat_folder_conversations
for select to authenticated
using (user_id = (select auth.uid()) and public.is_conversation_member(conversation_id));

drop policy if exists folder_conversations_insert_self on public.chat_folder_conversations;
create policy folder_conversations_insert_self on public.chat_folder_conversations
for insert to authenticated
with check (user_id = (select auth.uid()) and public.is_conversation_member(conversation_id));

drop policy if exists folder_conversations_update_self on public.chat_folder_conversations;
create policy folder_conversations_update_self on public.chat_folder_conversations
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()) and public.is_conversation_member(conversation_id));

drop policy if exists folder_conversations_delete_self on public.chat_folder_conversations;
create policy folder_conversations_delete_self on public.chat_folder_conversations
for delete to authenticated
using (user_id = (select auth.uid()));

drop policy if exists user_settings_all_self on public.user_settings;
create policy user_settings_all_self on public.user_settings
for all to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists presence_select_visible on public.user_presence;
create policy presence_select_visible on public.user_presence
for select to authenticated
using (public.can_view_presence(user_id));

drop policy if exists presence_insert_self on public.user_presence;
create policy presence_insert_self on public.user_presence
for insert to authenticated
with check (user_id = (select auth.uid()));

drop policy if exists presence_update_self on public.user_presence;
create policy presence_update_self on public.user_presence
for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

drop policy if exists presence_delete_self on public.user_presence;
create policy presence_delete_self on public.user_presence
for delete to authenticated
using (user_id = (select auth.uid()));

drop policy if exists devices_all_self on public.user_devices;
create policy devices_all_self on public.user_devices
for all to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

-- Reports
drop policy if exists reports_select_own on public.reports;
create policy reports_select_own on public.reports
for select to authenticated
using (reporter_id = (select auth.uid()));

drop policy if exists reports_insert_own on public.reports;
create policy reports_insert_own on public.reports
for insert to authenticated
with check (
  reporter_id = (select auth.uid())
  and num_nonnulls(reported_user_id, reported_conversation_id, reported_message_id) = 1
  and (reported_user_id is null or public.can_report_user(reported_user_id))
  and (reported_conversation_id is null or public.is_conversation_member(reported_conversation_id))
  and (reported_message_id is null or public.message_is_visible(reported_message_id))
);

-- Invitations and join requests
drop policy if exists invitations_select_related on public.group_invitations;
create policy invitations_select_related on public.group_invitations
for select to authenticated
using (
  inviter_id = (select auth.uid())
  or invitee_id = (select auth.uid())
  or public.is_conversation_admin(conversation_id)
);

drop policy if exists invitations_insert_admin on public.group_invitations;
create policy invitations_insert_admin on public.group_invitations
for insert to authenticated
with check (
  inviter_id = (select auth.uid())
  and invitee_id is not null
  and token_hash is null
  and public.is_conversation_admin(conversation_id)
);

drop policy if exists invitations_update_related on public.group_invitations;
create policy invitations_update_related on public.group_invitations
for update to authenticated
using (invitee_id = (select auth.uid()) or public.is_conversation_admin(conversation_id))
with check (invitee_id = (select auth.uid()) or public.is_conversation_admin(conversation_id));

drop policy if exists requests_select_related on public.group_join_requests;
create policy requests_select_related on public.group_join_requests
for select to authenticated
using (requester_id = (select auth.uid()) or public.is_conversation_admin(conversation_id));

drop policy if exists requests_insert_self on public.group_join_requests;
create policy requests_insert_self on public.group_join_requests
for insert to authenticated
with check (requester_id = (select auth.uid()));

drop policy if exists requests_update_related on public.group_join_requests;
create policy requests_update_related on public.group_join_requests
for update to authenticated
using (requester_id = (select auth.uid()) or public.is_conversation_admin(conversation_id))
with check (requester_id = (select auth.uid()) or public.is_conversation_admin(conversation_id));

drop policy if exists requests_delete_self on public.group_join_requests;
create policy requests_delete_self on public.group_join_requests
for delete to authenticated
using (requester_id = (select auth.uid()) and status = 'pending');

-- Polls
drop policy if exists polls_select_member on public.polls;
create policy polls_select_member on public.polls
for select to authenticated
using (public.poll_is_visible(id));

drop policy if exists polls_update_creator_or_admin on public.polls;
create policy polls_update_creator_or_admin on public.polls
for update to authenticated
using (
  public.is_conversation_member(conversation_id)
  and (creator_id = (select auth.uid()) or public.is_conversation_admin(conversation_id))
)
with check (
  public.is_conversation_member(conversation_id)
  and (creator_id = (select auth.uid()) or public.is_conversation_admin(conversation_id))
);

drop policy if exists poll_options_select_member on public.poll_options;
create policy poll_options_select_member on public.poll_options
for select to authenticated
using (public.poll_is_visible(poll_id));

drop policy if exists poll_options_update_creator_or_admin on public.poll_options;
create policy poll_options_update_creator_or_admin on public.poll_options
for update to authenticated
using (
  public.is_conversation_member(conversation_id)
  and exists (
    select 1 from public.polls p
    where p.id = poll_id
      and (p.creator_id = (select auth.uid()) or public.is_conversation_admin(p.conversation_id))
  )
)
with check (public.is_conversation_member(conversation_id));

drop policy if exists poll_votes_select_allowed on public.poll_votes;
create policy poll_votes_select_allowed on public.poll_votes
for select to authenticated
using (
  public.poll_is_visible(poll_id)
  and (
    voter_id = (select auth.uid())
    or exists (select 1 from public.polls p where p.id = poll_id and not p.is_anonymous)
  )
);

drop policy if exists poll_votes_insert_self on public.poll_votes;
create policy poll_votes_insert_self on public.poll_votes
for insert to authenticated
with check (
  voter_id = (select auth.uid())
  and public.is_conversation_member(conversation_id)
);

drop policy if exists poll_votes_delete_self on public.poll_votes;
create policy poll_votes_delete_self on public.poll_votes
for delete to authenticated
using (voter_id = (select auth.uid()));

-- Explicit API grants (RLS remains authoritative) ------------------------------
alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema public revoke all on tables from anon, authenticated;

revoke all on
  public.profiles, public.contacts, public.user_blocks, public.conversations,
  public.conversation_members, public.messages, public.message_attachments,
  public.message_reactions, public.conversation_read_receipts, public.conversation_typing,
  public.message_pins, public.conversation_user_settings, public.chat_folders,
  public.chat_folder_conversations, public.user_settings, public.user_presence, public.user_devices,
  public.reports, public.group_invitations, public.group_join_requests,
  public.polls, public.poll_options, public.poll_votes
  from anon, authenticated;
revoke create on schema public from public, anon, authenticated, service_role;
revoke usage on schema public from public, anon;
grant usage on schema public to authenticated, service_role;

grant all on
  public.profiles, public.contacts, public.user_blocks, public.conversations,
  public.conversation_members, public.messages, public.message_attachments,
  public.message_reactions, public.conversation_read_receipts, public.conversation_typing,
  public.message_pins, public.conversation_user_settings, public.chat_folders,
  public.chat_folder_conversations, public.user_settings, public.user_presence, public.user_devices,
  public.reports, public.group_invitations, public.group_join_requests,
  public.polls, public.poll_options, public.poll_votes
  to service_role;

grant select on
  public.profiles, public.contacts, public.user_blocks, public.conversations,
  public.conversation_members, public.messages, public.message_attachments,
  public.message_reactions, public.conversation_read_receipts, public.conversation_typing,
  public.message_pins, public.conversation_user_settings, public.chat_folders,
  public.chat_folder_conversations, public.user_settings, public.user_presence, public.user_devices,
  public.reports, public.group_invitations, public.group_join_requests,
  public.polls, public.poll_options, public.poll_votes
  to authenticated, service_role;

grant insert on
  public.profiles, public.contacts, public.user_blocks,
  public.messages, public.message_attachments, public.message_reactions,
  public.conversation_read_receipts, public.conversation_typing, public.message_pins,
  public.conversation_user_settings, public.chat_folders, public.chat_folder_conversations,
  public.user_settings, public.user_presence, public.user_devices, public.reports, public.group_invitations,
  public.group_join_requests, public.poll_votes
  to authenticated, service_role;

grant update (username, display_name, bio, avatar_path, is_discoverable, onboarding_completed)
  on public.profiles to authenticated, service_role;
grant update (status) on public.contacts to authenticated, service_role;
grant update (title, description, avatar_path, is_locked, join_requests_enabled) on public.conversations to authenticated, service_role;
grant update (role, status) on public.conversation_members to authenticated, service_role;
grant update (body, metadata, deleted_at) on public.messages to authenticated, service_role;
grant update (last_read_message_id, last_read_at) on public.conversation_read_receipts to authenticated, service_role;
grant update (is_typing, expires_at) on public.conversation_typing to authenticated, service_role;
grant update (is_archived, is_pinned, mute_until, notification_level, custom_title, draft)
  on public.conversation_user_settings to authenticated, service_role;
grant update (name, color, icon, sort_order) on public.chat_folders to authenticated, service_role;
grant update (sort_order) on public.chat_folder_conversations to authenticated, service_role;
grant update (
  locale, theme, send_read_receipts, show_typing_status, show_last_seen,
  push_enabled, push_message_preview, auto_download_media, settings
) on public.user_settings to authenticated, service_role;
grant update (online_until) on public.user_presence to authenticated, service_role;
grant update (platform, device_name, fcm_token, app_version, last_seen_at, disabled_at)
  on public.user_devices to authenticated, service_role;
grant update (status) on public.group_invitations to authenticated, service_role;
grant update (status) on public.group_join_requests to authenticated, service_role;
grant update (question, allow_multiple, max_selections, is_anonymous, closes_at, closed_at)
  on public.polls to authenticated, service_role;
grant update (option_text, position) on public.poll_options to authenticated, service_role;

grant delete on
  public.contacts, public.user_blocks, public.message_attachments, public.message_reactions,
  public.conversation_typing, public.message_pins,
  public.conversation_user_settings, public.chat_folders, public.chat_folder_conversations,
  public.user_presence, public.user_devices, public.group_join_requests, public.poll_votes
  to authenticated, service_role;

-- Functions start closed: PostgreSQL grants EXECUTE to PUBLIC by default. Trigger
-- functions and internal helpers remain owner-only; the client allow-list below is
-- the complete authenticated RPC/helper surface.
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
        'set_updated_at',
        'object_path_conversation_id', 'object_path_owner_id',
        'is_safe_storage_path', 'is_profile_avatar_path', 'is_conversation_object_path',
        'is_blocked_pair', 'is_conversation_member', 'can_view_conversation',
        'is_conversation_admin', 'is_conversation_owner', 'can_send_to_conversation',
        'can_pin_messages', 'can_view_read_receipt', 'can_view_typing_status',
        'can_view_presence', 'can_view_profile', 'can_report_user',
        'message_is_visible', 'poll_is_visible', 'can_read_attachment', 'can_read_chat_object',
        'guard_profile_write', 'lock_user_pair', 'cleanup_contacts_after_block',
        'guard_contact_write', 'guard_conversation_write', 'guard_conversation_member_write',
        'validate_conversation_membership_shape', 'handle_profile_deletion',
        'guard_message_write', 'sync_conversation_last_message', 'guard_attachment_write',
        'guard_reaction_write', 'guard_read_receipt_write', 'guard_typing_write', 'guard_presence_write',
        'guard_device_write', 'guard_message_pin_write',
        'guard_conversation_user_settings_write', 'guard_user_settings_write',
        'guard_chat_folder_write', 'guard_folder_conversation_write', 'guard_report_write', 'guard_invitation_write',
        'apply_accepted_invitation', 'guard_join_request_write',
        'apply_approved_join_request', 'guard_poll_write', 'guard_poll_option_write',
        'guard_poll_vote_write', 'sync_poll_vote_count', 'validate_poll_message_shape',
        'validate_poll_options_shape', 'register_device', 'create_direct_conversation',
        'create_group_conversation', 'transfer_conversation_ownership',
        'create_group_invite_link', 'accept_group_invite_token',
        'accept_group_invitation', 'review_group_join_request', 'create_poll',
        'get_poll_results', 'ensure_profile_settings', 'handle_new_auth_user'
      ]::text[])
  loop
    execute format(
      'revoke all on function %s from public, anon, authenticated',
      _function
    );
  end loop;
end $$;

revoke all on function public.is_blocked_pair(uuid, uuid) from public, anon;
revoke all on function public.is_conversation_member(uuid) from public, anon;
revoke all on function public.can_view_conversation(uuid) from public, anon;
revoke all on function public.is_conversation_admin(uuid) from public, anon;
revoke all on function public.is_conversation_owner(uuid) from public, anon;
revoke all on function public.can_send_to_conversation(uuid) from public, anon;
revoke all on function public.can_pin_messages(uuid) from public, anon;
revoke all on function public.can_view_read_receipt(uuid, uuid) from public, anon;
revoke all on function public.can_view_typing_status(uuid, uuid) from public, anon;
revoke all on function public.can_view_presence(uuid) from public, anon;
revoke all on function public.can_view_profile(uuid) from public, anon;
revoke all on function public.can_report_user(uuid) from public, anon;
revoke all on function public.message_is_visible(uuid) from public, anon;
revoke all on function public.poll_is_visible(uuid) from public, anon;
revoke all on function public.can_read_attachment(uuid) from public, anon;
revoke all on function public.can_read_chat_object(text, text) from public, anon;

revoke all on function public.register_device(public.device_platform, text, text, text) from public, anon;
revoke all on function public.create_direct_conversation(uuid) from public, anon;
revoke all on function public.create_group_conversation(text, text) from public, anon;
revoke all on function public.transfer_conversation_ownership(uuid, uuid) from public, anon;
revoke all on function public.create_group_invite_link(uuid, timestamptz, integer) from public, anon;
revoke all on function public.accept_group_invite_token(text) from public, anon;
revoke all on function public.accept_group_invitation(uuid) from public, anon;
revoke all on function public.review_group_join_request(uuid, boolean) from public, anon;
revoke all on function public.create_poll(uuid, text, text[], boolean, smallint, boolean, timestamptz) from public, anon;
revoke all on function public.get_poll_results(uuid) from public, anon;

grant execute on function public.is_conversation_member(uuid) to authenticated, service_role;
grant execute on function public.can_view_conversation(uuid) to authenticated, service_role;
grant execute on function public.is_conversation_admin(uuid) to authenticated, service_role;
grant execute on function public.is_conversation_owner(uuid) to authenticated, service_role;
grant execute on function public.can_send_to_conversation(uuid) to authenticated, service_role;
grant execute on function public.can_pin_messages(uuid) to authenticated, service_role;
grant execute on function public.can_view_read_receipt(uuid, uuid) to authenticated, service_role;
grant execute on function public.can_view_typing_status(uuid, uuid) to authenticated, service_role;
grant execute on function public.can_view_presence(uuid) to authenticated, service_role;
grant execute on function public.can_view_profile(uuid) to authenticated, service_role;
grant execute on function public.can_report_user(uuid) to authenticated, service_role;
grant execute on function public.message_is_visible(uuid) to authenticated, service_role;
grant execute on function public.poll_is_visible(uuid) to authenticated, service_role;
grant execute on function public.can_read_attachment(uuid) to authenticated, service_role;
grant execute on function public.can_read_chat_object(text, text) to authenticated, service_role;
grant execute on function public.object_path_conversation_id(text) to authenticated, service_role;
grant execute on function public.object_path_owner_id(text, integer) to authenticated, service_role;
grant execute on function public.is_safe_storage_path(text, integer) to authenticated, service_role;
grant execute on function public.is_profile_avatar_path(text, uuid) to authenticated, service_role;
grant execute on function public.is_conversation_object_path(text, uuid, uuid) to authenticated, service_role;

grant execute on function public.register_device(public.device_platform, text, text, text) to authenticated, service_role;
grant execute on function public.create_direct_conversation(uuid) to authenticated, service_role;
grant execute on function public.create_group_conversation(text, text) to authenticated, service_role;
grant execute on function public.transfer_conversation_ownership(uuid, uuid) to authenticated, service_role;
grant execute on function public.create_group_invite_link(uuid, timestamptz, integer) to authenticated, service_role;
grant execute on function public.accept_group_invite_token(text) to authenticated, service_role;
grant execute on function public.accept_group_invitation(uuid) to authenticated, service_role;
grant execute on function public.review_group_join_request(uuid, boolean) to authenticated, service_role;
grant execute on function public.create_poll(uuid, text, text[], boolean, smallint, boolean, timestamptz) to authenticated, service_role;
grant execute on function public.get_poll_results(uuid) to authenticated, service_role;

-- Private Supabase Storage buckets ---------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  (
    'avatars', 'avatars', false, 10485760,
    array['image/jpeg', 'image/png', 'image/webp', 'image/heic']::text[]
  ),
  (
    'chat-media', 'chat-media', false, 104857600,
    array[
      'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic',
      'video/mp4', 'video/quicktime', 'video/webm',
      'audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/ogg', 'audio/webm', 'audio/wav',
      'application/pdf', 'application/zip', 'application/x-7z-compressed',
      'application/msword', 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/vnd.ms-excel', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'application/vnd.ms-powerpoint', 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'text/plain', 'text/csv'
    ]::text[]
  ),
  (
    'voice-messages', 'voice-messages', false, 52428800,
    array['audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/ogg', 'audio/webm', 'audio/wav', 'audio/x-m4a']::text[]
  )
on conflict (id) do update
set name = excluded.name,
    public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Profile avatar paths: <user_uuid>/<file>.
-- Group avatar and chat paths: <conversation_uuid>/<uploader_uuid>/<file>.
drop policy if exists storage_avatars_select_visible on storage.objects;
create policy storage_avatars_select_visible on storage.objects
for select to authenticated
using (
  bucket_id = 'avatars'
  and (
    public.is_profile_avatar_path(name, (select auth.uid()))
    or exists (
      select 1 from public.profiles p
      where public.is_profile_avatar_path(name, p.id)
        and p.avatar_path = name
        and public.can_view_profile(p.id)
    )
    or exists (
      select 1 from public.conversations c
      where c.id = public.object_path_conversation_id(name)
        and c.kind <> 'direct'
        and public.is_conversation_object_path(
          name,
          c.id,
          public.object_path_owner_id(name, 2)
        )
        and c.avatar_path = name
        and public.can_view_conversation(c.id)
    )
  )
);

drop policy if exists storage_avatars_insert_self on storage.objects;
create policy storage_avatars_insert_self on storage.objects
for insert to authenticated
with check (
  bucket_id = 'avatars'
  and (
    public.is_profile_avatar_path(name, (select auth.uid()))
    or (
      public.is_conversation_object_path(
        name,
        public.object_path_conversation_id(name),
        (select auth.uid())
      )
      and public.is_conversation_admin(public.object_path_conversation_id(name))
    )
  )
);

drop policy if exists storage_avatars_update_self on storage.objects;
create policy storage_avatars_update_self on storage.objects
for update to authenticated
using (
  bucket_id = 'avatars'
  and (
    public.is_profile_avatar_path(name, (select auth.uid()))
    or (
      public.is_conversation_object_path(
        name,
        public.object_path_conversation_id(name),
        (select auth.uid())
      )
      and public.is_conversation_admin(public.object_path_conversation_id(name))
    )
  )
)
with check (
  bucket_id = 'avatars'
  and (
    public.is_profile_avatar_path(name, (select auth.uid()))
    or (
      public.is_conversation_object_path(
        name,
        public.object_path_conversation_id(name),
        (select auth.uid())
      )
      and public.is_conversation_admin(public.object_path_conversation_id(name))
    )
  )
);

drop policy if exists storage_avatars_delete_self on storage.objects;
create policy storage_avatars_delete_self on storage.objects
for delete to authenticated
using (
  bucket_id = 'avatars'
  and (
    public.is_profile_avatar_path(name, (select auth.uid()))
    or (
      public.is_conversation_object_path(
        name,
        public.object_path_conversation_id(name),
        public.object_path_owner_id(name, 2)
      )
      and public.is_conversation_admin(public.object_path_conversation_id(name))
    )
  )
);

drop policy if exists storage_chat_select_member on storage.objects;
create policy storage_chat_select_member on storage.objects
for select to authenticated
using (
  bucket_id in ('chat-media', 'voice-messages')
  and public.can_read_chat_object(bucket_id, name)
);

drop policy if exists storage_chat_insert_member on storage.objects;
create policy storage_chat_insert_member on storage.objects
for insert to authenticated
with check (
  bucket_id in ('chat-media', 'voice-messages')
  and public.is_conversation_object_path(
    name,
    public.object_path_conversation_id(name),
    (select auth.uid())
  )
  and public.can_send_to_conversation(public.object_path_conversation_id(name))
);

drop policy if exists storage_chat_update_uploader on storage.objects;
create policy storage_chat_update_uploader on storage.objects
for update to authenticated
using (
  bucket_id in ('chat-media', 'voice-messages')
  and public.is_conversation_object_path(
    name,
    public.object_path_conversation_id(name),
    (select auth.uid())
  )
  and public.is_conversation_member(public.object_path_conversation_id(name))
)
with check (
  bucket_id in ('chat-media', 'voice-messages')
  and public.is_conversation_object_path(
    name,
    public.object_path_conversation_id(name),
    (select auth.uid())
  )
  and public.is_conversation_member(public.object_path_conversation_id(name))
);

drop policy if exists storage_chat_delete_uploader on storage.objects;
create policy storage_chat_delete_uploader on storage.objects
for delete to authenticated
using (
  bucket_id in ('chat-media', 'voice-messages')
  and public.is_conversation_object_path(
    name,
    public.object_path_conversation_id(name),
    (select auth.uid())
  )
  and public.is_conversation_member(public.object_path_conversation_id(name))
);

-- Realtime --------------------------------------------------------------------
alter table public.conversations replica identity full;
alter table public.conversation_members replica identity full;
alter table public.messages replica identity full;
alter table public.message_attachments replica identity full;
alter table public.message_reactions replica identity full;
alter table public.conversation_read_receipts replica identity full;
alter table public.conversation_typing replica identity full;
alter table public.message_pins replica identity full;
alter table public.conversation_user_settings replica identity full;
alter table public.user_presence replica identity full;
alter table public.group_invitations replica identity full;
alter table public.group_join_requests replica identity full;
alter table public.polls replica identity full;
alter table public.poll_options replica identity full;
alter table public.poll_votes replica identity full;

do $$
declare
  _table text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;

  foreach _table in array array[
    'conversations', 'conversation_members', 'messages', 'message_attachments',
    'message_reactions', 'conversation_read_receipts', 'conversation_typing',
    'message_pins', 'conversation_user_settings', 'user_presence', 'group_invitations',
    'group_join_requests', 'polls', 'poll_options', 'poll_votes'
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
end $$;

commit;
