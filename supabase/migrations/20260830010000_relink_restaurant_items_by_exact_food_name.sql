-- Repair imported restaurant_item.local_food_id values only when the menu
-- item contains one unique, complete local-food catalogue name. Ambiguous
-- combo items are intentionally left unchanged so the client can use its
-- neutral image fallback instead of displaying an unrelated dish.
with food_names as (
  select
    local_food_id,
    trim(
      regexp_replace(
        replace(lower(food_name), 'chilli', 'chili'),
        '[^a-z0-9]+',
        ' ',
        'g'
      )
    ) as normalized_name
  from public.local_food
),
restaurant_items as (
  select
    restaurant_item_id,
    local_food_id as current_local_food_id,
    trim(
      regexp_replace(
        replace(lower(restaurant_item_name), 'chilli', 'chili'),
        '[^a-z0-9]+',
        ' ',
        'g'
      )
    ) as normalized_name
  from public.restaurant_item
),
name_matches as (
  select
    item.restaurant_item_id,
    item.current_local_food_id,
    item.normalized_name as item_name,
    food.local_food_id as matched_local_food_id,
    count(*) over (
      partition by item.restaurant_item_id
    ) as match_count
  from restaurant_items item
  join food_names food
    on length(food.normalized_name) >= 4
   and (' ' || item.normalized_name || ' ')
       like ('% ' || food.normalized_name || ' %')
),
unambiguous_repairs as (
  select match.restaurant_item_id, match.matched_local_food_id
  from name_matches match
  join food_names current_food
    on current_food.local_food_id = match.current_local_food_id
  where match.match_count = 1
    and match.matched_local_food_id <> match.current_local_food_id
    and (' ' || match.item_name || ' ')
        not like ('% ' || current_food.normalized_name || ' %')
)
update public.restaurant_item item
set local_food_id = repair.matched_local_food_id
from unambiguous_repairs repair
where item.restaurant_item_id = repair.restaurant_item_id;
