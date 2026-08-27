import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';

enum FoodNoticeType { allergy, caution }

class FoodNoticeBanner extends StatelessWidget {
  const FoodNoticeBanner({
    super.key,
    required this.message,
    required this.type,
    this.onTap,
  });

  final String message;
  final FoodNoticeType type;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final bool warning = type == FoodNoticeType.allergy;
    final Color background = warning
        ? AppColors.bannerWarningBackground
        : AppColors.bannerCautionBackground;
    final Color foreground = warning
        ? AppColors.bannerWarningText
        : AppColors.bannerCautionText;
    return Material(
      color: background,
      borderRadius: AppRadius.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Row(
            children: <Widget>[
              Icon(
                warning ? Icons.warning_amber_rounded : Icons.info_outline,
                color: foreground,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: foreground),
                ),
              ),
              if (onTap != null) Icon(Icons.chevron_right, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}
