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
  // fails after registration). Always returns null for now, so
  // AddLandmarkViewModel.submitLandmark() correctly stops with a clear
  // "unable to identify tourist session" error instead of submitting with a
  // fake id.
  // TODO: read `storage.readJson(LocalStorageManager.keyAuthSession)` and
  // resolve it to a `tourist_id` (see `Tourist.touristId` vs `authUserId` -
  // they are different columns).
  // ==========================================================================
  /// The signed-in tourist's id, or null if nobody is signed in.
  Future<String?> currentTouristId() async {
    return null;
  }
}
