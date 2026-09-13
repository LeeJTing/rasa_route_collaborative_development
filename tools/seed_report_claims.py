"""Seed simulated report claims so YOUR next report is the one that applies.

Every category applies its fix when enough DISTINCT tourists file the same
claim (thresholds: hours/closure 10; price / not-exist / address 5). This
tool inserts `--count` rows (default: the threshold minus ONE) for one place,
all carrying the same canonical payload and `location_valid = true`, each
under a different `sim-report-...` tourist id - so the report YOU file from
the app becomes the claim that crosses the threshold, and the fix applies
immediately (the app even keeps its normal "Applied: ..." confirmation).

Your own (valid) claim must produce the IDENTICAL payload to join the group:
  * itemNotExist      payload is always 'not-exist'          (easiest demo)
  * itemPrice         --price 9.90 -> 'price:9.90'           (type 9.90)
  * operatingHours    --day monday --hours "open:540:1080"   (same hours)
  * address           --address "..." (+ --latitude/--longitude pins for
                      the 3-pin consensus; type/pick the same text)
  * closedPermanently 'closed-permanently'
  * closedTemporarily --days 30 (durations may differ - the most common wins)

Your report only COUNTS when you are on site: mock-GPS (or stand) within
50 m of where the place is stored before filing it. If your account already
reported this issue once, it is de-duplicated - use a fresh account or clear
that account's row first.

Simulated rows are tagged with a `sim-report-` tourist id, so `--clear`
removes ONLY them and never your real claims.

Usage:
    python tools/seed_report_claims.py --kind landmark --place-id 12 \
        --reason itemNotExist --item-id 345
    python tools/seed_report_claims.py --kind restaurant --place-id 9865 \
        --reason itemPrice --item-id 55555 --price 9.90
    python tools/seed_report_claims.py --kind landmark --place-id 12 \
        --reason itemNotExist --clear
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import seed_landmarks as seed  # noqa: E402

THRESHOLDS = {
    "operatingHours": 10,
    "itemPrice": 5,
    "itemNotExist": 5,
    "address": 5,
    "closedPermanently": 10,
    "closedTemporarily": 10,
}

ITEM_REASONS = ("itemPrice", "itemNotExist")
SIM_PREFIX = "sim-report-"
DAY_NAMES = [
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
]


def payload_for(args: argparse.Namespace) -> str:
    if args.reason == "itemNotExist":
        return "not-exist"
    if args.reason == "itemPrice":
        if args.price is None:
            raise SystemExit("--price is required for an itemPrice claim")
        return f"price:{args.price:.2f}"
    if args.reason == "operatingHours":
        if args.hours:
            return f"hours:{args.hours}"
        if args.closed:
            return "hours:closed"
        raise SystemExit(
            'operatingHours needs --hours "open:540:1080[|open:...]" --closed'
        )
    if args.reason == "address":
        if not args.address:
            raise SystemExit("--address is required for an address claim")
        return f"address:{args.address.strip()}"
    if args.reason == "closedPermanently":
        return "closed-permanently"
    if args.reason == "closedTemporarily":
        if args.months:
            return f"closed-temporarily:{args.months}:months"
        return f"closed-temporarily:{args.days or 30}:days"
    raise SystemExit(f"unknown reason {args.reason}")


def echo_item(
    url: str, key: str, args: argparse.Namespace
) -> None:
    """Print the item's name (and current price) so the app's picker can find
    the exact same row - the claim only groups when the item id matches."""
    if args.reason not in ITEM_REASONS or not args.item_id:
        return
    if args.kind == "landmark":
        table, id_col, name_col, price_col = (
            "landmark_item",
            "landmark_item_id",
            "dish",
            "item_price",
        )
    else:
        table, id_col, name_col, price_col = (
            "restaurant_item",
            "restaurant_item_id",
            "restaurant_item_name",
            "restaurant_item_price",
        )
    rows = seed.get_rows(
        url,
        key,
        f"{table}?select={name_col},{price_col},is_removed&{id_col}=eq.{args.item_id}",
    )
    if not rows:
        print(f"  WARNING: {table} {args.item_id} does not exist!")
        return
    row = rows[0]
    print(
        f"  item to select in the app: '{row[name_col]}' "
        f"(id {args.item_id}, current price {row[price_col]})"
    )
    if row.get("is_removed"):
        print("  WARNING: this item is already soft-removed (is_removed=true)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--kind", choices=["landmark", "restaurant"], required=True
    )
    parser.add_argument("--place-id", type=int, required=True)
    parser.add_argument("--reason", choices=sorted(THRESHOLDS), required=True)
    parser.add_argument(
        "--count",
        type=int,
        default=0,
        help="rows to insert (default: the category's threshold minus 1)",
    )
    parser.add_argument("--item-id", type=int)
    parser.add_argument("--price", type=float)
    parser.add_argument("--day", choices=DAY_NAMES)
    parser.add_argument(
        "--hours",
        help='payload rows, e.g. "open:540:1080" or "closed"',
    )
    parser.add_argument(
        "--closed",
        action="store_true",
        help="operatingHours payload 'hours:closed'",
    )
    parser.add_argument("--address")
    parser.add_argument("--days", type=int)
    parser.add_argument("--months", type=int)
    parser.add_argument("--latitude", type=float)
    parser.add_argument("--longitude", type=float)
    parser.add_argument(
        "--clear",
        action="store_true",
        help="delete the simulated rows for this place+reason and exit",
    )
    args = parser.parse_args()

    if args.reason == "operatingHours" and not args.day:
        raise SystemExit("operatingHours needs --day (e.g. --day monday)")

    env = seed.read_env()
    url = env["SUPABASE_URL"].rstrip("/")
    key = env.get("SUPABASE_PUBLISHABLE_KEY") or env["SUPABASE_ANON_KEY"]

    where = (
        f"kind=eq.{args.kind}&place_id=eq.{args.place_id}"
        f"&reason=eq.{args.reason}"
    )
    sim_only = f"tourist_id=like.{SIM_PREFIX}*"

    # Idempotent setup: previous simulated rows for THIS issue go first.
    status, _, body = seed.call(
        url, key, f"report?{where}&{sim_only}", method="DELETE"
    )
    if status not in (200, 204):
        raise SystemExit(f"could not clear simulated rows: {status} {body[:200]!r}")
    print(f"cleared previous simulated rows for {args.kind} {args.place_id} "
          f"({args.reason}): {status}")
    if args.clear:
        print("done - only sim-report-* rows were touched.")
        return

    count = args.count or (THRESHOLDS[args.reason] - 1)
    payload = payload_for(args)
    item_kind = {
        "landmark": "landmark_item",
        "restaurant": "restaurant_item",
    }[args.kind]

    # Address pins: without explicit coordinates, borrow the place's own
    # stored spot so all simulated pins agree and the 3-pin consensus can
    # succeed as soon as the user's report joins them.
    latitude = args.latitude
    longitude = args.longitude
    if args.reason == "address" and (latitude is None or longitude is None):
        if args.kind == "landmark":
            table, id_col = "submitted_landmark", "landmark_id"
        else:
            table, id_col = "restaurant", "restaurant_id"
        found = seed.get_rows(
            url,
            key,
            f"{table}?select=latitude,longitude&{id_col}=eq.{args.place_id}",
        )
        if found and found[0].get("latitude") and found[0].get("longitude"):
            latitude = float(found[0]["latitude"])
            longitude = float(found[0]["longitude"])
            print(f"  pins: using the place's own spot {latitude}, {longitude}")
        else:
            print(
                "  WARNING: place has no coordinates - pass --latitude/"
                "--longitude or the consensus can never agree"
            )

    rows = [
        {
            "kind": args.kind,
            "place_id": args.place_id,
            "reason": args.reason,
            # `report.item_kind` stores the enum's columnValue, not its name.
            "item_kind": item_kind if args.reason in ITEM_REASONS else None,
            "item_id": args.item_id if args.reason in ITEM_REASONS else None,
            "day": args.day if args.reason == "operatingHours" else None,
            "payload": payload,
            "latitude": latitude if args.reason == "address" else None,
            "longitude": longitude if args.reason == "address" else None,
            "location_valid": True,
            "tourist_id": f"{SIM_PREFIX}{index + 1:02d}",
        }
        for index in range(count)
    ]
    seed.insert_rows(url, key, "report", rows)

    print(f"inserted {count} simulated VALID claims")
    print(f"  payload to match in the app: {payload!r}")
    print(
        f"  threshold {THRESHOLDS[args.reason]} -> your report becomes claim "
        f"#{count + 1} and applies the fix"
    )
    echo_item(url, key, args)
    if args.reason == "address":
        print(
            "  pins: the 3+ consensus pins come from these rows - pass "
            "--latitude/--longitude (or all rows share one spot)"
        )
    print(
        "  remember: mock-GPS within 50 m of the place, use the SAME item/"
        "price/address/hours, and this account must not have claimed this "
        "issue before"
    )
    print(
        "  undo with: --clear (removes only tourist_id like 'sim-report-*')"
    )


if __name__ == "__main__":
    main()
