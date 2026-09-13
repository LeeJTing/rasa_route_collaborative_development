/// The ONE place-category rule, shared by every screen that shows a place's
/// category, so Quick Mode, Matches, the map pin sheet, Landmark History and
/// Landmark Place Detail can never read differently.
///
/// Two facts drive it:
///   * a landmark is STORED with one category (its primary dish's food
///     category) even though its dishes can disagree, so the category the
///     tourist sees is the one MOST of the dishes carry;
///   * the `restaurant` catalogue stores the FULL phrase ("Chinese
///     restaurant"), so a landmark says the same thing instead of a bare
///     "Chinese".
library;

/// The category MOST of [dishCategories] carry - each trimmed, blanks
/// skipped. A tie goes to the category whose dish comes first, which keeps
/// the answer stable for a given dish order (user request, 2026-09-13).
/// Falls back to [fallback] (trimmed) when no dish carries one, and to ''
/// when neither does - an unknown category is never invented.
String majorityCategory(
  Iterable<String> dishCategories, {
  String fallback = '',
}) {
  final Map<String, int> counts = <String, int>{};
  String best = '';
  for (final String raw in dishCategories) {
    final String category = raw.trim();
    if (category.isEmpty) continue;
    final int count = (counts[category] ?? 0) + 1;
    counts[category] = count;
    // Strictly greater, so the FIRST category to reach a count keeps it.
    if (best.isEmpty || count > counts[best]!) best = category;
  }
  return best.isNotEmpty ? best : fallback.trim();
}

/// [category] worded the way the catalogue's own places read theirs: the
/// `restaurant` table stores the full phrase ("Chinese restaurant"), so a
/// landmark says the same thing instead of a bare "Chinese" (user request,
/// 2026-09-13) - with the word "Restaurant" CAPITALISED (user request,
/// 2026-09-14: "make the restaurant capital letter R"), whether the word is
/// appended or already in the stored phrase. An unknown category stays empty
/// rather than inventing the word.
String placeCategoryLabel(String category) {
  final String trimmed = category.trim();
  if (trimmed.isEmpty) return '';
  if (trimmed.toLowerCase().contains('restaurant')) {
    return trimmed.replaceFirst(
      RegExp('restaurant', caseSensitive: false),
      'Restaurant',
    );
  }
  return '$trimmed Restaurant';
}
