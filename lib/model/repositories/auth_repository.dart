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
}
