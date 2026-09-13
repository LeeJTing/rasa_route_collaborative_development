import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/submitted_landmark.dart';
import '../../common_widgets/information_row.dart';
import '../../common_widgets/opening_hours_table.dart';

/// The landmark's contact details and opening hours in ONE card, matching the
/// catalogue restaurant detail's "Restaurant Information" card (white surface,
/// bordered, section headings in accent brown) - the two place pages present
/// their facts the same way, INCLUDING the link treatment: a row the tourist
/// can act on (address, phone, website) is underlined in
/// [AppColors.textPrimary] with an open-in-new icon and opens the matching
/// app - the same black link text the restaurant card uses (user request,
/// 2026-09-14: black, not the old blue); a row with nothing behind it stays
/// plain text.
///
/// One deliberate difference from the restaurant card: a landmark with no
/// address falls back to its COORDINATES ("3.13900, 101.68690") instead of
/// "Address unavailable" - a submitted pin always knows where it is, and a
/// bare lat/long is more use than a dead end. Only when neither exists does
/// the row give up.
class LandmarkInformationSection extends StatelessWidget {
  const LandmarkInformationSection({
    super.key,
    required this.landmark,
    this.onAddressTap,
    this.onPhoneTap,
    this.onWebsiteTap,
  });

  final SubmittedLandmark landmark;
  final VoidCallback? onAddressTap;
  final VoidCallback? onPhoneTap;
  final VoidCallback? onWebsiteTap;

  /// Whether the address row has anything to OPEN - an address to search for,
  /// or coordinates to centre the map on. Without either it stays plain text.
  bool get _addressIsOpenable =>
      landmark.address.trim().isNotEmpty ||
      (landmark.latitude != null && landmark.longitude != null);

  /// The address row's text: the landmark's address, else its coordinates,
  /// else the same "unavailable" wording the restaurant card uses.
  String get _addressLabel {
    if (landmark.address.trim().isNotEmpty) return landmark.address;
    final double? latitude = landmark.latitude;
    final double? longitude = landmark.longitude;
    if (latitude != null && longitude != null) {
      return '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';
    }
    return 'Address unavailable';
  }

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
          Text('Landmark Information', style: _sectionStyle(context)),
          const SizedBox(height: AppSpacing.md),
          InformationRow(
            icon: Icons.location_on_outlined,
            label: _addressLabel,
            onTap: _addressIsOpenable ? onAddressTap : null,
            textColor: AppColors.textPrimary,
          ),
          const SizedBox(height: AppSpacing.md),
          InformationRow(
            icon: Icons.phone_outlined,
            label: landmark.phone.isEmpty
                ? 'Phone unavailable'
                : landmark.phone,
            onTap: landmark.phone.isEmpty ? null : onPhoneTap,
            textColor: AppColors.textPrimary,
          ),
          const SizedBox(height: AppSpacing.md),
          InformationRow(
            icon: Icons.language_outlined,
            label: landmark.website.isEmpty
                ? 'Website unavailable'
                : landmark.website,
            onTap: landmark.website.isEmpty ? null : onWebsiteTap,
            textColor: AppColors.textPrimary,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Opening Hours', style: _sectionStyle(context)),
          const SizedBox(height: AppSpacing.md),
          OpeningHoursTable(openingHours: landmark.openingHours),
        ],
      ),
    );
  }

  TextStyle? _sectionStyle(BuildContext context) => Theme.of(
    context,
  ).textTheme.titleMedium?.copyWith(color: AppColors.accentBrown);
}
