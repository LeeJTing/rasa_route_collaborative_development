import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';

/// The signed-in tourist's email address, shown as a display-only row at the
/// top of the Profile screen (above the preference cards).
///
/// Mirrors the mock-up's cards: white surface, warm border, rounded corners.
class ProfileEmailCard extends StatelessWidget {
  const ProfileEmailCard({super.key, required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: AppColors.cardBorderWarm),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.mail_outline,
            color: AppColors.accentBrown,
            size: AppSizes.profileListIconSize,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Email',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: Text(
              email.isEmpty ? 'Not signed in' : email,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.accentBrown,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
