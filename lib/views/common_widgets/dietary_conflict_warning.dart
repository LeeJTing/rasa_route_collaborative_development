import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';

/// Warning box: this dish conflicts with the signed-in tourist's dietary
/// restrictions. Informative only - adding is still allowed.
///
/// Shared by the recognition result card and the recognised-food card, so
/// the wording (and the restriction formatting below) can never drift apart.
class DietaryConflictWarning extends StatelessWidget {
  const DietaryConflictWarning({super.key, required this.conflicts});

  final List<String> conflicts;

  /// One restriction as the sentence reads it: the stored names are the
  /// phrase "No ..." ("No Pork", "No Peanuts", ... from
  /// `dietary_restriction.restriction_name`) and the sentence already says
  /// "avoids" - "Your profile avoids: No Peanuts" reads wrong, so the prefix
  /// is dropped for display ("... avoids: Peanuts.").
  static String label(String restriction) => restriction
      .replaceFirst(RegExp(r'^\s*no\s+', caseSensitive: false), '')
      .trim();

  @override
  Widget build(BuildContext context) {
    final String names = conflicts.map(label).join(', ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.bannerCautionBackground,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.warning_amber_rounded,
            size: AppSizes.inlineNoticeIconSize,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Your profile avoids: $names. This dish may not suit you.',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
