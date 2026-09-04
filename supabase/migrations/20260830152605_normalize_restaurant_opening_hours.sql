alter table public.opening_hours
  add column if not exists status text;

update public.opening_hours
set status = case
  when opening_time is not null and closing_time is not null then 'open'
  else 'closed'
end
where status is null;

with source_days as (
  select
    restaurant.restaurant_id,
    initcap(
      (regexp_match(
        lower(entry.key),
        '^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)'
      ))[1]
    ) as day_name,
    lower(
      trim(
        regexp_replace(
          regexp_replace(
            replace(replace(entry.value, chr(8239), ' '), chr(160), ' '),
            ',?[[:space:]]*hours might differ',
            '',
            'gi'
          ),
          ',?[[:space:]]*holiday hours',
          '',
          'gi'
        )
      )
    ) as day_value
  from public.restaurant
  cross join lateral jsonb_each_text(restaurant.opening_hours::jsonb)
    as entry(key, value)
  where pg_input_is_valid(restaurant.opening_hours, 'jsonb')
)
update public.opening_hours as hours
set status = case
  when source_days.day_value = 'closed' then 'closed'
  else 'open'
end
from source_days
where hours.restaurant_id = source_days.restaurant_id
  and lower(hours.day) = lower(source_days.day_name);

alter table public.opening_hours
  alter column status set default 'unknown',
  alter column status set not null;

alter table public.opening_hours
  add constraint opening_hours_status_check
  check (status in ('open', 'closed', 'unknown'));

with valid_restaurants as (
  select restaurant_id, opening_hours::jsonb as hours
  from public.restaurant
  where pg_input_is_valid(opening_hours, 'jsonb')
),
day_values as (
  select
    valid_restaurants.restaurant_id,
    initcap(
      (regexp_match(
        lower(entry.key),
        '^(monday|tuesday|wednesday|thursday|friday|saturday|sunday)'
      ))[1]
    ) as day_name,
    trim(
      regexp_replace(
        regexp_replace(
          replace(replace(entry.value, chr(8239), ' '), chr(160), ' '),
          ',?[[:space:]]*hours might differ',
          '',
          'gi'
        ),
        ',?[[:space:]]*holiday hours',
        '',
        'gi'
      )
    ) as day_value
  from valid_restaurants
  cross join lateral jsonb_each_text(valid_restaurants.hours)
    as entry(key, value)
),
closed_and_24_hour_rows as (
  select
    restaurant_id,
    day_name,
    case when lower(day_value) = 'closed' then 'closed' else 'open' end
      as status,
    case
      when lower(day_value) = 'closed' then null::time
      else time '00:00:00'
    end as opening_time,
    case
      when lower(day_value) = 'closed' then null::time
      else time '23:59:59'
    end as closing_time
  from day_values
  where lower(day_value) in ('closed', 'open 24 hours')
),
range_parts as (
  select
    day_values.restaurant_id,
    day_values.day_name,
    matches.parts
  from day_values
  cross join lateral regexp_matches(
    lower(day_values.day_value),
    '([0-9]{1,2})(:([0-9]{2}))?[[:space:]]*(am|pm)?[[:space:]]*[–—-][[:space:]]*([0-9]{1,2})(:([0-9]{2}))?[[:space:]]*(am|pm)',
    'g'
  ) as matches(parts)
  where lower(day_values.day_value) not in ('closed', 'open 24 hours')
),
range_components as (
  select
    restaurant_id,
    day_name,
    parts,
    (
      ((parts[5]::integer % 12)
        + case when parts[8] = 'pm' then 12 else 0 end) * 60
      + coalesce(parts[7], '0')::integer
    ) as end_minutes,
    case
      when parts[4] is null then null
      else (
        ((parts[1]::integer % 12)
          + case when parts[4] = 'pm' then 12 else 0 end) * 60
        + coalesce(parts[3], '0')::integer
      )
    end as explicit_start_minutes,
    (
      ((parts[1]::integer % 12)
        + case when parts[8] = 'pm' then 12 else 0 end) * 60
      + coalesce(parts[3], '0')::integer
    ) as same_meridiem_start_minutes,
    (
      ((parts[1]::integer % 12)
        + case when parts[8] = 'am' then 12 else 0 end) * 60
      + coalesce(parts[3], '0')::integer
    ) as opposite_meridiem_start_minutes
  from range_parts
),
range_minutes as (
  select
    restaurant_id,
    day_name,
    end_minutes,
    case
      when explicit_start_minutes is not null then explicit_start_minutes
      when mod(end_minutes - same_meridiem_start_minutes + 1440, 1440)
         <= mod(end_minutes - opposite_meridiem_start_minutes + 1440, 1440)
        then same_meridiem_start_minutes
      else opposite_meridiem_start_minutes
    end as start_minutes
  from range_components
),
range_rows as (
  select
    restaurant_id,
    day_name,
    'open'::text as status,
    make_time(start_minutes / 60, mod(start_minutes, 60), 0) as opening_time,
    make_time(end_minutes / 60, mod(end_minutes, 60), 0) as closing_time
  from range_minutes
),
candidate_rows as (
  select * from closed_and_24_hour_rows
  union all
  select * from range_rows
),
missing_rows as (
  select distinct candidate_rows.*
  from candidate_rows
  where candidate_rows.day_name is not null
    and not exists (
      select 1
      from public.opening_hours existing
      where existing.restaurant_id = candidate_rows.restaurant_id
        and lower(existing.day) = lower(candidate_rows.day_name)
        and existing.status = candidate_rows.status
        and existing.opening_time is not distinct from candidate_rows.opening_time
        and existing.closing_time is not distinct from candidate_rows.closing_time
    )
),
numbered_rows as (
  select
    coalesce((select max(opening_hours_id) from public.opening_hours), 0)
      + row_number() over (
          order by
            restaurant_id,
            case lower(day_name)
              when 'monday' then 1
              when 'tuesday' then 2
              when 'wednesday' then 3
              when 'thursday' then 4
              when 'friday' then 5
              when 'saturday' then 6
              when 'sunday' then 7
            end,
            opening_time nulls first,
            closing_time nulls first
        ) as opening_hours_id,
    day_name,
    status,
    opening_time,
    closing_time,
    restaurant_id
  from missing_rows
)
insert into public.opening_hours (
  opening_hours_id,
  day,
  status,
  opening_time,
  closing_time,
  landmark_id,
  restaurant_id
)
select
  opening_hours_id,
  day_name,
  status,
  opening_time,
  closing_time,
  null,
  restaurant_id
from numbered_rows;

create index if not exists opening_hours_restaurant_id_idx
  on public.opening_hours (restaurant_id);
