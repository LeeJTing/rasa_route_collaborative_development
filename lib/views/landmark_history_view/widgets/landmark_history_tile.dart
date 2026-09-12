import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../domain_model/submitted_landmark.dart';
import '../../common_widgets/app_image.dart';

/// One submitted landmark in the tourist's history list - photo, name,
/// category, moderation status and the dishes attached to it. Tapping opens
/// the full place-detail screen.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class LandmarkHistoryTile extends StatelessWidget {
  const LandmarkHistoryTile({super.key, required this.landmark, this.onTap});

  final SubmittedLandmark landmark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Thumbnail(landmark: landmark),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      landmark.name.isEmpty
                          ? 'Unnamed landmark'
                          : landmark.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      landmark.category.isEmpty
                          ? 'Landmark submitted by a tourist'
                          : landmark.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _StatusAndDishes(landmark: landmark),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Icon(Icons.chevron_right, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 56-square place photo; a missing DB value degrades to a plain icon tile.
class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.landmark});

  final SubmittedLandmark landmark;

  @override
  Widget build(BuildContext context) {
    final String? url = landmark.imageUrl;
    final Widget placeholder = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.location_on, color: AppColors.textSecondary),
    );
    if (url == null || url.isEmpty) return placeholder;
    return SizedBox(
      width: 56,
      height: 56,
      child: AppImage(
        source: url,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        semanticLabel: landmark.name,
        fallback: placeholder,
      ),
    );
  }
}

/// Moderation status plus a one-line dish preview - a tourist can attach
/// many dishes, so the line shows a count and the first few names.
class _StatusAndDishes extends StatelessWidget {
  const _StatusAndDishes({required this.landmark});

  final SubmittedLandmark landmark;

  @override
  Widget build(BuildContext context) {
    final bool frozen = landmark.status == LandmarkStatus.frozen;
    final List<LandmarkItem> items = landmark.items;
    final String dishLine = items.isEmpty
        ? 'No dishes recorded'
        : items.length == 1
        ? 'Serves: ${items.first.displayName}'
        : 'Serves ${items.length} dishes: '
              '${items.take(3).map((LandmarkItem i) => i.displayName).join(', ')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          frozen ? 'Temporarily hidden after reports' : 'Available',
          style: AppTextStyles.bodySmall.copyWith(
            color: frozen ? AppColors.error : AppColors.success,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (dishLine.isNotEmpty) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            dishLine,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
