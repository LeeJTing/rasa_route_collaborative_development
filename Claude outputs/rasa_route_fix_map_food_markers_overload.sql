-- rasa_route_fix_map_food_markers_overload.sql
--
-- WHY (owner SQL - the app's map currently shows
-- "Unable to load the map for this area. Check your connection and try again."):
--
-- The map calls RPC `public.map_food_markers`, and the database now holds TWO
-- overloads of it:
--
--   * the original 10-parameter version (no p_max_zoom), and
--   * a version WITH `p_max_zoom double precision` (which also has a DEFAULT,
--     because it matches calls that do not pass that argument).
--
-- A later `create or replace function` that ADDED the p_max_zoom parameter
-- created a second overload instead of replacing the old one - Postgres treats
-- a changed parameter list as a NEW function. With both present, PostgREST
-- cannot pick a candidate for the app's call (which does not send p_max_zoom):
--
--     PGRST203  Could not choose the best candidate function between:
--       public.map_food_markers(..., p_search_landmark_ids => bigint[])
--       public.map_food_markers(..., p_search_landmark_ids => bigint[], p_max_zoom => double precision)
--
-- NOTHING IS WRONG WITH THE ROW DATA (landmarks/items/photos inserted by the
-- seed tool are plain INSERTs and cannot create function overloads).
--
-- The newer overload serves EVERY caller - old app builds (no p_max_zoom) and
-- the new max-zoom feature alike - so the stale 10-parameter overload is
-- dropped. Verified before writing this: a call WITH p_max_zoom returns rows,
-- and the 10-parameter overload was itself a valid candidate without it,
-- which proves p_max_zoom has a DEFAULT.

-- ---------------------------------------------------------------- 1. PREVIEW
-- Expect TWO rows: one without p_max_zoom (stale) and one with it (keep).

select
  p.oid::regprocedure as signature,
  pg_get_function_arguments(p.oid) as arguments,
  (pg_get_function_arguments(p.oid) like '%p_max_zoom%') as has_max_zoom
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'map_food_markers'
order by p.oid;

-- ---------------------------------------------------------------- 2. THE FIX
-- Drop the OLD overload (the one WITHOUT p_max_zoom).

drop function if exists public.map_food_markers(
  double precision, double precision, double precision, double precision,
  double precision, integer[], integer, integer[], bigint[], bigint[]
);

-- --------------------------------------------------------------- 3. VERIFY
-- Exactly ONE row must remain and has_max_zoom must be true.
-- Then a direct call (as the app makes it, no p_max_zoom) must work:

select
  p.oid::regprocedure as signature,
  (pg_get_function_arguments(p.oid) like '%p_max_zoom%') as has_max_zoom
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'map_food_markers';

-- Optional smoke test - returns marker rows for the Setapak box:
-- select count(*) from public.map_food_markers(
--   3.17, 101.69, 3.22, 101.73, 13, null, 400, null, null, null);

-- NOTE FOR WHOEVER ADDS FUTURE PARAMETERS: when a function's parameter list
-- changes, use `drop function` first (or recreate with the same list) - a
-- `create or replace` with a new parameter list silently adds an overload.
