import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';

/// "Other tourists added places - Update?" (UC300, C21).
///
/// Landmarks are contributed by tourists, so a map opened five minutes ago can
/// already be behind. `RestaurantMonitor` notices and this offers the refresh.
///
/// **It asks rather than refreshing itself.** Swapping the pins out while
/// somebody is reading a restaurant sheet is worse than being a couple of
/// minutes stale, and a map that rearranges itself unprompted feels broken.
/// Dismissing is equally valid - the next change raises it again.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class MapUpdateBanner extends StatelessWidget {
  const MapUpdateBanner({
    super.key,
    required this.message,
    required this.onUpdate,
    required this.onDismiss,
    this.busy = false,
  });

  final String message;
  final VoidCallback onUpdate;
  final VoidCallback onDismiss;

  /// The refresh is running - keeps a second tap from starting another.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bannerInfoBackground,
      borderRadius: AppRadius.cardRadius,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.sync,
              size: 18,
              color: AppColors.bannerInfoIcon,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.bannerInfoText,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else ...<Widget>[
              TextButton(
                onPressed: onUpdate,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.bannerInfoText,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                  ),
                ),
                child: const Text('Update'),
              ),
              InkWell(
                onTap: onDismiss,
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: AppSizes.minTapTarget,
                  height: 32,
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: AppColors.bannerInfoText,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
