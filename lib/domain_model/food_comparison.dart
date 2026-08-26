import 'local_food.dart';

/// Which slot in the side-by-side comparison a quick-switch replaces.
enum ComparisonSide { left, right }

/// Whether a dish fits the tourist's active dietary restrictions.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class DietaryAssessment {
  const DietaryAssessment({required this.isSuitable, required this.message});

  final bool isSuitable;
  final String message;
}

/// A side-by-side comparison of two or more dishes.
/// [foodNames] is in the same order as [foodIds], and [foods] holds the full
/// [LocalFood] objects the UI renders (images, ingredients, prices, ...).
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class FoodComparison {
  const FoodComparison({
    required this.foodIds,
    required this.foodNames,
    required this.rows,
    this.foods = const <LocalFood>[],
    this.activeTouristRestrictions = const <String>[],
    this.leftDietaryAssessment = const DietaryAssessment(
      isSuitable: true,
      message: 'No dietary restrictions to check.',
    ),
    this.rightDietaryAssessment = const DietaryAssessment(
      isSuitable: true,
      message: 'No dietary restrictions to check.',
    ),
  });

  final List<int> foodIds;
  final List<String> foodNames;
  final List<ComparisonRow> rows;

  /// Full dishes in the same order as [foodIds].
  final List<LocalFood> foods;

  /// The tourist's saved restrictions the comparison was checked against.
  final List<String> activeTouristRestrictions;

  /// Dietary fit of the left / right dish.
  final DietaryAssessment leftDietaryAssessment;
  final DietaryAssessment rightDietaryAssessment;

  /// First compared dish. Valid because a comparison is only built with at
  /// least two dishes.
  LocalFood get leftFood => foods[0];

  /// Second compared dish. Valid because a comparison is only built with at
  /// least two dishes.
  LocalFood get rightFood => foods[1];
}

/// One attribute compared across every column. [values] has one entry per
/// compared dish, in the same order as `FoodComparison.foodIds`.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class ComparisonRow {
  const ComparisonRow({
    required this.attribute,
    required this.values,
    required this.isDifference,
  });

  final String attribute;
  final List<String> values;
  final bool isDifference;
}
