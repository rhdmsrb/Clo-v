-- Curated clothing catalog: vetted stock pieces any signed-in user can browse
-- and add to their wardrobe. Read-only for clients; rows and images are loaded
-- by an admin or the seed script with the service role (which bypasses RLS).

create table if not exists public.catalog_items (
  id           uuid primary key default gen_random_uuid(),
  name         text not null check (char_length(name) between 1 and 80),
  category     text not null check (category in
                 ('top','bottom','dress','outerwear','shoes','accessory','set','other')),
  subcategory  text check (subcategory is null or char_length(subcategory) <= 40),
  color        text check (color is null or char_length(color) <= 30),
  season       text check (season is null or season in ('spring','summer','fall','winter','all')),
  brand        text check (brand is null or char_length(brand) <= 60),
  tags         text[] not null default '{}' check (cardinality(tags) <= 12),
  -- Path inside the private `catalog-items` bucket, e.g. 'top/linen-shirt.jpg'.
  image_path   text not null
               check (image_path ~ '^[A-Za-z0-9_-][A-Za-z0-9_/.-]*\.(jpg|jpeg|png|webp)$'
                      and image_path not like '%..%'),
  -- Attribution for openly licensed photos; shown in the app and kept when saved.
  creator      text,
  license      text,
  license_url  text check (license_url is null or license_url ~ '^https://'),
  source_url   text check (source_url is null or source_url ~ '^https://'),
  sort_order   integer not null default 0,
  is_active    boolean not null default true,
  created_at   timestamptz not null default now()
);

create index if not exists catalog_items_browse_idx
  on public.catalog_items (category, sort_order, created_at desc) where is_active;

alter table public.catalog_items enable row level security;

drop policy if exists "catalog_items: read active" on public.catalog_items;
create policy "catalog_items: read active" on public.catalog_items
  for select to authenticated using (is_active);

revoke all on public.catalog_items from public, anon, authenticated;
grant select on public.catalog_items to authenticated;

-- Private bucket; signed URLs are issued to signed-in users only.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('catalog-items', 'catalog-items', false, 10485760,
        array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

drop policy if exists "catalog-items: authenticated read" on storage.objects;
create policy "catalog-items: authenticated read" on storage.objects
  for select to authenticated using (bucket_id = 'catalog-items');
