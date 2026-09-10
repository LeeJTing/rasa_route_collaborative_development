import 'package:meta/meta.dart' show protected;

import '../core/base_view_model.dart';
import '../domain_model/submitted_landmark.dart';
import '../model/business_logic/landmark_logic_facade.dart';

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
class LandmarkPlaceDetailViewModel extends BaseViewModel {
  LandmarkPlaceDetailViewModel();

  @protected
  LandmarkLogicFacade createLandmarkLogic() => LandmarkLogicFacade();

  late final LandmarkLogicFacade landmarkLogic = createLandmarkLogic();

  int _landmarkId = 0;
  SubmittedLandmark? _landmark;

  SubmittedLandmark? get landmark => _landmark;

  /// Set from `MapSelectionHandoff` in the View's `initState`, before
  /// `onInit()` - see that class's doc.
  void setLandmarkId(int landmarkId) {
    _landmarkId = landmarkId;
  }

  @override
  Future<void> onInit() async {
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
