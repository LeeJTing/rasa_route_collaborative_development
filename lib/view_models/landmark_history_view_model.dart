import '../app/routing/app_navigator.dart';
import '../app/routing/map_selection_handoff.dart';
import '../app/routing/app_routes.dart';
import '../core/base_view_model.dart';
import '../domain_model/submitted_landmark.dart';
import '../model/business_logic/landmark_logic_facade.dart';

/// ViewModel for `LandmarkHistoryView`.
///
/// Landmarks this tourist submitted, with moderation status. One tourist can
/// add MANY landmarks, so this is a plain scrollable list - the underlying
/// query is already bounded to the tourist's own rows (see
/// `SubmittedLandmarkRepository.getSubmittedLandmarksByTourist`), so there
/// is nothing to paginate by hand.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class LandmarkHistoryViewModel extends BaseViewModel {
  LandmarkHistoryViewModel();

  final LandmarkLogicFacade landmarkLogic = LandmarkLogicFacade();

  List<SubmittedLandmark> _landmarks = const <SubmittedLandmark>[];

  List<SubmittedLandmark> get landmarks => _landmarks;

  @override
  Future<void> onInit() async {
    await load();
  }

  Future<void> load() => runGuarded(() async {
    final String? touristId = await landmarkLogic.currentTouristId();
    if (touristId == null || touristId.isEmpty) {
      // Not signed in (or session not resolved yet) - nothing to show.
      _landmarks = const <SubmittedLandmark>[];
      return;
    }
    _landmarks = await landmarkLogic.getSubmittedLandmarksByTourist(touristId);
  });

  /// Open one of the tourist's landmarks in the full place-detail screen
  /// (the same screen the map's "View Landmark" button opens) - the id rides
  /// the shared [MapSelectionHandoff], which that screen reads in `initState`.
  void openLandmark(SubmittedLandmark landmark) {
    MapSelectionHandoff().pendingLandmarkId = landmark.id;
    AppNavigator.push(AppRoutes.landmarkPlaceDetail);
  }
}
