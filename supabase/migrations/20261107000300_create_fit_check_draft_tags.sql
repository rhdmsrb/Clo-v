-- create_fit_check_draft gains optional p_tags (post-level tags) and p_vote_prompt
-- (the wizard Title, trimmed, max 120 chars).
--
-- The 3-arg and 4-arg overloads are replaced by one function whose new params all
-- have defaults, so existing named-argument calls from older app builds
-- (p_id, p_caption, p_group_id, p_occasion) still resolve. Keeping separate
-- overloads would make those calls ambiguous.
--
-- Per-photo description/tags need no RPC change: the client inserts them with the
-- photo row (fit_check_photos INSERT is already allowed on the owner's draft, and
-- the column CHECKs from 20261107000100 enforce limits). publish_fit_check is
-- unchanged.
--
-- Rollback: supabase/rollback/20261107000300_create_fit_check_draft_tags.sql

drop function if exists public.create_fit_check_draft(uuid, text, uuid);
drop function if exists public.create_fit_check_draft(uuid, text, uuid, text);
-- Also drop the 5-arg form in case an earlier draft of this migration was applied;
-- any leftover overload makes named-arg calls ambiguous (PostgREST PGRST203).
drop function if exists public.create_fit_check_draft(uuid, text, uuid, text, text[]);

create or replace function public.create_fit_check_draft(
  p_id uuid,
  p_caption text default null,
  p_group_id uuid default null,
  p_occasion text default null,
  p_tags text[] default null,
  p_vote_prompt text default null
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  f public.fit_checks;
  v_tags text[];
  v_prompt text := nullif(btrim(p_vote_prompt), '');
begin
  if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
  if p_group_id is not null and not public.is_group_member(p_group_id) then
    raise exception 'Group membership required' using errcode='42501';
  end if;

  if char_length(v_prompt) > 120 then raise exception 'Title too long' using errcode='22023'; end if;

  -- Normalise: trim, lowercase, drop empties/duplicates, cap at 8 tags of <=30 chars.
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

  insert into public.fit_checks(id,creator_id,caption,occasion,tags,vote_prompt,status,is_public,group_id)
  values(p_id,auth.uid(),nullif(btrim(p_caption),''),nullif(btrim(p_occasion),''),v_tags,v_prompt,'draft',p_group_id is null,p_group_id)
  on conflict(id) do nothing;

  select * into f from public.fit_checks where id=p_id for update;
  if f.creator_id is distinct from auth.uid() or f.status<>'draft'
     or f.group_id is distinct from p_group_id
     or f.caption is distinct from nullif(btrim(p_caption),'')
     or f.occasion is distinct from nullif(btrim(p_occasion),'')
     or f.tags is distinct from v_tags
     or f.vote_prompt is distinct from v_prompt then
    raise exception 'Draft request conflicts with an existing post' using errcode='22023';
  end if;
  return f.id;
end; $$;

revoke all on function public.create_fit_check_draft(uuid, text, uuid, text, text[], text) from public, anon;
grant execute on function public.create_fit_check_draft(uuid, text, uuid, text, text[], text) to authenticated, service_role;
