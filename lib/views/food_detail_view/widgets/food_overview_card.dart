import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/local_food.dart';
import '../../common_widgets/app_tag_chip.dart';

class FoodOverviewCard extends StatelessWidget {
  const FoodOverviewCard({super.key, required this.food});

  final LocalFood food;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: AppSpacing.cardPadding,
    decoration: BoxDecoration(
      color: AppColors.surface,
      border: Border.all(color: AppColors.cardBorderWarm),
      borderRadius: AppRadius.cardRadius,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    children: <Widget>[
                      Text(
                        food.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (food.foodType.isNotEmpty)
                        AppTagChip(
                          label: food.foodType,
                          style: AppTagStyle.neutral,
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    food.pronunciationText.isEmpty
                        ? food.name
                        : food.pronunciationText,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.accentBrown,
                    ),
                  ),
                  Text(
                    'Pronunciation guide',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.accentRust,
                    ),
                  ),
                ],
              ),
            ),
            Material(
              color: AppColors.cardBorderWarm,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Audio guide unavailable',
                onPressed: null,
                icon: const Icon(
                  Icons.volume_off_outlined,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
        const Divider(height: AppSpacing.xl),
        if (food.synonyms.isNotEmpty) ...<Widget>[
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: AppColors.tagTasteBackground,
              borderRadius: const BorderRadius.all(
                Radius.circular(AppRadius.pill),
              ),
            ),
            child: Text(
              'Also known as: ${food.synonyms.join(' • ')}',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: AppColors.tagTasteText),
            ),
          ),
        ],
        if (food.synonyms.isNotEmpty) const SizedBox(height: AppSpacing.md),
        _MetadataRow(
          label: 'Food Category',
          children: <Widget>[
            AppTagChip(label: food.category, style: AppTagStyle.category),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _MetadataRow(
          label: 'Meal Type',
          children: <Widget>[
            AppTagChip(label: food.mealType, style: AppTagStyle.meal),
          ],
        ),
        if (food.tastes.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.sm),
          _MetadataRow(
            label: 'Food Taste',
            children: food.tastes
                .map(
                  (String taste) =>
                      AppTagChip(label: taste, style: AppTagStyle.taste),
                )
                .toList(growable: false),
          ),
        ],
      ],
    ),
  );
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      SizedBox(
        width: AppSizes.recommendationImage,
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppColors.accentBrown),
        ),
      ),
      Expanded(
        child: Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: children,
        ),
      ),
    ],
  );
}
