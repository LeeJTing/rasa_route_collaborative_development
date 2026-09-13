import 'package:flutter/material.dart';

/// Single source of truth for every colour in Rasa Route.
///
/// Values marked `[Figma]` are lifted directly from the mock-up
/// (https://www.figma.com/design/oOcjCvoyodV4qdNvOW2dlg/Colloborative-Development-Mock-up).
/// Values marked `[Derived]` are tints/shades computed from the Figma palette so
/// that states (hover, disabled, dividers) stay on-brand.
///
/// RULE: never write a raw `Color(0xFF...)` inside a View or Widget.
/// Add the token here first, then reference it as `AppColors.xxx`, or better,
/// read it off the theme via `Theme.of(context).colorScheme`.
abstract final class AppColors {
  const AppColors._();

  // ---------------------------------------------------------------------------
  // Brand
  // ---------------------------------------------------------------------------

  /// [Figma] Primary action orange - CTA buttons, active nav item, camera FAB.
  static const Color primary = Color(0xFFFF9700);

  /// [Derived] Pressed / hovered state of [primary].
  static const Color primaryDark = Color(0xFFE07E00);

  /// [Derived] 12% primary - selected chips, highlighted list rows.
  static const Color primaryContainer = Color(0xFFFFE3BF);

  /// [Figma] Secondary amber - ratings, badges, secondary emphasis.
  static const Color secondary = Color(0xFFF0B400);

  /// [Derived] Muted amber background for badges.
  static const Color secondaryContainer = Color(0xFFFDEFC2);

  // ---------------------------------------------------------------------------
  // Surfaces
  // ---------------------------------------------------------------------------

  /// [Figma] App-wide cream scaffold background.
  static const Color background = Color(0xFFFFF8E7);

  /// [Derived] Cards, sheets, dialogs sitting on top of [background].
  static const Color surface = Color(0xFFFFFFFF);

  /// [Figma] Bottom navigation bar / elevated cream band.
  static const Color surfaceVariant = Color(0xFFFFEDBE);

  /// [Derived] Hairline dividers and input borders on cream.
  static const Color outline = Color(0xFFE8DCBB);

  // ---------------------------------------------------------------------------
  // Content
  // ---------------------------------------------------------------------------

  /// [Derived] Default body / heading text.
  static const Color textPrimary = Color(0xFF2B2B2B);

  /// [Figma] Muted text and inactive nav icons.
  static const Color textSecondary = Color(0xFF7F91A8);

  /// [Derived] Placeholder text, disabled labels.
  static const Color textDisabled = Color(0xFFB4BFCB);

  /// [Derived] Text/icons drawn on top of [primary].
  static const Color onPrimary = Color(0xFFFFFFFF);

  // ---------------------------------------------------------------------------
  // Semantic / status
  // ---------------------------------------------------------------------------

  static const Color success = Color(0xFF3FA34D);
  static const Color warning = Color(0xFFF0B400);
  static const Color error = Color(0xFFD64545);
  static const Color info = Color(0xFF3E7CB1);

  // ---------------------------------------------------------------------------
  // Utility
  // ---------------------------------------------------------------------------

  static const Color transparent = Color(0x00000000);

  /// Solid backdrop behind the live camera preview and capture controls.
  static const Color cameraBackground = Color(0xFF000000);

  /// [Derived] Scrim behind modal bottom sheets and image overlays.
  static const Color scrim = Color(0x66000000);

  /// [Derived] Card shadow.
  static const Color shadow = Color(0x1A000000);

  // ---------------------------------------------------------------------------
  // Accent text (Quick Mode / Food Detail headings)
  // ---------------------------------------------------------------------------

  /// [Figma] Warm brown used for section headings and the Food Detail /
  /// Quick Mode app-bar titles - "Quick Mode", "Prawn Noodle", "Description".
  static const Color accentBrown = Color(0xFFAC7F5E);

  /// [Figma] Rust-brown used for prices and pairing dish names.
  static const Color accentRust = Color(0xFFA05823);

  /// [Figma] Muted brown body text on restaurant/article cards.
  static const Color accentBrownMuted = Color(0xFF7A6A5B);

  // ---------------------------------------------------------------------------
  // Tag chips (cuisine / taste / meal-type / food-type)
  // ---------------------------------------------------------------------------
  // The mock-up colour-codes chips by what they describe. Reused across the
  // Quick Mode restaurant cards and the Food Detail tag row.

  /// [Figma] Cuisine / category chip, e.g. "Chinese". Also the match-score badge.
  static const Color tagCategoryBackground = Color(0xFFE8F5E9);
  static const Color tagCategoryBorder = Color(0xFFC8E6C9);
  static const Color tagCategoryText = Color(0xFF1B5E20);

  /// [Figma] Taste / cooking-style chip, e.g. "Spicy".
  static const Color tagTasteBackground = Color(0xFFFFEBEE);
  static const Color tagTasteBorder = Color(0xFFFFCDD2);
  static const Color tagTasteText = Color(0xFFC62828);

  /// [Figma] Meal-type chip, e.g. "All-Day Dining", "Street Food".
  static const Color tagMealTypeBackground = Color(0xFFFFEACA);
  static const Color tagMealTypeBorder = Color(0xFFFFD79B);
  static const Color tagMealTypeText = Color(0xFFE65100);

  /// [Figma] Generic food-type chip, e.g. "Food", "Beverage".
  static const Color tagNeutralBackground = Color(0xFFF5F5F5);
  static const Color tagNeutralBorder = Color(0xFFE0E0E0);
  static const Color tagNeutralText = Color(0xFF424242);

  // ===========================================================================
  // Tourist profile (ChinShunYon) - dietary-restriction chips
  // ===========================================================================

  /// [Figma] Dietary-restriction chip, Matches the mock-up's chip colours.
  static const Color tagDietaryBackground = Color(0xFFEBF8FF);
  static const Color tagDietaryBorder = Color(0xFFBEE3F8);
  static const Color tagDietaryText = Color(0xFF3182CE);

  // ===========================================================================
  // End of Tourist profile (ChinShunYon)
  // ===========================================================================

  // ---------------------------------------------------------------------------
  // Banners (Quick Mode notice, allergy warning, name-collision caution)
  // ---------------------------------------------------------------------------

  /// [Figma] "Showing Nearby Restaurants" info banner.
  static const Color bannerInfoBackground = Color(0xB39EFFB3);
  static const Color bannerInfoIcon = Color(0xFF1F7300);
  static const Color bannerInfoText = Color(0xFF1F7300);

  /// [Figma] Allergy warning banner on Food Detail.
  static const Color bannerWarningBackground = Color(0xB3FFA9A9);
  static const Color bannerWarningText = Color(0xFF921616);

  /// [Figma] Name-collision caution banner on Food Detail.
  static const Color bannerCautionBackground = Color(0xB3FDFD82);
  static const Color bannerCautionText = Color(0xFF575700);

  /// [Figma] Warm card border used on Food Detail's info card.
  static const Color cardBorderWarm = Color(0xFFFFE082);

  /// [Figma] Neutral border around catalogue and restaurant cards.
  static const Color cardBorder = Color(0xFFEEE3D5);

  /// [Figma] Warm inset panel used by an expanded restaurant menu.
  static const Color insetSurface = Color(0xFFF8F1E6);

  /// [Figma] Selected source-tab background.
  static const Color tabBackground = Color(0xFFFFEACA);

  // ---------------------------------------------------------------------------
  // UC500 (Add Landmark / recognition flow)
  // ---------------------------------------------------------------------------

  /// [Derived] 15% success - the "recognised successfully" banner.
  static const Color successContainer = Color(0x263FA34D);

  /// [Figma] Field-label colour on the food detail card - Dish, Variant,
  /// Origin, Food Category, Meal Type, Taste, Description, Cooking Style,
  /// Cultural Background.
  static const Color detailLabel = Color(0xFFAC7F5E);

  /// [Figma] Highlight box behind the Dish/Variant/description preview in
  /// the recognition-result popup (`FoodRecognitionView`) - FFE082 at 40%
  /// opacity.
  static const Color recognitionHighlight = Color(0x66FFE082);

  /// [Figma] Background for the "Taste" tags (Spicy / Sweet / Rich).
  static const Color tasteTagBackground = Color(0xFFFFCDD2);

  /// [Figma] Text colour on [tasteTagBackground].
  static const Color tasteTagText = Color(0xFFC62828);

  /// [Figma] Opening/closing time chip in the operating-hours grid
  /// (`AddLandmarkView`).
  static const Color timeChipBackground = Color(0xFFFFF0C5);

  // ---------------------------------------------------------------------------
  // REQ102 - Local food distribution heatmap
  // ---------------------------------------------------------------------------
  // REQ102_16: green is the highest local-food availability score, grey the
  // lowest. REQ102_17: every shade in between is `Color.lerp`-ed from these
  // two, so the gradient is generated, never hand-picked per state.

  // The five-step availability scale, highest score first. REQ102_16 fixes the
  // ends - green for the highest score, grey for the lowest; REQ102_17
  // generates everything between, which `heatmapColourFor` does by
  // interpolating along this list. The legend prints the five steps as-is.

  /// [REQ102_16] Highest availability score.
  ///
  /// Sampled off the reference mock-up rather than invented: its land runs
  /// from about #A0D375 to #D8E67C, a yellow-green range rather than the
  /// blue-greens a default palette reaches for. The top step is pushed a
  /// little darker than anything in the reference so the scale has somewhere
  /// to go at the high end.
  static const Color heatmapStep1 = Color(0xFF6FBB5E);
  static const Color heatmapStep2 = Color(0xFF96CC6E);
  static const Color heatmapStep3 = Color(0xFFB9D97B);
  static const Color heatmapStep4 = Color(0xFFD6E27F);

  /// [REQ102_16] Lowest availability score. Warm grey, not neutral - a cold
  /// grey reads as "broken" next to the cream ground.
  static const Color heatmapStep5 = Color(0xFFDDDCD0);

  static const List<Color> heatmapScale = <Color>[
    heatmapStep1,
    heatmapStep2,
    heatmapStep3,
    heatmapStep4,
    heatmapStep5,
  ];

  static const Color heatmapHigh = heatmapStep1;
  static const Color heatmapLow = heatmapStep5;

  /// The heatmap draws on the plain cream scaffold rather than over map tiles,
  /// so the fill is close to opaque - the softness comes from the blur, not
  /// from transparency.
  static const double heatmapFillOpacity = 1;

  /// Boundary line between states on the heatmap. Warm grey rather than black
  /// so it separates the states without turning a soft map into a chart.
  static const Color heatmapBorder = Color(0xFF8A8578);
  static const double heatmapBorderOpacity = 0.58;

  /// Label text sitting directly on the heatmap.
  static const Color heatmapLabel = Color(0xFF3D3D3D);

  /// Floating map control (zoom, Find Me) background.
  static const Color mapControlBackground = Color(0xFFFFFFFF);

  /// Hairline between the "+" and "-" halves of the zoom control.
  static const Color mapControlDivider = Color(0xFFE0E0E0);

  /// The tourist's own position marker on the detailed map.
  static const Color currentLocationMarker = Color(0xFF1E88E5);

  // ---------------------------------------------------------------------------
  // Map pins (REQ102_32)
  // ---------------------------------------------------------------------------
  // Two sources, two colours, so a tourist can tell at a glance whether a place
  // came from the catalogue or from another tourist.

  /// A landmark another tourist submitted.
  static const Color pinUserLandmark = Color(0xFFF2B01E);

  /// A restaurant the system already knew about.
  static const Color pinSystemRestaurant = Color(0xFFD32F2F);

  /// Darker edge of whichever pin colour, for the selected pin.
  static const Color pinSelectedRing = Color(0xFF2B2B2B);

  // A search result keeps its source colour - a restaurant found by name is
  // still a restaurant - and is marked by a ring around it instead. Colouring
  // it differently would have cost the one thing the two pin colours exist to
  // say.

  /// Ring drawn around a marker the current keyword matched.
  static const Color pinSearchRing = Color(0xFF00897B);

  /// The wash inside that ring, so the marker reads as lifted off the map.
  static const Color pinSearchHalo = Color(0x3300897B);

  /// A cluster badge on the search layer. The same teal as the pin ring, so
  /// "this came from what you typed" is one colour whether it is drawn as a
  /// marker or as a count.
  static const Color clusterSearchFill = secondary;
}
