-- Comments from a blocked user (in either direction) must not be readable
-- through the API; until now only the client filtered them. is_blocked_pair
-- is SECURITY DEFINER with an empty search_path and false for the caller's
-- own id, so a user always sees their own comments.
alter policy "fit_check_comments: read (parent visible)" on public.fit_check_comments
    using (
        exists (select 1 from public.fit_checks f where f.id = fit_check_comments.fit_check_id)
        and not public.is_blocked_pair(commenter_id)
    );
