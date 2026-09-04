import 'package:meta/meta.dart' show protected;

import '../core/base_view_model.dart';
import '../domain_model/landmark_report_reason.dart';
import '../domain_model/submitted_landmark.dart';
import '../model/business_logic/landmark_logic_facade.dart';
import 'update_restaurant_facade.dart';

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

  @protected
  LandmarkLogicFacade createLandmarkLogic() => LandmarkLogicFacade();

  late final LandmarkLogicFacade landmarkLogic = createLandmarkLogic();

  /// Broadcasts "this tourist changed the map themselves" (a report just
  /// froze the landmark they were viewing) so every live dashboard silently
  /// drops its caches and re-reads - the frozen pin disappears without a
  /// banner.
  final UpdateRestaurantFacade mapRefresh = UpdateRestaurantFacade();

  int _landmarkId = 0;
  SubmittedLandmark? _landmark;
  bool _reportSubmitted = false;
  bool _alreadyReported = false;
  bool _reportFailed = false;
  bool _requiresSignIn = false;
  bool _reportFrozePlace = false;

  SubmittedLandmark? get landmark => _landmark;

  /// True between a successfully-recorded [submitReport] and
  /// [consumeReportSubmitted] - lets the View show its confirmation after the
  /// sheet pops. A duplicate report (same tourist, same landmark) records
  /// [_alreadyReported] instead and does not flip this flag.
  bool get reportSubmitted => _reportSubmitted;

  /// True when [submitReport] found this tourist already reported this pin -
  /// the View thanks them without counting the report twice.
  bool get alreadyReported => _alreadyReported;

  /// True when [submitReport] could not reach the backend - the View shows a
  /// retry message instead of pretending the report went through.
  bool get reportFailed => _reportFailed;

  /// True when [submitReport] was attempted while signed out - reporting is a
  /// signed-in feature, so nothing was written and the View asks the tourist
  /// to sign in.
  bool get requiresSignIn => _requiresSignIn;

  /// True when THIS report crossed the freeze threshold and froze the
  /// landmark - the View leaves the page (back to the map) so the now-hidden
  /// pin is no longer shown.
  bool get reportFrozePlace => _reportFrozePlace;

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

  /// Records a report against this landmark pin in the shared `report` table
  /// (signed-in only; per-tourist dedupe, count bump, freeze once it passes
  /// the threshold - see `LandmarkSubmissionLogic.submitLandmarkReport`). The
  /// button is only reachable in the ready state, so there is no
  /// `_landmark == null` guard here - that would also block unit-testing the
  /// state transition without a loaded landmark. Failures are surfaced
  /// through [reportFailed] rather than throwing into the sheet.
  Future<void> submitReport(LandmarkReportReason reason) async {
    if (_landmarkId <= 0) return;
    try {
      final ({bool requiresSignIn, bool alreadyReported, bool frozePlace})
      outcome = await landmarkLogic.submitLandmarkReport(
        landmarkId: _landmarkId,
        reason: reason,
      );
      if (outcome.requiresSignIn) {
        _requiresSignIn = true;
      } else {
        _alreadyReported = outcome.alreadyReported;
        _reportSubmitted = !outcome.alreadyReported;
        _reportFrozePlace = outcome.frozePlace;
        if (outcome.frozePlace) {
          mapRefresh.publishOwnMapDataChanged();
        }
      }
    } catch (_) {
      _reportFailed = true;
    } finally {
      safeNotifyListeners();
    }
  }

  void consumeReportSubmitted() {
    if (!_reportSubmitted &&
        !_alreadyReported &&
        !_reportFailed &&
        !_requiresSignIn &&
        !_reportFrozePlace) {
      return;
    }
    _reportSubmitted = false;
    _alreadyReported = false;
    _reportFailed = false;
    _requiresSignIn = false;
    _reportFrozePlace = false;
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
