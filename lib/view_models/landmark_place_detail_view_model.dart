import '../core/base_view_model.dart';
import '../domain_model/submitted_landmark.dart';
import '../model/business_logic/landmark_logic_facade.dart';

/// Why a tourist is reporting a submitted-landmark pin. Mirrors the
/// catalogue's `RestaurantReportReason` (the report feature was first built
/// for normal restaurant detail, and is now also offered on submitted
/// landmark pins) - reasons phrased for a tourist-submitted restaurant.
enum LandmarkReportReason {
  noLongerExists,
  incorrectName,
  incorrectLocation,
  incorrectOperatingHours,
  incorrectInformation,
}

/// ViewModel for `LandmarkPlaceDetailView` - the full-detail page for a
/// tourist-submitted landmark, opened from the dashboard map's "View
/// Landmark" button (A11-4).
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

  final LandmarkLogicFacade landmarkLogic = LandmarkLogicFacade();

  int _landmarkId = 0;
  SubmittedLandmark? _landmark;
  bool _reportSubmitted = false;

  SubmittedLandmark? get landmark => _landmark;

  /// True between a successful [submitReport] and [consumeReportSubmitted] -
  /// lets the View show its confirmation after the sheet pops.
  bool get reportSubmitted => _reportSubmitted;

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

  /// Records a report against this landmark pin. UI-only stub for now, the
  /// same as `RestaurantDetailViewModel.submitReport` - a later repository
  /// iteration will submit the reason through an authenticated RPC and
  /// enforce the unique-user threshold that freezes a landmark after enough
  /// reports. The button is only reachable in the ready state (a landmark is
  /// loaded), so there is no `_landmark == null` guard here - that would also
  /// block unit-testing the state transition without a loaded landmark.
  Future<void> submitReport(LandmarkReportReason reason) async {
    _reportSubmitted = true;
    safeNotifyListeners();
  }

  void consumeReportSubmitted() {
    if (!_reportSubmitted) return;
    _reportSubmitted = false;
    safeNotifyListeners();
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
