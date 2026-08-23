/// The Smart Filtering selection driving the heatmap (REQ102_23 - REQ102_29).
///
/// Four independent groups, **one option each**. Picking a different option in
/// a group replaces whatever was there; picking the option that is already
/// chosen clears the group. `null` means "no constraint from this group",
/// which is what the "All" chip selects.
///
/// Modelled as four nullable values rather than four sets, so the type itself
/// says only one option can be held. The option lists (C2 - C5) are business
/// reference data and live on `MapExplorationLogic`, not here.
///
/// Domain models are plain data types: constructor and fields. No JSON, no
/// matching rules - matching a food against a filter is the logic layer's job.
class ExplorationFilter {
  const ExplorationFilter({this.meal, this.category, this.taste, this.type});

  /// Nothing selected - the default state of the dashboard.
  static const ExplorationFilter none = ExplorationFilter();

  /// C2: All-Day Dining | Breakfast | Brunch | Lunch | High Tea | Dinner |
  /// Supper | Street Food (REQ102_24).
  final String? meal;

  /// C3: Malay | Chinese | Indian | Nyonya | Sabah | Sarawak (REQ102_25).
  final String? category;

  /// C4: Sweet | Salty | Sour | ... | Refreshing (REQ102_26).
  final String? taste;

  /// C5: Food | Beverage | Fruit | Dessert | Kuih (REQ102_27).
  final String? type;

  /// How many of the four groups are constrained - the badge on the Filter
  /// button.
  int get selectionCount => <String?>[
    meal,
    category,
    taste,
    type,
  ].where((String? option) => option != null).length;
}

/// The four independent groups of [ExplorationFilter] (REQ102_23).
///
/// A domain enum rather than a ViewModel one, so the filter widgets can name a
/// group without importing a ViewModel.
enum ExplorationFilterGroup { meal, category, taste, type }
