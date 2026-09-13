import 'dart:math' as math;

import '../../domain_model/opening_hour.dart';
import '../../domain_model/report_category.dart';
import '../../domain_model/report_claim.dart';
import '../../domain_model/tourist_location.dart';
import 'landmark_submission_logic.dart';

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
///   closed_temporarily   10 (durations may differ; claims are normalised to
///                            the END DATE they mean - most-voted date wins,
///                            tie -> the later date)
class ReportModerationRules {
  ReportModerationRules._();

  static const double minimumPrice = 0.01;

  /// The same band the Add-Landmark form's prices use (see
  /// `LandmarkSubmissionLogic.maxPrice`) - a claim about a RM2,500 dish must
  /// be expressible.
  static const double maximumPrice = 9999.99;

  /// The address limits are the Add-New-Landmark form's - the two screens
  /// accept and reject exactly the same strings, with the same wording (see
  /// [addressError]).
  static const int minimumAddressLength =
      LandmarkSubmissionLogic.minAddressLength;
  static const int maximumAddressLength =
      LandmarkSubmissionLogic.maxAddressLength;
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

  /// How long a claim stays ALIVE: after a year it no longer counts toward
  /// its threshold and no longer blocks the same tourist from reporting the
  /// issue again (user request, 2026-09-14). The constant and the comparison
  /// live on the domain model (`reportClaimLifetime` / `isReportClaimExpired`)
  /// so `ReportRepository` can apply exactly the same rule without importing
  /// this layer - these are the moderation-facing aliases.
  static const Duration claimLifetime = reportClaimLifetime;

  static bool isClaimExpired(DateTime? createdAt, DateTime now) =>
      isReportClaimExpired(createdAt, now);

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

  /// The report page's address field, judged by the Add-New-Landmark form's
  /// rules. The WHOLE judgement - raw control characters, the minimum length,
  /// every shape rule and the 150 hard stop, in the form's order and its
  /// words - is `LandmarkSubmissionLogic.addressError`: both fields call the
  /// same method, so they can never drift apart again.
  ///
  /// Only the empty field differs. The form's field is optional; this one is
  /// required work (you are proposing a replacement), so an empty answer is
  /// "Enter the corrected address." rather than silence.
  static String? addressError(String raw, {bool required = false}) {
    if (raw.trim().isEmpty) {
      return required ? 'Enter the corrected address.' : null;
    }
    return LandmarkSubmissionLogic.addressError(raw);
  }

  /// The field's amber "close to the cap" nudge (141-149), in the same words
  /// the Add-Landmark form uses - see
  /// `LandmarkSubmissionLogic.addressLengthWarning`.
  static String? addressLengthWarning(String raw) =>
      LandmarkSubmissionLogic.addressLengthWarning(raw);

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

  // ===========================================================================
  // On-site validity + pin consensus (the location half of a report)
  // ===========================================================================
  //
  // A claim counts only when the tourist was actually THERE, and a place's
  // coordinates move only when the valid tourists AGREE on where the spot is
  // (user's design, 2026-09-13). Both are pure so they are unit-testable:
  // the ViewModel feeds the rules a raw GPS fix, and the moderation logic
  // feeds them the stored pins.

  /// How close the reporter's own fix must be to the spot they are reporting
  /// about for the claim to count. Beyond this the claim is stored with
  /// `location_valid = false` and never counts toward a threshold.
  static const double onsiteRadiusMetres = 50;

  /// How close the agreeing pins have to be to each other. Deliberately much
  /// tighter than [onsiteRadiusMetres]: 100 m spans a whole row of shops, and
  /// the point is to pin ONE place.
  static const double consensusRadiusMetres = 30;

  /// The fewest pins that must fall inside [consensusRadiusMetres] of the
  /// group's median. Two is not a consensus (a median of two is just the
  /// midpoint); three independent fixes of a phone-grade GPS land within
  /// roughly +/-10 m, which is well inside a shopfront.
  static const int minimumAgreeingPins = 3;

  /// Whether [reporter]'s own fix is close enough to [target] (the spot the
  /// claim is about) to verify the report. An unknown fix is never valid -
  /// nothing can be checked without a position.
  static bool isWithinOnsiteRange(
    TouristLocation reporter,
    TouristLocation target, {
    double radiusMetres = onsiteRadiusMetres,
  }) =>
      reporter.isKnown &&
      target.isKnown &&
      distanceMetres(reporter, target) <= radiusMetres;

  /// The spot a group of VALID pins agrees on, or null when fewer than
  /// [minimumAgreeingPins] of them fall within [radiusMetres] of the group's
  /// median.
  ///
  /// Null means "hold the fix back": nothing is written and the claims stay,
  /// so every further valid report re-runs this check (the escalation the
  /// user asked for). The returned spot is the median of the AGREEING pins
  /// only - a dissenting tourist cannot drag the place.
  static TouristLocation? consensusLocation(
    List<TouristLocation> pins, {
    double radiusMetres = consensusRadiusMetres,
    int minimumAgreeing = minimumAgreeingPins,
  }) {
    final List<TouristLocation> known = <TouristLocation>[
      for (final TouristLocation pin in pins)
        if (pin.isKnown) pin,
    ];
    if (known.length < minimumAgreeing) return null;

    final TouristLocation median = TouristLocation(
      latitude: _median(<double>[
        for (final TouristLocation p in known) p.latitude,
      ]),
      longitude: _median(<double>[
        for (final TouristLocation p in known) p.longitude,
      ]),
    );
    final List<TouristLocation> agreeing = <TouristLocation>[
      for (final TouristLocation pin in known)
        if (distanceMetres(median, pin) <= radiusMetres) pin,
    ];
    if (agreeing.length < minimumAgreeing) return null;

    return TouristLocation(
      latitude: _median(<double>[
        for (final TouristLocation p in agreeing) p.latitude,
      ]),
      longitude: _median(<double>[
        for (final TouristLocation p in agreeing) p.longitude,
      ]),
    );
  }

  /// Haversine distance in metres - the same formula the landmark flow uses,
  /// kept here so these rules stay pure and depend on nothing.
  static double distanceMetres(TouristLocation a, TouristLocation b) {
    const double earthRadius = 6371000;
    final double dLat = _radians(b.latitude - a.latitude);
    final double dLng = _radians(b.longitude - a.longitude);
    final double h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_radians(a.latitude)) *
            math.cos(_radians(b.latitude)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  static double _radians(double degrees) => degrees * math.pi / 180;

  /// The median of [values] (the average of the two middles when the count is
  /// even). Sorts a copy - callers keep their list.
  static double _median(List<double> values) {
    final List<double> sorted = List<double>.of(values)..sort();
    final int middle = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[middle];
    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

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

  /// Picks the closure the reporters agreed on, as the END DATE they meant.
  ///
  /// Every claim is normalised to `createdAt + duration days`, so STAGGERED
  /// reports of the same closure vote together - "15 days" filed three days
  /// ago and "12 days" filed today are the same end date instead of
  /// fragmenting the tally by day-count (user's design, 2026-09-14). The
  /// most-voted END DAY (Malaysia calendar day - voters mean "the 26th",
  /// whatever hour they filed) wins; ties go to the LATER day so a place is
  /// never re-opened early. The returned instant is the LATEST end stamp of
  /// the winning day; it is stored as `closed_until` verbatim, so a date
  /// already in the past simply means the place reads as open again. Returns
  /// null when [claims] is empty or none carries a closure payload.
  static DateTime? resolveClosureUntil(List<ClosureClaim> claims) {
    if (claims.isEmpty) return null;
    final Map<int, List<DateTime>> endsByDay = <int, List<DateTime>>{};
    for (final ClosureClaim claim in claims) {
      final ProposedClosure? parsed = parseTemporaryClosurePayload(
        claim.payload,
      );
      if (parsed == null) continue;
      final DateTime end = claim.createdAt.toUtc().add(
        Duration(days: closureDurationDays(parsed)),
      );
      // Group by the Malaysia calendar day the end falls on - two voters
      // meaning "the 26th" must land in one bucket whatever hour they filed.
      final DateTime local = end.add(const Duration(hours: 8));
      final int day = local.year * 10000 + local.month * 100 + local.day;
      endsByDay.putIfAbsent(day, () => <DateTime>[]).add(end);
    }
    if (endsByDay.isEmpty) return null;
    int bestDay = 0;
    int bestCount = 0;
    // Descending order + strictly-greater keeps the LATER day on ties.
    final List<int> days = endsByDay.keys.toList()
      ..sort((int a, int b) => b.compareTo(a));
    for (final int day in days) {
      if (endsByDay[day]!.length > bestCount) {
        bestCount = endsByDay[day]!.length;
        bestDay = day;
      }
    }
    DateTime latest = endsByDay[bestDay]!.first;
    for (final DateTime end in endsByDay[bestDay]!) {
      if (end.isAfter(latest)) latest = end;
    }
    return latest;
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

  /// Days represented by a closure of [amount] [unit]s - what the closure
  /// resolution adds to a claim's `created_at` to find the END DATE it meant.
  /// Months are approximated as 30 days (the app has no calendar dependency;
  /// close enough for a moderation flag).
  static int closureDurationDays(ProposedClosure closure) =>
      closure.unit == ClosureUnit.days ? closure.amount : closure.amount * 30;
}
