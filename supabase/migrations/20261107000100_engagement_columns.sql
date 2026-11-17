-- Engagement columns: post-level tags, like_count, per-photo description/tags,
-- and fit_checks.vote_prompt.
--
-- Additive and idempotent. Old app builds ignore the new columns.
-- vote_prompt is read by the app (attachVotePrompts) but is absent from
-- baseline/remote_schema_2026-11-03.sql, so it is guarded with IF NOT EXISTS in
-- case the live project already has it from a dashboard change.
-- Rollback: supabase/rollback/20261107000100_engagement_columns.sql

alter table public.fit_checks
  add column if not exists vote_prompt text,
  add column if not exists tags text[] not null default '{}'::text[],
  add column if not exists like_count integer not null default 0;

alter table public.fit_check_photos
  add column if not exists description text,
  add column if not exists tags text[] not null default '{}'::text[];

-- Preserve any legacy prompts already over the new limit. The draft RPC checks
-- new titles; this trigger also checks direct inserts and actual title changes,
-- without blocking unrelated updates to old rows or rewriting their content.
create or replace function public.validate_fit_check_vote_prompt()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    if char_length(new.vote_prompt) > 120 then
      raise exception 'Title too long' using errcode = '22023';
    end if;
  elsif new.vote_prompt is distinct from old.vote_prompt and char_length(new.vote_prompt) > 120 then
    raise exception 'Title too long' using errcode = '22023';
  end if;
  return new;
end;
$$;
revoke all on function public.validate_fit_check_vote_prompt() from public, anon, authenticated;

drop trigger if exists validate_fit_check_vote_prompt_write on public.fit_checks;
create trigger validate_fit_check_vote_prompt_write
  before insert or update of vote_prompt on public.fit_checks
  for each row execute function public.validate_fit_check_vote_prompt();

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'fit_checks_tags_max') then
    alter table public.fit_checks
      add constraint fit_checks_tags_max check (cardinality(tags) <= 8);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'fit_checks_like_count_nonneg') then
    alter table public.fit_checks
      add constraint fit_checks_like_count_nonneg check (like_count >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'fit_check_photos_description_length') then
    alter table public.fit_check_photos
      add constraint fit_check_photos_description_length check (char_length(description) <= 200);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'fit_check_photos_tags_max') then
    alter table public.fit_check_photos
      add constraint fit_check_photos_tags_max check (cardinality(tags) <= 8);
  end if;
  -- Per-element length cannot be a CHECK (no subqueries); bound the joined size instead.
  if not exists (select 1 from pg_constraint where conname = 'fit_checks_tags_size') then
    alter table public.fit_checks
      add constraint fit_checks_tags_size check (char_length(array_to_string(tags, ',')) <= 300);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'fit_check_photos_tags_size') then
    alter table public.fit_check_photos
      add constraint fit_check_photos_tags_size check (char_length(array_to_string(tags, ',')) <= 300);
  end if;
end $$;

create index if not exists fit_checks_tags_gin_idx on public.fit_checks using gin (tags);

-- Server-side normalisation of per-photo tags (the column CHECKs only bound count and
-- total size): trim, lowercase, drop empties, cap each at 30 chars, dedupe keeping
-- first occurrence, keep at most 8. 8*30 + 7 commas = 247 <= the 300 tags_size CHECK,
-- so normalised output always satisfies fit_check_photos_tags_max/_size.
create or replace function public.normalize_photo_tags()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  select coalesce(array_agg(t order by first_pos), '{}'::text[]) into new.tags
    from (
      select t, first_pos
        from (
          select left(lower(btrim(x)), 30) as t, min(ord) as first_pos
            from unnest(coalesce(new.tags, '{}'::text[])) with ordinality as u(x, ord)
           where btrim(x) <> ''
           group by left(lower(btrim(x)), 30)
        ) d
       order by first_pos
       limit 8
    ) s;
  return new;
end;
$$;

revoke all on function public.normalize_photo_tags() from public, anon, authenticated;

drop trigger if exists normalize_photo_tags_write on public.fit_check_photos;
create trigger normalize_photo_tags_write
  before insert or update of tags on public.fit_check_photos
  for each row execute function public.normalize_photo_tags();
