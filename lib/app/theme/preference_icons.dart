import 'package:flutter/material.dart';

/// Icons for the profile option cards (food preferences + dietary
/// restrictions).
///
/// The `food_preference` and `dietary_restriction` tables carry NO icon data,
/// so icons are resolved client-side from the option NAME to one of the bundled
/// photos in `assets/images/profile/`.
///
/// The photos ship at 256px on the long edge - the box they render in is 72pt
/// (216px at 3x), so anything larger only inflated the bundle. They must NOT be
/// tinted: a photo carries its own colour, and the selected state is shown by
/// the card's border instead (see `PreferenceOptionCard`).
///
/// Unknown/renamed rows return `null` so the caller falls back to a generic
/// Material icon instead of breaking the layout.
abstract final class PreferenceIcons {
  const PreferenceIcons._();

  /// Folder holding the per-option photos.
  static const String assetRoot = 'assets/images/profile/';

  /// Generic fallback for a food preference with no known icon.
  static const IconData fallbackFood = Icons.local_dining;

  /// Generic fallback for a dietary restriction with no known icon.
  static const IconData fallbackDietary = Icons.no_food;

  /// Asset for a taste/culture option, or `null` when unknown.
  static String? foodPreferenceIconAsset(String name) =>
      _asset(name, _foodAssets);

  /// Asset for a dietary restriction, or `null` when unknown.
  static String? dietaryRestrictionIconAsset(String name) =>
      _asset(name, _dietaryAssets);

  /// Exact (lower-cased) name -> asset file. Keys match the seeded
  /// `food_preference` / `dietary_restriction` values.
  static const Map<String, String> _foodAssets = <String, String>{
    'sweet': 'sweet.png',
    'salty': 'salty.png',
    'sour': 'sour.png',
    'bitter': 'bitter.png',
    'umami': 'umami.png',
    'spicy': 'spicy.png',
    'mild': 'mild.png',
    'buttery': 'buttery.png',
    'peppery': 'peppery.png',
    'savoury': 'savoury.png',
    'rich': 'rich.png',
    'light': 'light.png',
    'creamy': 'creamy.png',
    'smoky': 'smoky.png',
    'roasted': 'roasted.png',
    'fresh': 'fresh.png',
    'herbal': 'herbal.png',
    // No 'nutty' entry: the photo set has no nutty.png yet, so that option
    // falls back to the generic Material glyph. Add `'nutty': 'nutty.png'`
    // here the moment the image lands - mapping a missing file would render
    // an error box in debug instead.
    'earthy': 'earthy.png',
    'fermented': 'fermented.png',
    'tangy': 'tangy.png',
    'fragrant': 'fragrant.png',
    'refreshing': 'refreshing.png',
    'malay': 'malay.png',
    'chinese': 'chinese.png',
    'indian': 'indian.png',
    'nyonya': 'nyonya.png',
  };

  static const Map<String, String> _dietaryAssets = <String, String>{
    'no beef': 'no_beef.png',
    'no chicken': 'no_chicken.png',
    'no coconut': 'no_coconut.png',
    'no coriander/cilantro': 'no_coriander.png',
    'no corn': 'no_corn.png',
    'no dairy': 'no_dairy.png',
    'no duck': 'no_duck.png',
    'no egg': 'no_egg.png',
    'no fish': 'no_fish.png',
    'no garlic': 'no_garlic.png',
    'no ginger': 'no_ginger.png',
    'no gluten': 'no_gluten.png',
    'no mayonnaise': 'no_mayonnaise.png',
    'no mushrooms': 'no_mushrooms.png',
    'no mustard': 'no_mustard.png',
    'no mutton': 'no_mutton.png',
    'no onion': 'no_onion.png',
    'no organ meat': 'no_organ_meat.png',
    'no peanuts': 'no_peanuts.png',
    'no pork': 'no_pork.png',
    'no sesame': 'no_sesame.png',
    'no shellfish': 'no_shellfish.png',
    'no shrimp/prawn': 'no_shrimp.png',
    'no soy': 'no_soy.png',
    'no squid/octopus': 'no_squid.png',
    'no tomato': 'no_tomato.png',
    'no tree nuts': 'no_tree_nuts.png',
    'no wheat': 'no_wheat.png',
  };

  /// Exact lower-cased match first, then substring - so a renamed option
  /// (e.g. "No Peanuts Peanut Allergy") still finds its icon.
  static String? _asset(String name, Map<String, String> assets) {
    final String needle = name.toLowerCase().trim();
    final String? exact = assets[needle];
    if (exact != null) return '$assetRoot$exact';
    for (final MapEntry<String, String> entry in assets.entries) {
      if (needle.contains(entry.key)) return '$assetRoot${entry.value}';
    }
    return null;
  }
}
