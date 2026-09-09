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

  // ===========================================================================
  // Auth (ChinShunYon) - Login / OTP screens
  // ===========================================================================

  /// [Figma] Pill radius for auth fields and buttons - the mock-up uses
  /// `border-radius: 24px` on every control.
  static const double authPillRadius = 24;

  // ===========================================================================
  // End of Auth (ChinShunYon)
  // ===========================================================================
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

  /// Small icon sitting inline with body text - e.g. the "low confidence"
  /// cue on `RecognitionResultCard`. Deliberately smaller than a standard
  /// icon so it reads as part of the sentence rather than its own element.
  static const double inlineNoticeIconSize = 14;

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

  // ---------------------------------------------------------------------------
  // REQ102 - Dashboard map (measured off the Figma "Heatmap View" /
  // "Detialed Map View" frames, both 390 x 833)
  // ---------------------------------------------------------------------------

  /// Search field on the heatmap view - narrower, because the Filter button
  /// sits beside it.
  static const double mapSearchFieldWidth = 264;

  /// Search field / Filter button height on the heatmap view.
  static const double mapSearchFieldHeight = 44;

  /// The "Filter" pill next to the heatmap search field.
  static const double mapFilterButtonWidth = 92;

  /// Floating map control column width (zoom in/out, Find Me).
  static const double mapControlWidth = 44;

  /// Combined height of the stacked zoom-in / zoom-out control.
  static const double mapZoomControlHeight = 73;

  /// Height of the Find Me control.
  static const double mapFindMeHeight = 38;

  /// Icon inside a floating map control.
  static const double mapControlIconSize = 20;

  /// The round Quick Mode button in the bottom-left corner of the map.
  static const double mapQuickModeButton = 50;

  /// The visible height of one filter chip - 24 in the Figma frame.
  static const double filterChipHeight = 24;

  /// The chip's *tap* height. The pill stays 24 tall, but a 24pt target is
  /// half [minTapTarget] and misses are easy - and a miss used to land on the
  /// map behind the panel and close it, which made the filter feel like it
  /// only accepted one choice. 40 rather than the full 48 because four rows of
  /// 48 would make the panel taller than the map it is filtering.
  static const double filterChipTapHeight = 40;

  /// Ceiling on the filter panel. Open every group and the Taste row alone
  /// wraps to five lines - past this the rows scroll instead of the panel
  /// growing off the screen and taking its own close control with it.
  static const double filterPanelMaxHeight = 340;

  /// The fixed label pill ("Meal", "Category", "Taste", "Type") that opens a
  /// filter row.
  static const double filterGroupLabelWidth = 72;

  /// Discovery Layer Bar (REQ102_10) - the centred Target Frame card.
  static const double discoveryTargetCardWidth = 167;
  static const double discoveryTargetCardHeight = 218;

  /// Discovery Layer Bar - the cards queued either side of the Target Frame.
  static const double discoveryQueueCardWidth = 163;
  static const double discoveryQueueCardHeight = 143;

  /// Height of the Discovery Layer Bar when the tourist has opened it.
  static const double discoveryLayerBarHeight = 236;

  /// Its resting height - a peek showing the grabber, what the map is filtered
  /// to, and the Matches count. REQ103_1 describes the bar as a sliding
  /// bottom-sheet, and 236pt of empty placeholder over the map is not a map.
  static const double discoveryLayerBarCollapsedHeight = 66;

  /// The "Matches" pill floating above the Discovery Layer Bar.
  static const double matchesButtonHeight = 31;

  /// "Click Map Pin" sheet - the square restaurant photo on its left.
  static const double pinSheetImage = 102;

  /// The "Serves: ..." strip under the details.
  static const double pinSheetServesStrip = 35;

  /// Marker drawn for a restaurant / landmark pin on the detailed map.
  static const double mapPinSize = 36;

  /// Maximum height of the search-suggestion dropdown.
  static const double searchSuggestionsMaxHeight = 280;

  /// Boundary line between states on the heatmap, in logical pixels. Divided
  /// by the canvas scale when painted, so it stays this wide on screen however
  /// far the tourist has zoomed in.
  static const double heatmapBorderWidth = 1.1;

  /// The same line for the state the tourist has selected.
  static const double heatmapSelectedBorderWidth = 2.6;

  /// The tourist's own position marker.
  static const double currentLocationDot = 11;

  /// Corner radius of the map surface, which sits as a card on the cream
  /// scaffold rather than bleeding to the screen edge.
  static const double mapCardRadius = 18;

  /// One swatch in the availability legend.
  static const double legendSwatch = 18;

  /// Elevation of a card while it is selected for comparison - a stronger
  /// shadow so the selected card stands out without tinting its surface.
  static const double selectedCardElevation = 4;

  /// Standard small icon (inline with body text).
  static const double iconSmall = 18;

  /// Compact icon used inside dense catalogue and restaurant metadata rows.
  static const double iconCompact = 16;

  /// Standard medium icon (section headers, notices).
  static const double iconMedium = 24;

  /// Hairline divider / border width.
  static const double borderWidth = 1;

  /// Stronger border width (1.5) - auth pill borders and selected-option
  /// borders that need to read clearly on cream.
  static const double borderWidthStrong = 1.5;

  /// Dish image height in the food-comparison pair card.
  static const double comparisonImageHeight = 140;

  /// Max body width of `FoodComparisonView` (two columns side by side).
  static const double comparisonMaxWidth = 720;

  /// `LandmarkPlaceDetailView`'s photo, sized by `imageCategory` (signboard
  /// vs stall) rather than one fixed height for both - a stall photo is
  /// captured tall (see `AppLayoutRatios.stallFrameHeightFactor`), and
  /// forcing it into a short, wide frame with `BoxFit.cover` was cropping
  /// away most of it. A signboard photo is captured wide/short, so it fits
  /// the shorter frame fine.
  static const double landmarkPhotoHeightWide = 140;
  static const double landmarkPhotoHeightTall = 280;

  /// Fallback when `imageCategory` is unknown - splits the difference.
  static const double landmarkPhotoHeightDefault = 180;

  // ===========================================================================
  // Auth (ChinShunYon) - Login / OTP screens
  // ===========================================================================

  /// [Figma] Login avatar: 100px cream circle holding the rice-ball.
  static const double authAvatarRadius = 50;

  /// [Figma] Rice-ball emoji inside the login avatar.
  static const double authEmojiSize = 48;

  /// [Figma] OTP badge: 80px cream circle holding the mail icon.
  static const double authBadgeRadius = 40;

  /// [Figma] Mail icon inside the OTP badge.
  static const double authBadgeIconSize = 36;

  // ===========================================================================
  // End of Auth (ChinShunYon)
  // ===========================================================================

  // ===========================================================================
  // Tourist profile (ChinShunYon) - edit-screen option cards
  // ===========================================================================

  /// [Figma] Square icon box inside a preference/restriction option card.
  static const double profileOptionBox = 72;

  /// [Figma] Placeholder icon inside [profileOptionBox] (images not added).
  static const double profileOptionIcon = 32;

  /// Long-label max width - matches the 72px option box so the card never
  /// grows wider than its box. A wider label (e.g. "No Coriander/Cilantro")
  /// is what pushed a 4-per-row Wrap onto a new line; capping the label to
  /// the box width keeps every card the same size.
  static const double profileOptionLabelMaxWidth = 72;

  /// Leading icon inside the Profile screen's list rows and email card.
  static const double profileListIconSize = 22;

  /// Trailing icon (chevron / edit) inside the Profile screen's rows.
  static const double profileListTrailingIconSize = 20;

  /// Inline loader diameter shown in the Profile email card while the
  /// tourist's profile is still being fetched on first open.
  static const double profileEmailLoaderSize = 18;

  /// Blur radius of the soft shadow under the edit-screen option cards.
  static const double cardShadowBlur = 8;

  /// Vertical offset of the edit-screen option-card shadow.
  static const double cardShadowOffsetY = 2;

  // ===========================================================================
  // End of Tourist profile (ChinShunYon)
  // ===========================================================================
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

  /// Initial and maximum heights for the catalogue filter bottom sheet.
  static const double catalogueFilterSheetInitial = 0.8;
  static const double catalogueFilterSheetMaximum = 0.92;

  // ===========================================================================
  // Tourist profile (ChinShunYon) - edit-screen option grid
  // ===========================================================================

  /// [Figma] Fixed height (px) of one cell in the "All Restrictions" grid:
  /// the 72px option box plus a two-line label (e.g. "No Coriander/Cilantro")
  /// with room to spare, so long restriction names wrap instead of
  /// overflowing the cell. A fixed extent (rather than a width-relative
  /// aspect ratio) keeps two-line labels fitting on narrow phones too.
  static const double profileOptionGridMainAxisExtent = 140;

  /// Columns in the "Chosen on top" / "All Restrictions" option grids.
  static const int profileOptionGridCrossAxisCount = 4;

  // ===========================================================================
  // End of Tourist profile (ChinShunYon)
  // ===========================================================================

  // ===========================================================================
  // Auth (ChinShunYon) - Login / OTP form rhythm
  // ===========================================================================

  /// Top spacer weight on the login and OTP forms (pushes the avatar / badge
  /// group down from the app-bar area).
  static const int authTopSpacerFlex = 2;

  /// Bottom spacer weight on the login form (pushes the Google row up).
  static const int authBottomSpacerFlex = 3;

  // ===========================================================================
  // End of Auth (ChinShunYon)
  // ===========================================================================
}
