// Supabase Edge Function: `report-housekeeping`.
//
// WHAT: the time-based cleanup the app can only do lazily, on read:
//
//   1. DELETE report claims older than 1 year. The app's `reportClaimLifetime`
//      (`lib/domain_model/report_claim.dart`) makes every read IGNORE expired
//      rows - counts, dedupe, pin consensus, the closure end-date resolution -
//      but only this job removes them, so the table does not grow forever.
//
//   2. REACTIVATE temporary closures whose end date has passed. A reported
//      closure freezes the place (`status='frozen'` + `closed_until`). Once
//      the end date passes the app treats the place as available AND writes
//      'available' back - but only for places some client happens to read.
//      This job applies the SAME rule the app uses (`PlaceClosureRules`:
//      status 'frozen' AND closed_until <= now) to the whole table, daily.
//      `closed_permanently` freezes (`closed_until = NULL`) are deliberately
//      NOT touched - the standing outcome stays until a human reviews it.
//
// HOW IT RUNS: once a day by pg_cron - see
// `supabase/migrations/20260914000000_report_housekeeping_cron.sql`, which
// calls this endpoint over pg_net with the public (publishable) key. Deploy
// this function BEFORE running that migration:
//   supabase functions deploy report-housekeeping --project-ref odtmtukexckfjbuqkxyo
// or Dashboard -> Edge Functions -> Create -> name it exactly
// `report-housekeeping` and paste this file. Leave *Verify JWT* enabled.
//
// CALL IT: no parameters needed. `{"dry_run": true}` counts what WOULD be
// cleaned and writes nothing - use it any time to check the schedule's reach.
// The caller only needs the public key; the privileged work runs with the
// service_role key Supabase injects into every Edge Function.
//
// SAFETY: the app's read-time filters (`_isExpired` in `report_repository.dart`
// for claims, `PlaceClosureRules.isEffectivelyAvailable`/`needsReactivation`
// for closures) stay in place as the real-time net. This job is persistence
// hygiene - deleting a row here can never change what a client is showing.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

/// The same one year the app uses (`reportClaimLifetime`).
const CLAIM_LIFETIME_MS = 365 * 24 * 60 * 60 * 1000;

function jsonResponse(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/// The first non-empty environment variable - Supabase injects the legacy
/// `SUPABASE_SERVICE_ROLE_KEY` name in every project and the new
/// `SUPABASE_SECRET_KEY` name once the project moved to the new API keys, so
/// accept both rather than hard-failing on one.
function firstEnv(...names: string[]): string {
  for (const name of names) {
    const value = Deno.env.get(name);
    if (value && value.trim().length > 0) return value.trim();
  }
  return "";
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return jsonResponse({ ok: false, error: "POST only" }, 405);
  }

  // The cron call posts `{}`; a missing or unparsable body means the same.
  let payload: Record<string, unknown> = {};
  try {
    payload = (await request.json()) as Record<string, unknown>;
  } catch {
    payload = {};
  }
  const dryRun = payload.dry_run === true;

  const url = firstEnv("SUPABASE_URL");
  const serviceKey = firstEnv(
    "SUPABASE_SERVICE_ROLE_KEY",
    "SUPABASE_SECRET_KEY",
  );
  if (url.length === 0 || serviceKey.length === 0) {
    return jsonResponse(
      { ok: false, error: "SUPABASE_URL / service-role key missing." },
      500,
    );
  }

  const client = createClient(url, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const nowIso = new Date().toISOString();
  const cutoffIso = new Date(Date.now() - CLAIM_LIFETIME_MS).toISOString();

  // Count BEFORE writing so a dry run and a real run report the same numbers.
  const countExpiredClosures = (table: string) =>
    client
      .from(table)
      .select("*", { count: "exact", head: true })
      .eq("status", "frozen")
      .not("closed_until", "is", null)
      .lte("closed_until", nowIso);

  const [claimsCount, restaurantsCount, landmarksCount] = await Promise.all([
    client
      .from("report")
      .select("*", { count: "exact", head: true })
      .lt("created_at", cutoffIso),
    countExpiredClosures("restaurant"),
    countExpiredClosures("submitted_landmark"),
  ]);

  const readError =
    claimsCount.error ?? restaurantsCount.error ?? landmarksCount.error;
  if (readError) {
    return jsonResponse({ ok: false, error: readError.message }, 500);
  }

  const pending = {
    expired_claims: claimsCount.count ?? 0,
    expired_closures: {
      restaurants: restaurantsCount.count ?? 0,
      landmarks: landmarksCount.count ?? 0,
    },
  };

  if (dryRun) {
    return jsonResponse(
      { ok: true, dry_run: true, cutoff: cutoffIso, would_clean: pending },
      200,
    );
  }

  const deletedClaims = await client
    .from("report")
    .delete({ count: "exact" })
    .lt("created_at", cutoffIso);

  const reactivate = (table: string) =>
    client
      .from(table)
      .update({ status: "available", closed_until: null }, { count: "exact" })
      .eq("status", "frozen")
      .not("closed_until", "is", null)
      .lte("closed_until", nowIso);

  const [restaurantsUpdate, landmarksUpdate] = await Promise.all([
    reactivate("restaurant"),
    reactivate("submitted_landmark"),
  ]);

  const failures = [
    deletedClaims.error,
    restaurantsUpdate.error,
    landmarksUpdate.error,
  ].filter((error): error is NonNullable<typeof error> => error !== null);
  if (failures.length > 0) {
    return jsonResponse(
      {
        ok: false,
        cutoff: cutoffIso,
        error: failures.map((error) => error.message).join("; "),
      },
      500,
    );
  }

  return jsonResponse(
    {
      ok: true,
      dry_run: false,
      cutoff: cutoffIso,
      cleaned: {
        deleted_claims: deletedClaims.count ?? pending.expired_claims,
        reactivated_restaurants:
          restaurantsUpdate.count ?? pending.expired_closures.restaurants,
        reactivated_landmarks:
          landmarksUpdate.count ?? pending.expired_closures.landmarks,
      },
    },
    200,
  );
});
