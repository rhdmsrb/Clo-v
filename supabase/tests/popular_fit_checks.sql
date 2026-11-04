-- Manual test for popular_fit_checks. Run against a DEV database only:
--   psql "$DEV_DATABASE_URL" -f supabase/tests/popular_fit_checks.sql
-- Rolls back; raises (and aborts) on the first failed assertion.
-- Needs no fixture rows: it checks access control and argument clamping.
begin;

insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000c3');

-- 1. Anonymous callers cannot execute the function.
set local role anon;
do $$ begin
  begin
    perform * from public.popular_fit_checks();
    assert false, 'anon call should be denied';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- 2. Out-of-range arguments are clamped instead of failing.
set local role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c3', true), set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-0000000000c3"}', true);
do $$ begin
  assert (select count(*) from public.popular_fit_checks(-5, -10, 100000)) <= 1,
         'a negative limit must clamp to 1 row at most';
  assert (select count(*) from public.popular_fit_checks(1000, 0, 7)) <= 50,
         'the limit must be capped at 50';
  assert (select count(*) from public.popular_fit_checks(null, null, null)) <= 20,
         'null arguments must fall back to defaults';
end $$;

rollback;
