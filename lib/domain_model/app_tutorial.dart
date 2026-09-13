/// The guided walkthrough a tourist sees the first time they open Rasa Route,
/// and again after a long absence (REQ107).
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. The step list itself is business
/// reference data and lives on `AppTutorialLogic`, not here, exactly as the
/// filter option lists live on `MapExplorationLogic`.

/// One card of the walkthrough: a heading, a sentence, and a picture.
///
/// **Adding a feature to the tutorial is adding one of these** to
/// `AppTutorialLogic.steps` and bumping `AppTutorialLogic.version`. Nothing
/// else in the tutorial knows how many steps there are.
class TutorialStep {
  const TutorialStep({
    required this.id,
    required this.title,
    required this.message,
    required this.illustration,
    this.imageAsset,
  });

  /// Stable identifier for this step, e.g. `heatmap`. Never shown; it exists so
  /// a step can be reordered or removed without the others shifting meaning.
  final String id;

  /// The heading - four or five words.
  final String title;

  /// One sentence. Two at the very most: a tourist reads this standing up.
  final String message;

  /// Which built-in picture to draw. Drawn from the app's own theme rather
  /// than shipped as a bitmap, so it can never drift from the screen it is
  /// describing and costs the bundle nothing.
  final TutorialIllustration illustration;

  /// A real screenshot to show instead of [illustration], when one exists.
  ///
  /// The escape hatch, and the reason the two live side by side: the drawn
  /// pictures are here so the tutorial works today, and a designer can replace
  /// any one of them with a screenshot later by filling this in and registering
  /// the file under `assets:` in `pubspec.yaml`. Nothing else has to change.
  final String? imageAsset;

  /// Whether [imageAsset] names a file to load.
  bool get hasImage => imageAsset != null && imageAsset!.trim().isNotEmpty;
}

/// The pictures the walkthrough can draw for itself.
///
/// A domain enum rather than a widget one, so the step list can name a picture
/// without the business layer importing Flutter.
enum TutorialIllustration {
  welcome,
  heatmap,
  pins,
  swipe,
  filters,
  search,
  placeDetails,
  addLandmark,
}

/// What the device remembers about the walkthrough.
///
/// Deliberately small: whether it has been finished, when it was last put in
/// front of somebody, and which version of the step list that was. Everything
/// the "show it again?" rule needs and nothing else.
class TutorialProgress {
  const TutorialProgress({
    required this.completed,
    required this.shownAt,
    required this.version,
  });

  /// Nothing stored yet - a device that has never shown the tutorial.
  static const TutorialProgress never = TutorialProgress(
    completed: false,
    shownAt: null,
    version: 0,
  );

  /// True once the tourist reached the end **or** pressed Skip. Skipping is a
  /// decision, not an interruption, so it counts the same.
  final bool completed;

  /// When the tutorial was last dismissed, either way. Null means never.
  final DateTime? shownAt;

  /// `AppTutorialLogic.version` as it was at that moment, so a later release
  /// that adds a step can show the walkthrough again without waiting a year.
  final int version;

  /// Whether this device has seen the tutorial at all.
  bool get hasBeenShown => shownAt != null;
}
