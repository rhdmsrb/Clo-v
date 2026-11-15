-- Destroys all likes and bookmarks.
drop table if exists public.fit_check_likes cascade;
drop table if exists public.fit_check_bookmarks cascade;
drop function if exists public.bump_like_count();
