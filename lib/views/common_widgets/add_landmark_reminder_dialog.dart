import 'package:flutter/material.dart';

import '../../app/theme/app_dimensions.dart';
import 'app_dialog.dart';

/// The "Add New Landmark" reminder, shown the moment the tourist commits to
/// filling in the form (from the recognition result card, or the food-detail
/// screen's "Add New Landmark").
///
/// A landmark can only be added while the tourist is at the restaurant - the
/// form must be completed within its range. The reminder states that up
/// front, and they must ACKNOWLEDGE it (press "I Understand") before the form
/// opens; dismissing it any other way ("Not Now", the system back gesture)
/// leaves them where they were. What they had filled in can still be kept as
/// an incomplete submission and finished on a later visit.
///
/// Returns true only when the tourist explicitly acknowledged it.
Future<bool> showAddLandmarkReminderDialog(BuildContext context) async {
  final bool? acknowledged = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => AppDialog(
      icon: Icons.storefront_rounded,
      title: 'Before you start',
      message:
          'New landmarks can only be added while you are at the '
          'restaurant.',
      extra: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppDialogRule(
            icon: Icons.location_on_outlined,
            text: 'Fill in and submit the form within the restaurant range.',
          ),
          SizedBox(height: AppSpacing.md),
          AppDialogRule(
            icon: Icons.schedule_outlined,
            text:
                'Leaving early? Save your progress - it is kept for '
                '24 hours. Check the Profile screen to continue later.',
          ),
        ],
      ),
      actions: <Widget>[
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('I Understand'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Not Now'),
        ),
      ],
    ),
  );
  return acknowledged == true;
}
