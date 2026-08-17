import 'package:flutter/widgets.dart';

/// Spacing, radius and sizing scale.
///
/// RULE: no magic numbers in Views. Every `EdgeInsets`, `SizedBox` and
/// `BorderRadius` should pull from here so the 4pt grid stays consistent
/// with the Figma mock-up.
abstract final class AppSpacing {
  const AppSpacing._();

  /// 4
  static const double xs = 4;

  /// 8
  static const double sm = 8;

  /// 12
  static const double md = 12;

  /// 16 - default screen gutter.
  static const double lg = 16;

  /// 24
  static const double xl = 24;

  /// 32
  static const double xxl = 32;

  /// Default horizontal padding for a screen body.
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(horizontal: lg);

  /// Default padding inside a card.
  static const EdgeInsets cardPadding = EdgeInsets.all(md);
}

/// Corner radii.
abstract final class AppRadius {
  const AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius buttonRadius = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius sheetRadius = BorderRadius.vertical(
    top: Radius.circular(xl),
  );

  static const double xl = 24;
}

/// Fixed component sizes taken from the mock-up.
abstract final class AppSizes {
  const AppSizes._();

  /// [Figma] App bar height, measured off the mock-up's "App bar" component.
  static const double appBarHeight = 81;

  /// [Figma] Compact app bar variant, used on screens with no back button.
  static const double appBarHeightCompact = 70;

  /// [Figma] Back / action icon inside the app bar.
  static const double appBarIconSize = 30;

  /// [Figma] Bottom navigation bar height.
  static const double bottomNavHeight = 74;

  /// [Figma] Centre camera button diameter.
  static const double navFabDiameter = 58;

  /// [Figma] Bottom nav icon size.
  static const double navIconSize = 25;

  /// Standard minimum tap target (accessibility).
  static const double minTapTarget = 48;

  /// Default button height.
  static const double buttonHeight = 52;

  /// Default text field height.
  static const double fieldHeight = 52;

  /// Avatar sizes.
  static const double avatarSm = 32;
  static const double avatarMd = 48;
  static const double avatarLg = 96;
}
