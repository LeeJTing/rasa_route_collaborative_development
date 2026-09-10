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
  static const String tableLocalFoodPreference = 'local_food_preference';
  static const String tableReport = 'report';

  /// Searchable geography for the dashboard: cities, towns, areas and notable
  /// locations (REQ102_19). Read-only - seeded by migration.
  static const String tablePlace = 'place';
  static const String tableFoodDietaryRestriction = 'food_dietary_restriction';
  static const String tableUserDietaryRestriction = 'user_dietary_restriction';

  // ===========================================================================
  // Auth & Tourist (ChinShunYon) - tourist rows
  // ===========================================================================

  /// One row per signed-in tourist. `tourist.tourist_id` is the app-facing
  /// id (used as the `tourist_id` FK on `favourite_food`, `landmark_item`,
  /// etc.); `tourist.id` links the row to `auth.users.id`. See
  /// `TouristDataModel`.
  static const String tableTourist = 'tourist';

  /// Links a tourist to the `food_preference` rows they picked
  /// (`tourist_id` -> `food_preference_id`). Each `food_preference` row is a
  /// single taste OR a single category (the other field is null).
  static const String tablePersonalisedPreference = 'personalised_preference';

  // ===========================================================================
  // End of Auth & Tourist (ChinShunYon)
  // ===========================================================================

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
    Map<String, num> gte = const <String, num>{},
    Map<String, num> lte = const <String, num>{},
    Map<String, List<Object?>>? inFilter,
    String? orderBy,
    bool ascending = true,
    int? limit,
    int? rangeStart,
    int? rangeEnd,
  }) => _supabase.selectAll(
    table,
    columns: columns,
    eq: eq,
    gte: gte,
    lte: lte,
    inFilter: inFilter,
    orderBy: orderBy,
    ascending: ascending,
    limit: limit,
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
  );

  /// `select` returning **every** matching row rather than the first page.
  ///
  /// [selectAll] is answered by PostgREST with at most 1000 rows and no
  /// indication that it stopped there, so any table that can grow past that -
  /// `restaurant`, `restaurant_item`, `opening_hours` - must be read through
  /// this instead. [orderBy] must be a unique column (the primary key), or the
  /// paging is not stable.
  Future<List<Map<String, dynamic>>> selectEvery(
    String table, {
    required String orderBy,
    String columns = '*',
    Map<String, Object?> eq = const <String, Object?>{},
    Map<String, List<Object?>>? inFilter,
    bool ascending = true,
  }) => _supabase.selectEvery(
    table,
    orderBy: orderBy,
    columns: columns,
    eq: eq,
    inFilter: inFilter,
    ascending: ascending,
  );

  /// How many rows a table holds, without downloading them.
  Future<int> countRows(String table) => _supabase.countRows(table);

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

  // ===========================================================================
  // Auth & Tourist (ChinShunYon) - tourist id resolution
  // ===========================================================================

  /// The signed-in tourist's app-facing `tourist_id` (from the `tourist`
  /// row), or `''` when nobody is signed in or the row does not exist yet.
  ///
  /// Every table that stores "whose is this" (`favourite_food`,
  /// `personalised_preference`, `user_dietary_restriction`, ...) keys on
  /// `tourist.tourist_id`, NOT on the auth user id (`auth.uid()`) that
  /// [currentUserId] returns. Exposing the resolution here - the single
  /// remote source every repository already depends on - lets any module
  /// fetch the right id without one repository reaching into another
  /// module's repository.
  Future<String> resolveCurrentTouristId() async {
    final String authUserId = currentUserId;
    if (authUserId.isEmpty) return '';
    final Map<String, dynamic>? row = await _supabase.selectOne(
      tableTourist,
      columns: 'tourist_id',
      eq: <String, Object?>{'id': authUserId},
    );
    return row == null ? '' : (row['tourist_id'] as String? ?? '');
  }

  // ===========================================================================
  // End of Auth & Tourist (ChinShunYon)
  // ===========================================================================

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

  // ---------------------------------------------------------------------------
  // Authentication, forwarded to SupabaseService.
  // ---------------------------------------------------------------------------

  Future<void> sendEmailOtp({required String email}) {
    return _supabase.sendEmailOtp(email: email);
  }

  Future<Map<String, dynamic>?> verifyEmailOtp({
    required String email,
    required String token,
  }) {
    return _supabase.verifyEmailOtp(email: email, token: token);
  }

  Future<bool> signInWithGoogle({required String redirectTo}) {
    return _supabase.signInWithGoogle(redirectTo: redirectTo);
  }

  Future<Map<String, dynamic>?> getCurrentAuthSession() =>
      _supabase.getCurrentAuthSession();

  Future<void> signOut() {
    return _supabase.signOut();
  }

  //End of Authentication -------------------------------------------------------
}
