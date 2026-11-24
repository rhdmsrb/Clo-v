-- Wardrobe insights: an optional purchase price (US dollars) per piece, used
-- for wardrobe value, average price and cost per wear. Additive only.
alter table public.wardrobe_items
  add column if not exists price numeric(10, 2)
    constraint wardrobe_items_price_non_negative check (price is null or price >= 0);
