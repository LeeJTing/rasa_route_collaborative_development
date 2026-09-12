/// The Smart Filtering selection driving the heatmap (REQ102_23 - REQ102_29).
///
/// Four independent groups, **any number of options each**. Ticking an option
/// adds it to its group; ticking it again takes it out. An empty group is no
/// constraint from that group, which is what the "All" chip selects.
///
/// The two rules the sets encode:
///
/// * options **within** one group are OR - Breakfast *or* Lunch;
/// * the groups themselves are AND - (Breakfast or Lunch) *and* Malay.
///
/// Modelled as four sets rather than four nullable strings. It began as the
/// latter, on the reading that a group behaved like a radio row, but JT asked
/// for several options at once per category, and the type is what has to say so
/// - matching code that reads a `String?` cannot be handed two answers.
///
/// Domain models are plain data types: constructor and fields. No JSON, no
/// matching rules - matching a food against a filter is the logic layer's job.
/// The option lists themselves (C2 - C5) are business reference data and live
/// on `MapExplorationLogic`, not here.
class ExplorationFilter {
  const ExplorationFilter({
    this.meals = const <String>{},
    this.categories = const <String>{},
    this.tastes = const <String>{},
    this.types = const <String>{},
  });

  /// Nothing selected - the default state of the dashboard.
  static const ExplorationFilter none = ExplorationFilter();

  /// C2: All-Day Dining | Breakfast | Brunch | Lunch | High Tea | Dinner |
  /// Supper | Street Food (REQ102_24).
  final Set<String> meals;

  /// C3: Malay | Chinese | Indian | Nyonya | Sabah | Sarawak (REQ102_25).
  final Set<String> categories;

  /// C4: Sweet | Salty | Sour | ... | Refreshing (REQ102_26).
  final Set<String> tastes;

  /// C5: Food | Beverage | Fruit | Dessert | Kuih (REQ102_27).
  final Set<String> types;

  /// The options ticked in [group].
  ///
  /// A field lookup, not a rule: it saves every caller that works group by
  /// group - the panel, the ViewModel, the cache key - writing out the same
  /// four-way switch over the field names.
  Set<String> selectionFor(ExplorationFilterGroup group) => switch (group) {
    ExplorationFilterGroup.meal => meals,
    ExplorationFilterGroup.category => categories,
    ExplorationFilterGroup.taste => tastes,
    ExplorationFilterGroup.type => types,
  };

  /// How many options are ticked in total - the badge on the Filter button.
  ///
  /// Options rather than groups. With one option per group the two numbers were
  /// the same; now that a group can hold several, the count of chips is the one
  /// that matches what the tourist can see selected.
  int get selectionCount =>
      meals.length + categories.length + tastes.length + types.length;

  /// True when no group constrains anything.
  bool get isEmpty => selectionCount == 0;
}

/// The four independent groups of [ExplorationFilter] (REQ102_23).
///
/// A domain enum rather than a ViewModel one, so the filter widgets can name a
/// group without importing a ViewModel.
enum ExplorationFilterGroup { meal, category, taste, type }
