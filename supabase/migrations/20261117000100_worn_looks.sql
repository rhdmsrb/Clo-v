begin;
create table public.fit_check_worn_looks (
  fit_check_id uuid primary key references public.fit_checks(id) on delete cascade,
  photo_id uuid not null references public.fit_check_photos(id) on delete cascade
);
alter table public.fit_check_worn_looks enable row level security;
revoke all on public.fit_check_worn_looks from public, anon, authenticated;
grant select, insert, update on public.fit_check_worn_looks to authenticated;
create policy visible on public.fit_check_worn_looks for select to authenticated using
  (exists (select 1 from public.fit_checks f where f.id = fit_check_id));
create policy creator_choice on public.fit_check_worn_looks for all to authenticated using
  (exists (select 1 from public.fit_checks f where f.id = fit_check_id and f.creator_id = auth.uid()))
with check (exists (
  select 1 from public.fit_checks f join public.fit_check_photos p on p.fit_check_id = f.id
  where f.id = fit_check_worn_looks.fit_check_id and p.id = fit_check_worn_looks.photo_id
    and f.creator_id = auth.uid() and (f.status = 'archived' or (f.status = 'live' and f.expires_at <= now()))
));
commit;
