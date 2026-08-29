import 'fluttermocklocation_platform_interface.dart';
import 'mock_location_updates.dart';

class Fluttermocklocation {
  Future<String?> getPlatformVersion() {
    return FluttermocklocationPlatform.instance.getPlatformVersion();
  }

  Future<void> updateMockLocation(double latitude, double longitude,
      {double altitude = 0, int delay = 5000}) {
    return FluttermocklocationPlatform.instance.updateMockLocation(
      latitude,
      longitude,
      altitude: altitude,
      delay: delay,
    );
  }

  /// Stops mocking and hands the GPS back to the real providers.
  ///
  /// Cancels the repeating mock-update timer and removes the Android test
  /// provider, so subsequent fixes are the device's real location again.
  Future<void> stopMockLocation() {
    return FluttermocklocationPlatform.instance.stopMockLocation();
  }

  // Aggiungi un metodo per ottenere il flusso di aggiornamenti
  Stream<Map<String, double>> get locationUpdates =>
      MockLocationUpdates.locationStream;
}
