import '../../shared_client/device_capability_manager/device_capability_manager.dart';

/// The device camera: checking and asking for the OS camera permission.
///
/// A repository is the only layer that talks to the shared clients.
/// `DeviceCapabilityManager` is the one place `permission_handler` is touched
/// (camera and location alike); nothing above this class sees it.
///
/// Reached from `FoodRecognitionLogic.requestCameraPermission` through
/// `DiscoveryRepositoryFacade.camera`, so `FoodRecognitionView` never imports
/// a shared client for the gate that opens its camera preview (REQ106_1).
class CameraRepository {
  CameraRepository();

  final DeviceCapabilityManager device = DeviceCapabilityManager();

  /// True when the OS camera permission is granted (Android/iOS runtime
  /// permission - the `CAMERA` manifest permission alone is not enough on
  /// Android 6+).
  Future<bool> hasCameraPermission() => device.hasCameraPermission();

  /// Asks for the OS camera permission if it isn't granted yet, and reports
  /// whether it is granted afterwards.
  Future<bool> requestCameraPermission() => device.requestCameraPermission();
}
