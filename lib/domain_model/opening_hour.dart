/// Opening hours for one day, for a restaurant or a landmark.
/// [opensAt] and [closesAt] are minutes since midnight, null when closed.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class OpeningHour {
  const OpeningHour({
    required this.id,
    required this.day,
    this.opensAt,
    this.closesAt,
  });

  final int id;
  final Weekday day;
  final int? opensAt;
  final int? closesAt;
}

enum Weekday { monday, tuesday, wednesday, thursday, friday, saturday, sunday }
