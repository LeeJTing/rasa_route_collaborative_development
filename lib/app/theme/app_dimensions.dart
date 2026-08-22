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

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double pill = 999;

  static const BorderRadius cardRadius = BorderRadius.all(Radius.circular(md));
  static const BorderRadius buttonRadius = BorderRadius.all(
    Radius.circular(lg),
  );
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

  /// Figma's catalogue search field.
  static const double searchFieldHeight = 46;

  /// Figma's compact Sort / Filter / Select controls.
  static const double compactControlHeight = 44;

  /// Images inside catalogue food cards.
  static const double foodCardImage = 92;

  /// Images inside restaurant cards.
  static const double restaurantCardImage = 80;

  /// Main image on the Prawn Noodle details screen.
  static const double foodHeroImage = 164;

  /// Images used in pairing rows.
  static const double pairingImage = 60;

  /// Images used in the similar-food strip.
  static const double recommendationImage = 100;

  /// Status icon used in notice and warning banners.
  static const double bannerIcon = 30;

  /// Height of the captured signboard/stall image preview in the Add
  /// Landmark image-capture row.
  static const double capturedPhotoPreviewHeight = 160;

  /// "+" icon that adds another operating-hours range row.
  static const double addRangeIconSize = 24;

  /// Short day label ("Mon"...) in the operating-hours grid.
  static const double shortDayLabelWidth = 28;

  /// Day-status toggle (dash / ? / check) box size.
  static const double compactCheckboxSize = 24;

  /// Icon inside the day-status toggle.
  static const double compactCheckboxIconSize = 16;

  /// Reserved slot for the "Open" label beside a time dropdown - wide
  /// enough for the word itself (24 clipped it).
  static const double openLabelSlotWidth = 36;

  /// Opening/closing time dropdown width - a FIXED width wide enough to show
  /// "00:00" on one line, so the box never resizes when the time changes.
  static const double timeDropdownWidth = 86;

  /// Recognised-food card label column (Dish/Variant/...) width.
  static const double fieldLabelWidth = 110;

  /// Compact label column for the recognition-result popup.
  static const double fieldLabelWidthCompact = 84;

  /// Max width of the recognition-result popup.
  static const double dialogMaxWidth = 420;

  /// Subtle catalogue-card elevation from the Figma list treatment.
  static const double cardElevation = 1;
}

/// Camera-frame guide proportions (REQ106_1) - fractions of the viewfinder's
/// own width/height, centred within it. Three distinct shapes, one per
/// capture purpose (`FoodRecognitionPurpose`) - a food item, a signboard and
/// a stall are physically different-shaped subjects, so one fixed frame
/// doesn't suit all three. Also holds the recognition result popup's
/// placement on screen.
abstract final class AppLayoutRatios {
  const AppLayoutRatios._();

  /// food / additional food: a moderate rectangle, roughly matching a plated
  /// dish.
  static const double foodFrameWidthFactor = 0.82;
  static const double foodFrameHeightFactor = 0.55;

  /// signboard: wide and short - most signboards are a horizontal banner
  /// shape, not square.
  static const double signboardFrameWidthFactor = 0.9;
  static const double signboardFrameHeightFactor = 0.3;

  /// stall: large, near-full-screen - physically the biggest subject of the
  /// three, so it needs more of the frame to fit in it.
  static const double stallFrameWidthFactor = 0.92;
  static const double stallFrameHeightFactor = 0.78;

  /// `FoodRecognitionView`'s result popup - vertical alignment offset from
  /// screen centre (negative = above centre).
  static const double popupVerticalOffset = -0.3;

  /// The result popup's max height as a fraction of the screen height.
  static const double popupMaxHeightFraction = 0.8;
}
