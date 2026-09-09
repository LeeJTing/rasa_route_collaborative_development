-- Correct clearly mislinked Char Kway Teow menu items. The imported rows were
-- linked to Bak Kut Teh, which made both Quick Mode and Restaurant Detail
-- reject the catalogue image as unrelated.
update public.restaurant_item
set local_food_id = (
  select local_food_id
  from public.local_food
  where food_name = 'Char Kway Teow'
  limit 1
)
where local_food_id = (
  select local_food_id
  from public.local_food
  where food_name = 'Bak Kut Teh'
  limit 1
)
and lower(restaurant_item_name)
  ~ 'char.*(kuey|kway|kuay|koay)[ -]?teow';
