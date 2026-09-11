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
