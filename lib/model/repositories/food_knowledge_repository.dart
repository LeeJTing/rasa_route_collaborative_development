import 'dart:developer' as developer;

import '../../core/json_model.dart';
import '../../domain_model/local_food.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../data_models/food_preference_data_model.dart';
import '../data_models/local_food_data_model.dart';
import '../data_models/local_food_image_data_model.dart';
import '../data_models/local_food_preference_data_model.dart';

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
    local_food_image(local_food_image_id, img_name, local_food_id),
    local_food_preference(
      food_preference_id,
      local_food_id,
      is_main,
      food_preference(
        food_preference_id,
        preferred_categories,
        preferred_taste
      )
    )
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
          .map(
            (Map<String, dynamic> row) => _toDomain(
              row,
              isFavourite: favouriteIds.contains(
                JsonReader.asInt(row['local_food_id']),
              ),
            ),
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
      return _toDomain(row, isFavourite: await _isFavouriteSafely(foodId));
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

  /// Adds a genuinely-new, tourist-confirmed Malaysian local food to the
  /// catalogue (Option C - catalogue growth from submissions). The logic
  /// layer already ran the full matcher; this is a belt-and-suspenders dedupe
  /// on the normalized name. Returns the saved row with its assigned id, or
  /// null when a duplicate already exists.
  Future<LocalFood?> insertFood(LocalFood food) async {
    final String normalized = food.name.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final List<LocalFood> existing = await getFoods();
    if (existing.any(
      (LocalFood f) => f.name.trim().toLowerCase() == normalized,
    )) {
      return null;
    }
    final Map<String, dynamic>? row = await api
        .insertRowReturning(APIManager.tableLocalFood, <String, dynamic>{
          'food_name': food.name.trim(),
          'description': food.description.isEmpty ? null : food.description,
          'origin': food.origin.isEmpty ? null : food.origin,
          'cultural_background': food.culturalBackground.isEmpty
              ? null
              : food.culturalBackground,
          'ingredients': food.ingredients.isEmpty ? null : food.ingredients,
          'food_category': food.category.isEmpty ? null : food.category,
          'cooking_style': food.cookingStyle.isEmpty ? null : food.cookingStyle,
          'meal_type': food.mealType.isEmpty ? null : food.mealType,
          'food_type': food.foodType.isEmpty ? null : food.foodType,
          'synonyms': food.synonyms.isEmpty ? null : food.synonyms.join(','),
        });
    if (row == null) return null;
    final LocalFood saved = _toDomain(row, isFavourite: false);
    // The cached catalogue no longer reflects what is on the server.
    invalidate();
    return saved;
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

  /// Converts one nested Supabase response into the screen-facing domain
  /// object. Each table is parsed by its own data model before composition.
  LocalFood _toDomain(Map<String, dynamic> row, {required bool isFavourite}) {
    final LocalFoodDataModel food = LocalFoodDataModel.fromJson(row);
    final List<LocalFoodImageDataModel> images =
        JsonReader.asModelList(
          row['local_food_image'],
          LocalFoodImageDataModel.fromJson,
        )..sort(
          (LocalFoodImageDataModel a, LocalFoodImageDataModel b) =>
              a.localFoodImageId.compareTo(b.localFoodImageId),
        );

    final Set<String> tastes = <String>{};
    String mainTaste = '';
    final Object? rawLinks = row['local_food_preference'];
    if (rawLinks is List) {
      for (final Object? rawLink in rawLinks) {
        if (rawLink is! Map) continue;
        final Map<String, dynamic> linkRow = Map<String, dynamic>.from(rawLink);
        final LocalFoodPreferenceDataModel link =
            LocalFoodPreferenceDataModel.fromJson(linkRow);
        final Map<String, dynamic>? preferenceRow = JsonReader.asMapOrNull(
          linkRow['food_preference'],
        );
        if (preferenceRow == null) continue;
        final FoodPreferenceDataModel preference =
            FoodPreferenceDataModel.fromJson(preferenceRow);
        final String? rawTaste = preference.preferredTaste;
        if (rawTaste == null) continue;
        final List<String> values = _splitValues(rawTaste);
        tastes.addAll(values);
        if (link.isMain && values.isNotEmpty) mainTaste = values.first;
      }
    }

    return LocalFood(
      id: food.localFoodId,
      name: food.foodName,
      description: food.description ?? '',
      origin: food.origin ?? '',
      culturalBackground: food.culturalBackground ?? '',
      ingredients: food.ingredients ?? '',
      category: food.foodCategory ?? '',
      cookingStyle: food.cookingStyle ?? '',
      mealType: food.mealType ?? '',
      foodType: food.foodType ?? '',
      tastes: List<String>.unmodifiable(tastes),
      mainTaste: mainTaste,
      pronunciationText: food.pronunciationText ?? '',
      audioGuideUrl: food.audioGuideUrl,
      synonyms: JsonReader.asStringList(food.synonyms),
      imageUrls: _resolveImageUrls(
        images
            .map((LocalFoodImageDataModel image) => image.imageName)
            .where((String name) => name.isNotEmpty)
            .toList(growable: false),
      ),
      isFavourite: isFavourite,
    );
  }

  List<String> _splitValues(String raw) => raw
      .split(RegExp(r'[,;/|]'))
      .map((String value) => value.trim())
      .where((String value) => value.isNotEmpty)
      .toList(growable: false);

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
