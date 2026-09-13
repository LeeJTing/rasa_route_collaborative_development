import '../../domain_model/opening_hour.dart';

/// The confidence the stored schedule gives about a place at one instant.
///
/// Missing, unknown, or malformed scraped hours are [unknown], never closed.
/// Discovery features may therefore exclude [closed] without inventing a
/// closure for places whose source data is incomplete.
enum OpeningHoursAvailability { open, closed, unknown }

class OpeningHoursLogic {
  const OpeningHoursLogic._();

  /// The encoded close for a row being edited: a selected closing time at or
  /// BEFORE the opening time means the NEXT day - "10:00 -> 02:00" is
  /// `600 -> 1560`, i.e. minutes past midnight plus 1440 (see
  /// `OpeningHoursRows` for how that is stored). A closing time after the
  /// opening stays same-day. `24:00` and `00:00` both mean midnight, so they
  /// encode to 1440 whatever the opening time.
  static int encodeClose({required int opensAt, required int closeMinutes}) {
    final int raw = closeMinutes % 1440;
    return raw <= opensAt ? raw + 1440 : raw;
  }

  static OpeningHoursAvailability availabilityAt(
    List<OpeningHour>? hours,
    DateTime malaysiaTime,
  ) {
    if (hours == null || hours.isEmpty) {
      return OpeningHoursAvailability.unknown;
    }

    final Weekday today = Weekday.values[malaysiaTime.weekday - 1];
    final Weekday previous =
        Weekday.values[(malaysiaTime.weekday + Weekday.values.length - 2) %
            Weekday.values.length];
    final int minute = malaysiaTime.hour * 60 + malaysiaTime.minute;

    for (final OpeningHour row in hours) {
      if (row.day != previous || row.status != DayStatus.open) continue;
      final int? opens = row.opensAt;
      final int? closes = row.closesAt;
      if (opens == null || closes == null) continue;
      // "Ran into today" is encoded two ways: the editor's next-day close
      // (closesAt > 1440 - Monday 600 -> 1560) and a wrapped close
      // (closes < opens) some sources use. Both end in the small hours.
      final int morningEnd = closes > 1440
          ? closes - 1440
          : (closes < opens ? closes : 0);
      if (morningEnd > 0 && minute < morningEnd) {
        return OpeningHoursAvailability.open;
      }
    }

    final List<OpeningHour> todayRows = hours
        .where((OpeningHour row) => row.day == today)
        .toList(growable: false);
    if (todayRows.isEmpty) return OpeningHoursAvailability.unknown;

    bool containsUnknown = false;
    bool containsUsableSchedule = false;
    for (final OpeningHour row in todayRows) {
      if (row.status == DayStatus.unknown) {
        containsUnknown = true;
        continue;
      }
      if (row.status == DayStatus.closed) {
        containsUsableSchedule = true;
        continue;
      }

      final int? opens = row.opensAt;
      final int? closes = row.closesAt;
      if (opens == null || closes == null) {
        containsUnknown = true;
        continue;
      }
      containsUsableSchedule = true;
      final bool openNow = closes == 1440
          ? minute >= opens
          : closes < opens
          ? minute >= opens
          : minute >= opens && minute < closes;
      if (openNow) return OpeningHoursAvailability.open;
    }

    if (containsUnknown || !containsUsableSchedule) {
      return OpeningHoursAvailability.unknown;
    }
    return OpeningHoursAvailability.closed;
  }

  static bool isConfidentlyClosedAt(
    List<OpeningHour>? hours,
    DateTime malaysiaTime,
  ) => availabilityAt(hours, malaysiaTime) == OpeningHoursAvailability.closed;

  static bool isConfidentlyOpenAt(
    List<OpeningHour>? hours,
    DateTime malaysiaTime,
  ) => availabilityAt(hours, malaysiaTime) == OpeningHoursAvailability.open;
}
