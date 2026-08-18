/// "Goes well with" - one dish paired with another. [score] is 0..1.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class FoodPairing {
  const FoodPairing({
    required this.localFoodId,
    required this.pairedLocalFoodId,
    required this.pairedFoodName,
    required this.score,
    required this.reason,
  });

  final int localFoodId;
  final int pairedLocalFoodId;
  final String pairedFoodName;
  final double score;
  final String reason;
}
