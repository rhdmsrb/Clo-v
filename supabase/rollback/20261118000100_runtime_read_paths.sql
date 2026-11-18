begin;
drop function if exists public.group_card_previews_v1(uuid[]);
drop function if exists public.home_feed_page_v1(integer, timestamptz, uuid);
drop index if exists public.fit_checks_home_live_newest_idx;
commit;
