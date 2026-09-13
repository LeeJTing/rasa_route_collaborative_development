import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/local_food.dart';
import '../../common_widgets/food_section_card.dart';

/// Food facts and the optional cultural background. Receives presentation
/// state and a callback; the owning View keeps the ViewModel interaction.
class FoodInformationCard extends StatelessWidget {
  const FoodInformationCard({
    super.key,
    required this.food,
    required this.isExpanded,
    required this.onToggle,
  });

  final LocalFood food;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) => FoodSectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _InformationItem(label: 'Description', body: food.description),
        _InformationItem(label: 'Origin', body: food.origin),
        _InformationItem(label: 'Ingredients', body: food.ingredients),
        if (isExpanded) ...<Widget>[
          _InformationItem(label: 'Cooking Styles', body: food.cookingStyle),
          _InformationItem(
            label: 'Cultural Background',
            body: food.culturalBackground,
          ),
        ],
        Center(
          child: IconButton(
            tooltip: isExpanded ? 'Hide more details' : 'Show more details',
            onPressed: onToggle,
            icon: Icon(
              isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            ),
          ),
        ),
      ],
    ),
  );
}

class _InformationItem extends StatelessWidget {
  const _InformationItem({required this.label, required this.body});

  final String label;
  final String body;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: AppColors.accentBrown),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          body.isEmpty ? 'Not available' : body,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}
