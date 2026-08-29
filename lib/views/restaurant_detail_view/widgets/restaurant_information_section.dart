import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/restaurant.dart';
import 'opening_hours_table.dart';

class RestaurantInformationSection extends StatelessWidget {
  const RestaurantInformationSection({super.key, required this.restaurant});

  final Restaurant restaurant;

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
          _InformationRow(
            icon: Icons.location_on_outlined,
            label: restaurant.address.isEmpty
                ? 'Address unavailable'
                : restaurant.address,
          ),
          const SizedBox(height: AppSpacing.md),
          _InformationRow(
            icon: Icons.phone_outlined,
            label: restaurant.phone.isEmpty
                ? 'Phone unavailable'
                : restaurant.phone,
          ),
          const SizedBox(height: AppSpacing.md),
          _InformationRow(
            icon: Icons.language_outlined,
            label: restaurant.website.isEmpty
                ? 'Website unavailable'
                : restaurant.website,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Opening Hours', style: _sectionStyle(context)),
          const SizedBox(height: AppSpacing.md),
          OpeningHoursTable(openingHours: restaurant.openingHours),
        ],
      ),
    );
  }

  TextStyle? _sectionStyle(BuildContext context) => Theme.of(
    context,
  ).textTheme.titleMedium?.copyWith(color: AppColors.accentBrown);
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, color: AppColors.accentBrown),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(label)),
      ],
    );
  }
}
