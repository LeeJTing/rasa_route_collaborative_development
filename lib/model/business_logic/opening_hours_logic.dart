import '../../domain_model/opening_hour.dart';

/// The confidence the stored schedule gives about a place at one instant.
///
/// Missing, unknown, or malformed scraped hours are [unknown], never closed.
/// Discovery features may therefore exclude [closed] without inventing a
/// closure for places whose source data is incomplete.
enum OpeningHoursAvailability { open, closed, unknown }

class OpeningHoursLogic {
  const OpeningHoursLogic._();

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
      if (opens != null &&
          closes != null &&
          closes < opens &&
          minute < closes) {
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
