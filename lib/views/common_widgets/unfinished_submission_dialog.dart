import 'package:flutter/material.dart';

import '../../app/theme/app_dimensions.dart';
import 'app_dialog.dart';

/// The unfinished-submission notice, shown once when the camera is opened for
/// a fresh food capture while a saved (incomplete) Add-New-Landmark form
/// exists.
///
/// Informational by design - it does NOT continue the draft (the tourist may
/// be capturing something else entirely) and offers NO Discard (deleting a
/// form and its photos belongs on the Incomplete Submissions screen, where
/// the tourist can see exactly what they are deleting). A single "Got it"
/// acknowledges the notice; the draft then waits on the Profile screen's
/// Incomplete Submissions list until it is finished or deleted there.
///
/// Uses the shared [AppDialog] frame, so it matches every other modal in the
/// Add-Landmark flow.
Future<void> showUnfinishedSubmissionDialog(
  BuildContext context, {
  required String restaurantName,
  required int draftCount,
}) async {
  final String named = restaurantName.trim();
  final String message = draftCount > 1
      ? 'You have $draftCount unfinished landmark submissions saved.'
      : named.isEmpty
      ? 'You have an unfinished landmark submission saved.'
      : 'You have an unfinished landmark submission for "$named" saved.';

  await showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) => AppDialog(
      icon: Icons.pending_actions_rounded,
      title: 'Unfinished submission',
      message: message,
      extra: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppDialogRule(
            icon: Icons.person_outline,
            text:
                'You can go to your Profile to continue it - open '
                'Incomplete Submissions. You can delete it there too.',
          ),
          SizedBox(height: AppSpacing.md),
          AppDialogRule(
            icon: Icons.schedule_outlined,
            text: 'It is kept for 24 hours after its last save.',
          ),
        ],
      ),
      actions: <Widget>[
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}
