import '../../shared_client/local_storage_manager/local_storage_manager.dart';

/// The swipe-to-discover deck.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`), then
/// converts that data model into a **domain model** for everything above.
class SwipeRepository {
  SwipeRepository();

  final LocalStorageManager storage = LocalStorageManager();
}
