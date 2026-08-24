import '../../external/gemini/gemini_landmark_service.dart';
import '../../external/gemini/gemini_service.dart';
import '../../external/supabase/supabase_service.dart';

/// The single remote data source for the whole app.
///
/// Repositories depend on `APIManager`, never on `SupabaseService` or
/// `GeminiService` directly. That keeps every network concern - table names,
/// select strings, storage buckets, error translation - in one file.
///
/// It returns raw rows. Turning a row into an object is the **data model's**
/// job (`LocalFoodDataModel.fromJson(row)`); turning that into something the
/// app reasons about is the **repository's** job (data model -> domain model).
///
/// A singleton: `APIManager()` always returns the same instance, so no one has
/// to pass it down through constructors.
class APIManager {
  factory APIManager() => _instance;

  APIManager._();

  static final APIManager _instance = APIManager._();

  final SupabaseService _supabase = SupabaseService();
  final GeminiService _gemini = GeminiService();
  final GeminiLandmarkService _geminiLandmark = GeminiLandmarkService();

  SupabaseService get supabase => _supabase;
  GeminiService get gemini => _gemini;

  /// UC500's food/signboard/stall recognition prompts - see
  /// `GeminiLandmarkService`'s doc for why these live in their own service
  /// rather than on [gemini] directly.
  GeminiLandmarkService get geminiLandmark => _geminiLandmark;

  // ---------------------------------------------------------------------------
  // Table names - the only place a table string is spelled out.
  // ---------------------------------------------------------------------------

  static const String tableLocalFood = 'local_food';
  static const String tableLocalFoodImage = 'local_food_image';
  static const String tableFavouriteFood = 'favourite_food';
  static const String tableRestaurant = 'restaurant';
  static const String tableRestaurantItem = 'restaurant_item';
  static const String tableOpeningHours = 'opening_hours';
  static const String tableSubmittedLandmark = 'submitted_landmark';
  static const String tableLandmarkItem = 'landmark_item';
  static const String tableFoodPreference = 'food_preference';
  static const String tableDietaryRestriction = 'dietary_restriction';
  static const String tableFoodDietaryRestriction = 'food_dietary_restriction';
  static const String tableUserDietaryRestriction = 'user_dietary_restriction';

  /// Supabase Storage bucket holding local-food dish photos. The
  /// `local_food_image.img_name` column stores the object name in this bucket.
  static const String storageBucketFoodImages = 'food-images';

  /// Supabase Storage bucket holding tourist food photos attached to
  /// submitted landmarks. `landmark_item.image_id` stores the object name in
  /// this bucket and `landmark_item.image_url` the public URL of that object.
  static const String storageBucketLandmarkImages = 'landmark-images';

  // ---------------------------------------------------------------------------
  // Generic row access, forwarded straight to SupabaseService.
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> selectAll(
    String table, {
    String columns = '*',
    Map<String, Object?> eq = const <String, Object?>{},
    String? orderBy,
    bool ascending = true,
    int? limit,
  }) => _supabase.selectAll(
    table,
    columns: columns,
    eq: eq,
    orderBy: orderBy,
    ascending: ascending,
    limit: limit,
  );

  Future<Map<String, dynamic>?> selectOne(
    String table, {
    String columns = '*',
    required Map<String, Object?> eq,
  }) => _supabase.selectOne(table, columns: columns, eq: eq);

  Future<void> insertRow(String table, Map<String, dynamic> values) =>
      _supabase.insertRow(table, values);

  /// Insert a row and return it back - needed when the DB assigns a generated
  /// id the caller needs (e.g. `landmark_item.landmark_item_id`).
  Future<Map<String, dynamic>?> insertRowReturning(
    String table,
    Map<String, dynamic> values,
  ) => _supabase.insertRowReturning(table, values);

  Future<void> deleteRows(String table, {required Map<String, Object?> eq}) =>
      _supabase.deleteRows(table, eq: eq);

  /// Update the rows matching [eq], setting [values].
  Future<void> updateRow(
    String table,
    Map<String, Object?> values, {
    required Map<String, Object?> eq,
  }) => _supabase.updateRow(table, values, eq: eq);

  /// Uploads a captured food photo to [storageBucketLandmarkImages] and
  /// returns the storage object name - the `landmark_item.image_id` value.
  /// The public URL is `_supabase.storagePublicUrl(...)` on the same name
  /// (see [resolveImageUrl]).
  Future<String> uploadLandmarkImage({
    required List<int> bytes,
    required String path,
  }) => _supabase.uploadBytes(
    bucket: storageBucketLandmarkImages,
    path: path,
    bytes: bytes,
  );

  /// The signed-in user's id, or `''` when nobody is signed in.
  String get currentUserId => _supabase.currentUserId;

  /// Plain-text prompt to Gemini, with the app's configured timeout + retry.
  Future<String> askGemini(String prompt) => _gemini.generateText(prompt);

  /// Turns a Supabase Storage object name into a public HTTPS URL so the UI
  /// can `Image.network` it. Full URLs and bundled `assets/...` paths are
  /// passed through unchanged; empty values become `null`.
  String? resolveImageUrl(String? name, {required String bucket}) {
    final String? trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (trimmed.startsWith('http') || trimmed.startsWith('assets/')) {
      return trimmed;
    }
    return _supabase.storagePublicUrl(bucket, trimmed);
  }
}
