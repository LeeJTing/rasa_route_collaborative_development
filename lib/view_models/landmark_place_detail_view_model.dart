import 'package:meta/meta.dart' show protected;

import '../core/base_view_model.dart';
import '../domain_model/submitted_landmark.dart';
import '../domain_model/tourist_location.dart';
import '../model/business_logic/landmark_logic_facade.dart';
import 'current_location_facade.dart';

/// ViewModel for `LandmarkPlaceDetailView` - the full-detail page for a
/// tourist-submitted landmark, opened from the dashboard map's "View
/// Landmark" button (A11-4). Reporting lives on the separate full-screen
/// report page (`ReportPlaceView` / `ReportPlaceViewModel`), not here.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class LandmarkPlaceDetailViewModel extends BaseViewModel
    implements CurrentLocationListener {
  LandmarkPlaceDetailViewModel();

  @protected
  LandmarkLogicFacade createLandmarkLogic() => LandmarkLogicFacade();

  late final LandmarkLogicFacade landmarkLogic = createLandmarkLogic();

  /// Inbound: `LocationMonitor` publishes here (registering replays the last
  /// fix) so the header can show how far away the landmark is - the same
  /// metric the catalogue restaurant page shows.
  final CurrentLocationFacade locationFacade = CurrentLocationFacade();

  TouristLocation _currentLocation = TouristLocation.unknown;

  /// The most recent fix. [TouristLocation.unknown] until one arrives.
  TouristLocation get currentLocation => _currentLocation;

  int _landmarkId = 0;
  SubmittedLandmark? _landmark;

  SubmittedLandmark? get landmark => _landmark;

  /// Straight-line distance from the tourist to this landmark, in metres -
  /// null while the landmark has no coordinates or there is no GPS fix yet.
  /// The View formats it exactly like the restaurant header's distance.
  double? get landmarkDistanceMetres {
    final SubmittedLandmark? place = _landmark;
    final double? lat = place?.latitude;
    final double? lon = place?.longitude;
    if (place == null || lat == null || lon == null) return null;
    if (!_currentLocation.isKnown) return null;
    return landmarkLogic.distanceMetres(
      _currentLocation,
      TouristLocation(latitude: lat, longitude: lon),
    );
  }

  @override
  void onCurrentLocationChanged(TouristLocation location) {
    _currentLocation = location;
    safeNotifyListeners();
  }

  /// Set from `MapSelectionHandoff` in the View's `initState`, before
  /// `onInit()` - see that class's doc.
  void setLandmarkId(int landmarkId) {
    _landmarkId = landmarkId;
  }

  @override
  Future<void> onInit() async {
    locationFacade.register(this);
    if (_landmarkId <= 0) {
      setError('No landmark selected.');
      return;
    }
    await load();
  }

  Future<void> load() => runGuarded(() async {
    final SubmittedLandmark? landmark = await landmarkLogic
        .getSubmittedLandmarkById(_landmarkId);
    if (landmark == null) {
      // A landmark that no longer exists (e.g. reported past the threshold
      // and hidden since the pin was drawn) - say so instead of showing an
      // empty page.
      throw Exception('This landmark is no longer available.');
    }
    _landmark = landmark;
  });

  @override
  void dispose() {
    locationFacade.unregister(this);
    super.dispose();
  }
}

/// Hands a tapped `LandmarkItem` from `LandmarkPlaceDetailView`'s dish list
/// to `LandmarkItemDetailView` - same singleton hand-off pattern as
/// `LandmarkDraftHandoff`/`MapSelectionHandoff`.
///
/// Carries the whole item directly rather than just an id: unlike
/// `SubmittedLandmark`, a `LandmarkItem` has no "fetch by id" repository
/// method, and none is needed - the tapped item's full data already came
/// from this same screen's own load of the landmark, so there is nothing
/// left to fetch. `LandmarkItemDetailView` reads straight off the item,
/// no network call.
class LandmarkItemHandoff {
  factory LandmarkItemHandoff() => _instance;

  LandmarkItemHandoff._();

  static final LandmarkItemHandoff _instance = LandmarkItemHandoff._();

  LandmarkItem? pendingItem;

  /// Reads and clears the pending item.
  LandmarkItem? takeItem() {
    final LandmarkItem? item = pendingItem;
    pendingItem = null;
    return item;
  }
}
