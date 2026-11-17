-- Local-only Supabase prerequisites for loading the checked-in schema dump.
-- Run as a superuser in a disposable PostgreSQL cluster, never on a live project.
do $$ begin
  if not exists(select 1 from pg_roles where rolname='anon') then create role anon; end if;
  if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated; end if;
  if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role; end if;
  if not exists(select 1 from pg_roles where rolname='supabase_admin') then create role supabase_admin; end if;
  if not exists(select 1 from pg_roles where rolname='supabase_storage_admin') then create role supabase_storage_admin; end if;
  if not exists(select 1 from pg_roles where rolname='dashboard_user') then create role dashboard_user; end if;
end $$;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create table auth.users(id uuid primary key, email text);
grant usage on schema auth to authenticated, anon, service_role;
grant execute on function auth.uid() to authenticated, anon, service_role;
create schema extensions;
create extension if not exists pgcrypto with schema extensions;
