import 'dart:async';

import '../../domain_model/tourist_location.dart';
import '../../view_models/current_location_facade.dart';
import '../repositories/landmark_repository_facade.dart';

/// Watches where the tourist is and pushes it to whichever ViewModels care.
///
/// A background process is the one component that faces both ways: it reads
/// down through a **repository facade** and writes up through a **ViewModel
/// facade**. It never holds a ViewModel, never imports Flutter, and owns no UI
/// state.
///
/// **It publishes losing the fix as loudly as getting one.** Turning GPS off
/// does not produce an event on the position stream - the stream simply goes
/// quiet, or errors - so a monitor that only forwarded fixes would leave the
/// last known position sitting on the map indefinitely. Two things guard
/// against that: the service-status stream, which fires the moment the tourist
/// flips location off in settings, and an error handler on the position stream
/// itself. Either one publishes [TouristLocation.unknown], and every ViewModel
/// downstream treats that as "no fix" and hides the marker.
///
/// **A dev GPS mock wins over the real GPS.** While `MockLocationService` is
/// active (Android presenter tool), the mocked spot is held and real fixes are
/// ignored - so the map does not jump back to the tourist's real location
/// mid-demo - and the moment the mock is stopped the real stream resumes.
class LocationMonitor {
  LocationMonitor();

  /// Down: where the fixes come from.
  final LandmarkRepositoryFacade repository = LandmarkRepositoryFacade();

  /// Up: how the fixes reach the ViewModels.
  final CurrentLocationFacade viewModelFacade = CurrentLocationFacade();

  StreamSubscription<TouristLocation>? _fixes;
  StreamSubscription<bool>? _service;
  StreamSubscription<bool>? _mock;

  /// Starts watching. Safe to call more than once - anything already running is
  /// stopped first. Publishes one immediate fix so the first screen is not
  /// blank while waiting for the stream.
  Future<void> start() async {
    await stop();

    // No permission, no fixes - and say so, rather than leaving whatever was
    // on screen before.
    if (!await repository.location.ensureLocationPermission()) {
      viewModelFacade.publish(TouristLocation.unknown);
      return;
    }

    _service = repository.location.locationServiceStream().listen(
      _onServiceChanged,
      onError: (Object _) => viewModelFacade.publish(TouristLocation.unknown),
      cancelOnError: false,
    );

    // A live dev GPS mock wins over the real GPS: hold it and do not trust
    // whatever the real stream reports until the mock is stopped.
    _mock = repository.location.mockActiveChanges().listen(
      _onMockChanged,
      onError: (Object _) {},
    );
    if (repository.location.mockActive) {
      _publishMock();
    } else {
      await _subscribeToFixes();
      viewModelFacade.publish(await repository.location.currentLocation());
    }
  }

  /// The dev mock started or stopped. Start = hold the mocked spot and drop
  /// the real stream (real fixes are not to be trusted while presenting);
  /// stop = resume real fixes and push one immediately.
  Future<void> _onMockChanged(bool active) async {
    if (active) {
      await _fixes?.cancel();
      _fixes = null;
      _publishMock();
    } else {
      await _subscribeToFixes();
      viewModelFacade.publish(await repository.location.currentLocation());
    }
  }

  /// Publishes the mocked spot, or `unknown` if the mock has no coordinates.
  void _publishMock() {
    viewModelFacade.publish(
      repository.location.mockLocation ?? TouristLocation.unknown,
    );
  }

  /// The tourist flipped location on or off in system settings.
  Future<void> _onServiceChanged(bool enabled) async {
    if (!enabled) {
      // Drop the position subscription too: it is dead once the service is
      // off, and holding it would stop a clean restart later.
      await _fixes?.cancel();
      _fixes = null;
      viewModelFacade.publish(TouristLocation.unknown);
      return;
    }

    // Back on - resubscribe and push a fresh fix straight away rather than
    // waiting for the tourist to move far enough to trigger the stream.
    // While a mock is live there is nothing to subscribe to - the mock is
    // the fix.
    if (repository.location.mockActive) {
      _publishMock();
      return;
    }
    await _subscribeToFixes();
    viewModelFacade.publish(await repository.location.currentLocation());
  }

  Future<void> _subscribeToFixes() async {
    await _fixes?.cancel();
    _fixes = repository.location.locationStream().listen(
      // Published unfiltered, including an unknown fix - that *is* the
      // signal that the position is gone.
      viewModelFacade.publish,
      onError: (Object _) => viewModelFacade.publish(TouristLocation.unknown),
      cancelOnError: false,
    );
  }

  Future<void> stop() async {
    await _fixes?.cancel();
    _fixes = null;
    await _service?.cancel();
    _service = null;
    await _mock?.cancel();
    _mock = null;
  }
}
