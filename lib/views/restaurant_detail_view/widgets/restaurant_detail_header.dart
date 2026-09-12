import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/restaurant.dart';
import '../../common_widgets/app_image.dart';
import '../../common_widgets/app_tag_chip.dart';

class RestaurantDetailHeader extends StatelessWidget {
  const RestaurantDetailHeader({super.key, required this.restaurant});

  final Restaurant restaurant;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AspectRatio(
          aspectRatio: 2,
          child: AppImage(
            source: restaurant.imageUrl,
            borderRadius: AppRadius.cardRadius,
            semanticLabel: restaurant.name,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(restaurant.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: <Widget>[
            const Icon(Icons.star, color: AppColors.secondary),
            const SizedBox(width: AppSpacing.xs),
            Text(
              restaurant.rating == null
                  ? 'No rating yet'
                  : restaurant.rating!.toStringAsFixed(1),
            ),
            const Spacer(),
            const Icon(Icons.location_on_outlined),
            const SizedBox(width: AppSpacing.xs),
            Text(_distanceLabel(restaurant.distanceMetres)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: <Widget>[
            AppTagChip(label: restaurant.category, style: AppTagStyle.category),
          ],
        ),
      ],
    );
  }

  String _distanceLabel(double? distanceMetres) {
    if (distanceMetres == null) return 'Distance unavailable';
    if (distanceMetres < 1000) return '${distanceMetres.round()} m';
    return '${(distanceMetres / 1000).toStringAsFixed(1)} km';
  }
}
