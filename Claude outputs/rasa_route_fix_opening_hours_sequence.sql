-- rasa_route_fix_opening_hours_sequence.sql
--
-- WHY (owner SQL - the anon key cannot touch sequences):
--
-- `opening_hours` holds every restaurant's hours too (~124,340 rows with
-- `landmark_id` null, ids from 19 upwards). Those rows were imported with
-- EXPLICIT ids, so the table's identity sequence is still far BEHIND them.
-- Any insert that lets the identity generate the id - which is what the app
-- deliberately does (see `SubmittedLandmarkRepository._insertOpeningHours`)
-- - hits an id that already exists:
--
--     duplicate key value violates unique constraint "opening_hours_pkey"
--
-- Until this is re-synced, Add-Landmark submissions fail at the hours step.
--
-- RUN THIS **AFTER** `tools/seed_landmarks.py` (the seeder also writes
-- explicit ids, max+1, and does not move the sequence either). Running it
-- before the seeder would leave the sequence behind again, because the
-- seeder's explicit inserts do not advance it.
--
-- ---------------------------------------------------------------- 1. PREVIEW
-- Current max id vs what the sequence would hand out next.

select
  (select max(opening_hours_id) from public.opening_hours) as max_existing_id,
  pg_get_serial_sequence('public.opening_hours',
                         'opening_hours_id') as sequence_name;

-- ---------------------------------------------------------------- 2. THE FIX
-- Point the sequence at the current max: the NEXT insert gets max + 1.

select setval(
  pg_get_serial_sequence('public.opening_hours', 'opening_hours_id'),
  (select max(opening_hours_id) from public.opening_hours)
) as fixed_to;

-- --------------------------------------------------------------- 3. VERIFY
-- last_value must be >= max_existing_id (is_called = true, so the next
-- nextval() is last_value + 1 - one past every existing row).

select
  last_value as sequence_last_value,
  is_called  as sequence_is_called,
  (select max(opening_hours_id) from public.opening_hours) as max_existing_id
from opening_hours_opening_hours_id_seq;

-- Expect: sequence_last_value >= max_existing_id (equal is correct).
