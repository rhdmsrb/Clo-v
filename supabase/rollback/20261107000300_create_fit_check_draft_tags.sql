-- ROLLBACK ORDER: 400, 300, 200, 100. Run this before rolling back 100 (the new
-- function references fit_checks.tags and vote_prompt).
--
-- Restores the 4-arg overload. The 3-arg overload is not restored; no client calls it.
drop function if exists public.create_fit_check_draft(uuid, text, uuid, text, text[], text);
drop function if exists public.create_fit_check_draft(uuid, text, uuid, text, text[]);

create or replace function public.create_fit_check_draft(
  p_id uuid, p_caption text default null, p_group_id uuid default null, p_occasion text default null
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare f public.fit_checks;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_group_id is not null and not public.is_group_member(p_group_id) then raise exception 'Group membership required' using errcode='42501'; end if;
 insert into public.fit_checks(id,creator_id,caption,occasion,status,is_public,group_id) values(p_id,auth.uid(),nullif(btrim(p_caption),''),nullif(btrim(p_occasion),''),'draft',p_group_id is null,p_group_id) on conflict(id) do nothing;
 select * into f from public.fit_checks where id=p_id for update;
 if f.creator_id is distinct from auth.uid() or f.status<>'draft' or f.group_id is distinct from p_group_id or f.caption is distinct from nullif(btrim(p_caption),'') or f.occasion is distinct from nullif(btrim(p_occasion),'') then raise exception 'Draft request conflicts with an existing post' using errcode='22023'; end if;
 return f.id;
end; $$;
revoke all on function public.create_fit_check_draft(uuid, text, uuid, text) from public, anon;
grant execute on function public.create_fit_check_draft(uuid, text, uuid, text) to authenticated, service_role;
