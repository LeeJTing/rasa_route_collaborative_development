import '../../shared_client/api_manager/api_manager.dart';

/// Records what the tourist viewed, liked and favourited.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`), then
/// converts that data model into a **domain model** for everything above.
class InteractionRepository {
  InteractionRepository();

  final APIManager api = APIManager();
}
