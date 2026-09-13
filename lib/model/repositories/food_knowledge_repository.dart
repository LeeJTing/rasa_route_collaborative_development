import 'dart:developer' as developer;

import '../../core/json_model.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/pronunciation_playback_result.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../../shared_client/device_capability_manager/device_capability_manager.dart';
import '../data_models/food_preference_data_model.dart';
import '../data_models/local_food_data_model.dart';
import '../data_models/local_food_image_data_model.dart';
import '../data_models/local_food_preference_data_model.dart';

// ====== Auth/Profile (ChinShunYon): favourite tourist_id fix ======
// `favourite_food.tourist_id` must be `tourist.tourist_id` (see RLS policy 6
// in rls_policies_auth_profile.txt). The original food-module code used
// `api.currentUserId` (the Supabase AUTH user id), which is a different
// value - so RLS rejected every favourite write and the profile module's
// favourites never saw the rows. The fix resolves the real `tourist_id` via
// `APIManager.resolveCurrentTouristId` - the shared single remote source - so
// no repository ever reaches into another module's repository.
// ====== End of Auth/Profile (ChinShunYon) ======

/// Supabase-backed access to the local-food catalogue and favourites.
///
/// Catalogue data is never replaced with sample dishes. An unavailable or
/// misconfigured backend must reach the ViewModel as an error so the View can
/// present an honest retry state.
class FoodKnowledgeRepository {
  FoodKnowledgeRepository();

  final APIManager api = APIManager();
  final DeviceCapabilityManager deviceCapabilities = DeviceCapabilityManager();

  Future<PronunciationPlaybackResult> playPronunciation(LocalFood food) async {
    final DevicePronunciationPlaybackResult result = await deviceCapabilities
        .playPronunciation(
          foodName: food.name,
          audioUrl: food.audioGuideUrl,
          fallbackText: food.pronunciationText,
        );
    return switch (result) {
      DevicePronunciationPlaybackResult.curatedAudio =>
        PronunciationPlaybackResult.curatedAudio,
      DevicePronunciationPlaybackResult.deviceVoice =>
        PronunciationPlaybackResult.deviceVoice,
      DevicePronunciationPlaybackResult.unavailable =>
        PronunciationPlaybackResult.unavailable,
    };
  }

  // ---------------------------------------------------------------------------
  // Catalogue cache
  // ---------------------------------------------------------------------------
  //
  // The catalogue query is wide and the map can request it repeatedly. Public
  // food data is effectively static at runtime, so only that portion is
  // cached. Favourite ids are fetched and overlaid for the current tourist.
  //
  // Static so every screen shares one copy, however many facades exist.

  static const Duration cacheTtl = Duration(minutes: 5);

  static List<LocalFood>? _cachedFoods;
  static DateTime? _cachedFoodsAt;
  static Future<List<LocalFood>>? _foodsRequest;

  /// Drops only the public catalogue cache. Favourite state is deliberately
  /// overlaid per request so it can never leak between signed-in tourists.
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
  Future<List<LocalFood>> getFoods() async {
    final List<Object> results = await Future.wait(<Future<Object>>[
      _getCatalogueFoods(),
      _getFavouriteFoodIdsSafely(),
    ]);
    final List<LocalFood> foods = results[0] as List<LocalFood>;
    final Set<int> favouriteIds = results[1] as Set<int>;
    return foods
        .map(
          (LocalFood food) =>
              food.copyWith(isFavourite: favouriteIds.contains(food.id)),
        )
        .toList(growable: false);
  }

  Future<List<LocalFood>> _getCatalogueFoods() {
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
      final List<Map<String, dynamic>> rows = await api.selectAll(
        APIManager.tableLocalFood,
        columns: _selectColumns,
        orderBy: 'food_name',
      );
      return rows
          .map((Map<String, dynamic> row) => _toDomain(row, isFavourite: false))
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
        .where(
          (LocalFood food) =>
              food.name.toLowerCase().contains(normalized) ||
              food.synonyms.any(
                (String synonym) => synonym.toLowerCase().contains(normalized),
              ),
        )
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
    final Map<String, dynamic>? row = await api.insertRowReturning(
      APIManager.tableLocalFood,
      <String, dynamic>{
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
        // How the dish name is said (Gemini's respelling) - the same
        // column the curated rows carry; without it the pronunciation
        // button has no text to fall back to until a curated recording is
        // generated for this dish.
        'pronunciation_text': food.pronunciationText.isEmpty
            ? null
            : food.pronunciationText,
        'synonyms': food.synonyms.isEmpty ? null : food.synonyms.join(','),
      },
    );
    if (row == null) return null;
    final LocalFood saved = _toDomain(row, isFavourite: false);
    // The cached catalogue no longer reflects what is on the server.
    invalidate();
    return saved;
  }

  /// Attaches a photo to a catalogue dish (`local_food_image`) - used when a
  /// brand-new dish is added from a landmark submission, so the catalogue row
  /// carries the tourist's own photo of the dish instead of appearing with no
  /// image. [imageName] may be either a storage object name in the
  /// food-images bucket or a full public URL: `APIManager.resolveImageUrl`
  /// passes `http(s)` values through unchanged, so the submission's already
  /// uploaded `landmark-images` URL works as-is (no second upload).
  ///
  /// `local_food_image_id` may or may not be an identity column depending on
  /// how the table was created, so the natural insert is attempted first and
  /// an explicit next id is supplied when that is refused (the same
  /// belt-and-suspenders pattern `SubmittedLandmarkRepository` uses for
  /// tables without an identity default). Throws when neither works - callers
  /// treat a failed photo link as best-effort.
  Future<void> addFoodImage({
    required int localFoodId,
    required String imageName,
  }) async {
    final String name = imageName.trim();
    if (localFoodId <= 0 || name.isEmpty) return;
    try {
      await api.insertRow(APIManager.tableLocalFoodImage, <String, dynamic>{
        'img_name': name,
        'local_food_id': localFoodId,
      });
      return;
    } catch (_) {
      // Fall through to the explicit-id attempt.
    }
    final int nextId = await _nextLocalFoodImageId();
    await api.insertRow(APIManager.tableLocalFoodImage, <String, dynamic>{
      'local_food_image_id': nextId,
      'img_name': name,
      'local_food_id': localFoodId,
    });
  }

  /// Next `local_food_image_id` (max + 1); 1 when the table is empty (or the
  /// read is denied).
  Future<int> _nextLocalFoodImageId() async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableLocalFoodImage,
      columns: 'local_food_image_id',
      orderBy: 'local_food_image_id',
      ascending: false,
      limit: 1,
    );
    if (rows.isEmpty) return 1;
    return ((rows.first['local_food_image_id'] as num?)?.toInt() ?? 0) + 1;
  }

  /// Writes the `local_food_preference` links for a freshly-inserted dish -
  /// its tastes (with the main taste marked `is_main`) and its category.
  /// [tasteIds] must already be normalised against `food_preference`
  /// (`FoodRecognitionLogic` does that via `preferenceIdLookup`). Duplicates
  /// are skipped (the composite PK would 409), and one bad link must not fail
  /// the whole insert flow.
  Future<void> linkFoodPreferences(
    int localFoodId, {
    required List<int> tasteIds,
    int mainTasteId = 0,
    int? categoryId,
  }) async {
    final Set<int> seen = <int>{};
    for (final int tasteId in tasteIds) {
      if (tasteId <= 0 || !seen.add(tasteId)) continue;
      try {
        await api
            .insertRow(APIManager.tableLocalFoodPreference, <String, dynamic>{
              'local_food_id': localFoodId,
              'food_preference_id': tasteId,
              'is_main': tasteId == mainTasteId,
            });
      } catch (_) {
        // Ignored - see doc above.
      }
    }
    if (categoryId != null && categoryId > 0 && seen.add(categoryId)) {
      try {
        await api
            .insertRow(APIManager.tableLocalFoodPreference, <String, dynamic>{
              'local_food_id': localFoodId,
              'food_preference_id': categoryId,
              'is_main': false,
            });
      } catch (_) {
        // Ignored - see doc above.
      }
    }
  }

  /// Writes the `food_dietary_restriction` links for a freshly-inserted dish.
  /// [restrictionIds] are `dietary_restriction` ids - the link table's PK
  /// column `food_dietary_restriction_id` IS the restriction id. Duplicates
  /// skipped; one bad link must not fail the whole insert flow.
  Future<void> linkFoodDietaryRestrictions(
    int localFoodId,
    List<int> restrictionIds,
  ) async {
    final Set<int> seen = <int>{};
    for (final int restrictionId in restrictionIds) {
      if (restrictionId <= 0 || !seen.add(restrictionId)) continue;
      try {
        await api.insertRow(
          APIManager.tableFoodDietaryRestriction,
          <String, dynamic>{
            'food_dietary_restriction_id': restrictionId,
            'local_food_id': localFoodId,
          },
        );
      } catch (_) {
        // Ignored - see doc above.
      }
    }
  }

  /// Toggles one favourite and returns the state confirmed by the database.
  Future<bool> toggleFavourite(int localFoodId) async {
    final String touristId = await api.resolveCurrentTouristId();
    if (touristId.isEmpty) {
      throw Exception('Sign in to save local food to your favourites.');
    }

    try {
      final bool isFavourite = await _isFavourite(localFoodId, touristId);
      if (isFavourite) {
        await api.deleteRows(
          APIManager.tableFavouriteFood,
          eq: <String, Object?>{
            'tourist_id': touristId,
            'local_food_id': localFoodId,
          },
        );
        return false;
      } else {
        await api.insertRow(APIManager.tableFavouriteFood, <String, dynamic>{
          'tourist_id': touristId,
          'local_food_id': localFoodId,
        });
        return true;
      }
    } catch (_) {
      throw Exception('Unable to update favourites. Please try again.');
    }
  }

  /// The signed-in tourist's favourited food ids (`favourite_food`), or an
  /// empty set when nobody is signed in. Used to prioritise similar foods.
  Future<Set<int>> favouriteFoodIds() async {
    final String touristId = await api.resolveCurrentTouristId();
    if (touristId.isEmpty) return <int>{};
    return _getFavouriteFoodIds(touristId);
  }

  Future<Set<int>> _getFavouriteFoodIdsSafely() async {
    // FIX (ChinShunYon): gate on the resolved tourist_id, not the auth user
    // id - see APIManager.resolveCurrentTouristId.
    final String touristId = await api.resolveCurrentTouristId();
    if (touristId.isEmpty) return <int>{};
    try {
      return await _getFavouriteFoodIds(touristId);
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

  Future<Set<int>> _getFavouriteFoodIds(String touristId) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableFavouriteFood,
      columns: 'local_food_id',
      eq: <String, Object?>{
        // 'tourist_id': api.currentUserId, // ORIGINAL (food module) - the
        //   auth user id, not tourist.tourist_id. Kept for record.
        'tourist_id': touristId, // FIX (ChinShunYon): real tourist_id
      },
    );
    return rows
        .map((Map<String, dynamic> row) => row['local_food_id'])
        .whereType<num>()
        .map((num id) => id.toInt())
        .toSet();
  }

  /// Reads favourites for an explicitly resolved tourist. Swipe Mode uses the
  /// temporary development tourist until the authentication module is live.
  Future<Set<int>> favouriteFoodIdsForTourist(String touristId) async {
    if (touristId.isEmpty) return <int>{};
    return _getFavouriteFoodIds(touristId);
  }

  Future<bool> _isFavouriteSafely(int localFoodId) async {
    // FIX (ChinShunYon): gate on the resolved tourist_id, not the auth user
    // id - see APIManager.resolveCurrentTouristId.
    final String touristId = await api.resolveCurrentTouristId();
    if (touristId.isEmpty) return false;
    try {
      return await _isFavourite(localFoodId, touristId);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isFavourite(int localFoodId, String touristId) async =>
      (await _getFavouriteFoodIds(touristId)).contains(localFoodId);

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
      synonyms: _splitValues(food.synonyms ?? ''),
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
