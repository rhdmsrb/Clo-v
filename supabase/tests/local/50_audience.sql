-- Run after 00_stub.sql. Covers 20261108000100_fit_check_audience.sql and its rollback.
-- Stubs are not the real schema: a pass proves the SQL's logic, not that it fits the live DB.
\set ON_ERROR_STOP on
set client_min_messages = warning;

create role service_role nologin;
alter table public.fit_checks add column group_id uuid, add column tags text[], add column vote_prompt text, add column occasion text, add column caption text;
create table public.fit_check_photos(id uuid primary key default gen_random_uuid(), fit_check_id uuid);
create table public.memberships(group_id uuid, profile_id uuid);
create function public.is_group_member(gid uuid) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.memberships m where m.group_id = gid and m.profile_id = auth.uid()) $$;
grant all on all tables in schema public to anon, authenticated;

alter table public.fit_checks enable row level security;
create policy "fit_checks: read (published audience or owner)" on public.fit_checks for select to authenticated using (
  creator_id = auth.uid() or (status <> 'draft' and not public.is_blocked_pair(creator_id)
    and (is_public or (group_id is not null and public.is_group_member(group_id)))));
create policy fc_insert on public.fit_checks for insert to authenticated with check (creator_id = auth.uid());
create policy fc_update on public.fit_checks for update to authenticated using (creator_id = auth.uid());
-- Baseline (pre-migration) activity guard, attached to votes for the test.
create function public.validate_fit_check_activity() returns trigger language plpgsql security definer set search_path='' as $$
declare f public.fit_checks;
begin
 select * into f from public.fit_checks where id=new.fit_check_id for update;
 if not (f.is_public or f.creator_id=auth.uid() or public.is_group_member(f.group_id)) then raise exception 'Post unavailable' using errcode='42501'; end if;
 return new;
end; $$;
create trigger vote_guard before insert on public.fit_check_votes for each row execute function public.validate_fit_check_activity();
-- Baseline draft RPC (6-arg) so the migration's drop/replace is exercised.
create function public.create_fit_check_draft(p_id uuid, p_caption text default null, p_group_id uuid default null,
  p_occasion text default null, p_tags text[] default null, p_vote_prompt text default null) returns uuid
  language sql as 'select p_id';

\set c '''c0000000-0000-4000-8000-000000000000'''
\set f '''f0000000-0000-4000-8000-000000000000'''
\set s '''50000000-0000-4000-8000-000000000000'''
\set m '''d0000000-0000-4000-8000-000000000000'''
\set g '''90000000-0000-4000-8000-000000000000'''
\set pub '''10000000-0000-4000-8000-000000000001'''
\set grp '''10000000-0000-4000-8000-000000000003'''
\set old_priv '''10000000-0000-4000-8000-000000000004'''
\set fr '''20000000-0000-4000-8000-000000000001'''
\set pr '''20000000-0000-4000-8000-000000000002'''
\set gx '''20000000-0000-4000-8000-000000000003'''
\set ph '''e0000000-0000-4000-8000-00000000000a'''
\set ph2 '''e0000000-0000-4000-8000-00000000000b'''

insert into public.profiles(id, nickname) values (:c::uuid,'c'),(:f::uuid,'f'),(:s::uuid,'s'),(:m::uuid,'m');
insert into public.friendships(user_low, user_high) values (least(:c::uuid,:f::uuid), greatest(:c::uuid,:f::uuid));
insert into public.memberships values (:g::uuid, :m::uuid);
insert into public.fit_checks(id, creator_id, is_public, status, expires_at, group_id) values
  (:pub::uuid, :c::uuid, true,  'live', now() + interval '1 hour', null),
  (:grp::uuid, :c::uuid, false, 'live', now() + interval '1 hour', :g::uuid),
  (:old_priv::uuid, :c::uuid, false, 'live', now() + interval '1 hour', null);

\ir ../../migrations/20261108000100_fit_check_audience.sql

create function pg_temp.expect(label text, actual bigint, wanted bigint) returns void language plpgsql as $$
begin
  if actual is distinct from wanted then raise exception 'FAIL %: got %, wanted %', label, actual, wanted; end if;
  raise notice 'ok  %', label;
end $$;
create function pg_temp.try(who text, stmt text) returns int language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', who, true);
  set local role authenticated;
  execute stmt;
  reset role;
  return 1;
exception when others then
  reset role;
  return 0;
end $$;
create function pg_temp.n(who text, q text) returns bigint language plpgsql as $$
declare r bigint;
begin
  perform set_config('request.jwt.claim.sub', who, true);
  set local role authenticated;
  execute q into r;
  reset role;
  return r;
end $$;

set client_min_messages = notice;
begin;
-- Backfill and sync trigger.
select pg_temp.expect('backfill public', (select (audience = 'public' and is_public)::int from public.fit_checks where id = :pub::uuid), 1);
select pg_temp.expect('backfill group', (select (audience = 'group' and not is_public)::int from public.fit_checks where id = :grp::uuid), 1);
select pg_temp.expect('backfill legacy private', (select (audience = 'private' and not is_public)::int from public.fit_checks where id = :old_priv::uuid), 1);
select pg_temp.expect('group_id without audience becomes group', pg_temp.try(:c, format('insert into public.fit_checks(id,creator_id,status,group_id) values (%L,%L,''live'',%L)', gen_random_uuid(), :c, :g)), 1);
select pg_temp.expect('group audience needs group_id', pg_temp.try(:c, format('insert into public.fit_checks(id,creator_id,status,audience) values (%L,%L,''live'',''group'')', gen_random_uuid(), :c)), 0);
select pg_temp.expect('unknown audience rejected', pg_temp.try(:c, format('insert into public.fit_checks(id,creator_id,status,audience) values (%L,%L,''live'',''staff'')', gen_random_uuid(), :c)), 0);

-- Draft RPC (real body is replaced by the migration; stub it as a plain insert path).
select pg_temp.expect('draft friends', pg_temp.n(:c, format('select 1 from (select public.create_fit_check_draft(%L, ''x'', null, null, null, null, ''friends'')) q', :fr)), 1);
select pg_temp.expect('draft private', pg_temp.n(:c, format('select 1 from (select public.create_fit_check_draft(%L, ''x'', null, null, null, null, ''private'')) q', :pr)), 1);
select pg_temp.expect('friends post is_public false', (select (not is_public and audience = 'friends' and group_id is null)::int from public.fit_checks where id = :fr::uuid), 1);
select pg_temp.expect('draft with friends + group_id rejected', pg_temp.try(:c, format('select public.create_fit_check_draft(%L, ''x'', %L, null, null, null, ''friends'')', gen_random_uuid(), :g)), 0);
select pg_temp.expect('draft group audience without group rejected', pg_temp.try(:c, format('select public.create_fit_check_draft(%L, ''x'', null, null, null, null, ''group'')', gen_random_uuid())), 0);
select pg_temp.expect('draft unknown audience rejected', pg_temp.try(:c, format('select public.create_fit_check_draft(%L, ''x'', null, null, null, null, ''staff'')', gen_random_uuid())), 0);
select pg_temp.expect('old client (no audience) public', pg_temp.n(:c, format('select 1 from (select public.create_fit_check_draft(%L, ''y'')) q', :gx)), 1);
select pg_temp.expect('derived public', (select (audience = 'public')::int from public.fit_checks where id = :gx::uuid), 1);
select pg_temp.expect('replay same request ok', pg_temp.try(:c, format('select public.create_fit_check_draft(%L, ''x'', null, null, null, null, ''friends'')', :fr)), 1);
select pg_temp.expect('replay with other audience conflicts', pg_temp.try(:c, format('select public.create_fit_check_draft(%L, ''x'', null, null, null, null, ''private'')', :fr)), 0);
select pg_temp.expect('non-member cannot draft group', pg_temp.try(:s, format('select public.create_fit_check_draft(%L, ''x'', %L, null, null, null, ''group'')', gen_random_uuid(), :g)), 0);

-- Publish the drafts the way publish_fit_check would.
update public.fit_checks set status = 'live', expires_at = now() + interval '1 hour' where id in (:fr::uuid, :pr::uuid);

insert into public.fit_check_photos(id, fit_check_id) values (:ph::uuid, :fr::uuid), (:ph2::uuid, :pr::uuid);

-- Visibility through the read policy.
select pg_temp.expect('creator sees friends post', pg_temp.n(:c, format('select count(*) from public.fit_checks where id = %L', :fr)), 1);
select pg_temp.expect('friend sees friends post', pg_temp.n(:f, format('select count(*) from public.fit_checks where id = %L', :fr)), 1);
select pg_temp.expect('stranger cannot see friends post', pg_temp.n(:s, format('select count(*) from public.fit_checks where id = %L', :fr)), 0);
select pg_temp.expect('group member cannot see friends post', pg_temp.n(:m, format('select count(*) from public.fit_checks where id = %L', :fr)), 0);
select pg_temp.expect('creator sees private post', pg_temp.n(:c, format('select count(*) from public.fit_checks where id = %L', :pr)), 1);
select pg_temp.expect('friend cannot see private post', pg_temp.n(:f, format('select count(*) from public.fit_checks where id = %L', :pr)), 0);
select pg_temp.expect('stranger sees public', pg_temp.n(:s, format('select count(*) from public.fit_checks where id = %L', :pub)), 1);
select pg_temp.expect('member sees group', pg_temp.n(:m, format('select count(*) from public.fit_checks where id = %L', :grp)), 1);
select pg_temp.expect('stranger cannot see group', pg_temp.n(:s, format('select count(*) from public.fit_checks where id = %L', :grp)), 0);
select pg_temp.expect('friend of creator cannot see group-only post', pg_temp.n(:f, format('select count(*) from public.fit_checks where id = %L', :grp)), 0);
select pg_temp.expect('public feed filter excludes friends/private', (select count(*) from public.fit_checks where is_public and id in (:fr::uuid, :pr::uuid)), 0);

-- Votes through the activity guard.
select pg_temp.expect('friend can vote on friends post', pg_temp.try(:f, format('insert into public.fit_check_votes(fit_check_id,photo_id,voter_id) values (%L,%L,%L)', :fr, :ph, :f)), 1);
select pg_temp.expect('stranger cannot vote on friends post', pg_temp.try(:s, format('insert into public.fit_check_votes(fit_check_id,photo_id,voter_id) values (%L,%L,%L)', :fr, :ph, :s)), 0);
select pg_temp.expect('friend cannot vote on private post', pg_temp.try(:f, format('insert into public.fit_check_votes(fit_check_id,photo_id,voter_id) values (%L,%L,%L)', :pr, :ph2, :f)), 0);

-- Tally and results.
select pg_temp.expect('voting friend sees tally', pg_temp.n(:f, format('select count(*) from public.get_live_vote_tally(%L)', :fr)), 1);
select pg_temp.expect('creator sees tally', pg_temp.n(:c, format('select count(*) from public.get_live_vote_tally(%L)', :fr)), 1);
select pg_temp.expect('stranger gets no tally', pg_temp.n(:s, format('select count(*) from public.get_live_vote_tally(%L)', :fr)), 0);
update public.fit_checks set expires_at = now() - interval '1 minute' where id = :fr::uuid;
select pg_temp.expect('friend sees results after close', pg_temp.n(:f, format('select count(*) from public.get_fit_check_results(%L)', :fr)), 1);
select pg_temp.expect('stranger gets no results', pg_temp.n(:s, format('select count(*) from public.get_fit_check_results(%L)', :fr)), 0);
select pg_temp.expect('is_friend_of is symmetric', pg_temp.n(:f, format('select public.is_friend_of(%L)::int', :c)), 1);
select pg_temp.expect('is_friend_of false for stranger', pg_temp.n(:s, format('select public.is_friend_of(%L)::int', :c)), 0);
select pg_temp.expect('anon cannot call can_view_audience', has_function_privilege('anon', 'public.can_view_audience(uuid,text,uuid)', 'execute')::int, 0);
commit;

-- Rollback: friends/private stay invisible to non-creators; old API restored.
begin;
\ir ../../rollback/20261108000100_fit_check_audience.sql
select pg_temp.expect('audience column gone', (select count(*) from information_schema.columns where table_name='fit_checks' and column_name='audience'), 0);
select pg_temp.expect('friends post hidden from friend after rollback', pg_temp.n(:f, format('select count(*) from public.fit_checks where id = %L', :fr)), 0);
select pg_temp.expect('creator still sees it after rollback', pg_temp.n(:c, format('select count(*) from public.fit_checks where id = %L', :fr)), 1);
select pg_temp.expect('6-arg draft restored', (select count(*) from pg_proc where proname='create_fit_check_draft' and pronargs=6), 1);
commit;
\echo ALL PASS
