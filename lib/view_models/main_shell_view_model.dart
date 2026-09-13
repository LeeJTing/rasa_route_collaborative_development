import '../core/base_view_model.dart';
import '../domain_model/app_tutorial.dart';
import '../model/business_logic/tourist_information_logic_facade.dart';

/// ViewModel for `MainShellView`.
///
/// Which bottom-navigation tab is selected, and whether the guided walkthrough
/// is open over it (REQ107).
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class MainShellViewModel extends BaseViewModel {
  MainShellViewModel();

  static const int tabCount = 2;

  int _currentIndex = 0;
  int get currentIndex => _currentIndex;

  void selectTab(int index) {
    if (index < 0 || index >= tabCount || index == _currentIndex) return;
    _currentIndex = index;
    safeNotifyListeners();
  }

  final TouristInformationLogicFacade touristLogic =
      TouristInformationLogicFacade();

  // ===========================================================================
  // Guided walkthrough (REQ107)
  // ===========================================================================
  //
  // The shell is where this belongs, and nowhere lower. It is the first screen
  // a signed-in tourist lands on, it outlives both tabs, and the walkthrough
  // describes the app rather than any one screen - putting it on the dashboard
  // would tie a tour of six features to the lifetime of one of them.

  /// The cards, in order. Reference data from the logic layer; this ViewModel
  /// only counts them and walks them.
  List<TutorialStep> get tutorialSteps => touristLogic.tutorialSteps;

  bool _tutorialVisible = false;

  /// Whether the walkthrough is on screen right now.
  bool get tutorialVisible => _tutorialVisible;

  int _tutorialStepIndex = 0;

  /// Which card is showing, counting from zero.
  int get tutorialStepIndex => _tutorialStepIndex;

  /// How many cards there are, so the view can draw one dot each.
  int get tutorialStepCount => tutorialSteps.length;

  /// The card to draw, or null when the walkthrough is closed or empty.
  TutorialStep? get tutorialStep {
    final List<TutorialStep> steps = tutorialSteps;
    if (!_tutorialVisible) return null;
    if (_tutorialStepIndex < 0 || _tutorialStepIndex >= steps.length) {
      return null;
    }
    return steps[_tutorialStepIndex];
  }

  /// True on the last card, where "Next" becomes "Finish".
  bool get isLastTutorialStep => _tutorialStepIndex >= tutorialStepCount - 1;

  /// Opens the walkthrough if this device is due one.
  ///
  /// The decision is the logic layer's (`AppTutorialLogic.shouldShow`) - first
  /// run, a release that added a card, or a year since it was last dismissed.
  /// Everything else answers no, which is what keeps it off an ordinary
  /// launch.
  @override
  Future<void> onInit() async {
    if (tutorialSteps.isEmpty) return;
    if (!touristLogic.shouldShowTutorial()) return;
    _tutorialStepIndex = 0;
    _tutorialVisible = true;
    safeNotifyListeners();
  }

  /// "Next" - the card after this one. On the last card this is Finish, and
  /// the view calls [finishTutorial] instead; the guard here is for a double
  /// tap racing the last frame.
  void showNextTutorialStep() {
    if (!_tutorialVisible) return;
    if (isLastTutorialStep) {
      finishTutorial();
      return;
    }
    _tutorialStepIndex++;
    safeNotifyListeners();
  }

  /// "Finish" - the tourist read to the end.
  Future<void> finishTutorial() => _closeTutorial(skipped: false);

  /// "Skip" - the tourist has had enough. Recorded exactly like finishing, so
  /// the next launch does not ask them again.
  Future<void> skipTutorial() => _closeTutorial(skipped: true);

  /// Closes first, records second, and **never lets the write hold the screen**.
  ///
  /// A failed write is not worth a red banner over a tutorial: the worst it
  /// costs is one more walkthrough on the next launch, which is the same thing
  /// a tourist would see if they reinstalled. Silent, so a storage failure
  /// cannot turn the first minute of the app into an error message.
  Future<void> _closeTutorial({required bool skipped}) async {
    if (!_tutorialVisible) return;
    _tutorialVisible = false;
    safeNotifyListeners();
    await runGuarded(
      () => skipped
          ? touristLogic.skipTutorial()
          : touristLogic.completeTutorial(),
      silent: true,
    );
  }
}
