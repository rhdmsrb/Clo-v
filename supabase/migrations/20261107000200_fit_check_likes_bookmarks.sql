-- Likes and bookmarks on Fit-Checks.
--
-- Account deletion: delete_my_account() deletes public.profiles, and both new
-- tables reference profiles(id) and fit_checks(id) with ON DELETE CASCADE, so a
-- deleted user's likes/bookmarks (and anyone's on a deleted post) go with them
-- with no change to delete_my_account().
--
-- RLS: writes are the current user only. Likes are readable where the parent
-- post is visible (the subquery on fit_checks is subject to its own RLS, which
-- already enforces draft/audience/is_blocked_pair/is_group_member) and the liker
-- is not in a block pair with the reader. Bookmarks are readable by the owner only.
--
-- Rollback: supabase/rollback/20261107000200_fit_check_likes_bookmarks.sql

create table if not exists public.fit_check_likes (
  fit_check_id uuid not null references public.fit_checks(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (fit_check_id, user_id)
);
create index if not exists fit_check_likes_user_idx on public.fit_check_likes (user_id, created_at desc);

create table if not exists public.fit_check_bookmarks (
  fit_check_id uuid not null references public.fit_checks(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (fit_check_id, user_id)
);
create index if not exists fit_check_bookmarks_user_idx on public.fit_check_bookmarks (user_id, created_at desc);

alter table public.fit_check_likes enable row level security;
alter table public.fit_check_bookmarks enable row level security;

revoke all on public.fit_check_likes, public.fit_check_bookmarks from anon, authenticated;
grant select, insert, delete on public.fit_check_likes to authenticated;
grant select, insert, delete on public.fit_check_bookmarks to authenticated;
grant all on public.fit_check_likes, public.fit_check_bookmarks to service_role;

-- Likes
drop policy if exists "fit_check_likes: read (parent visible)" on public.fit_check_likes;
create policy "fit_check_likes: read (parent visible)" on public.fit_check_likes
  for select to authenticated
  using (
    exists (select 1 from public.fit_checks f where f.id = fit_check_likes.fit_check_id)
    and (user_id = (select auth.uid()) or not public.is_blocked_pair(user_id))
  );

drop policy if exists "fit_check_likes: insert own" on public.fit_check_likes;
create policy "fit_check_likes: insert own" on public.fit_check_likes
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.fit_checks f
      where f.id = fit_check_likes.fit_check_id and f.status <> 'draft'
    )
  );

drop policy if exists "fit_check_likes: delete own" on public.fit_check_likes;
create policy "fit_check_likes: delete own" on public.fit_check_likes
  for delete to authenticated using (user_id = (select auth.uid()));

-- Bookmarks (private to the owner)
drop policy if exists "fit_check_bookmarks: read own" on public.fit_check_bookmarks;
create policy "fit_check_bookmarks: read own" on public.fit_check_bookmarks
  for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists "fit_check_bookmarks: insert own" on public.fit_check_bookmarks;
create policy "fit_check_bookmarks: insert own" on public.fit_check_bookmarks
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (
      select 1 from public.fit_checks f
      where f.id = fit_check_bookmarks.fit_check_id and f.status <> 'draft'
    )
  );

drop policy if exists "fit_check_bookmarks: delete own" on public.fit_check_bookmarks;
create policy "fit_check_bookmarks: delete own" on public.fit_check_bookmarks
  for delete to authenticated using (user_id = (select auth.uid()));

-- like_count maintenance, mirroring bump_vote_count.
create or replace function public.bump_like_count()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.fit_checks set like_count = like_count + 1 where id = new.fit_check_id;
    return new;
  elsif tg_op = 'DELETE' then
    -- Parent cascade deletes the post first, so this may match no row.
    update public.fit_checks set like_count = greatest(like_count - 1, 0) where id = old.fit_check_id;
    return old;
  end if;
  return null;
end;
$$;

revoke all on function public.bump_like_count() from public, anon, authenticated;

drop trigger if exists trg_bump_like_count_insert on public.fit_check_likes;
create trigger trg_bump_like_count_insert after insert on public.fit_check_likes
  for each row execute function public.bump_like_count();
drop trigger if exists trg_bump_like_count_delete on public.fit_check_likes;
create trigger trg_bump_like_count_delete after delete on public.fit_check_likes
  for each row execute function public.bump_like_count();
