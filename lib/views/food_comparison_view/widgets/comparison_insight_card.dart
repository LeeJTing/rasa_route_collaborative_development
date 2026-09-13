import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/food_comparison.dart';

class ComparisonInsightCard extends StatelessWidget {
  const ComparisonInsightCard({
    required this.comparison,
    super.key,
  });

  final FoodComparison comparison;


  String get _bestMatchText {
    final bool leftOk = comparison.leftDietaryAssessment.isSuitable;
    final bool rightOk = comparison.rightDietaryAssessment.isSuitable;
    if (leftOk && rightOk) {
      return comparison.preferenceSuggestion ??
          "Try Both Food. Don't Miss Out!";
    }
    if (leftOk != rightOk) {
      final String safeName = leftOk
          ? comparison.leftFood.name
          : comparison.rightFood.name;
      return 'Try $safeName - It is Safe For You!';
    }
    return 'Both Foods Conflict With Your Dietary Restrictions. Be Careful!';
  }

  @override
  Widget build(BuildContext context) {
    final String restrictionSummary =
    comparison.activeTouristRestrictions.isEmpty
        ? 'No saved dietary restrictions were found.'
        : 'Checked against: ${comparison.activeTouristRestrictions.join(', ')}.';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadius.lg)),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.auto_awesome_rounded,
                color: AppColors.accentBrown,
                size: AppSizes.iconMedium,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'At a glance',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.accentBrown,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _InsightLine(
            label: 'Best match for you',
            value: _bestMatchText,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            restrictionSummary,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.accentBrown,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightLine extends StatelessWidget {
  const _InsightLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(
            text: '$label: ',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: AppColors.accentBrown,
            ),
          ),
          TextSpan(
            text: value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.accentBrown,
            ),
          ),
        ],
      ),
    );
  }
}