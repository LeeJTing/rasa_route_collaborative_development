/// Wrapper around the Supabase SDK.
///
/// External services are the only place a third-party SDK is imported. Nothing
/// above `APIManager` may touch this class.
///
/// A singleton: `SupabaseService()` always returns the same instance, so the
/// connection is shared without anyone having to pass it around.
class SupabaseService {
  factory SupabaseService() => _instance;

  SupabaseService._();

  static final SupabaseService _instance = SupabaseService._();

  static Future<void> initialise() async {}

  /// Raw rows straight from PostgREST. Turning them into objects is the data
  /// model's job (`XDataModel.fromJson`), not this class's.
  Future<List<Map<String, dynamic>>> select(
    String table, {
    String columns = '*',
    Map<String, Object>? equals,
    String? orderBy,
    bool ascending = true,
    int? limit,
  }) async {
    return const <Map<String, dynamic>>[];
  }

  Future<Map<String, dynamic>?> insert(
    String table,
    Map<String, dynamic> values,
  ) async {
    return null;
  }

  Future<Map<String, dynamic>?> upsert(
    String table,
    Map<String, dynamic> values,
  ) async {
    return null;
  }

  Future<void> update(
    String table,
    Map<String, dynamic> values, {
    required Map<String, Object> equals,
  }) async {}

  Future<void> delete(
    String table, {
    required Map<String, Object> equals,
  }) async {}

  Future<Object?> rpc(String function, {Map<String, dynamic>? params}) async {
    return null;
  }

  Future<String> uploadPublic({
    required String bucket,
    required String path,
    required List<int> bytes,
    String contentType = 'image/jpeg',
  }) async {
    return '';
  }

  // --- auth ------------------------------------------------------------------

  Future<Map<String, dynamic>?> signInWithPassword({
    required String email,
    required String password,
  }) async {
    return null;
  }

  Future<void> signUp({
    required String email,
    required String password,
  }) async {}

  Future<void> sendOtp(String email) async {}

  Future<Map<String, dynamic>?> verifyOtp({
    required String email,
    required String token,
  }) async {
    return null;
  }

  Future<void> signOut() async {}

  Map<String, dynamic>? get currentSession => null;

  Stream<Map<String, dynamic>?> get sessionChanges =>
      const Stream<Map<String, dynamic>?>.empty();
}
