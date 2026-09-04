import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../common_widgets/app_tag_chip.dart';

/// A wrapping row of tags, used for the Profile screen's preference and
/// dietary-restriction chips. Shows a muted hint when there is nothing to
/// display yet.
class ProfileChipRow extends StatelessWidget {
  const ProfileChipRow({
    super.key,
    required this.labels,
    required this.style,
    this.emptyHint,
  });

  final List<String> labels;
  final AppTagStyle style;

  /// Shown instead of the chips when [labels] is empty.
  final String? emptyHint;

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) {
      if (emptyHint == null) return const SizedBox.shrink();
      return Text(
        emptyHint!,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppColors.textDisabled),
      );
    }
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: <Widget>[
        for (final String label in labels)
          AppTagChip(label: label, style: style),
      ],
    );
  }
}
