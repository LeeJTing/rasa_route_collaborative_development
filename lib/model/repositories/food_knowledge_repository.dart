import 'dart:developer' as developer;

import '../../domain_model/local_food.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../data_models/local_food_data_model.dart';

/// Supabase-backed access to the local-food catalogue and favourites.
///
/// Catalogue data is never replaced with sample dishes. An unavailable or
/// misconfigured backend must reach the ViewModel as an error so the View can
/// present an honest retry state.
class FoodKnowledgeRepository {
  FoodKnowledgeRepository();

  final APIManager api = APIManager();

  // ---------------------------------------------------------------------------
  // Catalogue cache
  // ---------------------------------------------------------------------------
  //
  // `getFoods` is a wide nested select plus a favourites lookup, and the map
  // called it on every pan. The catalogue itself is effectively static at
  // runtime - only favourites move, and [toggleFavourite] clears this.
  //
  // Static so every screen shares one copy, however many facades exist.

  static const Duration cacheTtl = Duration(minutes: 5);

  static List<LocalFood>? _cachedFoods;
  static DateTime? _cachedFoodsAt;
  static Future<List<LocalFood>>? _foodsRequest;

  /// Drops the cached catalogue. Called by [toggleFavourite]; call it too after
  /// anything else that writes to `local_food`.
  static void invalidate() {
    _cachedFoods = null;
    _cachedFoodsAt = null;
  }

  static const String _selectColumns = '''
    local_food_id,
    food_name,
    description,
    origin,
    cultural_background,
    ingredients,
    food_category,
    cooking_style,
    meal_type,
    food_type,
    pronunciation_text,
    audio_guide_url,
    synonyms,
    local_food_image(img_name),
    local_food_preference(is_main, food_preference(preferred_taste))
  ''';

  /// The whole catalogue, cached for [cacheTtl]. Concurrent callers share one
  /// request instead of each firing their own.
  Future<List<LocalFood>> getFoods() {
    final List<LocalFood>? cached = _cachedFoods;
    if (cached != null &&
        _cachedFoodsAt != null &&
        DateTime.now().difference(_cachedFoodsAt!) < cacheTtl) {
      return Future<List<LocalFood>>.value(cached);
    }
    return _foodsRequest ??= _fetchFoods()
        .then((List<LocalFood> value) {
          _cachedFoods = value;
          _cachedFoodsAt = DateTime.now();
          return value;
        })
        .whenComplete(() => _foodsRequest = null);
  }

  Future<List<LocalFood>> _fetchFoods() async {
    try {
      // Independent of each other, so they go together.
      final List<Map<String, dynamic>> rows;
      final Set<int> favouriteIds;
      final List<Object> results = await Future.wait(<Future<Object>>[
        api.selectAll(
          APIManager.tableLocalFood,
          columns: _selectColumns,
          orderBy: 'food_name',
        ),
        _getFavouriteFoodIdsSafely(),
      ]);
      rows = results[0] as List<Map<String, dynamic>>;
      favouriteIds = results[1] as Set<int>;
      return rows
          .map(LocalFoodDataModel.fromJson)
          .map(
            (LocalFoodDataModel data) => data
                .toDomain(isFavourite: favouriteIds.contains(data.localFoodId))
                .copyWith(imageUrls: _resolveImageUrls(data.imageUrls)),
          )
          .toList(growable: false);
    } catch (error, stackTrace) {
      developer.log(
        'Local-food catalogue query failed.',
        name: 'FoodKnowledgeRepository',
        error: error,
        stackTrace: stackTrace,
      );
      throw Exception(
        'Unable to load local food. Check your connection and try again.',
      );
    }
  }

  Future<List<LocalFood>> searchFoods(String query) async {
    final String normalized = query.trim().toLowerCase();
    final List<LocalFood> foods = await getFoods();
    return foods
        .where((LocalFood food) => food.name.toLowerCase().contains(normalized))
        .toList(growable: false);
  }

  Future<LocalFood?> getFoodById(int foodId) async {
    try {
      final Map<String, dynamic>? row = await api.selectOne(
        APIManager.tableLocalFood,
        columns: _selectColumns,
        eq: <String, Object?>{'local_food_id': foodId},
      );
      if (row == null) return null;
      final LocalFoodDataModel data = LocalFoodDataModel.fromJson(row);
      final LocalFood food = data.toDomain(
        isFavourite: await _isFavouriteSafely(foodId),
      );
      return food.copyWith(imageUrls: _resolveImageUrls(data.imageUrls));
    } catch (error, stackTrace) {
      developer.log(
        'Local-food detail query failed.',
        name: 'FoodKnowledgeRepository',
        error: error,
        stackTrace: stackTrace,
      );
      throw Exception(
        'Unable to load this local food. Check your connection and try again.',
      );
    }
  }

  Future<void> toggleFavourite(int localFoodId) async {
    if (api.currentUserId.isEmpty) {
      throw Exception('Sign in to save local food to your favourites.');
    }

    try {
      final bool isFavourite = await _isFavourite(localFoodId);
      if (isFavourite) {
        await api.deleteRows(
          APIManager.tableFavouriteFood,
          eq: <String, Object?>{
            'tourist_id': api.currentUserId,
            'local_food_id': localFoodId,
          },
        );
      } else {
        await api.insertRow(APIManager.tableFavouriteFood, <String, dynamic>{
          'tourist_id': api.currentUserId,
          'local_food_id': localFoodId,
        });
      }
    } catch (_) {
      throw Exception('Unable to update favourites. Please try again.');
    }

    // The cached catalogue carries `isFavourite`, so it is now wrong.
    invalidate();
  }

  Future<Set<int>> _getFavouriteFoodIdsSafely() async {
    if (api.currentUserId.isEmpty) return <int>{};
    try {
      return await _getFavouriteFoodIds();
    } catch (_) {
      // Favourites should not prevent the public catalogue from loading.
      return <int>{};
    }
  }

  /// Looks up a catalogue entry by exact name match (case-insensitive) -
  /// used by the UC500 two-phase recognition flow to avoid re-generating an
  /// entry Gemini has already described once. Returns null when nothing
  /// matches.
  Future<LocalFood?> findByName(String name) async {
    final String normalized = name.trim().toLowerCase();
    final List<LocalFood> foods = await getFoods();
    for (final LocalFood food in foods) {
      if (food.name.toLowerCase() == normalized) return food;
    }
    return null;
  }

  Future<Set<int>> _getFavouriteFoodIds() async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableFavouriteFood,
      columns: 'local_food_id',
      eq: <String, Object?>{'tourist_id': api.currentUserId},
    );
    return rows
        .map((Map<String, dynamic> row) => row['local_food_id'])
        .whereType<num>()
        .map((num id) => id.toInt())
        .toSet();
  }

  Future<bool> _isFavouriteSafely(int localFoodId) async {
    if (api.currentUserId.isEmpty) return false;
    try {
      return await _isFavourite(localFoodId);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isFavourite(int localFoodId) async =>
      (await _getFavouriteFoodIds()).contains(localFoodId);

  List<String> _resolveImageUrls(List<String> names) => names
      .map(
        (String name) => api.resolveImageUrl(
          name,
          bucket: APIManager.storageBucketFoodImages,
        ),
      )
      .whereType<String>()
      .toList(growable: false);
}
