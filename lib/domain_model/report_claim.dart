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

  /// Canonical proposed value, stored verbatim in `report.payload`. Identical
  /// claims (same issue + same payload) count toward the threshold.
  final String payload;
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
