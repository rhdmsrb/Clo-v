begin;

alter table public.fit_checks add column draft_cleanup_claimed boolean not null default false;

-- A cleanup claim and publish both acquire the Fit-Check row lock. Once
-- claimed, a draft cannot be published even by an older app build.
create function public.prevent_claimed_draft_publication()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if old.draft_cleanup_claimed and new.status <> 'draft' then
        raise exception 'This draft was abandoned. Start a new Fit-Check.' using errcode = '55000';
    end if;
    if old.draft_cleanup_claimed and not new.draft_cleanup_claimed then
        raise exception 'This draft is being cleaned up.' using errcode = '55000';
    end if;
    return new;
end;
$$;

create trigger prevent_claimed_draft_publication
before update of status, draft_cleanup_claimed on public.fit_checks
for each row execute function public.prevent_claimed_draft_publication();

-- With no id, atomically claim up to 20 stale or previously abandoned drafts.
-- An explicit id supports immediate cleanup after the owner abandons a post.
create function public.claim_fit_check_drafts_for_cleanup_v1(p_id uuid default null)
returns table (id uuid)
language sql volatile security definer
set search_path = ''
as $$
    with candidates as (
        select f.id
        from public.fit_checks f
        where f.creator_id = (select auth.uid()) and f.status = 'draft'
          and (
              (p_id is not null and f.id = p_id)
              or (p_id is null and (f.draft_cleanup_claimed or f.created_at <= now() - interval '1 hour'))
          )
        order by f.created_at, f.id
        limit 20
        for update skip locked
    )
    update public.fit_checks f
    set draft_cleanup_claimed = true
    from candidates c
    where f.id = c.id
    returning f.id;
$$;

revoke all on function public.claim_fit_check_drafts_for_cleanup_v1(uuid) from public, anon;
grant execute on function public.claim_fit_check_drafts_for_cleanup_v1(uuid) to authenticated;
revoke all on function public.prevent_claimed_draft_publication() from public, anon, authenticated;

commit;
