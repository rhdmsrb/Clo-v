-- Fit-Check audiences: public | friends | group | private ("Only me").
--
-- Until now visibility was is_public + group_id. This adds fit_checks.audience as
-- the source of truth and keeps is_public = (audience = 'public') in sync by trigger,
-- so every existing is_public consumer (public feed, popular_fit_checks, indexes,
-- older app builds) keeps working and never sees a friends/group/private post.
--
-- One shared rule, public.can_view_audience(), replaces the four copies of
-- "creator, or not blocked and public/group member": the fit_checks read policy,
-- the vote/comment activity trigger, get_live_vote_tally and get_fit_check_results.
-- Child tables (photos, votes, comments, likes, storage) already key off the
-- fit_checks read policy, so they inherit it.
--
-- create_fit_check_draft gains p_audience (default null = derive from p_group_id, so
-- older app builds that send only p_group_id behave as before).
--
-- Additive; existing rows are backfilled. Rollback:
--   supabase/rollback/20261108000100_fit_check_audience.sql

-- 1. Column ------------------------------------------------------------------
alter table public.fit_checks add column if not exists audience text;

update public.fit_checks
   set audience = case when group_id is not null then 'group'
                       when is_public then 'public'
                       else 'private' end
 where audience is null;

alter table public.fit_checks alter column audience set default 'public';
alter table public.fit_checks alter column audience set not null;

alter table public.fit_checks drop constraint if exists fit_checks_audience_check;
alter table public.fit_checks add constraint fit_checks_audience_check
  check (audience in ('public', 'friends', 'group', 'private')
         and ((audience = 'group') = (group_id is not null)));

-- 2. Keep is_public in sync (and tolerate writers that only set group_id) -----
create or replace function public.sync_fit_check_audience()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.group_id is not null and new.audience = 'public' then new.audience := 'group'; end if;
  new.is_public := (new.audience = 'public');
  return new;
end; $$;

drop trigger if exists fit_checks_sync_audience on public.fit_checks;
create trigger fit_checks_sync_audience
  before insert or update of audience, group_id, is_public on public.fit_checks
  for each row execute function public.sync_fit_check_audience();

-- 3. Helpers -------------------------------------------------------------------
create or replace function public.is_friend_of(p_other uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and p_other is not null and exists (
    select 1 from public.friendships f
     where f.user_low = least(auth.uid(), p_other)
       and f.user_high = greatest(auth.uid(), p_other));
$$;
revoke all on function public.is_friend_of(uuid) from public, anon;
grant execute on function public.is_friend_of(uuid) to authenticated;

-- The one visibility rule. Draft handling stays with each caller.
create or replace function public.can_view_audience(p_creator uuid, p_audience text, p_group_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select auth.uid() is not null and (
    p_creator = auth.uid()
    or (
      not public.is_blocked_pair(p_creator)
      and (
        p_audience = 'public'
        or (p_audience = 'group' and p_group_id is not null and public.is_group_member(p_group_id))
        or (p_audience = 'friends' and public.is_friend_of(p_creator))
      )
    )
  );
$$;
revoke all on function public.can_view_audience(uuid, text, uuid) from public, anon;
grant execute on function public.can_view_audience(uuid, text, uuid) to authenticated;

-- 4. Read policy ---------------------------------------------------------------
drop policy if exists "fit_checks: read (published audience or owner)" on public.fit_checks;
create policy "fit_checks: read (published audience or owner)" on public.fit_checks
  for select to authenticated
  using (creator_id = auth.uid()
         or (status <> 'draft' and public.can_view_audience(creator_id, audience, group_id)));

-- 5. Vote / comment activity guard ---------------------------------------------
create or replace function public.validate_fit_check_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare f public.fit_checks;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select * into f from public.fit_checks where id = new.fit_check_id for update;
  if f.id is null or not public.can_view_audience(f.creator_id, f.audience, f.group_id) then
    raise exception 'Post unavailable' using errcode='42501';
  end if;
  if f.status <> 'live' or f.expires_at <= now() then raise exception 'Fit-Check is not live' using errcode='23514'; end if;
  if new.photo_id is not null and not exists (
       select 1 from public.fit_check_photos p where p.id = new.photo_id and p.fit_check_id = new.fit_check_id) then
    raise exception 'Photo does not belong to this Fit-Check' using errcode='23514';
  end if;
  return new;
end; $$;

-- 6. Tally and results ---------------------------------------------------------
create or replace function public.get_live_vote_tally(p_fit_check_id uuid)
returns table (photo_id uuid, vote_count integer, is_mine boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select v.photo_id, count(*)::integer, bool_or(v.voter_id = auth.uid())
    from public.fit_check_votes v
    join public.fit_checks f on f.id = v.fit_check_id
   where v.fit_check_id = p_fit_check_id
     and auth.uid() is not null
     and f.status <> 'draft'
     and public.can_view_audience(f.creator_id, f.audience, f.group_id)
     and (
       f.creator_id = auth.uid()
       or exists (select 1 from public.fit_check_votes mine
                   where mine.fit_check_id = p_fit_check_id and mine.voter_id = auth.uid())
     )
   group by v.photo_id;
$$;
revoke all on function public.get_live_vote_tally(uuid) from public, anon;
grant execute on function public.get_live_vote_tally(uuid) to authenticated;

create or replace function public.get_fit_check_results(p_fit_check_id uuid)
returns table (photo_id uuid, vote_count integer, is_mine boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select v.photo_id, count(*)::integer, bool_or(v.voter_id = auth.uid())
    from public.fit_check_votes v
    join public.fit_checks f on f.id = v.fit_check_id
   where v.fit_check_id = p_fit_check_id
     and auth.uid() is not null
     and f.status <> 'draft'
     and (f.status <> 'live' or f.expires_at <= now())
     and public.can_view_audience(f.creator_id, f.audience, f.group_id)
   group by v.photo_id;
$$;
revoke all on function public.get_fit_check_results(uuid) from public, anon;
grant execute on function public.get_fit_check_results(uuid) to authenticated;

-- 7. Draft RPC -----------------------------------------------------------------
drop function if exists public.create_fit_check_draft(uuid, text, uuid, text, text[], text);

create or replace function public.create_fit_check_draft(
  p_id uuid,
  p_caption text default null,
  p_group_id uuid default null,
  p_occasion text default null,
  p_tags text[] default null,
  p_vote_prompt text default null,
  p_audience text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  f public.fit_checks;
  v_tags text[];
  v_prompt text := nullif(btrim(p_vote_prompt), '');
  v_audience text := coalesce(p_audience, case when p_group_id is not null then 'group' else 'public' end);
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if v_audience not in ('public', 'friends', 'group', 'private')
     or (v_audience = 'group') <> (p_group_id is not null) then
    raise exception 'Invalid audience' using errcode='22023';
  end if;
  if p_group_id is not null and not public.is_group_member(p_group_id) then
    raise exception 'Group membership required' using errcode='42501';
  end if;
  if char_length(v_prompt) > 120 then raise exception 'Title too long' using errcode='22023'; end if;

  select coalesce(array_agg(t order by first_pos), '{}'::text[]) into v_tags
    from (
      select lower(btrim(x)) as t, min(ord) as first_pos
        from unnest(coalesce(p_tags, '{}'::text[])) with ordinality as u(x, ord)
       where btrim(x) <> ''
       group by lower(btrim(x))
    ) s;
  if cardinality(v_tags) > 8 or exists (select 1 from unnest(v_tags) t where char_length(t) > 30) then
    raise exception 'Invalid tags' using errcode='22023';
  end if;

  insert into public.fit_checks(id,creator_id,caption,occasion,tags,vote_prompt,status,audience,group_id)
  values(p_id,auth.uid(),nullif(btrim(p_caption),''),nullif(btrim(p_occasion),''),v_tags,v_prompt,'draft',v_audience,p_group_id)
  on conflict(id) do nothing;

  select * into f from public.fit_checks where id = p_id for update;
  if f.creator_id is distinct from auth.uid() or f.status <> 'draft'
     or f.group_id is distinct from p_group_id
     or f.audience is distinct from v_audience
     or f.caption is distinct from nullif(btrim(p_caption),'')
     or f.occasion is distinct from nullif(btrim(p_occasion),'')
     or f.tags is distinct from v_tags
     or f.vote_prompt is distinct from v_prompt then
    raise exception 'Draft request conflicts with an existing post' using errcode='22023';
  end if;
  return f.id;
end; $$;

revoke all on function public.create_fit_check_draft(uuid, text, uuid, text, text[], text, text) from public, anon;
grant execute on function public.create_fit_check_draft(uuid, text, uuid, text, text[], text, text) to authenticated, service_role;
