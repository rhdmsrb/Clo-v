-- Apply the snapshot, engagement and audience migrations and draft claims first.
\set ON_ERROR_STOP on
begin;

create function pg_temp.expect(label text, ok boolean) returns void language plpgsql as $$
begin
    if ok is distinct from true then raise exception 'FAIL %', label; end if;
    raise notice 'ok %', label;
end $$;

insert into auth.users(id) values ('a1000000-0000-4000-8000-000000000001'), ('a1000000-0000-4000-8000-000000000002');
insert into public.profiles(id, nickname) values
    ('a1000000-0000-4000-8000-000000000001', 'Draft owner'),
    ('a1000000-0000-4000-8000-000000000002', 'Other owner');
insert into storage.buckets(id, name) values ('fit-check-photos', 'fit-check-photos');
insert into public.fit_checks(id, creator_id, status, created_at) values
    ('b1000000-0000-4000-8000-000000000001', 'a1000000-0000-4000-8000-000000000001', 'draft', now() - interval '2 hours'),
    ('b1000000-0000-4000-8000-000000000002', 'a1000000-0000-4000-8000-000000000001', 'draft', now()),
    ('b1000000-0000-4000-8000-000000000003', 'a1000000-0000-4000-8000-000000000002', 'draft', now() - interval '2 hours'),
    ('b1000000-0000-4000-8000-000000000004', 'a1000000-0000-4000-8000-000000000001', 'live', now()),
    ('b1000000-0000-4000-8000-000000000005', 'a1000000-0000-4000-8000-000000000001', 'draft', now());

select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000001', true);
insert into public.fit_check_photos(fit_check_id, image_url, position)
select f.id, f.creator_id || '/' || f.id || '/' || n || '.jpg', n
from public.fit_checks f cross join generate_series(1, 2) n
where f.id in ('b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000005');
insert into storage.objects(bucket_id, name)
select 'fit-check-photos', image_url from public.fit_check_photos
where fit_check_id in ('b1000000-0000-4000-8000-000000000001', 'b1000000-0000-4000-8000-000000000005');

set local role authenticated;
select pg_temp.expect('claim only stale drafts owned by the caller',
    (select array_agg(id) = array['b1000000-0000-4000-8000-000000000001'::uuid]
     from public.claim_fit_check_drafts_for_cleanup_v1()));
select pg_temp.expect('another owner draft and live posts cannot be claimed',
    not exists (select 1 from public.claim_fit_check_drafts_for_cleanup_v1('b1000000-0000-4000-8000-000000000003'))
    and not exists (select 1 from public.claim_fit_check_drafts_for_cleanup_v1('b1000000-0000-4000-8000-000000000004')));
select public.publish_fit_check('b1000000-0000-4000-8000-000000000005', 3600);
select pg_temp.expect('a completed publish wins over a subsequent cleanup claim',
    not exists (select 1 from public.claim_fit_check_drafts_for_cleanup_v1('b1000000-0000-4000-8000-000000000005')));
do $$ begin
    begin
        perform public.publish_fit_check('b1000000-0000-4000-8000-000000000001', 3600);
        raise exception 'claimed draft was published';
    exception when sqlstate '55000' then
        null;
    end;
end $$;
select pg_temp.expect('claimed draft remains available to retry cleanup',
    (select count(*) = 1 from public.claim_fit_check_drafts_for_cleanup_v1()));
select pg_temp.expect('explicit abandon can claim an owned recent draft',
    (select count(*) = 1 from public.claim_fit_check_drafts_for_cleanup_v1('b1000000-0000-4000-8000-000000000002')));
delete from public.fit_checks
where id = 'b1000000-0000-4000-8000-000000000001' and status = 'draft' and draft_cleanup_claimed;
select pg_temp.expect('claimed rows can be deleted through existing RLS',
    not exists (select 1 from public.fit_checks where id = 'b1000000-0000-4000-8000-000000000001'));
reset role;
select pg_temp.expect('anonymous role cannot claim drafts',
    not has_function_privilege('anon', 'public.claim_fit_check_drafts_for_cleanup_v1(uuid)', 'execute'));
rollback;
