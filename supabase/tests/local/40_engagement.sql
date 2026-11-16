-- Run after 00_stub.sql. Covers 20261107000100 (columns), 000200 (likes/bookmarks),
-- 000400 (live tally) and their rollbacks. 000300 (create_fit_check_draft) is not
-- covered: it needs the real RPC. Stubs are not the real schema, so a pass proves
-- the SQL's logic, not that it fits the live database.
\set ON_ERROR_STOP on
set client_min_messages = warning;

create role service_role nologin;  -- referenced by the 000200 grants; not in 00_stub.sql
alter table public.fit_checks add column group_id uuid;
create table public.fit_check_photos(id uuid primary key default gen_random_uuid(), fit_check_id uuid);
create table public.memberships(group_id uuid, profile_id uuid);
create function public.is_group_member(gid uuid) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.memberships m where m.group_id = gid and m.profile_id = auth.uid()) $$;
grant all on all tables in schema public to anon, authenticated;

-- Mirror the real fit_checks read policy (baseline line 4011) so the likes policy's
-- parent-visibility subquery is subject to it.
alter table public.fit_checks enable row level security;
create policy fc_read on public.fit_checks for select to authenticated using (
  creator_id = auth.uid() or (status <> 'draft' and not public.is_blocked_pair(creator_id)
    and (is_public or (group_id is not null and public.is_group_member(group_id)))));

\set c '''c0000000-0000-4000-8000-000000000000'''
\set v '''a0000000-0000-4000-8000-000000000000'''
\set s '''50000000-0000-4000-8000-000000000000'''
\set b '''b0000000-0000-4000-8000-000000000000'''
\set m '''d0000000-0000-4000-8000-000000000000'''
\set g '''90000000-0000-4000-8000-000000000000'''
\set live '''10000000-0000-4000-8000-000000000001'''
\set draft '''10000000-0000-4000-8000-000000000002'''
\set grp '''10000000-0000-4000-8000-000000000003'''

insert into public.profiles(id, nickname) values (:c::uuid,'c'),(:v::uuid,'v'),(:s::uuid,'s'),(:b::uuid,'b'),(:m::uuid,'m');
insert into public.memberships values (:g::uuid, :m::uuid);
insert into public.blocked_users values (:c::uuid, :b::uuid);
insert into public.fit_checks(id, creator_id, is_public, status, expires_at, group_id) values
  (:live::uuid,  :c::uuid, true,  'live',  now() + interval '1 hour', null),
  (:draft::uuid, :c::uuid, true,  'draft', null, null),
  (:grp::uuid,   :c::uuid, false, 'live',  now() + interval '1 hour', :g::uuid);
insert into public.fit_check_votes(fit_check_id, photo_id, voter_id) values
  (:live::uuid, 'e0000000-0000-4000-8000-00000000000a', :v::uuid),
  (:live::uuid, 'e0000000-0000-4000-8000-00000000000b', :s::uuid);

\ir ../../migrations/20261107000100_engagement_columns.sql
\ir ../../migrations/20261107000200_fit_check_likes_bookmarks.sql
\ir ../../migrations/20261107000400_get_live_vote_tally.sql

create function pg_temp.expect(label text, actual bigint, wanted bigint) returns void language plpgsql as $$
begin
  if actual is distinct from wanted then raise exception 'FAIL %: got %, wanted %', label, actual, wanted; end if;
  raise notice 'ok  %', label;
end $$;

-- Run `stmt` as `who`; returns 1 if it succeeded, 0 if it raised (RLS / privilege).
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
-- Likes: own-row writes, visibility.
select pg_temp.expect('like public live post', pg_temp.try(:v, format('insert into public.fit_check_likes values (%L, %L)', :live, :v)), 1);
select pg_temp.expect('like count incremented', (select like_count from public.fit_checks where id = :live::uuid), 1);
select pg_temp.expect('cannot like as someone else', pg_temp.try(:s, format('insert into public.fit_check_likes values (%L, %L)', :live, :v)), 0);
select pg_temp.expect('cannot like a draft', pg_temp.try(:s, format('insert into public.fit_check_likes values (%L, %L)', :draft, :s)), 0);
select pg_temp.expect('blocked user cannot like', pg_temp.try(:b, format('insert into public.fit_check_likes values (%L, %L)', :live, :b)), 0);
select pg_temp.expect('non-member cannot like group post', pg_temp.try(:s, format('insert into public.fit_check_likes values (%L, %L)', :grp, :s)), 0);
select pg_temp.expect('member can like group post', pg_temp.try(:m, format('insert into public.fit_check_likes values (%L, %L)', :grp, :m)), 1);
select pg_temp.expect('duplicate like rejected', pg_temp.try(:v, format('insert into public.fit_check_likes values (%L, %L)', :live, :v)), 0);
select pg_temp.expect('stranger sees the like', pg_temp.n(:s, format('select count(*) from public.fit_check_likes where fit_check_id = %L', :live)), 1);
select pg_temp.expect('blocked user does not see likes', pg_temp.n(:b, format('select count(*) from public.fit_check_likes where fit_check_id = %L', :live)), 0);
select pg_temp.expect('cannot unlike for someone else', pg_temp.n(:s, format('with d as (delete from public.fit_check_likes where user_id = %L returning 1) select count(*) from d', :v)), 0);
select pg_temp.expect('can unlike own', pg_temp.n(:v, format('with d as (delete from public.fit_check_likes where user_id = %L and fit_check_id = %L returning 1) select count(*) from d', :v, :live)), 1);
select pg_temp.expect('like count back to 0', (select like_count from public.fit_checks where id = :live::uuid), 0);
select pg_temp.expect('no UPDATE privilege on likes', has_table_privilege('authenticated', 'public.fit_check_likes', 'update')::int, 0);
select pg_temp.expect('anon has no access to likes', has_table_privilege('anon', 'public.fit_check_likes', 'select')::int, 0);

-- Bookmarks: private to the owner.
select pg_temp.expect('bookmark live post', pg_temp.try(:v, format('insert into public.fit_check_bookmarks values (%L, %L)', :live, :v)), 1);
select pg_temp.expect('others cannot read my bookmark', pg_temp.n(:s, 'select count(*) from public.fit_check_bookmarks'), 0);
select pg_temp.expect('even the post creator cannot read it', pg_temp.n(:c, 'select count(*) from public.fit_check_bookmarks'), 0);
select pg_temp.expect('owner reads own bookmark', pg_temp.n(:v, 'select count(*) from public.fit_check_bookmarks'), 1);
select pg_temp.expect('cannot bookmark as someone else', pg_temp.try(:s, format('insert into public.fit_check_bookmarks values (%L, %L)', :live, :v)), 0);
select pg_temp.expect('cannot bookmark a draft', pg_temp.try(:s, format('insert into public.fit_check_bookmarks values (%L, %L)', :draft, :s)), 0);
select pg_temp.expect('cannot delete another bookmark', pg_temp.n(:s, 'with d as (delete from public.fit_check_bookmarks returning 1) select count(*) from d'), 0);

-- Cascades: deleting a profile removes their rows.
insert into public.fit_check_likes values (:live::uuid, :s::uuid);
delete from public.profiles where id = :s::uuid;
select pg_temp.expect('profile delete cascades likes', (select count(*) from public.fit_check_likes where user_id = :s::uuid), 0);

-- Live tally: voter or creator only.
select pg_temp.expect('tally: creator sees', pg_temp.n(:c, format('select count(*) from public.get_live_vote_tally(%L)', :live)), 2);
select pg_temp.expect('tally: voter sees', pg_temp.n(:v, format('select count(*) from public.get_live_vote_tally(%L)', :live)), 2);
select pg_temp.expect('tally: non-voter sees nothing', pg_temp.n(:m, format('select count(*) from public.get_live_vote_tally(%L)', :live)), 0);
select pg_temp.expect('tally: blocked voter sees nothing', pg_temp.n(:b, format('select count(*) from public.get_live_vote_tally(%L)', :live)), 0);
select pg_temp.expect('tally: no user sees nothing', pg_temp.n('', format('select count(*) from public.get_live_vote_tally(%L)', :live)), 0);
select pg_temp.expect('tally: draft returns nothing', pg_temp.n(:c, format('select count(*) from public.get_live_vote_tally(%L)', :draft)), 0);
delete from public.fit_check_votes where voter_id = :v::uuid;
select pg_temp.expect('tally: retracted voter sees nothing', pg_temp.n(:v, format('select count(*) from public.get_live_vote_tally(%L)', :live)), 0);
commit;

-- Privileges on functions.
select pg_temp.expect('tally: anon cannot execute', (not has_function_privilege('anon', 'public.get_live_vote_tally(uuid)', 'execute'))::int, 1);
select pg_temp.expect('tally: authenticated can execute', has_function_privilege('authenticated', 'public.get_live_vote_tally(uuid)', 'execute')::int, 1);
select pg_temp.expect('tally: definer with empty search_path', (select count(*) from pg_proc
  where proname = 'get_live_vote_tally' and prosecdef and proconfig @> array['search_path=""']), 1);
select pg_temp.expect('bump_like_count: definer with empty search_path', (select count(*) from pg_proc
  where proname = 'bump_like_count' and prosecdef and proconfig @> array['search_path=""']), 1);
select pg_temp.expect('bump_like_count: not executable by authenticated', (not has_function_privilege('authenticated', 'public.bump_like_count()', 'execute'))::int, 1);

-- Rollbacks.
\ir ../../rollback/20261107000400_get_live_vote_tally.sql
\ir ../../rollback/20261107000200_fit_check_likes_bookmarks.sql
select pg_temp.expect('rollback removes tally', (select count(*) from pg_proc where proname = 'get_live_vote_tally'), 0);
select pg_temp.expect('rollback removes likes table', (select count(*) from pg_class where relname in ('fit_check_likes','fit_check_bookmarks')), 0);
select pg_temp.expect('rollback removes trigger fn', (select count(*) from pg_proc where proname = 'bump_like_count'), 0);

\echo ALL PASS
