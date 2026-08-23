import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';

/// The floating white card the dashboard map slides up from the bottom.
///
/// One shell, two users: the state summary the heatmap shows when a state is
/// tapped, and the brief restaurant overlay of A11. Both are a title, a
/// subtitle, a few facts and one primary action, so they share this rather
/// than each rolling their own.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class DashboardMapCard extends StatelessWidget {
  const DashboardMapCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onDismiss,
    this.leading,
    this.facts = const <String>[],
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String subtitle;

  /// A11.1 - tapping the map outside the card, or the close button here.
  final VoidCallback onDismiss;

  final Widget? leading;

  /// Short one-line facts listed under the subtitle.
  final List<String> facts;

  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.sheetRadius,
        boxShadow: <BoxShadow>[
          BoxShadow(color: AppColors.shadow, blurRadius: 16, offset: Offset(0, -2)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.outline,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (leading != null) ...<Widget>[
                leading!,
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: AppTextStyles.titleMedium),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              InkWell(
                onTap: onDismiss,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(AppSpacing.xs),
                  child: Icon(
                    Icons.close,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (facts.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            for (final String fact in facts)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(
                      Icons.circle,
                      size: 5,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(fact, style: AppTextStyles.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],
          if (actionLabel != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
