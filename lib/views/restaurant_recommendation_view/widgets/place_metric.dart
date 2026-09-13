import 'package:flutter/material.dart';

import '../../../app/theme/app_dimensions.dart';

/// One metric line (icon + label) inside a Quick Mode place card.
///
/// Shared by `RestaurantCard` (rating, distance) and `SubmittedLandmarkCard`
/// (distance only) so the two cards line up metric-for-metric and can never
/// drift apart. A submitted landmark has no rating and NO empty slot is kept
/// for one (user request, 2026-09-14) - its distance simply stands alone.
class PlaceMetric extends StatelessWidget {
  const PlaceMetric({
    super.key,
    required this.icon,
    required this.label,
    this.iconColor,
    this.alignment = MainAxisAlignment.start,
  });

  final IconData icon;
  final String label;
  final Color? iconColor;

  /// Where the icon + label sit inside the width they are given.
  final MainAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final Widget labelText = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    return Row(
      mainAxisAlignment: alignment,
      children: <Widget>[
        Icon(icon, size: AppSizes.iconCompact, color: iconColor),
        const SizedBox(width: AppSpacing.xs),
        Flexible(child: labelText),
      ],
    );
  }
}
