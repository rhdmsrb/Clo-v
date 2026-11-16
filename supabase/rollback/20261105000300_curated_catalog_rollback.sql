-- Deletes catalog rows. Remove the bucket's files first (Storage API), then:
drop policy if exists "catalog-items: authenticated read" on storage.objects;
drop table if exists public.catalog_items;
-- delete from storage.buckets where id = 'catalog-items';  -- only after it is empty
