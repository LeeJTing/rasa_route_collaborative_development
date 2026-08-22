import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Typography scale for Rasa Route.
///
/// The mock-up uses Roboto throughout. Weights and sizes below map onto the
/// Material 3 `TextTheme` slots that [AppTheme] installs, so in a View you
/// normally read `Theme.of(context).textTheme.titleMedium` rather than
/// touching this class directly. Reach for [AppTextStyles] only when you need
/// a one-off style that has no `TextTheme` slot.
abstract final class AppTextStyles {
  const AppTextStyles._();

  static const String fontFamily = 'Roboto';

  // Display / headline -------------------------------------------------------

  static const TextStyle headlineLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: AppColors.textPrimary,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 1.25,
    color: AppColors.textPrimary,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 1.3,
    color: AppColors.textPrimary,
  );

  // Title --------------------------------------------------------------------

  static const TextStyle titleLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    fontWeight: FontWeight.w600,
    height: 1.35,
    color: AppColors.textPrimary,
  );

  static const TextStyle titleMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  static const TextStyle titleSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  // Body ---------------------------------------------------------------------

  static const TextStyle bodyLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodySmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.45,
    color: AppColors.textSecondary,
  );

  // Label --------------------------------------------------------------------

  static const TextStyle labelLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.onPrimary,
  );

  /// [Figma] Bottom navigation label - inactive.
  static const TextStyle labelMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
    color: AppColors.textSecondary,
  );

  /// [Figma] Bottom navigation label - active.
  static const TextStyle labelMediumSelected = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 1.2,
    color: AppColors.primary,
  );

  static const TextStyle labelSmall = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.2,
    color: AppColors.textSecondary,
  );

  /// [Figma] Operating-hours grid - day abbreviation (Mon/Tue/...) and the
  /// Open/Unknown/Closed checkbox labels. Deliberately much smaller than the
  /// rest of the scale - matches the mock-up's compact grid.
  static const TextStyle operatingHoursLabel = TextStyle(
    fontFamily: fontFamily,
    fontSize: 9,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: AppColors.textPrimary,
  );

  // Food detail card (RecognisedFoodDetailsView) ----------------------------
  //
  // These three use Inter (via google_fonts), not the shared Roboto
  // [fontFamily] above - that's per the Figma spec for this one card, not a
  // mistake. `GoogleFonts.inter(...)` fetches/caches the font at runtime
  // (see the google_fonts package), which is why these are `static final`
  // rather than `static const` like everything else in this file - a
  // network call can't happen at compile time.

  /// [Figma] "Taste" tag text (Spicy / Sweet / Rich) - pair with
  /// [AppColors.tasteTagText] on [AppColors.tasteTagBackground].
  static final TextStyle tasteTag = GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w600, // Semi Bold
    color: AppColors.tasteTagText,
  );

  /// [Figma] Field labels on the food detail card - Dish, Variant, Origin,
  /// Food Category, Meal Type, Taste, Description, Cooking Style, Cultural
  /// Background. Pair with [AppColors.detailLabel]. Reused for the same
  /// Dish/Variant labels in the `FoodRecognitionView` result popup.
  static final TextStyle detailLabel = GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w700, // Bold
    color: AppColors.detailLabel,
  );

  /// [Figma] Field values on the food detail card (e.g. the description
  /// paragraph) - plain black body text at the same 10sp scale.
  static final TextStyle detailValue = GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w500, // Medium
    color: const Color(0xFF000000),
  );

  /// [Figma] Dish/Variant values and the description preview in the
  /// `FoodRecognitionView` result popup. Spec calls for weight 236, which
  /// isn't a real font weight - Flutter (and every font file Google Fonts
  /// serves) only has the 9 standard steps, 100 through 900 in multiples of
  /// 100. w200 is the nearest available step; flag it if that reads too
  /// light in practice.
  static final TextStyle recognitionInfoValue = GoogleFonts.inter(
    fontSize: 10,
    fontWeight: FontWeight.w200,
    color: const Color(0xFF000000),
  );
}
