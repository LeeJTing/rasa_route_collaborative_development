import 'dart:async';

import 'package:fluttermocklocation/fluttermocklocation.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// On-device GPS mock (development only).
///
/// Wraps the vendored `fluttermocklocation` plugin - the only place that
/// third-party SDK is imported - so the app can teleport the OS-level GPS for
/// manual verification (e.g. watching a submitted landmark appear as a map pin
/// without physically moving the device).
///
/// **Android-only** (the plugin ships no iOS implementation). Requires
/// Android Developer Options > "Select mock location app" to point at this
/// app; otherwise Android ignores the mock and the fix never changes.
///
/// The service is stateful on purpose: it records whether a mock is live and
/// where, and streams that state so `LocationMonitor` can hold the mocked fix
/// (and stop trusting the real GPS) for exactly as long as the mock is active.
class MockLocationService {
  factory MockLocationService() => _instance;

  MockLocationService._();

  static final MockLocationService _instance = MockLocationService._();

  static final Fluttermocklocation _plugin = Fluttermocklocation();

  /// Whether this build can mock the OS GPS (Android, non-web). Callers hide
  /// the dev tool when false.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool _active = false;
  double? _latitude;
  double? _longitude;

  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  /// Whether a mock is live right now.
  bool get isActive => _active;

  /// The mocked latitude, or null when no mock is live.
  double? get latitude => _latitude;

  /// The mocked longitude, or null when no mock is live.
  double? get longitude => _longitude;

  /// Fires `true` the moment a mock starts and `false` the moment it stops.
  Stream<bool> get activeChanges => _changes.stream;

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
      _active = true;
      _latitude = latitude;
      _longitude = longitude;
      _changes.add(true);
      return null;
    } catch (error) {
      return 'Mock GPS failed: $error';
    }
  }

  /// Stops mocking: clears the OS test provider so real GPS returns, and tells
  /// `LocationMonitor` (via [activeChanges]) to resume trusting real fixes.
  ///
  /// The OS call is best-effort - even if the platform refuses, the in-app
  /// state is still cleared so the background process stops holding the mock.
  Future<void> stopMockLocation() async {
    try {
      await _plugin.stopMockLocation();
    } catch (_) {
      // Clearing the OS mock must not crash the app.
    }
    _active = false;
    _latitude = null;
    _longitude = null;
    _changes.add(false);
  }
}
