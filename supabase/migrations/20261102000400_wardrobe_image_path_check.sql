-- Defense in depth for the try-on function: a wardrobe photo path must live in
-- the owner's own storage folder ("<ownerId>/<itemId>/<file>.jpg"). NOT VALID
-- skips the existing rows (the live table was checked: all rows comply) but
-- enforces the rule on every new insert and update.
alter table public.wardrobe_items
    drop constraint if exists wardrobe_items_image_url_owner_prefix;
alter table public.wardrobe_items
    add constraint wardrobe_items_image_url_owner_prefix
    check (
        image_url like owner_id::text || '/%'
        and image_url not like '%..%'
        and image_url not like '%://%'
    ) not valid;
