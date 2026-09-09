import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';

/// The signed-in tourist's email address, shown as a display-only row at the
/// top of the Profile screen (above the preference cards).
///
/// Mirrors the mock-up's cards: white surface, warm border, rounded corners.
class ProfileEmailCard extends StatelessWidget {
  const ProfileEmailCard({
    super.key,
    required this.email,
    this.isLoading = false,
  });

  final String email;

  /// True while the tourist's profile is still being fetched on first open.
  /// While loading the trailing slot shows a small progress indicator instead
  /// of the email, so a profile that is about to show a real address never
  /// flashes the misleading "Not signed in" fallback for a moment.
  final bool isLoading;

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
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Flexible(
            child: isLoading
                ? const Align(
                    alignment: Alignment.centerRight,
                    child: SizedBox(
                      width: AppSizes.profileEmailLoaderSize,
                      height: AppSizes.profileEmailLoaderSize,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Text(
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
