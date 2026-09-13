import '../../domain_model/app_tutorial.dart';
import '../repositories/tourist_repository_facade.dart';

/// The guided walkthrough: what it says, and when it is shown (REQ107).
///
/// Business rules live here. The ViewModel asks "should I show this?" and
/// "what are the cards?" and does not know the answer to either.
///
/// **To add a feature to the tutorial:** add a [TutorialStep] to [steps] and
/// increase [version] by one. Nothing else changes - the overlay counts the
/// list, the progress dots count the list, and Next becomes Finish on the last
/// one. Raising [version] also brings the walkthrough back for tourists who
/// have already seen the old one, instead of leaving them a year behind the
/// feature it describes.
class AppTutorialLogic {
  AppTutorialLogic();

  final TouristRepositoryFacade repository = TouristRepositoryFacade();

  /// How long an existing tourist goes without the tutorial before it is worth
  /// showing again. A year, per the requirement: long enough that nobody sees
  /// it twice in one trip, short enough that somebody returning next season is
  /// reintroduced to a map they have forgotten.
  static const Duration repeatAfter = Duration(days: 365);

  /// Bumped whenever [steps] changes in a way a tourist should see.
  ///
  /// Reordering or rewording does not need it. Adding a card for a feature
  /// that did not exist last release does.
  static const int version = 1;

  /// The walkthrough, in order.
  ///
  /// Each card names one thing the tourist can do and stops. The order follows
  /// the order a tourist meets these screens: the country map first, then what
  /// is on it, then the ways to narrow it, then the two things they can do
  /// with what they found.
  static const List<TutorialStep> steps = <TutorialStep>[
    TutorialStep(
      id: 'welcome',
      title: 'Welcome to Rasa Route',
      message:
          'A quick tour of how to find Malaysian local food around you. '
          'It takes about a minute.',
      illustration: TutorialIllustration.welcome,
    ),
    TutorialStep(
      id: 'heatmap',
      title: 'See where the food is',
      message:
          'The map shades every state by how much local food it has. '
          'Greener means more; tap a state to look closer.',
      illustration: TutorialIllustration.heatmap,
    ),
    TutorialStep(
      id: 'pins',
      title: 'Zoom in for places',
      message:
          'Zoom past a state and the map shows individual restaurants and '
          'landmarks other tourists added. A numbered circle holds several - '
          'tap it to open it up.',
      illustration: TutorialIllustration.pins,
    ),
    TutorialStep(
      id: 'filters',
      title: 'Narrow it to your taste',
      message:
          'Filter by meal, cuisine, taste and food type. Pick as many as you '
          'like in each row, then press Apply.',
      illustration: TutorialIllustration.filters,
    ),
    TutorialStep(
      id: 'search',
      title: 'Search for anything',
      message:
          'Type a dish, a state, a city or a restaurant name. Spelling it the '
          'way you say it is fine - "nasi lemak" and "nasilemak" both work.',
      illustration: TutorialIllustration.search,
    ),
    TutorialStep(
      id: 'swipe',
      title: 'Swipe to discover',
      message:
          'Not sure what you want? Swipe through dishes near you and the map '
          'follows along. Double-tap one you like to save it to Matches.',
      illustration: TutorialIllustration.swipe,
    ),
    TutorialStep(
      id: 'place-details',
      title: 'Open a place',
      message:
          'Tap a pin for the photo, distance, price range, opening hours and '
          'the local food it serves.',
      illustration: TutorialIllustration.placeDetails,
    ),
    TutorialStep(
      id: 'add-landmark',
      title: 'Add what you find',
      message:
          'Point the camera at a dish to identify it, or add a stall that is '
          'not on the map yet so other tourists can find it too.',
      illustration: TutorialIllustration.addLandmark,
    ),
  ];

  /// Whether the walkthrough should open now.
  ///
  /// Three ways to say yes, and they are checked in this order because each is
  /// a stronger claim than the one after it:
  ///
  ///  * **this device has never shown it** - a first-time tourist;
  ///  * **it has, but of an older [version]** - there is a card they have not
  ///    seen;
  ///  * **it has, of this version, but [repeatAfter] ago or longer** - the
  ///    returning tourist the requirement is about.
  ///
  /// Anything else is no. That "anything else" is the important half: an
  /// ordinary launch the day after the tutorial was dismissed answers no, and
  /// that is what stops it appearing every time the app opens.
  bool shouldShow() {
    final TutorialProgress progress = repository.tutorialProgress();
    final DateTime? shownAt = progress.shownAt;
    if (shownAt == null) return true;
    if (progress.version < version) return true;

    final Duration elapsed = DateTime.now().difference(shownAt);
    // A record stamped in the future is one the device clock has moved under -
    // it cannot be aged, and leaving it alone would retire the tutorial
    // permanently on that phone. Treat it as due; the cost is one walkthrough.
    if (elapsed.isNegative) return true;
    return elapsed >= repeatAfter;
  }

  /// The tourist reached the last card and pressed Finish.
  Future<void> markCompleted() => _record(completed: true);

  /// The tourist pressed Skip. Recorded exactly like finishing: they have been
  /// offered the tour and answered, and asking again tomorrow would be asking
  /// them to answer twice.
  Future<void> markSkipped() => _record(completed: true);

  /// Forgets the record, so the next launch shows the walkthrough again.
  /// Nothing in the app calls this - it is for a debug build and for tests.
  Future<void> reset() => repository.clearTutorialProgress();

  Future<void> _record({required bool completed}) =>
      repository.saveTutorialProgress(
        TutorialProgress(
          completed: completed,
          shownAt: DateTime.now(),
          version: version,
        ),
      );
}
