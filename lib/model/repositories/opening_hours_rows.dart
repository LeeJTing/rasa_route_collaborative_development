import '../../domain_model/opening_hour.dart';

/// Pure helpers for the `opening_hours` table's row shape - the ONE place the
/// overnight split convention is encoded and decoded.
///
/// THE CONVENTION (2026-09-13, matching the dominant stored style: 15,221
/// `24:00` closes + 14,542 `00:00` starts in the restaurant rows):
///
/// The app EDITS an overnight period as ONE row on its starting day, with the
/// close encoded as minutes past midnight PLUS 1440 - "Monday 10:00 -> 02:00
/// next day" is `opensAt: 600, closesAt: 1560` (see `OpeningHour`'s note).
/// The DB's `(day, opening_time, closing_time)` shape cannot carry the close
/// day the way Google's API can (its close point names the next day), so
/// WRITES split it:
///
///     Monday  10:00-24:00   (ends at midnight)
///     Tuesday 00:00-02:00   (the tail - a real opening, so map "open now"
///                            maths keeps working with no wrap logic)
///
/// and READS merge the tail back into the previous day's end-of-day row, so
/// the detail pages show "Monday 10:00 AM - 2:00 AM" the way Google Maps
/// does.
///
/// The merge is HEURISTIC (the owner chose no marker column): a row that
/// STARTS at 00:00 and ENDS before [endOfDayFrom] is a tail when the previous
/// day has a row ending at/after [endOfDayFrom]. A genuine 00:00 opening with
/// no previous end-of-day row stays where it is, and all-day rows
/// (`00:00-23:59:59`) are never tails.
abstract final class OpeningHoursRows {
  const OpeningHoursRows._();

  /// Minutes that count as "runs to the end of the day" when READING stored
  /// closes: `24:00` (1440) and the Google-scraped `23:59` / `23:59:59`
  /// (1439).
  static const int endOfDayFrom = 1439;

  static Weekday dayAfter(Weekday day) =>
      Weekday.values[(day.index + 1) % Weekday.values.length];

  static Weekday dayBefore(Weekday day) =>
      Weekday.values[(day.index + Weekday.values.length - 1) %
          Weekday.values.length];

  /// Whether [row] could be a stored TAIL: an opening that starts at 00:00
  /// and ends in the small hours (before [endOfDayFrom] - so an all-day row
  /// encoded `00:00-23:59:59` is never treated as one).
  static bool isTailCandidate(OpeningHour row) =>
      row.status == DayStatus.open &&
      row.opensAt == 0 &&
      row.closesAt != null &&
      row.closesAt! > 0 &&
      row.closesAt! < endOfDayFrom;

  /// Whether [row] can CARRY a tail - it runs to (or past, when already
  /// merged) the end of its day.
  static bool endsAtEndOfDay(OpeningHour row) =>
      row.status == DayStatus.open &&
      row.opensAt != null &&
      (row.closesAt ?? -1) >= endOfDayFrom;

  /// The merged view of stored [rows]: every tail candidate that follows a
  /// previous-day end-of-day row is folded into it, producing one row per
  /// real opening period (`Monday 600 -> 1560`).
  ///
  /// Pure and order-preserving; a merged row keeps the host row's id (the
  /// tail row is the one that disappears from the view).
  static List<OpeningHour> mergeTails(List<OpeningHour> rows) {
    final Map<Weekday, List<int>> indexesByDay = <Weekday, List<int>>{};
    for (int i = 0; i < rows.length; i++) {
      indexesByDay.putIfAbsent(rows[i].day, () => <int>[]).add(i);
    }

    final Set<int> consumed = <int>{};
    final Map<int, OpeningHour> replaced = <int, OpeningHour>{};

    for (int i = 0; i < rows.length; i++) {
      final OpeningHour candidate = rows[i];
      if (!isTailCandidate(candidate)) continue;
      final List<int>? previous = indexesByDay[dayBefore(candidate.day)];
      if (previous == null) continue;

      // The previous day's LAST row that ends at the end of the day hosts
      // the tail. (Its own tail candidate rows cannot host - they do not
      // reach [endOfDayFrom].)
      int? host;
      for (final int index in previous) {
        if (consumed.contains(index)) continue;
        final OpeningHour row = replaced[index] ?? rows[index];
        if (endsAtEndOfDay(row)) host = index;
      }
      if (host == null) continue;

      final OpeningHour base = replaced[host] ?? rows[host];
      replaced[host] = OpeningHour(
        id: base.id,
        day: base.day,
        status: base.status,
        opensAt: base.opensAt,
        closesAt: 1440 + candidate.closesAt!,
      );
      consumed.add(i);
    }

    return List<OpeningHour>.unmodifiable(<OpeningHour>[
      for (int i = 0; i < rows.length; i++)
        if (!consumed.contains(i)) replaced[i] ?? rows[i],
    ]);
  }

  /// The stored rows for ONE edited row: a same-day row is written as
  /// itself; an overnight row (`closesAt > 1440`) becomes the end-of-day row
  /// plus the next-day tail. Non-Open rows return just themselves.
  static List<OpeningHour> splitForStorage(OpeningHour row) {
    final int? closesAt = row.closesAt;
    if (row.status != DayStatus.open ||
        row.opensAt == null ||
        closesAt == null ||
        closesAt <= 1440) {
      return <OpeningHour>[row];
    }
    return <OpeningHour>[
      OpeningHour(
        id: 0,
        day: row.day,
        status: DayStatus.open,
        opensAt: row.opensAt,
        closesAt: 1440,
      ),
      OpeningHour(
        id: 0,
        day: dayAfter(row.day),
        status: DayStatus.open,
        opensAt: 0,
        closesAt: closesAt - 1440,
      ),
    ];
  }

  /// The tail [day]'s overnight row wrote onto the NEXT day, or null when
  /// [day] has no overnight period. Read from the MERGED view (so
  /// `closesAt > 1440` is the signal).
  static OpeningHour? tailOf(
    Map<Weekday, List<OpeningHour>> mergedByDay,
    Weekday day,
  ) {
    for (final OpeningHour row in mergedByDay[day] ?? const <OpeningHour>[]) {
      final int? closesAt = row.closesAt;
      if (row.status == DayStatus.open &&
          row.opensAt != null &&
          closesAt != null &&
          closesAt > 1440) {
        return OpeningHour(
          id: 0,
          day: dayAfter(day),
          status: DayStatus.open,
          opensAt: 0,
          closesAt: closesAt - 1440,
        );
      }
    }
    return null;
  }
}
