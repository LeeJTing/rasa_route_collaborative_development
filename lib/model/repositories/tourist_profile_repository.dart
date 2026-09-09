import '../../core/json_model.dart';
import '../../domain_model/dietary_restriction.dart';
import '../../domain_model/food_preference.dart';
import '../../domain_model/tourist.dart';
import '../../model/data_models/dietary_restriction_data_model.dart';
import '../../model/data_models/food_preference_data_model.dart';
import '../../model/data_models/tourist_data_model.dart';
import '../../shared_client/api_manager/api_manager.dart';

/// The tourist's profile, preferences and dietary restrictions.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`), then
/// converts that data model into a **domain model** for everything above.
///
/// Tables involved (all keyed by `tourist.tourist_id`, NOT the auth user id):
///   * `tourist` - identity only (`tourist_id` + `id` -> auth user).
///   * `personalised_preference` -> `food_preference` - the tastes/categories
///     the tourist picked (one `food_preference` row per value).
///   * `user_dietary_restriction` -> `dietary_restriction` - the restrictions
///     the tourist holds.
///   * `favourite_food` - the local foods the tourist saved.
///
/// Everything above resolves the signed-in `tourist_id` first (via
/// `AuthRepository.currentTouristId`) and hands it in; this class never looks
/// at the auth session.
class TouristProfileRepository {
  TouristProfileRepository();

  final APIManager api = APIManager();

  // ---------------------------------------------------------------------------
  // The tourist as a whole
  // ---------------------------------------------------------------------------

  /// The full profile for [touristId]: identity (from the `tourist` row and
  /// the caller's auth info) plus the food preference and dietary
  /// restrictions pulled from their junction tables. `null` when the id
  /// matches no `tourist` row.
  ///
  /// The two section queries load independently and degrade to empty on their
  /// own failure. Previously a broken junction table (e.g. missing
  /// `user_dietary_restriction`, or RLS denying it) threw out of this method
  /// and blanked the WHOLE profile - food preferences AND email - even though
  /// the `tourist` row itself was fine. Now only the broken section is empty.
  Future<Tourist?> getTourist({
    required String touristId,
    String authUserId = '',
    String email = '',
    String displayName = '',
  }) async {
    final Map<String, dynamic>? row = await api.selectOne(
      APIManager.tableTourist,
      columns: 'tourist_id, id',
      eq: <String, Object?>{'tourist_id': touristId},
    );
    if (row == null) return null;
    final TouristDataModel data = TouristDataModel.fromJson(row);

    return Tourist(
      touristId: data.touristId,
      authUserId: data.authUserId,
      email: email,
      displayName: displayName,
      foodPreferences: await _loadSafely<FoodPreference>(
        () => getFoodPreferences(touristId),
      ),
      dietaryRestrictions: await _loadSafely<DietaryRestriction>(
        () => getDietaryRestrictions(touristId),
      ),
    );
  }

  /// Runs [fetch] and returns its result, or an empty list when it fails - a
  /// broken profile section must not blank the rest of the profile.
  Future<List<T>> _loadSafely<T>(Future<List<T>> Function() fetch) async {
    try {
      return await fetch();
    } catch (_) {
      return <T>[];
    }
  }

  // ---------------------------------------------------------------------------
  // Food preference (tastes + categories)
  // ---------------------------------------------------------------------------

  /// Every food preference [touristId] has picked, from the
  /// `personalised_preference` junction. Empty when nothing picked yet.
  Future<List<FoodPreference>> getFoodPreferences(String touristId) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tablePersonalisedPreference,
      columns:
          'food_preference(food_preference_id, preferred_taste, preferred_categories)',
      eq: <String, Object?>{'tourist_id': touristId},
    );
    return rows
        .map(_foodPreferenceFromRow)
        .whereType<FoodPreference>()
        .toList(growable: false);
  }

  /// Every selectable food preference from `food_preference` - each row is ONE
  /// taste or ONE category, so the list mixes both kinds (the caller groups
  /// them via [FoodPreference.kind]).
  Future<List<FoodPreference>> foodPreferenceOptions() async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableFoodPreference,
      orderBy: 'food_preference_id',
    );
    return rows
        .map(
          (Map<String, dynamic> row) => _foodPreferenceFromDataModel(
            FoodPreferenceDataModel.fromJson(row),
          ),
        )
        .whereType<FoodPreference>()
        .toList(growable: false);
  }

  /// Replaces [touristId]'s whole preference selection: deletes their
  /// `personalised_preference` rows, then re-inserts one row per selected
  /// `food_preference_id`.
  Future<void> saveFoodPreferences(
    String touristId,
    List<int> preferenceIds,
  ) async {
    final Set<int> unique = <int>{...preferenceIds}
      ..removeWhere((int id) => id <= 0);

    await api.deleteRows(
      APIManager.tablePersonalisedPreference,
      eq: <String, Object?>{'tourist_id': touristId},
    );
    for (final int id in unique) {
      await api.insertRow(
        APIManager.tablePersonalisedPreference,
        <String, dynamic>{'tourist_id': touristId, 'food_preference_id': id},
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Dietary restrictions
  // ---------------------------------------------------------------------------

  /// Every restriction [touristId] holds, via `user_dietary_restriction`.
  Future<List<DietaryRestriction>> getDietaryRestrictions(
    String touristId,
  ) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableUserDietaryRestriction,
      columns: 'dietary_restriction(dietary_restriction_id, restriction_name)',
      eq: <String, Object?>{'tourist_id': touristId},
    );
    return rows
        .map(_dietaryFromRow)
        .whereType<DietaryRestriction>()
        .toList(growable: false);
  }

  /// Every restriction a tourist can pick, from `dietary_restriction`.
  Future<List<DietaryRestriction>> dietaryRestrictionOptions() async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableDietaryRestriction,
      orderBy: 'restriction_name',
    );
    return rows
        .map((Map<String, dynamic> row) {
          final DietaryRestrictionDataModel data =
              DietaryRestrictionDataModel.fromJson(row);
          return DietaryRestriction(
            id: data.dietaryRestrictionId,
            name: data.restrictionName,
          );
        })
        .toList(growable: false);
  }

  /// Replaces [touristId]'s whole restriction selection: deletes their
  /// `user_dietary_restriction` rows, then re-inserts one row per id.
  Future<void> saveDietaryRestrictions(
    String touristId,
    List<int> restrictionIds,
  ) async {
    final Set<int> unique = <int>{...restrictionIds}
      ..removeWhere((int id) => id <= 0);

    await api.deleteRows(
      APIManager.tableUserDietaryRestriction,
      eq: <String, Object?>{'tourist_id': touristId},
    );
    for (final int id in unique) {
      await api.insertRow(
        APIManager.tableUserDietaryRestriction,
        <String, dynamic>{
          'tourist_id': touristId,
          'dietary_restriction_id': id,
        },
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Favourites
  // ---------------------------------------------------------------------------

  /// The local-food ids [touristId] has saved (`favourite_food`), or an empty
  /// set when none. The screen joins these against the catalogue (owned by the
  /// food module) rather than parsing `local_food` rows here.
  Future<Set<int>> favouriteFoodIds(String touristId) async {
    if (touristId.isEmpty) return <int>{};
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableFavouriteFood,
      columns: 'local_food_id',
      eq: <String, Object?>{'tourist_id': touristId},
    );
    return rows
        .map(
          (Map<String, dynamic> row) => JsonReader.asInt(row['local_food_id']),
        )
        .where((int id) => id > 0)
        .toSet();
  }

  /// Removes one saved dish from [touristId]'s `favourite_food` rows.
  Future<void> removeFavourite(String touristId, int localFoodId) async {
    await api.deleteRows(
      APIManager.tableFavouriteFood,
      eq: <String, Object?>{
        'tourist_id': touristId,
        'local_food_id': localFoodId,
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Row helpers
  // ---------------------------------------------------------------------------

  /// Parses a row holding an embedded `food_preference(...)` object into the
  /// domain; `null` when the embed is missing.
  FoodPreference? _foodPreferenceFromRow(Map<String, dynamic> row) {
    final Map<String, dynamic> embedded = JsonReader.asMap(
      row['food_preference'],
    );
    if (embedded.isEmpty || embedded['food_preference_id'] == null) {
      return null;
    }
    return _foodPreferenceFromDataModel(
      FoodPreferenceDataModel.fromJson(embedded),
    );
  }

  /// Data model -> domain. A row is a taste when `preferred_taste` is filled
  /// and a category when `preferred_categories` is; a row with neither is
  /// dropped (should not happen).
  FoodPreference? _foodPreferenceFromDataModel(FoodPreferenceDataModel data) {
    final String? taste = data.preferredTaste;
    if (taste != null && taste.trim().isNotEmpty) {
      return FoodPreference(
        id: data.foodPreferenceId,
        kind: FoodPreferenceKind.taste,
        name: taste.trim(),
      );
    }
    final String? category = data.preferredCategories;
    if (category != null && category.trim().isNotEmpty) {
      return FoodPreference(
        id: data.foodPreferenceId,
        kind: FoodPreferenceKind.category,
        name: category.trim(),
      );
    }
    return null;
  }

  /// Parses an embedded `dietary_restriction(...)` object; `null` when the
  /// embed is missing.
  DietaryRestriction? _dietaryFromRow(Map<String, dynamic> row) {
    final Map<String, dynamic> embedded = JsonReader.asMap(
      row['dietary_restriction'],
    );
    if (embedded.isEmpty || embedded['dietary_restriction_id'] == null) {
      return null;
    }
    final DietaryRestrictionDataModel data =
        DietaryRestrictionDataModel.fromJson(embedded);
    return DietaryRestriction(
      id: data.dietaryRestrictionId,
      name: data.restrictionName,
    );
  }
}
