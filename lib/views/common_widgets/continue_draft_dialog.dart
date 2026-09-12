import 'package:flutter/material.dart';

import '../../domain_model/landmark_draft.dart';
import 'app_dialog.dart';

/// The "same dish, same place - continue your unfinished submission?" ask,
/// shown when the tourist commits to adding a dish ("Add New Landmark" /
/// "Add to Landmark") and a saved incomplete submission already holds that
/// dish (same variant) at that spot.
///
/// "Continue submission" reopens the draft EXACTLY as saved - nothing from
/// this new capture refreshes it (see `LandmarkSubmissionLogic.matchingDraft`
/// for what counts as the same dish). "Start a new one" leaves the draft
/// alone and opens a fresh, empty form; the draft stays on the Profile's
/// Incomplete Submissions list.
///
/// Returns true only for "Continue submission". Uses the shared [AppDialog]
/// frame, like every other modal in this flow.
Future<bool> showContinueDraftDialog(
  BuildContext context, {
  required String dishLabel,
  required String restaurantName,
}) async {
  final String place = restaurantName.trim();
  final bool? continues = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AppDialog(
      icon: Icons.pending_actions_rounded,
      title: 'Continue your unfinished submission?',
      message: place.isEmpty
          ? 'You already started adding "$dishLabel" here.'
          : 'You already started adding "$dishLabel" for "$place" here.',
      extra: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppDialogRule(
            icon: Icons.assignment_outlined,
            text:
                'Your saved form opens with everything you already filled '
                'in.',
          ),
        ],
      ),
      actions: <Widget>[
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Continue submission'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Start a new one'),
        ),
      ],
    ),
  );
  return continues == true;
}

/// The label a draft's dish is shown under - in [showContinueDraftDialog]
/// and on the Incomplete Submissions card: the draft's recorded VARIANT when
/// it has one ("Cendol Jagung"), else its dictionary dish name. Two drafts
/// of the same dish that differ only by variant therefore read differently.
/// A draft with no foods yet falls back to a neutral phrase.
String continueDraftDishLabel(LandmarkDraft draft) {
  final LandmarkDraftFood? food = draft.primaryFood;
  if (food == null) return 'this dish';
  final String variant = food.variant.trim();
  return variant.isEmpty ? food.food.name : variant;
}
