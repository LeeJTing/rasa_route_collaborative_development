import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';

/// REQ102_16 / REQ102_17 - grey at 0, green at 1, generated in between.
///
/// Interpolates along `AppColors.heatmapScale` (which runs highest → lowest),
/// so the five legend swatches and every shade on the map come from one list
/// and nothing picks a colour per state.
Color heatmapColourFor(double score) {
  final List<Color> scale = AppColors.heatmapScale;
  final double clamped = score.clamp(0, 1).toDouble();

  // score 1 -> first entry (green), score 0 -> last entry (grey).
  final double position = (1 - clamped) * (scale.length - 1);
  final int lower = position.floor().clamp(0, scale.length - 1);
  final int upper = position.ceil().clamp(0, scale.length - 1);
  if (lower == upper) return scale[lower];

  return Color.lerp(scale[lower], scale[upper], position - lower) ??
      scale[lower];
}

/// The scale key: "High Availability" over the five steps, "Low Availability"
/// beside them (REQ102_16).
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key, required this.maximumPlaceCount});

  /// C1's denominator - how many places the best-served state has.
  /// Printed as a caption so the scale means something concrete, and so the
  /// map says plainly when there is no data behind it yet.
  final int maximumPlaceCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'High Availability',
          style: AppTextStyles.labelSmall.copyWith(
            color: AppColors.heatmapLabel,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final Color step in AppColors.heatmapScale)
              Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: Container(
                  width: AppSizes.legendSwatch,
                  height: AppSizes.legendSwatch,
                  decoration: BoxDecoration(
                    color: step,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                ),
              ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'Low Availability',
              style: AppTextStyles.labelSmall.copyWith(
                color: AppColors.heatmapLabel,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          maximumPlaceCount == 0
              ? 'No places mapped yet'
              : 'Best-served state: $maximumPlaceCount places',
          style: AppTextStyles.mapMicroLabel,
        ),
      ],
    );
  }
}
