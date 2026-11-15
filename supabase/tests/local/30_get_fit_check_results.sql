-- Run after 00_stub.sql. Stubs are not the real schema: a pass proves the
-- function's logic, not that it fits the live database.
\set ON_ERROR_STOP on
set client_min_messages = warning;

alter table public.fit_checks add column group_id uuid;
create table public.memberships(group_id uuid, profile_id uuid);
create function public.is_group_member(gid uuid) returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.memberships m where m.group_id = gid and m.profile_id = auth.uid()) $$;

-- creator c, voters v and w, stranger s, blocked b, member m
\set c '''c0000000-0000-4000-8000-000000000000'''
\set v '''a0000000-0000-4000-8000-000000000000'''
\set w '''a1000000-0000-4000-8000-000000000000'''
\set s '''50000000-0000-4000-8000-000000000000'''
\set b '''b0000000-0000-4000-8000-000000000000'''
\set m '''d0000000-0000-4000-8000-000000000000'''
\set g '''90000000-0000-4000-8000-000000000000'''

insert into public.memberships values (:g::uuid, :m::uuid);
insert into public.blocked_users values (:c::uuid, :b::uuid);
insert into public.fit_checks(id, creator_id, is_public, status, expires_at, group_id) values
  ('10000000-0000-4000-8000-000000000001', :c::uuid, true,  'live',     now() + interval '1 hour', null),
  ('10000000-0000-4000-8000-000000000002', :c::uuid, true,  'expired',  now() - interval '1 hour', null),
  ('10000000-0000-4000-8000-000000000003', :c::uuid, true,  'archived', now() + interval '1 hour', null),
  -- expired by the clock, but the job has not flipped its status yet
  ('10000000-0000-4000-8000-000000000004', :c::uuid, true,  'live',     now() - interval '1 minute', null),
  ('10000000-0000-4000-8000-000000000005', :c::uuid, false, 'expired',  now() - interval '1 hour', :g::uuid),
  ('10000000-0000-4000-8000-000000000006', :c::uuid, true,  'draft',    null, null),
  ('10000000-0000-4000-8000-000000000007', :c::uuid, true,  'live',     null, null);

-- Every post: v and w on photo A, s on photo B.
insert into public.fit_check_votes(fit_check_id, photo_id, voter_id)
select f.id, x.photo::uuid, x.voter::uuid from public.fit_checks f cross join (values
  ('e0000000-0000-4000-8000-00000000000a', :v), ('e0000000-0000-4000-8000-00000000000a', :w),
  ('e0000000-0000-4000-8000-00000000000b', :s)) x(photo, voter);

\ir ../../migrations/20261106000100_get_fit_check_results.sql

-- Rows for `post` as seen by `who`, called as the authenticated role.
create function pg_temp.results(who text, post int) returns setof jsonb language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', who, true);
  set local role authenticated;
  return query select to_jsonb(r) from public.get_fit_check_results(
    ('10000000-0000-4000-8000-00000000000' || post)::uuid) r;
  reset role;
end $$;

create function pg_temp.expect(label text, actual bigint, wanted bigint) returns void language plpgsql as $$
begin
  if actual is distinct from wanted then raise exception 'FAIL %: got %, wanted %', label, actual, wanted; end if;
  raise notice 'ok  %', label;
end $$;

create function pg_temp.total(who text, post int) returns bigint language sql as $$
  select coalesce(sum((r->>'vote_count')::int), 0) from pg_temp.results(who, post) r $$;

create function pg_temp.photos(who text, post int) returns bigint language sql as $$
  select count(*) from pg_temp.results(who, post) $$;
set client_min_messages = notice;

begin;
-- Closed posts return totals.
select pg_temp.expect('expired: stranger total',           pg_temp.total(:s, 2), 3);
select pg_temp.expect('expired: one row per voted photo',  pg_temp.photos(:s, 2), 2);
select pg_temp.expect('archived: stranger total',          pg_temp.total(:s, 3), 3);
select pg_temp.expect('past expiry, not flipped: total',   pg_temp.total(:s, 4), 3);
select pg_temp.expect('expired: creator total',            pg_temp.total(:c, 2), 3);

-- Open posts and drafts return nothing, even to their creator.
select pg_temp.expect('live: stranger gets nothing',       pg_temp.photos(:s, 1), 0);
select pg_temp.expect('live: voter gets nothing',          pg_temp.photos(:v, 1), 0);
select pg_temp.expect('live: creator gets nothing',        pg_temp.photos(:c, 1), 0);
select pg_temp.expect('live, no expiry: nothing',          pg_temp.photos(:s, 7), 0);
select pg_temp.expect('draft: stranger gets nothing',      pg_temp.photos(:s, 6), 0);
select pg_temp.expect('draft: creator gets nothing',       pg_temp.photos(:c, 6), 0);

-- Visibility.
select pg_temp.expect('blocked: public expired hidden',    pg_temp.photos(:b, 2), 0);
select pg_temp.expect('group: non-member hidden',          pg_temp.photos(:s, 5), 0);
select pg_temp.expect('group: member sees',                pg_temp.total(:m, 5), 3);
select pg_temp.expect('group: creator sees',               pg_temp.total(:c, 5), 3);
select pg_temp.expect('no signed-in user: nothing',        pg_temp.photos('', 2), 0);
select pg_temp.expect('unknown post: nothing',             pg_temp.photos(:s, 9), 0);

-- is_mine marks only the caller's own photo.
select pg_temp.expect('is_mine: voter, voted photo', (select count(*) from pg_temp.results(:v, 2) r
  where r->>'photo_id' = 'e0000000-0000-4000-8000-00000000000a' and (r->>'is_mine')::bool), 1);
select pg_temp.expect('is_mine: voter, exactly one', (select count(*) from pg_temp.results(:v, 2) r where (r->>'is_mine')::bool), 1);
select pg_temp.expect('is_mine: non-voter, none', (select count(*) from pg_temp.results(:m, 5) r where (r->>'is_mine')::bool), 0);
select pg_temp.expect('is_mine: creator, none', (select count(*) from pg_temp.results(:c, 2) r where (r->>'is_mine')::bool), 0);

-- Only these three keys, and no voter id anywhere in the output.
select pg_temp.expect('only photo_id, vote_count, is_mine', (select count(*) from pg_temp.results(:c, 2) r
  where r ?& array['photo_id','vote_count','is_mine'] and (select count(*) from jsonb_object_keys(r)) = 3), 2);
select pg_temp.expect('no voter ids in output', (select count(*) from pg_temp.results(:c, 2) r
  where r::text like '%a0000000-%' or r::text like '%a1000000-%' or r::text like '%50000000-%'), 0);
commit;

-- Privileges: definer, empty search_path, authenticated only.
select pg_temp.expect('anon cannot execute', (not has_function_privilege('anon', 'public.get_fit_check_results(uuid)', 'execute'))::int, 1);
select pg_temp.expect('authenticated can execute', has_function_privilege('authenticated', 'public.get_fit_check_results(uuid)', 'execute')::int, 1);
select pg_temp.expect('public has no grant', (select count(*) from pg_proc p, aclexplode(p.proacl) a
  where p.proname = 'get_fit_check_results' and a.grantee = 0), 0);
select pg_temp.expect('definer with empty search_path', (select count(*) from pg_proc
  where proname = 'get_fit_check_results' and prosecdef and proconfig @> array['search_path=""']), 1);

\ir ../../rollback/20261106000100_get_fit_check_results_rollback.sql
select pg_temp.expect('rollback removes the function', (select count(*) from pg_proc where proname = 'get_fit_check_results'), 0);

\echo ALL PASS
