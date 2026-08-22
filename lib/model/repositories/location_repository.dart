import '../../model/data_models/location_data_model.dart';
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

  /// One GPS fix (see `DeviceCapabilityManager.currentLocation`).
  Future<LocationDataModel> currentLocation() => device.currentLocation();

  /// Continuous GPS fixes, consumed by `LocationMonitor`.
  Stream<LocationDataModel> locationStream({
    Duration interval = const Duration(seconds: 30),
  }) => device.locationStream(interval: interval);

  /// True when the OS location permission is granted (asked for it if not).
  Future<bool> ensureLocationPermission() => device.requestLocationPermission();
}
