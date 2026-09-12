import '../app/routing/app_navigator.dart';
import '../app/routing/app_routes.dart';
import '../core/base_view_model.dart';
import '../domain_model/landmark_draft.dart';
import '../model/business_logic/landmark_logic_facade.dart';
import 'food_recognition_view_model.dart' show LandmarkDraftHandoff;

/// ViewModel for `IncompleteLandmarksView`.
///
/// The signed-in tourist's saved (incomplete) Add-New-Landmark forms - one
/// row each, newest first. Tapping one continues it on the Add-Landmark
/// form; discarding one deletes it (and the photos uploaded for it). Drafts
/// live 24 hours from their last save; expired ones are removed when the
/// list loads, so this screen never shows a draft that can no longer be
/// continued.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class IncompleteLandmarksViewModel extends BaseViewModel {
  IncompleteLandmarksViewModel();

  final LandmarkLogicFacade landmarkLogic = LandmarkLogicFacade();

  List<LandmarkDraft> _drafts = const <LandmarkDraft>[];

  List<LandmarkDraft> get drafts => List<LandmarkDraft>.unmodifiable(_drafts);

  /// How long a draft stays resumable after its last save (24 hours).
  Duration get draftLifetime => landmarkLogic.landmarkDraftLifetime;

  @override
  Future<void> onInit() async {
    await load();
  }

  Future<void> load() => runGuarded(() async {
    _drafts = await landmarkLogic.pendingLandmarkDrafts();
  });

  /// Continues a draft - the same hand-off + push the camera screen's
  /// auto-continue uses when the same dish is captured again. The list
  /// reloads when the form pops back, so a submitted/discarded draft
  /// disappears.
  Future<void> openDraft(LandmarkDraft draft) async {
    LandmarkDraftHandoff().pendingDraft = draft;
    await AppNavigator.push(AppRoutes.addLandmark);
    await load();
  }

  /// Discards one draft after the tourist confirmed it: the row and its
  /// uploaded photos are deleted.
  Future<void> discardDraft(LandmarkDraft draft) => runGuarded(() async {
    await landmarkLogic.discardLandmarkDraft(draft);
    _drafts = _drafts
        .where((LandmarkDraft pending) => pending.id != draft.id)
        .toList(growable: false);
  });
}
