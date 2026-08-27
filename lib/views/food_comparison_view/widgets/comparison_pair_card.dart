import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/food_comparison.dart';
import '../../../domain_model/local_food.dart';
import '../../common_widgets/app_image.dart';
import 'dietary_status_badge.dart';

class ComparisonPairCard extends StatelessWidget {
  const ComparisonPairCard({required this.comparison, super.key});

  final FoodComparison comparison;

  @override
  Widget build(BuildContext context) {
    final LocalFood left = comparison.leftFood;
    final LocalFood right = comparison.rightFood;

    return ClipRRect(
      borderRadius: AppRadius.cardRadius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.surface,
          border: Border.all(color: AppColors.outline),
          borderRadius: AppRadius.cardRadius,
        ),
        child: Column(
          children: <Widget>[
            _PairRow(
              left: _FoodHeader(food: left),
              right: _FoodHeader(food: right),
              padded: true,
            ),
            _ComparisonSection(
              title: 'Dietary safety',
              icon: Icons.health_and_safety_rounded,
              left: DietaryStatusBadge(
                assessment: comparison.leftDietaryAssessment,
              ),
              right: DietaryStatusBadge(
                assessment: comparison.rightDietaryAssessment,
              ),
            ),
            _ComparisonSection(
              title: 'Ingredients & allergens',
              icon: Icons.list_alt_rounded,
              left: _BulletList(items: _splitIngredients(left.ingredients)),
              right: _BulletList(items: _splitIngredients(right.ingredients)),
            ),
            _ComparisonSection(
              title: 'Origin & heritage',
              icon: Icons.public_rounded,
              left: _LabeledText(
                label: left.origin,
                value: left.culturalBackground,
              ),
              right: _LabeledText(
                label: right.origin,
                value: right.culturalBackground,
              ),
            ),
            _ComparisonSection(
              title: 'Cooking style',
              icon: Icons.soup_kitchen_rounded,
              left: Text(left.cookingStyle),
              right: Text(right.cookingStyle),
            ),
            _ComparisonSection(
              title: 'Time and Price',
              icon: Icons.schedule_rounded,
              left: _TimeAndPrice(mealType: left.mealType),
              right: _TimeAndPrice(mealType: right.mealType),
            ),
            _ComparisonSection(
              title: 'What to expect',
              icon: Icons.reviews_rounded,
              left: Text(left.description),
              right: Text(right.description),
            ),
            _ComparisonSection(
              title: 'How to say it',
              icon: Icons.record_voice_over_rounded,
              left: Text(left.pronunciationText),
              right: Text(right.pronunciationText),
            ),
          ],
        ),
      ),
    );
  }
}

class _FoodHeader extends StatelessWidget {
  const _FoodHeader({required this.food});

  final LocalFood food;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SizedBox(
          height: AppSizes.comparisonImageHeight,
          width: double.infinity,
          child: AppImage(
            source: food.imageUrls.isEmpty ? null : food.imageUrls.first,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          food.name,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          food.category,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ComparisonSection extends StatelessWidget {
  const _ComparisonSection({
    required this.title,
    required this.icon,
    required this.left,
    required this.right,
  });

  final String title;
  final IconData icon;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return Padding(
      // More breathing room above and below each section now that the
      // horizontal dividers between them are gone.
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: <Widget>[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            // FFE082 at 100%.
            color: AppColors.cardBorderWarm,
            child: Row(
              children: <Widget>[
                Icon(
                  icon,
                  size: AppSizes.iconSmall,
                  color: AppColors.accentBrown,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: AppColors.accentBrown,
                  ),
                ),
              ],
            ),
          ),
          _PairRow(left: left, right: right, padded: true),
        ],
      ),
    );
  }
}

class _PairRow extends StatelessWidget {
  const _PairRow({
    required this.left,
    required this.right,
    required this.padded,
  });

  final Widget left;
  final Widget right;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final EdgeInsetsGeometry padding = padded
        ? const EdgeInsets.all(AppSpacing.md)
        : EdgeInsets.zero;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Padding(padding: padding, child: left),
          ),
          const VerticalDivider(
            width: AppSizes.borderWidth,
            color: AppColors.accentBrown,
          ),
          Expanded(
            child: Padding(padding: padding, child: right),
          ),
        ],
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('Ingredients not recorded.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map(
            (String item) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text('• $item'),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _LabeledText extends StatelessWidget {
  const _LabeledText({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(value),
      ],
    );
  }
}

/// One side of the "Time and Price" comparison section - shows when the dish
/// is best eaten and its restaurant price range.
class _TimeAndPrice extends StatelessWidget {
  const _TimeAndPrice({required this.mealType});

  final String mealType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Best For: $mealType',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        // Restaurant price data is not modelled in this app yet, so there is
        // no range to summarise - show the neutral placeholder.
        Text(
          'Price Range: Not listed yet',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// Splits the repository's raw ingredients string (comma / semicolon / a
/// JSON-array-shaped blob) into bullet-list entries.
List<String> _splitIngredients(String raw) => raw
    .replaceAll(RegExp(r'[\[\]"]'), '')
    .split(RegExp(r'[,;/]'))
    .map((String part) => part.trim())
    .where((String part) => part.isNotEmpty)
    .toList(growable: false);
