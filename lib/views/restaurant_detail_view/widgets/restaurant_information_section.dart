import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/restaurant.dart';
import '../../common_widgets/information_row.dart';
import '../../common_widgets/opening_hours_table.dart';

class RestaurantInformationSection extends StatelessWidget {
  const RestaurantInformationSection({
    super.key,
    required this.restaurant,
    this.onAddressTap,
    this.onPhoneTap,
    this.onWebsiteTap,
  });

  final Restaurant restaurant;
  final VoidCallback? onAddressTap;
  final VoidCallback? onPhoneTap;
  final VoidCallback? onWebsiteTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: AppRadius.cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Restaurant Information', style: _sectionStyle(context)),
          const SizedBox(height: AppSpacing.md),
          InformationRow(
            icon: Icons.location_on_outlined,
            label: restaurant.address.isEmpty
                ? 'Address unavailable'
                : restaurant.address,
            onTap: restaurant.address.isEmpty ? null : onAddressTap,
          ),
          const SizedBox(height: AppSpacing.md),
          InformationRow(
            icon: Icons.phone_outlined,
            label: restaurant.phone.isEmpty
                ? 'Phone unavailable'
                : restaurant.phone,
            onTap: restaurant.phone.isEmpty ? null : onPhoneTap,
          ),
          const SizedBox(height: AppSpacing.md),
          InformationRow(
            icon: Icons.language_outlined,
            label: restaurant.website.isEmpty
                ? 'Website unavailable'
                : restaurant.website,
            onTap: restaurant.website.isEmpty ? null : onWebsiteTap,
          ),
          const SizedBox(height: AppSpacing.sm),
          Material(
            color: Colors.transparent,
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: true,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: AppSpacing.sm),
                title: Text('Opening Hours', style: _sectionStyle(context)),
                children: <Widget>[
                  OpeningHoursTable(openingHours: restaurant.openingHours),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle? _sectionStyle(BuildContext context) => Theme.of(
    context,
  ).textTheme.titleMedium?.copyWith(color: AppColors.accentBrown);
}
