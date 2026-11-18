-- Apply the snapshot, engagement and audience migrations before running.
\set ON_ERROR_STOP on
begin;
set local row_security = on;

create function pg_temp.expect(label text, ok boolean) returns void language plpgsql as $$
begin
    if ok is distinct from true then raise exception 'FAIL %', label; end if;
    raise notice 'ok %', label;
end $$;

insert into auth.users(id)
select ('a0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid from generate_series(1, 6) n;
insert into public.profiles(id, nickname)
select id, 'Test member ' || right(id::text, 1) from auth.users where id::text like 'a0000000-%';
insert into public.friendships(user_low, user_high)
values ('a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000002');
insert into public.groups(id, name, creator_id, invite_code)
values ('c0000000-0000-4000-8000-000000000001', 'Preview test', 'a0000000-0000-4000-8000-000000000001', 'TEST24');
insert into public.group_members(group_id, profile_id)
select 'c0000000-0000-4000-8000-000000000001', id from public.profiles
where id::text like 'a0000000-%' and right(id::text, 1) <> '6';

insert into public.fit_checks(id, creator_id, status, audience, created_at, expires_at)
values
    ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'draft', 'public', '2026-11-18T01:00:00.123456Z', null),
    ('b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001', 'live', 'friends', '2026-11-18T01:00:00.123456Z', null),
    ('b0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000001', 'live', 'private', now(), null),
    ('b0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000001', 'live', 'public', now(), now() - interval '1 hour'),
    ('b0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000001', 'draft', 'public', now(), null),
    ('b0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000001', 'live', 'public', '2026-11-18T01:00:00.123455Z', null),
    ('b0000000-0000-4000-8000-000000000007', 'a0000000-0000-4000-8000-000000000003', 'live', 'public', now(), null);

insert into public.fit_checks(id, creator_id, status, audience, group_id, created_at)
select ('bb000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
    'a0000000-0000-4000-8000-000000000001', 'draft', 'group', 'c0000000-0000-4000-8000-000000000001',
    '2026-11-18T01:00:00Z'::timestamptz + n * interval '1 second'
from generate_series(1, 55) n;

select set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000001', true);
insert into public.fit_check_photos(id, fit_check_id, position, image_url)
values ('d0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000001', 1,
    'a0000000-0000-4000-8000-000000000001/b0000000-0000-4000-8000-000000000001/1.jpg');
insert into public.fit_check_photos(fit_check_id, position, image_url)
select f.id, n, f.creator_id || '/' || f.id || '/' || n || '.jpg'
from public.fit_checks f cross join generate_series(1, 2) n where f.group_id is not null;
update public.fit_checks set status = 'live'
where id = 'b0000000-0000-4000-8000-000000000001' or group_id is not null;

select set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000003', true);
insert into public.fit_check_comments(fit_check_id, commenter_id, body)
values ('b0000000-0000-4000-8000-000000000001', auth.uid(), 'Hidden from blocker');
insert into public.fit_check_votes(fit_check_id, photo_id, voter_id)
values ('b0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001', auth.uid());

select set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000002', true);
insert into public.fit_check_comments(fit_check_id, commenter_id, body)
values ('b0000000-0000-4000-8000-000000000001', auth.uid(), 'Visible to viewer');
insert into public.fit_check_votes(fit_check_id, photo_id, voter_id)
values ('b0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001', auth.uid());
insert into public.fit_check_likes(fit_check_id, user_id)
values ('b0000000-0000-4000-8000-000000000001', auth.uid());
insert into public.profile_follows(follower_id, following_id)
values (auth.uid(), 'a0000000-0000-4000-8000-000000000001');
insert into public.blocked_users(blocker_id, blocked_id)
values (auth.uid(), 'a0000000-0000-4000-8000-000000000003');
insert into public.feed_events(user_id, fit_check_id, event)
values (auth.uid(), 'b0000000-0000-4000-8000-000000000001', 'vote');

set local role authenticated;
select pg_temp.expect('viewer home has only visible public and friend posts',
    (select count(*) = 3 from public.home_feed_page_v1(24)));
select pg_temp.expect('first page uses unique order and retains all timestamp digits',
    (select row->'item'->>'id' = 'b0000000-0000-4000-8000-000000000002'
        and row->>'cursor_created_at' = '2026-11-18T01:00:00.123456Z'
    from public.home_feed_page_v1(1) row));
select pg_temp.expect('only viewer vote, authorized comment count and viewer engagement',
    exists (select 1 from public.home_feed_page_v1(24) row
        where row->'item'->>'id' = 'b0000000-0000-4000-8000-000000000001'
          and row->'item'->'visible_comment_count' = '1'::jsonb
          and jsonb_array_length(row->'item'->'fit_check_votes') = 1
          and row->'item'->'fit_check_votes'->0->>'voter_id' = auth.uid()::text
          and row->'viewer_liked' = 'true'::jsonb and row->'viewer_follows' = 'true'::jsonb
          and row->'signal_score' = '6'::jsonb));
select pg_temp.expect('group preview counts beyond 50 and returns tightly bounded summaries',
    exists (select 1 from public.group_card_previews_v1(array['c0000000-0000-4000-8000-000000000001'::uuid]) p
        where p.member_count = 5 and p.live_count = 55 and jsonb_array_length(p.members) = 4
          and jsonb_array_length(p.photo_paths) = 3
          and p.photo_paths->>0 = 'a0000000-0000-4000-8000-000000000001/bb000000-0000-4000-8000-000000000055/1.jpg'));

reset role;
insert into public.fit_checks(id, creator_id, status, audience, created_at)
values ('b0000000-0000-4000-8000-000000000008', 'a0000000-0000-4000-8000-000000000001', 'live', 'public', '2026-11-19T01:00:00Z');
set local role authenticated;
select pg_temp.expect('new inserts do not shift a continuation and equal timestamps page correctly',
    (select array_agg(row->'item'->>'id') = array['b0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000006']
    from public.home_feed_page_v1(24, '2026-11-18T01:00:00.123456Z', 'b0000000-0000-4000-8000-000000000002') row));
select set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000006', true);
select pg_temp.expect('non-member cannot request a group preview',
    not exists (select 1 from public.group_card_previews_v1(array['c0000000-0000-4000-8000-000000000001'::uuid])));
select pg_temp.expect('outsider cannot see friend posts or other voters',
    not exists (select 1 from public.home_feed_page_v1(24) row
        where row->'item'->>'audience' <> 'public' or row->'item'->'fit_check_votes' <> '[]'::jsonb));
select set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000001', true);
select pg_temp.expect('the home feed keeps the existing behavior for the viewer’s own friends-only posts',
    not exists (select 1 from public.home_feed_page_v1(24) row where row->'item'->>'audience' = 'friends'));

reset role;
select pg_temp.expect('anonymous roles cannot call the RPCs',
    not has_function_privilege('anon', 'public.home_feed_page_v1(integer,timestamptz,uuid)', 'execute')
    and not has_function_privilege('anon', 'public.group_card_previews_v1(uuid[])', 'execute'));
rollback;
