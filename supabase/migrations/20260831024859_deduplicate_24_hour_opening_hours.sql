delete from public.opening_hours as redundant
where redundant.restaurant_id is not null
  and redundant.status::text = 'open'
  and redundant.opening_time is null
  and redundant.closing_time is null
  and exists (
    select 1
    from public.opening_hours as canonical
    where canonical.restaurant_id = redundant.restaurant_id
      and canonical.day = redundant.day
      and canonical.status::text = 'open'
      and canonical.opening_time = time '00:00:00'
      and canonical.closing_time = time '23:59:59'
  );
