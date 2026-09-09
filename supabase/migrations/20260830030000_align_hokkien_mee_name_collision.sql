-- Align the two regional Hokkien Mee dishes with the Food Detail Figma copy.
-- The canonical names stay distinct while "Penang Hokkien Mee" remains a
-- searchable synonym for Prawn Noodle.
update public.local_food
set
  food_name = 'Hokkien Mee',
  synonyms = 'KL Hokkien Mee'
where local_food_id = 31
  and food_name = 'KL Hokkien Mee';

update public.local_food
set
  food_name = 'Prawn Noodle',
  synonyms = 'Penang Hokkien Mee; Har Mee; Prawn Mee'
where local_food_id = 32
  and food_name = 'Penang Hokkien Mee';
