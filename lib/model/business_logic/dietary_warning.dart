/// The dietary warning a dish row carries, and the label rule behind it.
///
/// Shared by `RestaurantDiscoveryLogic` and `LandmarkSubmissionLogic`: the
/// catalogue's restaurant page and the submitted-landmark page must warn with
/// the SAME words, and two copies of this sentence would drift apart.
abstract final class DietaryWarning {
  const DietaryWarning._();

  /// A dish the app cannot check at all: not linked to a catalogue row and
  /// carrying no recorded tags of its own.
  static const String unknown =
      'Dietary information is unavailable for this dish. Check with the '
      'seller before ordering.';

  /// The warning for a dish that really does clash, or null when nothing
  /// does. Opens with the same "Contains or may include: ..." line the
  /// local-food detail page prints for a dish's own restriction tags.
  static String? forLabels(List<String> labels) => labels.isEmpty
      ? null
      : 'Contains or may include: ${labels.join(', ')}. This clashes with '
            'your dietary restriction.';

  /// The ingredient part of a restriction's name: "No Chicken" and "Contains
  /// Chicken" both read as "Chicken". The catalogue, a landmark's recorded
  /// tags and the tourist's own picks word the same restriction differently,
  /// so labels are printed - and compared - through this.
  static String label(String restrictionName) => restrictionName
      .trim()
      .replaceFirst(
        RegExp(r'^(no|contains|may contain)\s+', caseSensitive: false),
        '',
      )
      .trim();

  /// Whether a dish's own tag is the same restriction as a tourist's pick.
  static bool matches(String dishTag, String touristPick) {
    final String tag = label(dishTag).toLowerCase();
    return tag.isNotEmpty && tag == label(touristPick).toLowerCase();
  }
}
