import 'package:fluttermocklocation/fluttermocklocation.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// On-device GPS mock (development only).
///
/// Wraps the `fluttermocklocation` plugin - the only place that third-party
/// SDK is imported - so the app can teleport the OS-level GPS for manual
/// verification (e.g. watching a submitted landmark appear as a map pin
/// without physically moving the device).
///
/// **Android-only** (the plugin ships no iOS implementation). Requires
/// Android Developer Options > "Select mock location app" to point at this
/// app; otherwise Android ignores the mock and the fix never changes.
class MockLocationService {
  const MockLocationService();

  static final Fluttermocklocation _plugin = Fluttermocklocation();

  /// Whether this build can mock the OS GPS (Android, non-web). Callers hide
  /// the dev tool when false.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Teleports the OS GPS to [latitude]/[longitude]. The app's
  /// `LocationMonitor` picks up the new fix through `geolocator` and every
  /// listening ViewModel (the dashboard included) updates - the map centres
  /// and refreshes its pins around the mocked spot.
  ///
  /// Returns `null` on success, or a message explaining why the mock failed
  /// (platform unsupported / Developer Options mock app not selected).
  Future<String?> setMockLocation(double latitude, double longitude) async {
    if (!isSupported) {
      return 'GPS mock is Android-only.';
    }
    try {
      await _plugin.updateMockLocation(latitude, longitude);
      return null;
    } catch (error) {
      return 'Mock GPS failed: $error';
    }
  }
}
