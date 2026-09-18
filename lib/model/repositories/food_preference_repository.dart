import '../../core/json_model.dart';
import '../../domain_model/food_preference.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../data_models/food_preference_data_model.dart';

/// Canonical taste/category options from `food_preference`.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`), then
/// converts that data model into a **domain model** for everything above.
class FoodPreferenceRepository {
  FoodPreferenceRepository();

  final APIManager api = APIManager();

  /// The canonical taste values (`food_preference.preferred_taste`) - the
  /// reference set taste tags are normalised against (Sweet, Salty, Sour,
  /// Spicy, Rich, ...). Deduplicated, empty values dropped.
  Future<List<String>> tasteOptions() async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableFoodPreference,
      columns: 'preferred_taste',
    );
    return <String>{
      for (final Map<String, dynamic> row in rows)
        if (row['preferred_taste'] is String &&
            (row['preferred_taste'] as String).isNotEmpty)
          row['preferred_taste'] as String,
    }.toList(growable: false);
  }

  Future<List<FoodPreference>> currentTouristPreferences() async {
    final String touristId = await api.resolveCurrentTouristId();
    if (touristId.isEmpty) return const <FoodPreference>[];
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tablePersonalisedPreference,
      columns:
          'food_preference(food_preference_id, preferred_taste, preferred_categories)',
      eq: <String, Object?>{'tourist_id': touristId},
    );
    return rows
        .map((Map<String, dynamic> row) {
          final Map<String, dynamic> embedded = JsonReader.asMap(
            row['food_preference'],
          );
          if (embedded.isEmpty || embedded['food_preference_id'] == null) {
            return null;
          }
          final FoodPreferenceDataModel data = FoodPreferenceDataModel.fromJson(
            embedded,
          );
          final String? taste = data.preferredTaste?.trim();
          if (taste != null && taste.isNotEmpty) {
            return FoodPreference(
              id: data.foodPreferenceId,
              kind: FoodPreferenceKind.taste,
              name: taste,
            );
          }
          final String? category = data.preferredCategories?.trim();
          if (category != null && category.isNotEmpty) {
            return FoodPreference(
              id: data.foodPreferenceId,
              kind: FoodPreferenceKind.category,
              name: category,
            );
          }
          return null;
        })
        .whereType<FoodPreference>()
        .toList(growable: false);
  }

  /// Taste and category name -> id lookups (lowercased), so a recognized
  /// food's taste tags / category can be normalised against the canonical
  /// `food_preference` rows before writing `local_food_preference` links
  /// (mirrors the scraper's `taste_by_name` / `category_by_name`).
  Future<({Map<String, int> tastes, Map<String, int> categories})>
  preferenceIdLookup() async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableFoodPreference,
      columns: 'food_preference_id, preferred_taste, preferred_categories',
    );
    final Map<String, int> tastes = <String, int>{};
    final Map<String, int> categories = <String, int>{};
    for (final Map<String, dynamic> row in rows) {
      final FoodPreferenceDataModel preference =
          FoodPreferenceDataModel.fromJson(row);
      final String? taste = preference.preferredTaste;
      if (taste != null && taste.trim().isNotEmpty) {
        tastes.putIfAbsent(
          taste.trim().toLowerCase(),
          () => preference.foodPreferenceId,
        );
      }
      final String? category = preference.preferredCategories;
      if (category != null && category.trim().isNotEmpty) {
        categories.putIfAbsent(
          category.trim().toLowerCase(),
          () => preference.foodPreferenceId,
        );
      }
    }
    return (tastes: tastes, categories: categories);
  }
}
