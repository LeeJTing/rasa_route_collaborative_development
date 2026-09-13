import 'opening_hour.dart';
import 'report_category.dart';

/// Unit for a temporary-closure duration - how long a place is reported
/// closed for (e.g. "3 days" or "2 months").
enum ClosureUnit {
  days,
  months;

  String get columnValue => name;

  static ClosureUnit? fromColumnValue(String? value) => switch (value) {
    'days' => ClosureUnit.days,
    'months' => ClosureUnit.months,
    _ => null,
  };
}

/// ONE report row - one tourist's claim about one specific issue (a single
/// day's hours, one item's price, one item existing, the place address, or a
/// closure). The `payload` is a CANONICAL string so "identical claims" can be
/// grouped by exact string equality (see `ReportModerationRules`).
///
/// For [ReportCategory.operatingHours], [day] is set and [payload] describes
/// that one day's proposed hours - a submission that corrects several days
/// becomes several [ReportClaim]s, each counted toward its own threshold.
/// For item categories, [itemKind] + [itemId] point at the disputed menu row.
/// [payload] is empty for [ReportCategory.closedPermanently].
///
/// Domain models are plain data types - they carry the canonical payload text
/// the repository stores in `report.payload`; the business-logic layer builds
/// it via the pure rules so insert and count always agree.
class ReportClaim {
  const ReportClaim({
    required this.placeKind,
    required this.placeId,
    required this.category,
    this.itemKind,
    this.itemId,
    this.day,
    this.latitude,
    this.longitude,
    this.locationValid = false,
    required this.payload,
  });

  final ReportPlaceKind placeKind;
  final int placeId;
  final ReportCategory category;

  /// Set when the claim is about a menu item ([ReportCategory.itemPrice] or
  /// [ReportCategory.itemNotExist]).
  final ReportItemKind? itemKind;
  final int? itemId;

  /// Set when the claim is about one weekday's hours
  /// ([ReportCategory.operatingHours]).
  final Weekday? day;

  /// Set by an ADDRESS claim: the exact spot the tourist pinned on the report
  /// page's map.
  ///
  /// The address text is usually the OpenStreetMap wording for that spot -
  /// approximate, because OSM addresses are - so the pin is the part that is
  /// exact, and the fix applies it to the place along with the text. It is
  /// deliberately NOT part of [payload]: two tourists correcting the same
  /// place tap different pixels, and identical claims have to keep grouping
  /// by the address text for the threshold to work.
  final double? latitude;
  final double? longitude;

  /// Whether the tourist was ON SITE when they reported: their own fix was
  /// within the on-site radius of the PLACE'S ORIGINAL LOCATION - where the
  /// app places the landmark/restaurant they are reporting - for every
  /// category (see `ReportModerationRules.isWithinOnsiteRange`).
  ///
  /// Set when the claim is built, stored on the row, and FALSE whenever the
  /// device had no fix - an unverifiable claim is kept for the record and for
  /// the one-claim-per-tourist dedupe, but it never counts toward a threshold
  /// and can never move a place. The tourist is told nothing about it.
  final bool locationValid;

  /// Canonical proposed value, stored verbatim in `report.payload`. Identical
  /// claims (same issue + same payload) count toward the threshold.
  final String payload;
}

/// How long a stored claim stays ALIVE (user request, 2026-09-14): after a
/// year a claim no longer counts toward its threshold and no longer blocks
/// the same tourist from reporting the issue again - a year-old report must
/// not stack with today's. Applied by `ReportRepository` on every read
/// (`countIdentical`, `countIssue`, `alreadyReported`, pins and payloads).
const Duration reportClaimLifetime = Duration(days: 365);

/// Whether a stored claim (its `created_at`) is past [reportClaimLifetime]
/// at [now]. A missing/unreadable timestamp is NOT expired - real rows always
/// carry `created_at` (not-null default), and dropping one would silently
/// weaken dedupe.
bool isReportClaimExpired(DateTime? createdAt, DateTime now) {
  if (createdAt == null) return false;
  return now.toUtc().difference(createdAt.toUtc()) > reportClaimLifetime;
}

/// A single day's PROPOSED hours for an operating-hours claim - mirrors
/// [OpeningHour] without the id.
class ProposedDayHours {
  const ProposedDayHours({required this.status, this.opensAt, this.closesAt});

  final DayStatus status;

  /// Minutes since midnight (only for [DayStatus.open]).
  final int? opensAt;
  final int? closesAt;
}

/// A reported temporary-closure duration.
class ProposedClosure {
  const ProposedClosure({required this.amount, required this.unit});

  final int amount;
  final ClosureUnit unit;
}

/// One stored temporary-closure claim as the closure resolution needs it:
/// its canonical payload and WHEN it was filed (`report.created_at`).
///
/// The resolution normalises each claim to the END DATE it points at
/// (`createdAt + duration`), so claims filed on different days that all mean
/// "closed until the same day" vote together (user's design, 2026-09-14).
class ClosureClaim {
  const ClosureClaim({required this.payload, required this.createdAt});

  /// The canonical `closed-temporarily:<amount>:<unit>` payload.
  final String payload;

  /// `report.created_at` - when the claim was filed (UTC instant).
  final DateTime createdAt;
}

/// A menu item a report can target, with just what the picker and claim need.
/// Domain-shaped so the report UI never touches repository/data models.
class ReportableMenuItem {
  const ReportableMenuItem({
    required this.itemKind,
    required this.id,
    required this.name,
    this.price,
    this.isRemoved = false,
  });

  final ReportItemKind itemKind;
  final int id;
  final String name;

  /// Current displayed price (MYR) - shown next to the item in the picker.
  final double? price;

  /// Whether this item was already soft-removed by an earlier report.
  final bool isRemoved;
}
