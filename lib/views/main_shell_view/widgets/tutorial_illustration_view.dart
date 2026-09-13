import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../domain_model/app_tutorial.dart';

/// The picture on a walkthrough card (REQ107).
///
/// **Drawn, not shipped.** Every illustration here is built from the app's own
/// colours and shapes rather than loaded as a bitmap, for three reasons: it
/// cannot drift out of date when a screen is restyled, it costs the bundle
/// nothing, and it renders at any density without a 1x/2x/3x set. A real
/// screenshot can replace any of them the moment one exists - fill in
/// [TutorialStep.imageAsset] and register the file under `assets:` in
/// `pubspec.yaml`, and this widget shows that instead without another change.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values. The numbers below are the
/// geometry of the drawings themselves, which is the one thing a theme cannot
/// own.
class TutorialIllustrationView extends StatelessWidget {
  const TutorialIllustrationView({super.key, required this.step});

  final TutorialStep step;

  /// Height of the picture panel. Tall enough to read, short enough that the
  /// card still fits a small phone with the text and the buttons under it.
  static const double panelHeight = 150;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: panelHeight,
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.insetSurface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Center(child: _picture()),
    );
  }

  Widget _picture() {
    // A real screenshot wins whenever one has been provided. The drawing is
    // the fallback, not the other way round.
    if (step.hasImage) {
      return Image.asset(
        step.imageAsset!,
        fit: BoxFit.contain,
        // A missing or unregistered asset must not put a red box in front of a
        // first-time tourist; fall back to the drawing.
        errorBuilder: (BuildContext _, Object __, StackTrace? ___) =>
            _drawing(),
      );
    }
    return _drawing();
  }

  Widget _drawing() => switch (step.illustration) {
    TutorialIllustration.welcome => const _WelcomeArt(),
    TutorialIllustration.heatmap => const _HeatmapArt(),
    TutorialIllustration.pins => const _PinsArt(),
    TutorialIllustration.filters => const _FiltersArt(),
    TutorialIllustration.search => const _SearchArt(),
    TutorialIllustration.swipe => const _SwipeArt(),
    TutorialIllustration.placeDetails => const _PlaceDetailsArt(),
    TutorialIllustration.addLandmark => const _AddLandmarkArt(),
  };
}

// =============================================================================
// The drawings
// =============================================================================

/// The app mark. The one illustration that is a real asset, because the logo
/// is the one thing here that cannot be redrawn from primitives.
class _WelcomeArt extends StatelessWidget {
  const _WelcomeArt();

  static const String _logo = 'assets/images/logo/logo.webp';
  static const double _size = 96;

  @override
  Widget build(BuildContext context) => Image.asset(
    _logo,
    height: _size,
    fit: BoxFit.contain,
    errorBuilder: (BuildContext _, Object __, StackTrace? ___) => const Icon(
      Icons.ramen_dining,
      size: _size,
      color: AppColors.primary,
    ),
  );
}

/// Four states shaded by availability, one of them picked out - the country
/// overview in miniature.
class _HeatmapArt extends StatelessWidget {
  const _HeatmapArt();

  static const double _tile = 34;
  static const List<Color> _shades = <Color>[
    AppColors.heatmapStep2,
    AppColors.heatmapStep1,
    AppColors.heatmapStep4,
    AppColors.heatmapStep3,
    AppColors.heatmapStep5,
    AppColors.heatmapStep2,
  ];

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    alignment: WrapAlignment.center,
    children: <Widget>[
      for (int index = 0; index < _shades.length; index++)
        Container(
          width: _tile,
          height: _tile,
          decoration: BoxDecoration(
            color: _shades[index],
            borderRadius: AppRadius.cardRadius,
            border: Border.all(
              // The one with a dark edge is the state under the tourist's
              // finger, which is the whole point of the picture.
              color: index == 1 ? AppColors.heatmapLabel : AppColors.outline,
              width: index == 1
                  ? AppSizes.heatmapSelectedBorderWidth
                  : AppSizes.heatmapBorderWidth,
            ),
          ),
        ),
    ],
  );
}

/// Two pins and a cluster badge on a patch of map.
class _PinsArt extends StatelessWidget {
  const _PinsArt();

  static const double _pin = 30;
  static const double _badge = 38;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.end,
    children: <Widget>[
      const Icon(
        Icons.place,
        size: _pin,
        color: AppColors.pinSystemRestaurant,
      ),
      const SizedBox(width: AppSpacing.lg),
      Container(
        width: _badge,
        height: _badge,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: Text(
          '12',
          style: AppTextStyles.compactBadgeLabel.copyWith(
            color: AppColors.onPrimary,
          ),
        ),
      ),
      const SizedBox(width: AppSpacing.lg),
      const Icon(Icons.place, size: _pin, color: AppColors.pinUserLandmark),
    ],
  );
}

/// Three filter rows, a couple of chips lit in each.
class _FiltersArt extends StatelessWidget {
  const _FiltersArt();

  static const List<List<bool>> _rows = <List<bool>>[
    <bool>[true, false, true],
    <bool>[false, true, false],
    <bool>[true, false, false],
  ];

  static const double _chipWidth = 44;
  static const double _chipHeight = 16;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      for (final List<bool> row in _rows)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              for (final bool selected in row)
                Container(
                  width: _chipWidth,
                  height: _chipHeight,
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(
                      color: selected ? AppColors.primary : AppColors.outline,
                    ),
                  ),
                ),
            ],
          ),
        ),
    ],
  );
}

/// A search field with two results under it.
class _SearchArt extends StatelessWidget {
  const _SearchArt();

  static const double _fieldHeight = 34;
  static const double _lineHeight = 10;

  /// How far across the panel each fake result line runs. Two different
  /// lengths, because a column of identical bars reads as a barcode rather
  /// than as text.
  static const List<double> _resultWidths = <double>[0.72, 0.48];

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      Container(
        height: _fieldHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.search,
              size: AppSizes.iconSmall,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Container(
                height: _lineHeight,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      for (final double width in _resultWidths)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: width,
              child: Container(
                height: _lineHeight,
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// Three dish cards, the middle one in the Target Frame, with a heart on it.
class _SwipeArt extends StatelessWidget {
  const _SwipeArt();

  static const double _cardWidth = 52;
  static const double _sideHeight = 68;
  static const double _centreHeight = 96;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: <Widget>[
      _card(height: _sideHeight, faded: true),
      const SizedBox(width: AppSpacing.sm),
      Stack(
        alignment: Alignment.center,
        children: <Widget>[
          _card(height: _centreHeight, faded: false),
          const Icon(
            Icons.favorite,
            size: AppSizes.addRangeIconSize,
            color: AppColors.pinSystemRestaurant,
          ),
        ],
      ),
      const SizedBox(width: AppSpacing.sm),
      _card(height: _sideHeight, faded: true),
    ],
  );

  Widget _card({required double height, required bool faded}) => Container(
    width: _cardWidth,
    height: height,
    decoration: BoxDecoration(
      color: faded ? AppColors.surfaceVariant : AppColors.surface,
      borderRadius: AppRadius.cardRadius,
      border: Border.all(
        color: faded ? AppColors.outline : AppColors.primary,
        width: faded ? AppSizes.heatmapBorderWidth : AppSizes.heatmapSelectedBorderWidth,
      ),
    ),
  );
}

/// The sheet that opens when a pin is tapped: photo, name, and a detail line.
class _PlaceDetailsArt extends StatelessWidget {
  const _PlaceDetailsArt();

  static const double _photo = 52;
  static const double _lineHeight = 10;

  /// The name line, then two shorter detail lines.
  static const List<double> _lineWidths = <double>[0.86, 0.62, 0.44];

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.cardRadius,
      border: Border.all(color: AppColors.outline),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: _photo,
          height: _photo,
          decoration: BoxDecoration(
            color: AppColors.surfaceVariant,
            borderRadius: AppRadius.cardRadius,
          ),
          child: const Icon(
            Icons.storefront,
            size: AppSizes.iconSmall,
            color: AppColors.accentBrown,
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final double width in _lineWidths) ...<Widget>[
                FractionallySizedBox(
                  widthFactor: width,
                  child: Container(
                    height: _lineHeight,
                    decoration: BoxDecoration(
                      color: AppColors.outline,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.star,
                    size: AppSizes.iconCompact,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '4.5',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// A camera frame around a dish - the recognise-and-add flow.
class _AddLandmarkArt extends StatelessWidget {
  const _AddLandmarkArt();

  static const double _frame = 92;
  static const double _dish = 46;

  @override
  Widget build(BuildContext context) => Container(
    width: _frame,
    height: _frame,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      borderRadius: AppRadius.cardRadius,
      border: Border.all(
        color: AppColors.primary,
        width: AppSizes.heatmapSelectedBorderWidth,
      ),
    ),
    child: Container(
      width: _dish,
      height: _dish,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.photo_camera,
        size: AppSizes.addRangeIconSize,
        color: AppColors.primary,
      ),
    ),
  );
}
