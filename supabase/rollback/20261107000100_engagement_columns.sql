-- ROLLBACK ORDER: 400, 300, 200, 100 (newest first; 300 references fit_checks.tags and
-- vote_prompt, 200 references fit_checks.like_count).
--
-- Destroys stored tags, descriptions and like counts.
-- vote_prompt is deliberately NOT dropped: the column may predate this migration (the
-- app already reads it). Only the length constraint is removed. If you have confirmed
-- this migration created the column, drop it by hand:
--   alter table public.fit_checks drop column vote_prompt;
drop trigger if exists normalize_photo_tags_write on public.fit_check_photos;
drop function if exists public.normalize_photo_tags();
drop index if exists public.fit_checks_tags_gin_idx;
alter table public.fit_check_photos
  drop constraint if exists fit_check_photos_description_length,
  drop constraint if exists fit_check_photos_tags_max,
  drop constraint if exists fit_check_photos_tags_size,
  drop column if exists description,
  drop column if exists tags;
alter table public.fit_checks
  drop constraint if exists fit_checks_vote_prompt_length,
  drop constraint if exists fit_checks_tags_max,
  drop constraint if exists fit_checks_tags_size,
  drop constraint if exists fit_checks_like_count_nonneg,
  drop column if exists like_count,
  drop column if exists tags;
