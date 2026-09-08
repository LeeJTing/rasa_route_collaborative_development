import 'package:flutter/material.dart';

/// Icons for the profile option cards (food preferences + dietary
/// restrictions).
///
/// The `food_preference` and `dietary_restriction` tables carry NO icon data,
/// so icons are resolved client-side from the option NAME to one of the
/// bundled SVG assets in `assets/images/profile/`. Those assets were sourced
/// from online open-source icon sets:
///   * Material Design Icons (Apache-2.0) - the majority;
///   * Phosphor Icons (MIT) - peppery, no_shrimp;
///   * Lucide-lab (ISC) - no_garlic, no_onion, no_shellfish.
///
/// Unknown/renamed rows return `null` so the caller falls back to a generic
/// Material icon instead of breaking the layout.
abstract final class PreferenceIcons {
  const PreferenceIcons._();

  /// Folder holding the per-option icon SVGs.
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
    'sweet': 'sweet.svg',
    'salty': 'salty.svg',
    'sour': 'sour.svg',
    'bitter': 'bitter.svg',
    'umami': 'umami.svg',
    'spicy': 'spicy.svg',
    'mild': 'mild.svg',
    'buttery': 'buttery.svg',
    'peppery': 'peppery.svg',
    'savoury': 'savoury.svg',
    'rich': 'rich.svg',
    'light': 'light.svg',
    'creamy': 'creamy.svg',
    'smoky': 'smoky.svg',
    'roasted': 'roasted.svg',
    'fresh': 'fresh.svg',
    'herbal': 'herbal.svg',
    'nutty': 'nutty.svg',
    'earthy': 'earthy.svg',
    'fermented': 'fermented.svg',
    'tangy': 'tangy.svg',
    'fragrant': 'fragrant.svg',
    'refreshing': 'refreshing.svg',
    'malay': 'malay.svg',
    'chinese': 'chinese.svg',
    'indian': 'indian.svg',
    'nyonya': 'nyonya.svg',
  };

  static const Map<String, String> _dietaryAssets = <String, String>{
    'no beef': 'no_beef.svg',
    'no chicken': 'no_chicken.svg',
    'no coconut': 'no_coconut.svg',
    'no coriander/cilantro': 'no_coriander.svg',
    'no corn': 'no_corn.svg',
    'no dairy': 'no_dairy.svg',
    'no duck': 'no_duck.svg',
    'no egg': 'no_egg.svg',
    'no fish': 'no_fish.svg',
    'no garlic': 'no_garlic.svg',
    'no ginger': 'no_ginger.svg',
    'no gluten': 'no_gluten.svg',
    'no mayonnaise': 'no_mayonnaise.svg',
    'no mushrooms': 'no_mushrooms.svg',
    'no mustard': 'no_mustard.svg',
    'no mutton': 'no_mutton.svg',
    'no onion': 'no_onion.svg',
    'no organ meat': 'no_organ_meat.svg',
    'no peanuts': 'no_peanuts.svg',
    'no pork': 'no_pork.svg',
    'no sesame': 'no_sesame.svg',
    'no shellfish': 'no_shellfish.svg',
    'no shrimp/prawn': 'no_shrimp.svg',
    'no soy': 'no_soy.svg',
    'no squid/octopus': 'no_squid.svg',
    'no tomato': 'no_tomato.svg',
    'no tree nuts': 'no_tree_nuts.svg',
    'no wheat': 'no_wheat.svg',
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
