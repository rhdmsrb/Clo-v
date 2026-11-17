-- Run on the checked-in 2026-11-03 schema snapshot with auth/users and roles
-- stubbed. Storage object rows stand in for successfully uploaded images.
\set ON_ERROR_STOP on
set row_security = on;

create function pg_temp.expect(label text, ok boolean) returns void language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FAIL %', label; end if;
  raise notice 'ok %', label;
end $$;

insert into auth.users(id) values ('a0000000-0000-4000-8000-000000000001'), ('a0000000-0000-4000-8000-000000000002');
insert into public.profiles(id, nickname) values ('a0000000-0000-4000-8000-000000000001','Creator'), ('a0000000-0000-4000-8000-000000000002','Viewer');
insert into storage.buckets(id, name) values ('fit-check-photos', 'fit-check-photos');
-- Simulate an existing dashboard column and an overlength title before migration.
alter table public.fit_checks add column vote_prompt text;
insert into public.fit_checks(id, creator_id, status, vote_prompt)
values ('b0000000-0000-4000-8000-000000000000', 'a0000000-0000-4000-8000-000000000001', 'live', repeat('x', 130));

\ir ../../migrations/20261107000100_engagement_columns.sql
\ir ../../migrations/20261107000200_fit_check_likes_bookmarks.sql
\ir ../../migrations/20261107000300_create_fit_check_draft_tags.sql
\ir ../../migrations/20261107000600_protect_fit_check_counts.sql
select pg_temp.expect('migration preserves old prompt', (select vote_prompt = repeat('x',130) from public.fit_checks where id='b0000000-0000-4000-8000-000000000000'));
update public.fit_checks set caption='still editable' where id='b0000000-0000-4000-8000-000000000000';
select pg_temp.expect('legacy row remains editable', (select caption = 'still editable' from public.fit_checks where id='b0000000-0000-4000-8000-000000000000'));
do $$ begin
  begin
    update public.fit_checks set vote_prompt=repeat('y',121) where id='b0000000-0000-4000-8000-000000000000';
    raise exception 'overlength title unexpectedly accepted';
  exception when sqlstate '22023' then null; end;
end $$;

select set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000001', false);
set role authenticated;
-- Old named-argument call, then real photo-row inserts and publish RPC.
select public.create_fit_check_draft(p_id => 'b0000000-0000-4000-8000-000000000001', p_caption => 'old post', p_group_id => null, p_occasion => 'Work');
insert into public.fit_check_photos(fit_check_id, image_url, position) values
 ('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001/b0000000-0000-4000-8000-000000000001/1.jpg',1),
 ('b0000000-0000-4000-8000-000000000001','a0000000-0000-4000-8000-000000000001/b0000000-0000-4000-8000-000000000001/2.jpg',2);
reset role;
insert into storage.objects(bucket_id,name) values
 ('fit-check-photos','a0000000-0000-4000-8000-000000000001/b0000000-0000-4000-8000-000000000001/1.jpg'),
 ('fit-check-photos','a0000000-0000-4000-8000-000000000001/b0000000-0000-4000-8000-000000000001/2.jpg');
set role authenticated;
select public.publish_fit_check('b0000000-0000-4000-8000-000000000001',3600);
select pg_temp.expect('old 2-photo post publishes', (select status='live' from public.fit_checks where id='b0000000-0000-4000-8000-000000000001'));
reset role;

-- Later deployed audience migration replaces the draft RPC; repeat an old call.
\ir ../../migrations/20261108000100_fit_check_audience.sql
\ir ../../migrations/20261109000100_feed_engagement_fields.sql
set role authenticated;
select public.create_fit_check_draft(p_id => 'b0000000-0000-4000-8000-000000000002', p_caption => 'old after audience', p_group_id => null, p_occasion => 'Work');
insert into public.fit_check_photos(fit_check_id,image_url,position)
 select 'b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000001/b0000000-0000-4000-8000-000000000002/'||n||'.jpg', n from generate_series(1,4) n;
reset role;
insert into storage.objects(bucket_id,name)
 select 'fit-check-photos','a0000000-0000-4000-8000-000000000001/b0000000-0000-4000-8000-000000000002/'||n||'.jpg' from generate_series(1,4) n;
set role authenticated;
select public.publish_fit_check('b0000000-0000-4000-8000-000000000002',21600);
select pg_temp.expect('old 4-photo post publishes after audience migration', (select status='live' from public.fit_checks where id='b0000000-0000-4000-8000-000000000002'));
select public.create_fit_check_draft(p_id => 'b0000000-0000-4000-8000-000000000003', p_caption => 'new post', p_tags => array[' Denim ','denim','Casual'], p_vote_prompt => 'Pick one');
select pg_temp.expect('new post fields normalized', (select tags=array['denim','casual'] and vote_prompt='Pick one' from public.fit_checks where id='b0000000-0000-4000-8000-000000000003'));
insert into public.fit_check_photos(fit_check_id,image_url,position,description,tags)
 select 'b0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000001/b0000000-0000-4000-8000-000000000003/'||n||'.jpg', n, 'Look '||n, array[' Casual ','casual'] from generate_series(1,4) n;
select pg_temp.expect('per-photo tags normalized', (select count(*)=4 and bool_and(tags=array['casual']) from public.fit_check_photos where fit_check_id='b0000000-0000-4000-8000-000000000003'));
reset role;
insert into storage.objects(bucket_id,name)
 select 'fit-check-photos','a0000000-0000-4000-8000-000000000001/b0000000-0000-4000-8000-000000000003/'||n||'.jpg' from generate_series(1,4) n;
set role authenticated;
select public.publish_fit_check('b0000000-0000-4000-8000-000000000003',86400);
select pg_temp.expect('new 4-photo post publishes', (select status='live' from public.fit_checks where id='b0000000-0000-4000-8000-000000000003'));
select pg_temp.expect('feed returns legacy and engagement fields', exists (
  select 1 from public.fetch_feed_page() row
  where row->>'id'='b0000000-0000-4000-8000-000000000003'
    and row->>'vote_prompt'='Pick one' and row->'tags'='["denim","casual"]'::jsonb
    and row->>'like_count'='0' and row ? 'fit_check_photos' and row ? 'vote_count'
));
reset role;

select set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000002', false);
set role authenticated;
insert into public.fit_check_likes(fit_check_id,user_id) values ('b0000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000002');
insert into public.fit_check_bookmarks(fit_check_id,user_id) values ('b0000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000002');
select pg_temp.expect('like count incremented', (select like_count=1 from public.fit_checks where id='b0000000-0000-4000-8000-000000000003'));
delete from public.fit_check_likes where fit_check_id='b0000000-0000-4000-8000-000000000003' and user_id='a0000000-0000-4000-8000-000000000002';
select pg_temp.expect('like count decremented', (select like_count=0 from public.fit_checks where id='b0000000-0000-4000-8000-000000000003'));
insert into public.fit_check_likes(fit_check_id,user_id) values ('b0000000-0000-4000-8000-000000000003','a0000000-0000-4000-8000-000000000002');
reset role;
select set_config('request.jwt.claim.sub', 'a0000000-0000-4000-8000-000000000001', false);
set role authenticated;
select pg_temp.expect('bookmarks private to owner', (select count(*)=0 from public.fit_check_bookmarks));
reset role;
delete from public.profiles where id='a0000000-0000-4000-8000-000000000002';
select pg_temp.expect('profile deletion cascades engagement',
  not exists(select 1 from public.fit_check_likes where user_id='a0000000-0000-4000-8000-000000000002')
  and not exists(select 1 from public.fit_check_bookmarks where user_id='a0000000-0000-4000-8000-000000000002')
  and (select like_count=0 from public.fit_checks where id='b0000000-0000-4000-8000-000000000003'));
-- The new feed rollback restores the old JSON contract without deleting data.
\ir ../../rollback/20261109000100_feed_engagement_fields.sql
set role authenticated;
select pg_temp.expect('feed rollback keeps legacy fields', exists (
  select 1 from public.fetch_feed_page() row
  where row->>'id'='b0000000-0000-4000-8000-000000000003'
    and not (row ? 'tags') and row ? 'fit_check_photos' and row ? 'vote_count'
));
reset role;
\ir ../../rollback/20261108000100_fit_check_audience.sql
\ir ../../rollback/20261107000600_protect_fit_check_counts.sql
\ir ../../rollback/20261107000300_create_fit_check_draft_tags.sql
\ir ../../rollback/20261107000200_fit_check_likes_bookmarks.sql
\ir ../../rollback/20261107000100_engagement_columns.sql
select pg_temp.expect('rollback preserves old prompt', (select vote_prompt=repeat('x',130) from public.fit_checks where id='b0000000-0000-4000-8000-000000000000'));
select pg_temp.expect('rollback removes prompt validation trigger', not exists (
  select 1 from pg_trigger where tgrelid='public.fit_checks'::regclass and tgname='validate_fit_check_vote_prompt_write'));
\echo ALL PASS
