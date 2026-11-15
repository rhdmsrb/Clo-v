-- Rollback for migrations/20261107000600_protect_fit_check_counts.sql.
-- Order: drop the trigger first, then the function. Idempotent. Data is untouched.
-- After this, clients with UPDATE on fit_checks can write like_count/vote_count again.
drop trigger if exists trg_fit_checks_protect_counts on public.fit_checks;
drop function if exists public.protect_fit_check_counts();
