import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_comparison.dart';
import '../../domain_model/local_food.dart';
import '../repositories/food_repository_facade.dart';

/// Builds the side-by-side comparison of two or more dishes.
///
/// A business-logic class knows exactly one thing below it: a **repository
/// facade**. It never sees a repository, a shared client or Flutter.
class FoodComparisonLogic {
  FoodComparisonLogic();

  final FoodRepositoryFacade repository = FoodRepositoryFacade();

  /// Fetches the dishes and builds a [FoodComparison] with the per-attribute
  /// rows, dietary assessments and the full [LocalFood] list for the UI.
  ///
  /// Dietary safety is driven by the database relations: a dish is flagged
  /// "not suitable" only when a restriction attached to it via
  /// `food_dietary_restriction` matches one the tourist holds via
  /// `user_dietary_restriction` (keyed by the signed-in tourist id).
  ///
  /// Requires at least two dishes.
  Future<FoodComparison> buildComparison(List<int> foodIds) async {
    final List<LocalFood> foods = <LocalFood>[];
    for (final int id in foodIds) {
      final LocalFood? food = await repository.getFoodById(id);
      if (food != null) foods.add(food);
    }
    if (foods.length < 2) {
      throw Exception('Select at least 2 local foods to compare.');
    }

    // Dietary safety is best-effort: if the restriction relation queries fail
    // (e.g. the `dietary_restriction(...)` FK embed isn't set up in Supabase),
    // degrade to "no conflicts" instead of crashing with a PostgrestException.
    List<DietaryRestriction> touristRestrictions;
    try {
      touristRestrictions = await repository.touristDietaryRestrictions();
    } catch (_) {
      touristRestrictions = const <DietaryRestriction>[];
    }
    final Set<int> touristRestrictionIds = touristRestrictions
        .map((DietaryRestriction r) => r.id)
        .toSet();
    final Map<int, Set<int>> foodRestrictionIds = <int, Set<int>>{};
    for (final LocalFood food in foods) {
      List<DietaryRestriction> restrictions;
      try {
        restrictions = await repository.foodDietaryRestrictions(food.id);
      } catch (_) {
        restrictions = const <DietaryRestriction>[];
      }
      foodRestrictionIds[food.id] = restrictions
          .map((DietaryRestriction restriction) => restriction.id)
          .toSet();
    }

    return FoodComparison(
      foodIds: foods.map((LocalFood food) => food.id).toList(growable: false),
      foodNames: foods
          .map((LocalFood food) => food.name)
          .toList(growable: false),
      rows: _buildRows(foods),
      foods: foods,
      activeTouristRestrictions: touristRestrictions
          .map((DietaryRestriction r) => r.name)
          .toList(growable: false),
      leftDietaryAssessment: _assess(
        foodRestrictionIds: foodRestrictionIds[foods[0].id] ?? const <int>{},
        touristRestrictionIds: touristRestrictionIds,
        touristRestrictions: touristRestrictions,
      ),
      rightDietaryAssessment: _assess(
        foodRestrictionIds: foodRestrictionIds[foods[1].id] ?? const <int>{},
        touristRestrictionIds: touristRestrictionIds,
        touristRestrictions: touristRestrictions,
      ),
    );
  }

  /// The dish that best fits [comparison]'s active restrictions, or `null`
  /// when there is nothing to match against.
  LocalFood? bestDietaryMatch(FoodComparison comparison) {
    final List<LocalFood> foods = comparison.foods;
    if (foods.length < 2) return null;
    if (comparison.activeTouristRestrictions.isEmpty) return null;
    final bool leftOk = comparison.leftDietaryAssessment.isSuitable;
    final bool rightOk = comparison.rightDietaryAssessment.isSuitable;
    if (leftOk != rightOk) return leftOk ? foods[0] : foods[1];
    return foods[0];
  }

  /// The dish with the best restaurant price value.
  ///
  /// Restaurant prices are not modelled yet, so there is no value ranking to
  /// compute - callers fall back to a "Not enough price data" message.
  LocalFood? bestValueFood(FoodComparison comparison) => null;

  /// Flags a dish "not suitable" only when a restriction attached to it
  /// ([foodRestrictionIds]) is one the tourist also holds
  /// ([touristRestrictionIds]). Otherwise it is suitable for them.
  DietaryAssessment _assess({
    required Set<int> foodRestrictionIds,
    required Set<int> touristRestrictionIds,
    required List<DietaryRestriction> touristRestrictions,
  }) {
    if (touristRestrictionIds.isEmpty) {
      return const DietaryAssessment(
        isSuitable: true,
        message: 'No dietary restrictions saved for this tourist.',
      );
    }
    final Set<int> matched = foodRestrictionIds.intersection(
      touristRestrictionIds,
    );
    if (matched.isEmpty) {
      return const DietaryAssessment(
        isSuitable: true,
        message: 'No dietary restriction conflicts found.',
      );
    }
    final String message = touristRestrictions
        .where((DietaryRestriction r) => matched.contains(r.id))
        .map((DietaryRestriction r) => _restrictionMessage(r.name))
        .join('; ');
    return DietaryAssessment(isSuitable: false, message: message);
  }

  /// Turns a restriction name into a user-facing warning phrase, e.g.
  /// "No Pork" -> "Contains pork", "Vegetarian" -> "Vegetarian cannot eat".
  String _restrictionMessage(String restrictionName) {
    final String trimmed = restrictionName.trim();
    if (trimmed.toLowerCase().startsWith('no ')) {
      final String subject = trimmed.substring(3).trim().toLowerCase();
      if (subject.isNotEmpty) return 'Contains $subject';
    }
    return '$trimmed cannot eat';
  }

  List<ComparisonRow> _buildRows(List<LocalFood> foods) {
    return <ComparisonRow>[
      _row('Origin', foods.map((LocalFood f) => f.origin).toList()),
      _row(
        'Cooking style',
        foods.map((LocalFood f) => f.cookingStyle).toList(),
      ),
      _row('Meal type', foods.map((LocalFood f) => f.mealType).toList()),
      _row('Food type', foods.map((LocalFood f) => f.foodType).toList()),
      _row('Taste', foods.map((LocalFood f) => f.tastes.join(', ')).toList()),
      _row('Description', foods.map((LocalFood f) => f.description).toList()),
    ];
  }

  ComparisonRow _row(String attribute, List<String> values) {
    return ComparisonRow(
      attribute: attribute,
      values: values,
      isDifference: values.toSet().length > 1,
    );
  }
}
