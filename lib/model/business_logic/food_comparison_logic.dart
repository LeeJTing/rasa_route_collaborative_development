import 'package:meta/meta.dart' show visibleForTesting;

import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_comparison.dart';
import '../../domain_model/food_preference.dart';
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

    Map<int, List<({String name, double price})>> menuItemsByFoodId =
        const <int, List<({String name, double price})>>{};
    try {
      menuItemsByFoodId = await repository.foodMenuItems(
        foods.map((LocalFood food) => food.id).toSet(),
      );
    } catch (_) {
      menuItemsByFoodId =
          const <int, List<({String name, double price})>>{};
    }

    // Preference matching is best-effort too: a signed-out tourist (or a
    // profile read that fails) simply has nothing to match on.
    List<FoodPreference> preferences;
    try {
      preferences = await repository.touristFoodPreferences();
    } catch (_) {
      preferences = const <FoodPreference>[];
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
      menuItemsByFoodId: menuItemsByFoodId,
      preferenceSuggestion: preferenceSuggestionFor(foods, preferences),
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
  /// when there is nothing to match against - including when BOTH dishes
  /// conflict (no dish is safe to recommend).
  LocalFood? bestDietaryMatch(FoodComparison comparison) {
    final List<LocalFood> foods = comparison.foods;
    if (foods.length < 2) return null;
    if (comparison.activeTouristRestrictions.isEmpty) return null;
    final bool leftOk = comparison.leftDietaryAssessment.isSuitable;
    final bool rightOk = comparison.rightDietaryAssessment.isSuitable;
    if (leftOk != rightOk) return leftOk ? foods[0] : foods[1];
    if (leftOk) return foods[0];
    // Both dishes conflict - do not pretend one is a safe match.
    return null;
  }

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

  @visibleForTesting
  String? preferenceSuggestionFor(
    List<LocalFood> foods,
    List<FoodPreference> preferences,
  ) {

    final List<_SavedPreference> saved = <_SavedPreference>[
      for (final FoodPreference preference in preferences)
        for (final String value in _splitRaw(preference.name))
          _SavedPreference(preference.kind, _normalise(value), value),
    ];
    if (foods.length < 2 || saved.isEmpty) return null;

    final List<_PreferenceMatch> scored = <_PreferenceMatch>[
      for (final LocalFood food in foods)
        _PreferenceMatch(food, _matchesFor(food, saved)),
    ];
    int best = 0;
    for (final _PreferenceMatch entry in scored) {
      if (entry.matches.length > best) best = entry.matches.length;
    }
    if (best == 0) return null;

    final List<_PreferenceMatch> winners = scored
        .where((_PreferenceMatch entry) => entry.matches.length == best)
        .toList(growable: false);
    final String matched = winners.first.matches.join(', ');
    if (winners.length > 1) {
      final String names = winners
          .map((_PreferenceMatch entry) => entry.food.name)
          .join(' and ');
      return 'Your saved preferences ($matched) fit $names equally - '
          'try either one.';
    }
    return 'Based on your saved preferences ($matched), '
        '${winners.first.food.name} is the closest to your taste - '
        'give it a try.';
  }

  /// The saved preference values [food] satisfies - its tastes plus its
  /// culture/category.
  List<String> _matchesFor(LocalFood food, List<_SavedPreference> saved) {
    final Set<String> tastes = food.tastes.map(_normalise).toSet();
    final Set<String> categories = _splitValues(food.category);
    final List<String> matched = <String>[];
    for (final _SavedPreference preference in saved) {
      final bool hit = switch (preference.kind) {
        FoodPreferenceKind.taste => tastes.contains(preference.key),
        FoodPreferenceKind.category => categories.contains(preference.key),
      };
      // The same value can be saved more than once; keep the sentence clean.
      if (hit && !matched.contains(preference.label)) {
        matched.add(preference.label);
      }
    }
    return matched;
  }

  String _normalise(String value) => value.trim().toLowerCase();

  /// Splits a stored comma-separated cell, keeping each value as written.
  List<String> _splitRaw(String raw) => raw
      .split(RegExp(r'[,;/|]'))
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty)
      .toList(growable: false);

  Set<String> _splitValues(String raw) =>
      _splitRaw(raw).map(_normalise).toSet();

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

/// One compared dish and the saved preference names it satisfies.
class _PreferenceMatch {
  const _PreferenceMatch(this.food, this.matches);

  final LocalFood food;
  final List<String> matches;
}

/// One saved preference VALUE (a row can hold several): its [kind] decides
/// whether it is matched against a dish's tastes or its culture/category,
/// [key] is the normalised form used for matching and [label] is the value as
/// stored, used in the sentence.
class _SavedPreference {
  const _SavedPreference(this.kind, this.key, this.label);

  final FoodPreferenceKind kind;
  final String key;
  final String label;
}
