-- Close live security and integrity gaps identified in the production SQL review.
-- Safe to rerun; existing profile data was checked before adding validated checks.

-- Profiles are readable by every signed-in user, so clients may only edit fields
-- the app actually uses. Prevent account-code changes and external avatar URLs.
revoke update on public.profiles from anon, authenticated;
grant update (nickname, avatar_url, style_preferences) on public.profiles to authenticated;

alter table public.profiles
  drop constraint if exists profiles_nickname_format;
alter table public.profiles
  add constraint profiles_nickname_format
  check (char_length(nickname) between 2 and 30 and nickname !~ '[[:cntrl:]]');

alter table public.profiles
  drop constraint if exists profiles_avatar_url_own_folder;
alter table public.profiles
  add constraint profiles_avatar_url_own_folder
  check (
    avatar_url is null
    or avatar_url ~ (
      '^https://exbozksjwpyvstqhcyqy\.supabase\.co/storage/v1/object/public/avatars/'
      || id::text || '/[A-Za-z0-9._-]+$'
    )
  );

-- Serialize registrations per account so simultaneous inserts cannot pass the
-- cap check against the same snapshot and leave more than 20 device tokens.
create or replace function public.device_tokens_enforce_cap()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.user_id::text, 0)
  );

  delete from public.device_tokens
   where token in (
     select token
       from public.device_tokens
      where user_id = new.user_id
        and token <> new.token
      order by updated_at desc, token
      offset 19
   );
  return new;
end;
$$;

-- Store only the six vote-reason tags offered by the app, with a hard maximum
-- of six entries. The text-array input is otherwise directly client-controlled.
create or replace function public.save_vote_reason(
  p_fit_check_id uuid,
  p_photo_id uuid,
  p_reason_tags text[] default '{}'::text[],
  p_reason_comment text default null::text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tags text[] := coalesce(p_reason_tags, '{}'::text[]);
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if cardinality(v_tags) > 6
     or array_ndims(v_tags) > 1
     or exists (
       select 1
         from unnest(v_tags) as tag(value)
        where value is null
           or value not in (
             'Love the colors',
             'Comfy',
             'Fits the occasion',
             'Great layers',
             'Shoes work',
             'Feels like you'
           )
     ) then
    raise exception 'Invalid vote reason tags' using errcode = '22023';
  end if;

  update public.fit_check_votes
     set reason_tags = v_tags,
         reason_comment = nullif(left(btrim(coalesce(p_reason_comment, '')), 280), '')
   where fit_check_id = p_fit_check_id
     and photo_id = p_photo_id
     and voter_id = auth.uid();
  if not found then
    raise exception 'Vote not found' using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.save_vote_reason(uuid, uuid, text[], text) from public, anon;
grant execute on function public.save_vote_reason(uuid, uuid, text[], text) to authenticated;

-- The client uses send/respond/cancel RPCs; direct writes bypass their checks.
drop policy if exists "fr_insert" on public.friend_requests;
revoke insert, update, delete on public.friend_requests from anon, authenticated;

-- Retraction cleanup filters by these columns for vote notifications.
create index if not exists notifications_vote_cleanup_idx
  on public.notifications (fit_check_id, actor_id)
  where type = 'vote';
