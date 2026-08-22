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
}
