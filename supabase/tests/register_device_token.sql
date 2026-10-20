-- Manual test for register_device_token. Run against a DEV database only:
--   psql "$DEV_DATABASE_URL" -f supabase/tests/register_device_token.sql
-- Rolls back; raises (and aborts) on the first failed assertion.
-- Sets both the legacy (claim.sub) and current (claims JSON) JWT settings so
-- auth.uid() resolves on any Supabase version.
begin;

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-0000000000b2');

set local role authenticated;

-- 1. User A registers a token.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', true), set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000a1"}', true);
select public.register_device_token('test-token-1');
do $$ begin
  assert (select user_id from public.device_tokens where token = 'test-token-1')
         = '00000000-0000-0000-0000-0000000000a1', 'token should belong to A';
end $$;

-- 2. User B registers the same token (A never signed out): it moves to B.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', true), set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000b2"}', true);
select public.register_device_token('test-token-1');
do $$ begin
  assert (select user_id from public.device_tokens where token = 'test-token-1')
         = '00000000-0000-0000-0000-0000000000b2', 'token should be re-homed to B';
  assert (select count(*) from public.device_tokens where token = 'test-token-1') = 1,
         'token row must stay unique';
end $$;

-- 3. Invalid tokens are rejected.
do $$ begin
  begin
    perform public.register_device_token('');
    assert false, 'empty token should raise';
  exception when sqlstate '22023' then null;
  end;
end $$;

-- 4. Unauthenticated callers are rejected.
select set_config('request.jwt.claim.sub', '', true), set_config('request.jwt.claims', '{"sub":""}', true);
do $$ begin
  begin
    perform public.register_device_token('test-token-2');
    assert false, 'unauthenticated call should raise';
  exception when sqlstate '28000' then null;
  end;
end $$;

rollback;
