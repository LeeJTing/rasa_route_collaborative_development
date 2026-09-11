import 'package:flutter/material.dart';

import 'app_dialog.dart';

/// The "you already have a submission for this restaurant - combine?" ask.
///
/// Shown when the Add-Landmark form's Confirm button finds a saved incomplete
/// submission for the SAME restaurant - same name and first-food spot within
/// 100 m (see `LandmarkSubmissionLogic.matchingDraftForRestaurant`).
///
/// "Combine them" keeps ONE submission: the saved form's dishes join this
/// form, its empty fields fill what this form left blank, and this form
/// updates that saved submission from then on (no second draft is kept).
/// "Keep separate" leaves the saved submission untouched and this form stays
/// its own.
///
/// Returns true only for "Combine them". Uses the shared [AppDialog] frame,
/// like every other modal in this flow.
Future<bool> showCombineDraftDialog(
  BuildContext context, {
  required String restaurantName,
}) async {
  final String place = restaurantName.trim();
  final bool? combines = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AppDialog(
      icon: Icons.call_merge_rounded,
      title: 'You already have a submission for this restaurant',
      message: place.isEmpty
          ? 'An unfinished submission from this place is saved.'
          : 'An unfinished submission for "$place" is saved.',
      extra: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppDialogRule(
            icon: Icons.assignment_outlined,
            text:
                'Combining keeps one form: dishes already on both are '
                'updated, new dishes are added.',
          ),
        ],
      ),
      actions: <Widget>[
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Combine them'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Keep separate'),
        ),
      ],
    ),
  );
  return combines == true;
}
