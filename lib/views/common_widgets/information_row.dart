import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';

/// One icon + text row of a place's information card ("Restaurant
/// Information" / "Landmark Information").
///
/// With an [onTap] the row is a LINK: the label turns [AppColors.info] with
/// an underline and an `open_in_new` icon appears on the right - the same
/// treatment both place pages give their address, phone and website, so a
/// tourist reads "this can be opened" the same way everywhere. Without one
/// the row is plain text - nothing behind it to open.
///
/// Shared because the two place pages must present their facts identically
/// (this project's convention: promote a screen-local widget to
/// `lib/views/common_widgets/` once a second screen needs it).
class InformationRow extends StatelessWidget {
  const InformationRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

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
