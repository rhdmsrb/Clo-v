-- "Wore it today": per-piece wear count and last-worn time, updated atomically
-- through an RPC so concurrent taps don't lose increments.
alter table public.wardrobe_items
  add column if not exists wear_count integer not null default 0,
  add column if not exists last_worn_at timestamptz;

create or replace function public.log_wardrobe_wear(p_item_id uuid)
returns public.wardrobe_items
language sql
security invoker
set search_path = public
as $$
  -- security invoker: RLS still limits this to rows the caller owns; the
  -- owner_id check makes that explicit for readers of this function.
  update public.wardrobe_items
     set wear_count = wear_count + 1,
         last_worn_at = now()
   where id = p_item_id
     and owner_id = auth.uid()
  returning *;
$$;

revoke all on function public.log_wardrobe_wear(uuid) from public, anon;
grant execute on function public.log_wardrobe_wear(uuid) to authenticated;
