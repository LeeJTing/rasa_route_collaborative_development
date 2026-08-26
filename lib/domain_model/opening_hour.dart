/// One opening-hours row for a landmark - matches the real `OpeningHours`
/// table directly: `(day, status, opening_time, closing_time)` per row, not
/// a day-level wrapper holding a list. There is no separate "range" concept
/// - a row *is* a range.
///
/// A day can have more than one row when [DayStatus.open] (e.g. a midday
/// closure: one row "12:00-14:00", another "15:00-20:00" - both rows share
/// the same [day] and [status], differing only in their own times).
/// [DayStatus.closed] and [DayStatus.unknown] days have exactly one row,
/// with [opensAt]/[closesAt] left null - there's nothing to carry for them.
///
/// [id] is `0` for a row not yet saved, same convention used throughout
/// this codebase (e.g. `LocalFood.id`, `LandmarkItem.id`).
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class OpeningHour {
  const OpeningHour({
    required this.id,
    required this.day,
    required this.status,
    this.opensAt,
    this.closesAt,
  });

  final int id;
  final Weekday day;

  /// Whether this row is confidently open, confidently closed, or not
  /// known either way (Figma "Form 1" - Saturday shows this: rendered as a
  /// distinct third state, not just a lighter shade of one of the other
  /// two).
  final DayStatus status;

  /// Minutes since midnight (0-1440, where 1440 is "24:00" - see
  /// `_TimeDropdown` in `add_landmark_view.dart`). Only meaningful for
  /// [DayStatus.open].
  final int? opensAt;
  final int? closesAt;
}

enum Weekday { monday, tuesday, wednesday, thursday, friday, saturday, sunday }

/// A landmark's confirmed status for one day of the week (BF-19..23, A14,
/// A15). Not a plain open/closed boolean - [unknown] exists because a
/// tourist reporting a landmark may simply not know the hours for a given
/// day (e.g. they never saw it open on that day), and shouldn't have to
/// guess or commit to a definitive answer either way.
enum DayStatus { open, unknown, closed }
