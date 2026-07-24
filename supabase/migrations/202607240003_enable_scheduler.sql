-- Enable Supabase Cron for scheduled-message delivery and auto-delete cleanup.
-- pg_cron is available on the free project and runs inside Postgres.

begin;

create extension if not exists pg_cron;

select cron.schedule(
  'vibe-deliver-scheduled-messages',
  '* * * * *',
  $$select public.process_due_scheduled_messages(200);$$
);

select cron.schedule(
  'vibe-cleanup-expired-messages',
  '*/5 * * * *',
  $$select public.cleanup_expired_messages(2000);$$
);

commit;
