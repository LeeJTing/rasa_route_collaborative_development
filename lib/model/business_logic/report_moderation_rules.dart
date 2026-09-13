import '../../domain_model/opening_hour.dart';
import '../../domain_model/report_category.dart';
import '../../domain_model/report_claim.dart';

/// Pure rules for the report redesign: claim thresholds, canonical payload
/// strings (so "identical claim" = exact string equality), issue signatures,
/// and the temporary-closure duration resolution. No repository, no I/O -
/// every decision the moderation flow makes is here so it is unit-testable.
///
/// Thresholds (see REPORT_REDESIGN_PLAN.md):
///   operating_hours      10 identical (same day + same hours)
///   item_price            5 identical (same item + same price)
///   item_not_exist        5 identical (same item)
///   address               5 identical (same address text)
///   closed_permanently   10
///   closed_temporarily   10 (most-common duration wins; tie -> longest)
class ReportModerationRules {
  ReportModerationRules._();

  static const double minimumPrice = 0.01;

  /// The same band the Add-Landmark form's prices use (see
  /// `LandmarkSubmissionLogic.maxPrice`) - a claim about a RM2,500 dish must
  /// be expressible.
  static const double maximumPrice = 9999.99;
  static const int maximumAddressLength = 150;
  static const int maximumClosureDays = 365;
  static const int maximumClosureMonths = 12;

  /// How many identical claims are needed before a fix is auto-applied.
  static const Map<ReportCategory, int> thresholds = <ReportCategory, int>{
    ReportCategory.operatingHours: 10,
    ReportCategory.itemPrice: 5,
    ReportCategory.itemNotExist: 5,
    ReportCategory.address: 5,
    ReportCategory.closedPermanently: 10,
    ReportCategory.closedTemporarily: 10,
  };

  static int thresholdFor(ReportCategory category) => thresholds[category] ?? 0;

  static String? priceError(String raw, {bool required = false}) {
    final String value = raw.trim();
    if (value.isEmpty) return required ? 'Enter the corrected price.' : null;
    if (!RegExp(r'^\d{1,4}(\.\d{1,2})?$').hasMatch(value)) {
      return 'Use numbers only, with up to 2 decimal places.';
    }
    final double? price = double.tryParse(value);
    if (price == null || price < minimumPrice || price > maximumPrice) {
      return 'Price must be between RM0.01 and RM9,999.99.';
    }
    return null;
  }

  static String? addressError(String raw, {bool required = false}) {
    final String value = raw.trim();
    if (value.isEmpty) return required ? 'Enter the corrected address.' : null;
    if (value.length > maximumAddressLength) {
      return 'Address must be $maximumAddressLength characters or fewer.';
    }
    if (RegExp(r'[\x00-\x1F\x7F]').hasMatch(value)) {
      return 'Address contains unsupported characters.';
    }
    if (!RegExp(r'[A-Za-z0-9]').hasMatch(value)) {
      return 'Enter a meaningful street or place address.';
    }
    return null;
  }

  static String? closureError(
    String raw,
    ClosureUnit unit, {
    bool required = false,
  }) {
    final String value = raw.trim();
    if (value.isEmpty) return required ? 'Enter the closure duration.' : null;
    final int? amount = int.tryParse(value);
    if (amount == null || amount <= 0) {
      return 'Closure duration must be greater than zero.';
    }
    final int maximum = unit == ClosureUnit.days
        ? maximumClosureDays
        : maximumClosureMonths;
    if (amount > maximum) {
      return unit == ClosureUnit.days
          ? 'Closure duration cannot exceed 365 days.'
          : 'Closure duration cannot exceed 12 months.';
    }
    return null;
  }

  static String? operatingHoursError(
    Map<Weekday, List<OpeningHour>> operatingHours,
  ) {
    for (final MapEntry<Weekday, List<OpeningHour>> entry
        in operatingHours.entries) {
      final List<OpeningHour> changed = entry.value
          .where((OpeningHour hour) => hour.status != DayStatus.unknown)
          .toList(growable: false);
      if (changed.isEmpty || changed.first.status == DayStatus.closed) continue;

      final List<OpeningHour> openRows = changed
          .where((OpeningHour hour) => hour.status == DayStatus.open)
          .toList(growable: false);
      for (final OpeningHour row in openRows) {
        if (row.opensAt == null || row.closesAt == null) {
          return 'Set both opening and closing times for ${_dayName(entry.key)}.';
        }
        if (row.closesAt! <= row.opensAt!) {
          return 'Closing time must be after opening time for ${_dayName(entry.key)}.';
        }
      }
      openRows.sort(
        (OpeningHour first, OpeningHour second) =>
            first.opensAt!.compareTo(second.opensAt!),
      );
      for (int index = 1; index < openRows.length; index++) {
        if (openRows[index].opensAt! < openRows[index - 1].closesAt!) {
          return 'Opening-hour ranges overlap for ${_dayName(entry.key)}.';
        }
      }
    }

    // An overnight row (a close past midnight, e.g. 600 -> 1560) is still
    // open into the NEXT day - it must not run into that day's own morning
    // rows. See `OpeningHoursRows` for the encoding.
    for (final MapEntry<Weekday, List<OpeningHour>> entry
        in operatingHours.entries) {
      final Weekday nextDay =
          Weekday.values[(entry.key.index + 1) % Weekday.values.length];
      for (final OpeningHour row in entry.value) {
        final int? closesAt = row.closesAt;
        if (row.status != DayStatus.open ||
            closesAt == null ||
            closesAt <= 1440) {
          continue;
        }
        final int tailEnd = closesAt - 1440;
        for (final OpeningHour next
            in operatingHours[nextDay] ?? const <OpeningHour>[]) {
          if (next.status != DayStatus.open || next.opensAt == null) continue;
          if (next.opensAt! < tailEnd) {
            return "${_dayName(entry.key)}'s overnight hours run until "
                '${_timeLabel(tailEnd)} the next day, which overlaps '
                "${_dayName(nextDay)}'s row starting at "
                '${_timeLabel(next.opensAt!)}.';
          }
        }
      }
    }
    return null;
  }

  /// "HH:MM" for a minutes-past-midnight value, used in the overnight
  /// overlap message.
  static String _timeLabel(int minutes) {
    final int hours = (minutes ~/ 60) % 24;
    final int mins = minutes % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${mins.toString().padLeft(2, '0')}';
  }

  static String _dayName(Weekday day) =>
      '${day.name[0].toUpperCase()}${day.name.substring(1)}';

  /// Whether [claimCount] identical claims (already at or past the threshold)
  /// should trigger the auto-apply for [category].
  static bool reachesThreshold(ReportCategory category, int claimCount) =>
      claimCount >= thresholdFor(category);

  // ===========================================================================
  // Canonical payloads - the exact string stored in `report.payload`. Two
  // claims are "the same" iff their payload strings are identical.
  // ===========================================================================

  /// Canonical payload for one day's proposed hours. A day's proposal is a
  /// LIST of rows (an Open day may carry several ranges, e.g. a midday
  /// closure; Closed/Unknown days carry exactly one row) - the same shape the
  /// Add-Landmark hours field edits. Rows are sorted so order never changes
  /// the identity of the proposal.
  static String hoursPayload(List<ProposedDayHours> dayRows) {
    final List<String> rows =
        dayRows
            .map(
              (ProposedDayHours h) => h.status == DayStatus.open
                  ? '${h.status.name}:${h.opensAt}:${h.closesAt}'
                  : h.status.name,
            )
            .toList(growable: false)
          ..sort();
    return 'hours:${rows.join('|')}';
  }

  /// Parses an hours payload back into the day's proposed rows (for the
  /// auto-apply write). Empty when malformed.
  static List<ProposedDayHours> parseHoursPayload(String payload) {
    const String prefix = 'hours:';
    if (!payload.startsWith(prefix)) return const <ProposedDayHours>[];
    final List<String> parts = payload.substring(prefix.length).split('|');
    final List<ProposedDayHours> out = <ProposedDayHours>[];
    for (final String part in parts) {
      final List<String> fields = part.split(':');
      DayStatus? status;
      for (final DayStatus candidate in DayStatus.values) {
        if (candidate.name == fields.first) {
          status = candidate;
          break;
        }
      }
      if (status == null) return const <ProposedDayHours>[];
      if (status != DayStatus.open) {
        out.add(ProposedDayHours(status: status));
        continue;
      }
      if (fields.length != 3) return const <ProposedDayHours>[];
      final int? opensAt = int.tryParse(fields[1]);
      final int? closesAt = int.tryParse(fields[2]);
      if (opensAt == null || closesAt == null) {
        return const <ProposedDayHours>[];
      }
      out.add(
        ProposedDayHours(status: status, opensAt: opensAt, closesAt: closesAt),
      );
    }
    return out;
  }

  /// Canonical payload for a proposed item price. [price] is formatted with a
  /// fixed scale so 8.5 and 8.50 count as the SAME price.
  static String pricePayload(double price) =>
      'price:${price.toStringAsFixed(2)}';

  /// Canonical payload for an item-not-exist claim (the issue is the item, so
  /// there is nothing to compare beyond the category itself).
  static const String itemNotExistPayload = 'not-exist';

  /// Canonical payload for a proposed address.
  static String addressPayload(String address) => 'address:${address.trim()}';

  /// Canonical payload for a permanent closure (issue is the place).
  static const String closedPermanentlyPayload = 'closed-permanently';

  /// Canonical payload for a temporary closure of [duration].
  static String temporaryClosurePayload(ProposedClosure duration) =>
      'closed-temporarily:${duration.amount}:${duration.unit.columnValue}';

  /// The canonical payload a [ReportClaim] carries - helper for tests/readers.
  static String payloadFor(ReportClaim claim) => claim.payload;

  // ===========================================================================
  // Claim signatures / grouping
  // ===========================================================================

  /// The set of columns that define the "issue" a claim is about (everything
  /// EXCEPT the tourist and the payload) - used for dedupe and counting.
  static String issueSignature(ReportClaim claim) {
    final String day = claim.day?.name ?? '-';
    final String itemKind = claim.itemKind?.columnValue ?? '-';
    final String itemId = claim.itemId?.toString() ?? '-';
    return '${claim.placeKind.columnValue}:${claim.placeId}:'
        '${claim.category.name}:$itemKind:$itemId:$day';
  }

  // ===========================================================================
  // Temporary-closure duration resolution
  // ===========================================================================

  /// Picks the `closed_until` offset from a list of temporary-closure claim
  /// payloads (the canonical strings). The MOST COMMON reported duration wins;
  /// ties break to the LONGER duration so a place is never re-opened early.
  /// Returns null when [payloads] is empty.
  static ProposedClosure? resolveMostCommonClosure(List<String> payloads) {
    if (payloads.isEmpty) return null;
    final Map<String, int> counts = <String, int>{};
    final Map<String, ProposedClosure> byPayload = <String, ProposedClosure>{};
    for (final String payload in payloads) {
      final ProposedClosure? parsed = parseTemporaryClosurePayload(payload);
      if (parsed == null) continue;
      counts[payload] = (counts[payload] ?? 0) + 1;
      byPayload[payload] = parsed;
    }
    if (counts.isEmpty) return null;
    ProposedClosure? best;
    int bestCount = 0;
    // Sort deterministically so the longest wins ties.
    final List<String> keys = counts.keys.toList()
      ..sort(
        (String a, String b) =>
            byPayload[b]!.amount.compareTo(byPayload[a]!.amount),
      );
    for (final String key in keys) {
      if (counts[key]! > bestCount) {
        bestCount = counts[key]!;
        best = byPayload[key];
      }
    }
    return best;
  }

  /// Parses a temporary-closure payload back into a [ProposedClosure] (for
  /// resolving the most common duration). Null when malformed.
  static ProposedClosure? parseTemporaryClosurePayload(String payload) {
    const String prefix = 'closed-temporarily:';
    if (!payload.startsWith(prefix)) return null;
    final List<String> parts = payload.substring(prefix.length).split(':');
    if (parts.length != 2) return null;
    final int? amount = int.tryParse(parts[0]);
    final ClosureUnit? unit = ClosureUnit.fromColumnValue(parts[1]);
    if (amount == null || amount <= 0 || unit == null) return null;
    return ProposedClosure(amount: amount, unit: unit);
  }

  /// Days represented by a closure of [amount] [unit]s - used to compute
  /// `closed_until = now + duration`. Months are approximated as 30 days (the
  /// app has no calendar dependency; close enough for a moderation flag).
  static int closureDurationDays(ProposedClosure closure) =>
      closure.unit == ClosureUnit.days ? closure.amount : closure.amount * 30;
}
