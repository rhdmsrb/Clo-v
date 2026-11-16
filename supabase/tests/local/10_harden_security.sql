\set ON_ERROR_STOP on
insert into public.profiles values ('00000000-0000-0000-0000-00000000000a','alice',null),('00000000-0000-0000-0000-00000000000b','bob',null),('00000000-0000-0000-0000-00000000000c','cara',null);
-- fit checks by b and c, both public/live
insert into public.fit_checks(id,creator_id,is_public,status,vote_count) values
 ('10000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000000b',true,'live',5),
 ('10000000-0000-0000-0000-00000000000c','00000000-0000-0000-0000-00000000000c',true,'live',3);
-- C blocked A (reverse direction)
insert into public.blocked_users values ('00000000-0000-0000-0000-00000000000c','00000000-0000-0000-0000-00000000000a');
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
do $$ begin
 assert (select count(*) from public.popular_fit_checks()) = 1, 'blocked-by-creator post must be hidden';
 assert (select id from public.popular_fit_checks()) = '10000000-0000-0000-0000-00000000000b', 'only b visible';
 -- nickname validation
 begin perform public.save_onboarding('x','{}'); assert false,'short nick'; exception when sqlstate '22023' then null; end;
 begin perform public.save_onboarding('ok name', array_fill('s'::text, array[21])); assert false,'styles'; exception when sqlstate '22023' then null; end;
 perform public.save_onboarding('  alice2  ','{Streetwear}');
 assert (select nickname from public.profiles where id='00000000-0000-0000-0000-00000000000a')='alice2','trim+save';
 -- mutual counts cap
 begin perform * from public.get_mutual_friend_counts(array(select gen_random_uuid() from generate_series(1,101))); assert false,'cap'; exception when sqlstate '22023' then null; end;
 -- report null reason
 begin perform public.submit_content_report(p_fit_check_id=>'10000000-0000-0000-0000-00000000000b', p_reason=>null); assert false,'null reason'; exception when sqlstate '22023' then null; end;
end $$;
-- friendships: b-c friends, a-b friends, a-c friends => mutual(a,{b,c}) : b has mutual c, c has mutual b
reset role;
insert into public.friendships(user_low,user_high) values
 ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000b'),
 ('00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000000c'),
 ('00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000c');
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
do $$ begin
 -- c blocked a => c excluded; b => mutual with a via c = 1
 assert (select count(*) from public.get_mutual_friend_counts(array['00000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000000c']::uuid[]))=1, 'blocked excluded';
 assert (select mutual_count from public.get_mutual_friend_counts(array['00000000-0000-0000-0000-00000000000b']::uuid[]))=1, 'mutual count';
end $$;
-- respond_friend_request: b requests a; a accepts fine; c requests a but c blocked a => accept denied
reset role;
insert into public.friend_requests(id,requester_id,addressee_id) values
 ('20000000-0000-0000-0000-00000000000c','00000000-0000-0000-0000-00000000000c','00000000-0000-0000-0000-00000000000a');
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
do $$ begin
 begin perform public.respond_friend_request('20000000-0000-0000-0000-00000000000c', true); assert false,'accept across block'; exception when sqlstate '42501' then null; end;
 perform public.respond_friend_request('20000000-0000-0000-0000-00000000000c', false);
end $$;
-- anon denied
reset role; set role anon;
do $$ begin begin perform public.save_onboarding('abc','{}'); assert false,'anon'; exception when insufficient_privilege then null; end; end $$;
reset role;
-- wardrobe constraint
do $$ begin
 insert into public.wardrobe_items values (gen_random_uuid(),'00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000a/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001.jpg');
 begin insert into public.wardrobe_items values (gen_random_uuid(),'00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000a/%2e%2e/x.jpg'); assert false,'enc'; exception when check_violation then null; end;
 begin insert into public.wardrobe_items values (gen_random_uuid(),'00000000-0000-0000-0000-00000000000a','00000000-0000-0000-0000-00000000000b/30000000-0000-0000-0000-000000000001/40000000-0000-0000-0000-000000000001.jpg'); assert false,'other owner'; exception when check_violation then null; end;
 begin insert into public.device_tokens values (repeat('a',513), gen_random_uuid()); assert false,'tok'; exception when check_violation then null; end;
end $$;
select 'ALL PASS';
