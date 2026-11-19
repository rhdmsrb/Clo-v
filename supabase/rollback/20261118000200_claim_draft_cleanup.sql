begin;
drop function if exists public.claim_fit_check_drafts_for_cleanup_v1(uuid);
drop trigger if exists prevent_claimed_draft_publication on public.fit_checks;
drop function if exists public.prevent_claimed_draft_publication();
alter table public.fit_checks drop column if exists draft_cleanup_claimed;
commit;
