-- Restore the feed JSON shape from the 2026-11-03 schema snapshot.

-- Refuse to overwrite a feed RPC that differs from both known definitions.
-- Review the live definition and prepare a compatible migration first.
do $guard$
declare current_body text;
begin
  select p.prosrc into current_body from pg_catalog.pg_proc p
   where p.oid = pg_catalog.to_regprocedure('public.fetch_feed_page(uuid,text,integer,integer)');
  if current_body is null or (current_body <> $old$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_sort is null or p_sort not in ('newest','votes') or p_offset is null or p_offset<0 or p_offset>10000 or p_limit is null or p_limit not between 1 and 24 then raise exception 'Invalid feed page' using errcode='22023'; end if;
 return query
 with page as materialized (
 select f.* from public.fit_checks f
 where f.status='live' and (f.expires_at is null or f.expires_at>now())
 and ((p_group_id is null and f.is_public) or (p_group_id is not null and f.group_id=p_group_id))
 order by case when p_sort='votes' then f.vote_count end desc, f.created_at desc,f.id desc
 limit p_limit offset p_offset)
 select jsonb_build_object(
 'id',f.id,'creator_id',f.creator_id,'caption',f.caption,'created_at',f.created_at,'expires_at',f.expires_at,
 'vote_count',f.vote_count,'comment_count',f.comment_count,
 'my_vote',(select v.photo_id from public.fit_check_votes v where v.fit_check_id=f.id and v.voter_id=auth.uid()),
 'photo_vote_counts',coalesce((select jsonb_agg(jsonb_build_object('photo_id',v.photo_id,'count',v.n)) from
 (select photo_id,count(*) as n from public.fit_check_votes where fit_check_id=f.id group by photo_id) v),'[]'::jsonb),
 'fit_check_photos',coalesce((select jsonb_agg(to_jsonb(p) order by p.position) from public.fit_check_photos p where p.fit_check_id=f.id),'[]'::jsonb),
 'profiles',(select jsonb_build_object('nickname',p.nickname,'avatar_url',p.avatar_url) from public.profiles p where p.id=f.creator_id))
 from page f
 order by case when p_sort='votes' then f.vote_count end desc,f.created_at desc,f.id desc;
end; $old$ and current_body <> $new$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_sort is null or p_sort not in ('newest','votes') or p_offset is null or p_offset<0 or p_offset>10000 or p_limit is null or p_limit not between 1 and 24 then raise exception 'Invalid feed page' using errcode='22023'; end if;
 return query
 with page as materialized (
 select f.* from public.fit_checks f
 where f.status='live' and (f.expires_at is null or f.expires_at>now())
 and ((p_group_id is null and f.is_public) or (p_group_id is not null and f.group_id=p_group_id))
 order by case when p_sort='votes' then f.vote_count end desc, f.created_at desc,f.id desc
 limit p_limit offset p_offset)
 select jsonb_build_object(
 'id',f.id,'creator_id',f.creator_id,'caption',f.caption,'created_at',f.created_at,'expires_at',f.expires_at,
 'vote_count',f.vote_count,'comment_count',f.comment_count,
 'tags',f.tags,'vote_prompt',f.vote_prompt,'like_count',f.like_count,
 'my_vote',(select v.photo_id from public.fit_check_votes v where v.fit_check_id=f.id and v.voter_id=auth.uid()),
 'photo_vote_counts',coalesce((select jsonb_agg(jsonb_build_object('photo_id',v.photo_id,'count',v.n)) from
 (select photo_id,count(*) as n from public.fit_check_votes where fit_check_id=f.id group by photo_id) v),'[]'::jsonb),
 'fit_check_photos',coalesce((select jsonb_agg(to_jsonb(p) order by p.position) from public.fit_check_photos p where p.fit_check_id=f.id),'[]'::jsonb),
 'profiles',(select jsonb_build_object('nickname',p.nickname,'avatar_url',p.avatar_url) from public.profiles p where p.id=f.creator_id))
 from page f
 order by case when p_sort='votes' then f.vote_count end desc,f.created_at desc,f.id desc;
end; $new$) then
    raise exception 'fetch_feed_page differs from the reviewed snapshot; aborting to preserve the existing RPC';
  end if;
end
$guard$;

CREATE OR REPLACE FUNCTION "public"."fetch_feed_page"("p_group_id" "uuid" DEFAULT NULL::"uuid", "p_sort" "text" DEFAULT 'newest'::"text", "p_offset" integer DEFAULT 0, "p_limit" integer DEFAULT 12) RETURNS SETOF "jsonb"
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $$
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_sort is null or p_sort not in ('newest','votes') or p_offset is null or p_offset<0 or p_offset>10000 or p_limit is null or p_limit not between 1 and 24 then raise exception 'Invalid feed page' using errcode='22023'; end if;
 return query
 with page as materialized (
 select f.* from public.fit_checks f
 where f.status='live' and (f.expires_at is null or f.expires_at>now())
 and ((p_group_id is null and f.is_public) or (p_group_id is not null and f.group_id=p_group_id))
 order by case when p_sort='votes' then f.vote_count end desc, f.created_at desc,f.id desc
 limit p_limit offset p_offset)
 select jsonb_build_object(
 'id',f.id,'creator_id',f.creator_id,'caption',f.caption,'created_at',f.created_at,'expires_at',f.expires_at,
 'vote_count',f.vote_count,'comment_count',f.comment_count,
 'my_vote',(select v.photo_id from public.fit_check_votes v where v.fit_check_id=f.id and v.voter_id=auth.uid()),
 'photo_vote_counts',coalesce((select jsonb_agg(jsonb_build_object('photo_id',v.photo_id,'count',v.n)) from
 (select photo_id,count(*) as n from public.fit_check_votes where fit_check_id=f.id group by photo_id) v),'[]'::jsonb),
 'fit_check_photos',coalesce((select jsonb_agg(to_jsonb(p) order by p.position) from public.fit_check_photos p where p.fit_check_id=f.id),'[]'::jsonb),
 'profiles',(select jsonb_build_object('nickname',p.nickname,'avatar_url',p.avatar_url) from public.profiles p where p.id=f.creator_id))
 from page f
 order by case when p_sort='votes' then f.vote_count end desc,f.created_at desc,f.id desc;
end; $$;
