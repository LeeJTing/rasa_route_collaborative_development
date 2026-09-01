-- Composite Nasi Lemak menu rows were imported against their side dish
-- (for example Sambal Sotong) instead of the principal local food. Quick Mode
-- applies dietary restrictions through restaurant_item.local_food_id, so those
-- incorrect foreign keys bypassed Nasi Lemak's No Coconut relationship.
--
-- This is an idempotent data correction. Runtime code continues to rely only
-- on the ERD relationship and contains no food-name exception.
with nasi_lemak as (
  select local_food_id
  from public.local_food
  where lower(btrim(food_name)) = 'nasi lemak'
)
update public.restaurant_item as item
set local_food_id = nasi_lemak.local_food_id
from nasi_lemak
where lower(item.restaurant_item_name) like '%nasi lemak%'
  and item.local_food_id is distinct from nasi_lemak.local_food_id;
