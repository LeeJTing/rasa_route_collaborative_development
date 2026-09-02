import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';

/// A white rounded card on the Profile screen: an accent-brown title with an
/// optional edit button on the right, then the card's content underneath.
///
/// Mirrors the "Food Preference" / "Dietary Restriction" cards in the mock-up
/// (white surface, warm border, brown title, edit affordance).
class ProfileSectionCard extends StatelessWidget {
  const ProfileSectionCard({
    super.key,
    required this.title,
    this.onEdit,
    required this.child,
  });

  final String title;

  /// When provided, an edit icon appears on the card's right edge.
  final VoidCallback? onEdit;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.cardBorderWarm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.accentBrown,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: 'Edit $title',
                  onPressed: onEdit,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.edit_outlined,
                    color: AppColors.accentBrown,
                    size: AppSizes.profileListTrailingIconSize,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}
