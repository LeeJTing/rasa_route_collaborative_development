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
}
