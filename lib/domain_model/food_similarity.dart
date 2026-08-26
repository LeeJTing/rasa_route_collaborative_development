/// "If you liked X, try Y" - similarity between two dishes. [score] is 0..1.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class FoodSimilarity {
  const FoodSimilarity({
    required this.localFoodId,
    required this.similarLocalFoodId,
    required this.similarFoodName,
    required this.score,
    required this.sharedAttributes,
  });

  final int localFoodId;
  final int similarLocalFoodId;
  final String similarFoodName;
  final double score;
  final List<String> sharedAttributes;
}
