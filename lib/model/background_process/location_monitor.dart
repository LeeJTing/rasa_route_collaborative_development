import 'dart:async';

import '../../model/data_models/location_data_model.dart';
import '../../view_models/current_location_facade.dart';
import '../repositories/landmark_repository_facade.dart';

/// Polls the device for GPS fixes and pushes them to whichever ViewModels care.
///
/// A background process is the one component that faces both ways: it reads
/// down through a **repository facade** and writes up through a **ViewModel
/// facade**. It never holds a ViewModel, never imports Flutter, and owns no UI
/// state.
class LocationMonitor {
  LocationMonitor();

  /// Down: where the fixes come from.
  final LandmarkRepositoryFacade repository = LandmarkRepositoryFacade();

  /// Up: how the fixes reach the ViewModels.
  final CurrentLocationFacade viewModelFacade = CurrentLocationFacade();

  StreamSubscription<LocationDataModel>? _subscription;

  /// Starts streaming GPS fixes into [viewModelFacade]. Safe to call more than
  /// once (any existing subscription is stopped first). Also pushes one
  /// immediate fix so the first screen isn't blank while waiting for the
  /// stream's first event.
  Future<void> start() async {
    await stop();

    // Ask for the OS permission once - no permission, no fixes, and the
    // location pickers simply keep showing "Locating...".
    if (!await repository.location.ensureLocationPermission()) return;

    final Stream<LocationDataModel> fixes = repository.location
        .locationStream();
    _subscription = fixes.listen((LocationDataModel fix) {
      if (fix.isKnown) viewModelFacade.publish(fix);
    });

    final LocationDataModel current = await repository.location
        .currentLocation();
    if (current.isKnown) viewModelFacade.publish(current);
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
