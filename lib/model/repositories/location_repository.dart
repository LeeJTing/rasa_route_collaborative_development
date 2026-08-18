import '../../shared_client/device_capability_manager/device_capability_manager.dart';
import '../../shared_client/local_storage_manager/local_storage_manager.dart';

/// Where the tourist is: permissions, fixes and the cached last position.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`), then
/// converts that data model into a **domain model** for everything above.
class LocationRepository {
  LocationRepository();

  final DeviceCapabilityManager device = DeviceCapabilityManager();
  final LocalStorageManager storage = LocalStorageManager();
}
