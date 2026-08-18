import '../../shared_client/api_manager/api_manager.dart';

/// Tourist-contributed landmarks and the dishes attached to them.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`), then
/// converts that data model into a **domain model** for everything above.
class SubmittedLandmarkRepository {
  SubmittedLandmarkRepository();

  final APIManager api = APIManager();
}
