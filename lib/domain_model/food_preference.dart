/// A tourist's taste profile, used to rank recommendations.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class FoodPreference {
  const FoodPreference({
    required this.id,
    required this.preferredCategories,
    required this.preferredTastes,
  });

  final int id;
  final List<String> preferredCategories;
  final List<String> preferredTastes;
}
