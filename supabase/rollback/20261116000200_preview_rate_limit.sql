-- Rollback for 20261116000200_preview_rate_limit.sql.
-- Redeploy the previous fit-check-preview first (it no longer calls this RPC).
drop function if exists public.reserve_preview_hit(text, integer, integer);
drop table if exists public.preview_rate_limits;
