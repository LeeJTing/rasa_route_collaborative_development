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
}
