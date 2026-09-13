import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// The collapsible "Local Foods Served (N)" section both place pages use.
///
/// Promoted out of `restaurant_detail_view` when the submitted-landmark page
/// needed the same treatment (the codebase convention: once a second screen
/// wants it, it stops being screen-local). It owns the section's FRAME only -
/// the wording, the count, the chevron, the collapsed-by-default state and
/// the empty message - while each page keeps its own rows, because the two
/// pages read different models (`RestaurantItem` vs `LandmarkItem`).
class PlaceMenuSection extends StatelessWidget {
  const PlaceMenuSection({
    super.key,
    required this.itemCount,
    required this.children,
    required this.emptyMessage,
  });

  /// Shown in the header as "Local Foods Served ($itemCount)".
  final int itemCount;

  /// One row per dish, already styled by the page that owns the model.
  final List<Widget> children;

  /// Shown inside the section when [children] is empty.
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return Theme(
      // The ExpansionTile's own divider would draw a line the rest of the
      // page does not use.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          'Local Foods Served ($itemCount)',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: AppColors.accentBrown),
        ),
        children: <Widget>[
          if (children.isEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                emptyMessage,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            )
          else
            ...children,
        ],
      ),
    );
  }
}
