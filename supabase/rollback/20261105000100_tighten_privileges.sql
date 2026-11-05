drop index if exists public.notifications_vote_cleanup_idx;
alter default privileges for role postgres in schema public grant all on tables to anon;
alter default privileges for role postgres in schema public grant truncate, trigger, references on tables to authenticated;
grant truncate, trigger, references on all tables in schema public to anon, authenticated;
