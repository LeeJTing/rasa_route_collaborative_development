/// What a [FoodPreference] is. Each `food_preference` row holds ONE value -
/// either a taste or a culture/category - never both (the other column is
/// null).
enum FoodPreferenceKind {
  /// e.g. "Sweet", "Sour", "Spicy".
  taste,

  /// e.g. "Malay", "Chinese", "Nyonya".
  category,
}

/// One food preference a tourist can hold - a single taste OR a single
/// culture/category option. Maps 1:1 to a `food_preference` table row.
///
/// A tourist holds MANY of these, linked through the `personalised_preference`
/// junction - which is why `Tourist` carries `List<FoodPreference>`, exactly
/// like `List<DietaryRestriction>`.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class FoodPreference {
  const FoodPreference({
    required this.id,
    required this.kind,
    required this.name,
  });

  /// `food_preference.food_preference_id` (bigint identity, PK).
  final int id;

  /// Whether this preference is a taste or a category.
  final FoodPreferenceKind kind;

  /// The value - e.g. "Sweet" (kind taste) or "Malay" (kind category).
  final String name;
}
