-- Table privileges the app never needs, plus an index for vote-notification cleanup.
--
-- 1. TRUNCATE bypasses RLS and TRIGGER/REFERENCES are never used by the API, yet
--    anon and authenticated hold all three on every public table. Remove them.
-- 2. Make future tables start without anon access (existing tables were handled
--    by the earlier hardening migration; this covers ones created later).
-- 3. remove_vote_notification (20261104000100) deletes by (fit_check_id, actor_id)
--    where type = 'vote'; without an index that scans notifications per vote.
--
-- Idempotent. Rollback: supabase/rollback/20261105000100_tighten_privileges.sql

revoke truncate, trigger, references on all tables in schema public from anon, authenticated;

alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke truncate, trigger, references on tables from authenticated;

create index if not exists notifications_vote_cleanup_idx
  on public.notifications (fit_check_id, actor_id)
  where type = 'vote';
