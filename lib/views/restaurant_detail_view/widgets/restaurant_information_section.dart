import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/restaurant.dart';
import 'opening_hours_table.dart';

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
          _InformationRow(
            icon: Icons.location_on_outlined,
            label: restaurant.address.isEmpty
                ? 'Address unavailable'
                : restaurant.address,
            onTap: restaurant.address.isEmpty ? null : onAddressTap,
          ),
          const SizedBox(height: AppSpacing.md),
          _InformationRow(
            icon: Icons.phone_outlined,
            label: restaurant.phone.isEmpty
                ? 'Phone unavailable'
                : restaurant.phone,
            onTap: restaurant.phone.isEmpty ? null : onPhoneTap,
          ),
          const SizedBox(height: AppSpacing.md),
          _InformationRow(
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

class _InformationRow extends StatelessWidget {
  const _InformationRow({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.buttonRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon, color: AppColors.accentBrown),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                label,
                style: onTap == null
                    ? null
                    : const TextStyle(
                        color: AppColors.info,
                        decoration: TextDecoration.underline,
                      ),
              ),
            ),
            if (onTap != null) ...<Widget>[
              const SizedBox(width: AppSpacing.sm),
              const Icon(
                Icons.open_in_new,
                size: AppSizes.iconSmall,
                color: AppColors.info,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
