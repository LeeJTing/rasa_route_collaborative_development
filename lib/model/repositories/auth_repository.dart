import '../../shared_client/api_manager/api_manager.dart';
import '../../shared_client/local_storage_manager/local_storage_manager.dart';

/// Sign-in, sign-up, OTP and session persistence.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`), then
/// converts that data model into a **domain model** for everything above.
class AuthRepository {
  AuthRepository();

  final APIManager api = APIManager();
  final LocalStorageManager storage = LocalStorageManager();

  // ==========================================================================
  // NOT IMPLEMENTED YET. No tourist row is created on sign-up yet
  // (ARCHITECTURE_ANALYSIS.md, Known Gaps - every tourist_id foreign key
  // fails after registration).
  // TODO: read `storage.readJson(LocalStorageManager.keyAuthSession)` and
  // resolve it to a `tourist_id` (see `Tourist.touristId` vs `authUserId` -
  // they are different columns), and DELETE [_devTouristId] below with the
  // same change.
  // ==========================================================================

  /// TEMPORARY (dev stage): the seeded test tourist row in Supabase, used
  /// until real sign-in exists so the submit flow can be exercised
  /// end-to-end.
  ///
  /// Lives here, not in a ViewModel: "who is the current tourist" is this
  /// repository's question to answer, including while the answer is a
  /// stand-in. `AddLandmarkViewModel` used to supply this same literal as a
  /// `?? '2222...'` fallback on [currentTouristId]'s result, which put an
  /// identity decision (and a magic UUID) in the presentation layer.
  ///
  /// Delete alongside the TODO above once sign-in is real.
  static const String _devTouristId = '22222222-2222-4222-8222-222222222222';

  /// The signed-in tourist's id, or null if nobody is signed in.
  ///
  /// Currently always resolves to [_devTouristId] - see above. Callers still
  /// handle null (there's no sign-in yet to make it impossible), they just
  /// won't hit it while the dev fallback stands in.
  Future<String?> currentTouristId() async {
    return _devTouristId;
  }
}
