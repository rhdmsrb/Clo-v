-- Rolls back 20261108000100_fit_check_audience.sql.
-- Friends/private posts keep is_public = false and group_id null, so after the old
-- policy returns they are visible to their creator only (never public).

drop trigger if exists fit_checks_sync_audience on public.fit_checks;

drop policy if exists "fit_checks: read (published audience or owner)" on public.fit_checks;
create policy "fit_checks: read (published audience or owner)" on public.fit_checks
  for select to authenticated
  using (creator_id = auth.uid()
         or (status <> 'draft' and not public.is_blocked_pair(creator_id)
             and (is_public or (group_id is not null and public.is_group_member(group_id)))));

create or replace function public.validate_fit_check_activity()
returns trigger language plpgsql security definer set search_path = '' as $$
declare f public.fit_checks;
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  select * into f from public.fit_checks where id=new.fit_check_id for update;
  if not (f.is_public or f.creator_id=auth.uid() or public.is_group_member(f.group_id)) then raise exception 'Post unavailable' using errcode='42501'; end if;
  if f.id is null or f.status<>'live' or f.expires_at<=now() then raise exception 'Fit-Check is not live' using errcode='23514'; end if;
  if new.photo_id is not null and not exists(select 1 from public.fit_check_photos p where p.id=new.photo_id and p.fit_check_id=new.fit_check_id) then
    raise exception 'Photo does not belong to this Fit-Check' using errcode='23514';
  end if;
  return new;
end; $$;

create or replace function public.get_live_vote_tally(p_fit_check_id uuid)
returns table (photo_id uuid, vote_count integer, is_mine boolean)
language sql stable security definer set search_path = '' as $$
  select v.photo_id, count(*)::integer, bool_or(v.voter_id = auth.uid())
    from public.fit_check_votes v
    join public.fit_checks f on f.id = v.fit_check_id
   where v.fit_check_id = p_fit_check_id and auth.uid() is not null and f.status <> 'draft'
     and (f.creator_id = auth.uid()
          or (not public.is_blocked_pair(f.creator_id)
              and (f.is_public or (f.group_id is not null and public.is_group_member(f.group_id)))
              and exists (select 1 from public.fit_check_votes mine
                           where mine.fit_check_id = p_fit_check_id and mine.voter_id = auth.uid())))
   group by v.photo_id;
$$;

create or replace function public.get_fit_check_results(p_fit_check_id uuid)
returns table (photo_id uuid, vote_count integer, is_mine boolean)
language sql stable security definer set search_path = '' as $$
  select v.photo_id, count(*)::integer, bool_or(v.voter_id = auth.uid())
    from public.fit_check_votes v
    join public.fit_checks f on f.id = v.fit_check_id
   where v.fit_check_id = p_fit_check_id and auth.uid() is not null and f.status <> 'draft'
     and (f.status <> 'live' or f.expires_at <= now())
     and (f.creator_id = auth.uid()
          or (not public.is_blocked_pair(f.creator_id)
              and (f.is_public or (f.group_id is not null and public.is_group_member(f.group_id)))))
   group by v.photo_id;
$$;

drop function if exists public.create_fit_check_draft(uuid, text, uuid, text, text[], text, text);
create or replace function public.create_fit_check_draft(
  p_id uuid, p_caption text default null, p_group_id uuid default null,
  p_occasion text default null, p_tags text[] default null, p_vote_prompt text default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare f public.fit_checks; v_tags text[]; v_prompt text := nullif(btrim(p_vote_prompt), '');
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_group_id is not null and not public.is_group_member(p_group_id) then
    raise exception 'Group membership required' using errcode='42501'; end if;
  if char_length(v_prompt) > 120 then raise exception 'Title too long' using errcode='22023'; end if;
  select coalesce(array_agg(t order by first_pos), '{}'::text[]) into v_tags from (
    select lower(btrim(x)) as t, min(ord) as first_pos
      from unnest(coalesce(p_tags, '{}'::text[])) with ordinality as u(x, ord)
     where btrim(x) <> '' group by lower(btrim(x))) s;
  if cardinality(v_tags) > 8 or exists (select 1 from unnest(v_tags) t where char_length(t) > 30) then
    raise exception 'Invalid tags' using errcode='22023'; end if;
  insert into public.fit_checks(id,creator_id,caption,occasion,tags,vote_prompt,status,is_public,group_id)
  values(p_id,auth.uid(),nullif(btrim(p_caption),''),nullif(btrim(p_occasion),''),v_tags,v_prompt,'draft',p_group_id is null,p_group_id)
  on conflict(id) do nothing;
  select * into f from public.fit_checks where id=p_id for update;
  if f.creator_id is distinct from auth.uid() or f.status<>'draft' or f.group_id is distinct from p_group_id
     or f.caption is distinct from nullif(btrim(p_caption),'') or f.occasion is distinct from nullif(btrim(p_occasion),'')
     or f.tags is distinct from v_tags or f.vote_prompt is distinct from v_prompt then
    raise exception 'Draft request conflicts with an existing post' using errcode='22023'; end if;
  return f.id;
end; $$;
revoke all on function public.create_fit_check_draft(uuid, text, uuid, text, text[], text) from public, anon;
grant execute on function public.create_fit_check_draft(uuid, text, uuid, text, text[], text) to authenticated, service_role;

drop function if exists public.sync_fit_check_audience();
drop function if exists public.can_view_audience(uuid, text, uuid);
drop function if exists public.is_friend_of(uuid);
alter table public.fit_checks drop constraint if exists fit_checks_audience_check;
alter table public.fit_checks drop column if exists audience;
