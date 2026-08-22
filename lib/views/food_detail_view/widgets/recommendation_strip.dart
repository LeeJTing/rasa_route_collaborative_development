import 'package:flutter/material.dart';

import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/local_food.dart';
import '../../common_widgets/app_image.dart';

class RecommendationStrip extends StatelessWidget {
  const RecommendationStrip({
    super.key,
    required this.foods,
    required this.onTap,
  });

  final List<LocalFood> foods;
  final ValueChanged<LocalFood> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.recommendationImage + AppSpacing.xxl,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: foods.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
        itemBuilder: (BuildContext context, int index) {
          final LocalFood food = foods[index];
          return InkWell(
            onTap: () => onTap(food),
            borderRadius: AppRadius.cardRadius,
            child: SizedBox(
              width: AppSizes.recommendationImage,
              child: Column(
                children: <Widget>[
                  Expanded(
                    child: AppImage(
                      source: food.imageUrl,
                      borderRadius: AppRadius.cardRadius,
                      semanticLabel: food.name,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    food.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
