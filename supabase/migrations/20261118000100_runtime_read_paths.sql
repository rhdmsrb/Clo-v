begin;

create index if not exists fit_checks_home_live_newest_idx
    on public.fit_checks (created_at desc, id desc)
    where status = 'live' and audience in ('public', 'friends');

-- RLS on the source tables protects posts, comments, profiles and votes.
-- Use the same sort key for the index, the page order and the continuation.
create function public.home_feed_page_v1(
    p_limit integer,
    p_before_created_at timestamptz default null,
    p_before_id uuid default null
)
returns setof jsonb
language sql stable security invoker
set search_path = ''
as $$
    with page as materialized (
        select f.*
        from public.fit_checks f
        where f.status = 'live'
          and f.audience in ('public', 'friends')
          and (f.audience = 'public' or f.creator_id <> (select auth.uid()))
          and (f.expires_at is null or f.expires_at > now())
          and (f.created_at, f.id) < (
              coalesce(p_before_created_at, 'infinity'::timestamptz),
              coalesce(p_before_id, 'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)
          )
        order by f.created_at desc, f.id desc
        limit least(greatest(coalesce(p_limit, 24), 1), 50)
    ),
    recent_events as materialized (
        select e.fit_check_id, e.event
        from public.feed_events e
        where e.user_id = (select auth.uid())
        order by e.created_at desc, e.id desc
        limit 500
    ),
    scores as (
        select e.fit_check_id, sum(case e.event
            when 'impression' then -1 when 'open_detail' then 3 when 'vote' then 6
            when 'save' then 4 when 'share' then 5 when 'follow' then 2
            when 'unfollow' then -2 when 'not_interested' then -8 else 0 end) as score
        from recent_events e join page p on p.id = e.fit_check_id
        group by e.fit_check_id
    )
    select jsonb_build_object(
        'cursor_created_at', to_char(p.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
        'viewer_follows', exists (
            select 1 from public.profile_follows f
            where f.follower_id = (select auth.uid()) and f.following_id = p.creator_id
        ),
        'viewer_liked', exists (
            select 1 from public.fit_check_likes l
            where l.fit_check_id = p.id and l.user_id = (select auth.uid())
        ),
        'signal_score', coalesce(s.score, 0),
        'item', jsonb_build_object(
            'id', p.id, 'creator_id', p.creator_id, 'caption', p.caption,
            'occasion', p.occasion, 'audience', p.audience, 'is_public', p.is_public,
            'vote_prompt', p.vote_prompt, 'tags', p.tags, 'like_count', p.like_count,
            'vote_count', p.vote_count, 'created_at', p.created_at, 'expires_at', p.expires_at,
            'visible_comment_count', (
                select count(*) from public.fit_check_comments c where c.fit_check_id = p.id
            ),
            'profiles', (
                select jsonb_build_object('nickname', a.nickname, 'avatar_url', a.avatar_url, 'account_code', a.account_code)
                from public.profiles a where a.id = p.creator_id
            ),
            'fit_check_photos', coalesce((
                select jsonb_agg(jsonb_build_object(
                    'id', ph.id, 'fit_check_id', ph.fit_check_id, 'image_url', ph.image_url,
                    'position', ph.position, 'description', ph.description, 'tags', ph.tags
                ) order by ph.position, ph.id)
                from public.fit_check_photos ph where ph.fit_check_id = p.id
            ), '[]'::jsonb),
            'fit_check_votes', coalesce((
                select jsonb_agg(jsonb_build_object('photo_id', v.photo_id, 'voter_id', v.voter_id))
                from public.fit_check_votes v
                where v.fit_check_id = p.id and v.voter_id = (select auth.uid())
            ), '[]'::jsonb)
        )
    )
    from page p
    left join scores s on s.fit_check_id = p.id
    order by p.created_at desc, p.id desc;
$$;

-- Only summarize groups the caller is still a member of. Each card has at
-- most four avatars and one photo from each of the three newest live posts.
create function public.group_card_previews_v1(p_group_ids uuid[])
returns table (group_id uuid, member_count bigint, live_count bigint, members jsonb, photo_paths jsonb)
language sql stable security invoker
set search_path = ''
as $$
    select mine.group_id,
        (select count(*) from public.group_members m where m.group_id = mine.group_id),
        (select count(*) from public.fit_checks f
         where f.group_id = mine.group_id and f.status = 'live'
           and (f.expires_at is null or f.expires_at > now())),
        coalesce((
            select jsonb_agg(jsonb_build_object('profile_id', m.profile_id, 'profiles',
                jsonb_build_object('nickname', a.nickname, 'avatar_url', a.avatar_url))
                order by m.profile_id)
            from (
                select gm.profile_id from public.group_members gm
                where gm.group_id = mine.group_id order by gm.profile_id limit 4
            ) m
            left join public.profiles a on a.id = m.profile_id
        ), '[]'::jsonb),
        coalesce((
            select jsonb_agg(ph.image_url order by f.created_at desc, f.id desc)
            from (
                select fc.id, fc.created_at from public.fit_checks fc
                where fc.group_id = mine.group_id and fc.status = 'live'
                  and (fc.expires_at is null or fc.expires_at > now())
                order by fc.created_at desc, fc.id desc limit 3
            ) f
            cross join lateral (
                select p.image_url from public.fit_check_photos p
                where p.fit_check_id = f.id order by p.position, p.id limit 1
            ) ph
        ), '[]'::jsonb)
    from public.group_members mine
    where mine.profile_id = (select auth.uid())
      and mine.group_id = any(p_group_ids)
    order by mine.group_id
    limit 32;
$$;

revoke all on function public.home_feed_page_v1(integer, timestamptz, uuid) from public, anon;
revoke all on function public.group_card_previews_v1(uuid[]) from public, anon;
grant execute on function public.home_feed_page_v1(integer, timestamptz, uuid) to authenticated;
grant execute on function public.group_card_previews_v1(uuid[]) to authenticated;

commit;
