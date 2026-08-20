import 'dart:typed_data';

import '../../model/data_models/location_data_model.dart';

/// Access to device hardware: camera, gallery, GPS, permissions.
///
/// A singleton, like the other shared clients - `DeviceCapabilityManager()`
/// always returns the same instance.
///
/// Wrap the platform plugins (`image_picker`, `geolocator`,
/// `permission_handler`) here and nowhere else, so a repository never asks for
/// a permission itself.
class DeviceCapabilityManager {
  factory DeviceCapabilityManager() => _instance;

  DeviceCapabilityManager._();

  static final DeviceCapabilityManager _instance = DeviceCapabilityManager._();

  // --- location --------------------------------------------------------------

  Future<bool> hasLocationPermission() async => false;

  Future<bool> requestLocationPermission() async => false;

  /// One GPS fix.
  Future<LocationDataModel> currentLocation() async =>
      LocationDataModel.unknown;

  /// Continuous fixes, consumed by `LocationMonitor`.
  Stream<LocationDataModel> locationStream({
    Duration interval = const Duration(seconds: 30),
  }) => const Stream<LocationDataModel>.empty();

  // --- camera ----------------------------------------------------------------

  Future<bool> hasCameraPermission() async => false;

  Future<bool> requestCameraPermission() async => false;

  /// Opens the camera. Returns null if the tourist cancels.
  Future<CapturedImage?> capturePhoto() async => null;

  /// Opens the gallery. Returns null if the tourist cancels.
  Future<CapturedImage?> pickPhoto() async => null;
}

/// A photo taken or picked by the tourist.
class CapturedImage {
  const CapturedImage({
    required this.path,
    required this.bytes,
    this.mimeType = 'image/jpeg',
  });

  final String path;
  final Uint8List bytes;
  final String mimeType;
}
