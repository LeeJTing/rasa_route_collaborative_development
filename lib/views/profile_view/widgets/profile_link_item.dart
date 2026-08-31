import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';

/// One tappable row on the Profile screen - e.g. "Favourite Foods",
/// "My Landmarks" or "Log Out".
///
/// Mirrors the mock-up's list items: a white rounded card, a leading icon, a
/// label and an optional chevron.
class ProfileLinkItem extends StatelessWidget {
  const ProfileLinkItem({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    this.onTap,
    this.showChevron = true,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback? onTap;

  /// False hides the trailing chevron - used by "Log Out", which has none.
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.cardBorderWarm),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.cardRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  color: iconColor,
                  size: AppSizes.profileListIconSize,
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (showChevron)
                  const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                    size: AppSizes.profileListTrailingIconSize,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
