import '../core/base_view_model.dart';
import '../model/business_logic/landmark_logic_facade.dart';
import '../model/data_models/location_data_model.dart';
import 'current_location_facade.dart';

/// ViewModel for `AddLandmarkView`.
///
/// Submit a new food landmark.
///
/// Implements [CurrentLocationListener] so a background process can
/// push updates in through an inbound ViewModel facade. Register in `onInit`,
/// unregister in `dispose` - forgetting the second leaks this object.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class AddLandmarkViewModel extends BaseViewModel implements CurrentLocationListener {
  AddLandmarkViewModel();

  final LandmarkLogicFacade landmarkLogic = LandmarkLogicFacade();

  /// Inbound: `LocationMonitor` publishes here.
  final CurrentLocationFacade locationFacade = CurrentLocationFacade();

  @override
  Future<void> onInit() async {
    locationFacade.register(this);
  }

  /// Pushed by `LocationMonitor` through [CurrentLocationFacade].
  @override
  void onCurrentLocationChanged(LocationDataModel location) {
    _location = location;
    safeNotifyListeners();
  }

  LocationDataModel _location = LocationDataModel.unknown;

  LocationDataModel get location => _location;

  @override
  void dispose() {
    locationFacade.unregister(this);
    super.dispose();
  }
}
