import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../domain_model/local_food.dart';
import 'manual_food_name_entry.dart';

/// Reusable piece of `FoodRecognitionView`: the "Multiple Results Found"
/// content shown inside the popup when Gemini is unsure which of a few likely
/// dishes the photo shows (A5). The tourist taps the one they meant; the
/// ViewModel then continues the normal single-result flow.
///
/// No outer `Card` here on purpose - `FoodRecognitionView` wraps every popup
/// state in one shared card, so this widget is just the content that goes
/// inside it. Widgets in a `widgets/` folder are driven entirely by
/// constructor parameters and callbacks - they never read a ViewModel
/// themselves, and they style from the theme rather than raw values.
class MultipleResultsCard extends StatelessWidget {
  const MultipleResultsCard({
    super.key,
    required this.results,
    required this.onSelect,
    this.onEnterName,
    required this.foodNameMaxLength,
    required this.foodNameWarning,
    this.isProcessing = false,
  });

  /// The candidate foods (usually 2-3), resolved against the catalogue.
  final List<LocalFood> results;

  /// Called with the food the tourist tapped.
  final ValueChanged<LocalFood> onSelect;

  /// Manual fallback when none of the candidates is right - called with the
  /// food name the tourist typed (see
  /// `FoodRecognitionViewModel.enterFoodName`). Null hides the manual-entry
  /// field.
  final ValueChanged<String>? onEnterName;

  /// Hard input cap for the manual name field (50) + its live amber warning
  /// (from 45 characters) - the shared `LandmarkSubmissionLogic` rule,
  /// surfaced by `FoodRecognitionViewModel` so BOTH entry fields obey it.
  final int foodNameMaxLength;
  final String? Function(String name) foodNameWarning;

  /// Disables the manual-entry field/button while a name is being resolved.
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Multiple Results Found',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Please select the correct food:',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.md),
          for (int i = 0; i < results.length; i++) ...<Widget>[
            _ResultRow(
              index: i + 1,
              food: results[i],
              onTap: () => onSelect(results[i]),
            ),
            if (i < results.length - 1) const SizedBox(height: AppSpacing.sm),
          ],
          if (onEnterName != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.sm),
            // The SAME fallback as the single-result card: a collapsed
            // "Wrong dish? Type the name" link that opens the name field
            // with Cancel / Show this food (see [ManualFoodNameEntry]) -
            // it used to be an always-open field with its own label and an
            // inline button.
            ManualFoodNameEntry(
              onEnterName: onEnterName!,
              isProcessing: isProcessing,
              maxNameLength: foodNameMaxLength,
              nameWarning: foodNameWarning,
            ),
          ],
        ],
      ),
    );
  }
}

/// One tappable candidate row - a numbered circle, the dish name and its
/// origin, and a chevron to signal "tap to choose".
class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.index,
    required this.food,
    required this.onTap,
  });

  final int index;
  final LocalFood food;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceVariant,
      borderRadius: AppRadius.cardRadius,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Row(
            children: <Widget>[
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$index',
                  style: AppTextStyles.bodySmall.copyWith(
                    color: AppColors.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(food.name, style: AppTextStyles.titleSmall),
                    if (food.origin.isNotEmpty)
                      Text(
                        food.origin,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall,
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
