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

  SupabaseService get supabase => _supabase;

  // ---------------------------------------------------------------------------
  // Table names - kept in sync with the ERD. Never type a table name at a call
  // site; a typo in a string is a runtime empty result, a typo here is a
  // compile error.
  // ---------------------------------------------------------------------------

  static const String tableTourist = 'tourist';
  static const String tableLocalFood = 'local_food';
  static const String tableLocalFoodImage = 'local_food_image';
  static const String tableDietaryRestriction = 'dietary_restriction';
  static const String tableFoodPreference = 'food_preference';
  static const String tablePersonalisedPreference = 'personalised_preference';
  static const String tableUserDietaryRestriction = 'user_dietary_restriction';
  static const String tableLocalFoodPreference = 'local_food_preference';
  static const String tableFoodDietaryRestriction = 'food_dietary_restriction';
  static const String tableFavouriteFood = 'favourite_food';
  static const String tableRestaurant = 'restaurant';
  static const String tableRestaurantItem = 'restaurant_item';
  static const String tableOpeningHours = 'opening_hours';
  static const String tableSubmittedLandmark = 'submitted_landmark';
  static const String tableLandmarkItem = 'landmark_item';

  static const String bucketFoodImages = 'food-images';
  static const String bucketLandmarkImages = 'landmark-images';

  // ---------------------------------------------------------------------------
  // CRUD - forwards to SupabaseService and translates failures into one
  // ApiException so ViewModels never switch on driver error types.
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> selectAll(
    String table, {
    String columns = '*',
    Map<String, Object>? equals,
    String? orderBy,
    bool ascending = true,
    int? limit,
  }) => _guard(
    () => _supabase.select(
      table,
      columns: columns,
      equals: equals,
      orderBy: orderBy,
      ascending: ascending,
      limit: limit,
    ),
    'select $table',
  );

  Future<Map<String, dynamic>?> selectOne(
    String table, {
    String columns = '*',
    required Map<String, Object> equals,
  }) async {
    final List<Map<String, dynamic>> rows = await selectAll(
      table,
      columns: columns,
      equals: equals,
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>?> insert(
    String table,
    Map<String, dynamic> values,
  ) => _guard(() => _supabase.insert(table, values), 'insert $table');

  Future<Map<String, dynamic>?> upsert(
    String table,
    Map<String, dynamic> values,
  ) => _guard(() => _supabase.upsert(table, values), 'upsert $table');

  Future<void> update(
    String table,
    Map<String, dynamic> values, {
    required Map<String, Object> equals,
  }) => _guard(
    () => _supabase.update(table, values, equals: equals),
    'update $table',
  );

  Future<void> delete(
    String table, {
    required Map<String, Object> equals,
  }) => _guard(
    () => _supabase.delete(table, equals: equals),
    'delete $table',
  );

  /// Calls a Postgres function - for heat-map aggregation and recommendation
  /// queries once those RPCs exist.
  Future<Object?> callRpc(String function, {Map<String, dynamic>? params}) =>
      _guard(() => _supabase.rpc(function, params: params), 'rpc $function');

  Future<String> uploadImage({
    required String bucket,
    required String path,
    required List<int> bytes,
  }) => _guard(
    () => _supabase.uploadPublic(bucket: bucket, path: path, bytes: bytes),
    'upload $bucket/$path',
  );

  Future<String> recogniseImage({
    required List<int> imageBytes,
    required String prompt,
  }) => _guard(
    () => _gemini.describeImage(imageBytes: imageBytes, prompt: prompt),
    'gemini recognise',
  );

  Future<T> _guard<T>(Future<T> Function() action, String what) async {
    try {
      return await action();
    } on ApiException {
      rethrow;
    } catch (error) {
      throw ApiException('$what failed: $error');
    }
  }
}

/// The one error type repositories surface upward.
class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
