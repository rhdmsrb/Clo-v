\set ON_ERROR_STOP on
-- triggers installed AFTER the migration revoked EXECUTE: they must still fire.
create trigger t_v1 after insert on public.fit_check_votes for each row execute function public.bump_vote_count();
create trigger t_v2 after insert on public.fit_check_votes for each row execute function public.notify_on_vote();
create trigger t_c1 after insert on public.fit_check_comments for each row execute function public.bump_comment_count();
create trigger t_c2 after insert on public.fit_check_comments for each row execute function public.notify_on_comment();
delete from public.notifications;
set role authenticated; select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false);
do $$ declare vc int; cc int; begin
  insert into public.fit_check_votes values ('10000000-0000-0000-0000-00000000000b', null, '00000000-0000-0000-0000-00000000000a');
  insert into public.fit_check_comments(fit_check_id, commenter_id, body) values ('10000000-0000-0000-0000-00000000000b','00000000-0000-0000-0000-00000000000a','hi');
  select vote_count, comment_count into vc, cc from public.fit_checks where id='10000000-0000-0000-0000-00000000000b';
  assert vc = 6 and cc = 1, 'counters bumped by triggers after revoke';
  assert (select count(*) from public.notifications) = 2, 'notifications created by triggers';
  -- trigger functions are not callable directly
  begin perform public.bump_vote_count(); assert false,'direct call'; exception when insufficient_privilege then null; end;
  -- friend requests: no direct writes
  begin insert into public.friend_requests(requester_id,addressee_id) values (auth.uid(),'00000000-0000-0000-0000-00000000000b'); assert false,'fr insert'; exception when insufficient_privilege then null; end;
  -- profiles: allowed columns only
  update public.profiles set avatar_url = 'https://exbozksjwpyvstqhcyqy.supabase.co/storage/v1/object/public/avatars/00000000-0000-0000-0000-00000000000a/x.jpg' where id=auth.uid();
  begin update public.profiles set account_code='CLOV-HACK' where id=auth.uid(); assert false,'account_code'; exception when insufficient_privilege then null; end;
  begin update public.profiles set avatar_url='https://evil.example/pixel.png' where id=auth.uid(); assert false,'avatar host'; exception when check_violation then null; end;
  begin update public.profiles set avatar_url='https://exbozksjwpyvstqhcyqy.supabase.co/storage/v1/object/public/avatars/00000000-0000-0000-0000-00000000000b/x.jpg' where id=auth.uid(); assert false,'avatar other folder'; exception when check_violation then null; end;
  begin update public.profiles set nickname='x' where id=auth.uid(); assert false,'nick'; exception when check_violation then null; end;
  update public.profiles set nickname='alice3' where id=auth.uid();
end $$;
reset role; set role anon;
do $$ begin begin perform count(*) from public.profiles; assert false,'anon table'; exception when insufficient_privilege then null; end; end $$;
reset role;
select 'ALL PASS 2';
