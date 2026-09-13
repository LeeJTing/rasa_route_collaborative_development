-- Rasa Route - CLEAR OUT ALL landmark data.
--
-- Deletes every tourist-submitted landmark and everything it owns:
--   * landmark_item rows (all of them),
--   * their opening_hours rows,
--   * their moderation report rows,
--   * the submitted_landmark rows themselves.
--
-- Supersedes `rasa_route_delete_landmarks_4_to_8.sql` (same idea, but this
-- covers EVERY landmark - at time of writing ids 4..14, 18 dish items).
--
-- PHOTOS: already deleted (2026-09-13) from the `landmark-images` bucket via
--   the storage API - all 28 objects referenced by the rows below, verified
--   gone (0 remain, a sample URL answers 400). The rows just still point at
--   them until this script runs.
--
-- WHY owner-run (Supabase dashboard -> SQL editor):
--   the app's anon publishable key has NO DELETE grant/policy on
--   submitted_landmark / landmark_item (supabase/migrations/20260822000000_rls.sql
--   - "NO DELETE anywhere"), so this cannot run through the app's client.
--
-- NOT touched (deliberately):
--   * `local_food` catalogue rows (incl. 375 'Cendol' - linked by the
--     landmark items being deleted, but a legitimate scraped row),
--   * `landmark_draft` (the fresh incomplete submission draft_id=20),
--   * catalogue restaurants and their `restaurant_item` rows.
--
-- Idempotent: re-running deletes nothing extra.

begin;

-- 1) Preview - what is about to go.
select landmark_id, landmark_name, status, category
  from public.submitted_landmark
 order by landmark_id;

select landmark_item_id, landmark_id, dish, variant, local_food_id
  from public.landmark_item
 order by landmark_item_id;

select count(*) as landmark_opening_hours_rows
  from public.opening_hours
 where landmark_id is not null;

select count(*) as landmark_report_rows
  from public.report
 where kind = 'landmark';

-- 2) Delete - children first (landmark_item.landmark_id -> submitted_landmark
--    is the only FK on the table), then the side rows keyed by the same id.
delete from public.landmark_item       where landmark_id is not null;
delete from public.opening_hours       where landmark_id is not null;
delete from public.report              where kind = 'landmark';
delete from public.submitted_landmark;

-- 3) Verify - every number must be 0.
select
  (select count(*) from public.submitted_landmark)                       as landmarks,
  (select count(*) from public.landmark_item)                            as items,
  (select count(*) from public.opening_hours where landmark_id is not null) as hours,
  (select count(*) from public.report where kind = 'landmark')           as reports;

-- 4) OPTIONAL - the fresh incomplete submission (draft_id = 20, created
--    2026-09-13, expires 2026-09-14). Left in place on purpose. If you want
--    it gone too, uncomment:
-- delete from public.landmark_draft;

-- 5) ONE dead catalogue image: `local_food_image` 867 (local_food_id 19
--    'Nasi Kukus Ayam Goreng Berempah') points at landmark 8's dish photo,
--    which the clear-out deleted - the URL is dead, the app falls back to
--    its placeholder.
--
--    Deliberately NOT a blanket rule ("img_name like '%/landmark-images/%'"):
--    the Add-New-Landmark flow INTENTIONALLY attaches the tourist's photo to
--    the catalogue row it creates (see `local_food_image` 868 for the new
--    豆腐花 row 376) - those must stay. This row is dead only because ITS
--    photo was removed.
delete from public.local_food_image
 where local_food_image_id = 867
   and img_name like '%/landmark-images/%';

commit;
