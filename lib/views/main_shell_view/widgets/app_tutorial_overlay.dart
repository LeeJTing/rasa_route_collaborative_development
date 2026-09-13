import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';
import '../../../domain_model/app_tutorial.dart';
import 'tutorial_illustration_view.dart';

/// The guided walkthrough, drawn over whatever the shell is showing (REQ107).
///
/// One card at a time: a picture, a heading, a sentence, a row of dots saying
/// how far along the tourist is, and the two ways out - **Next** (**Finish**
/// on the last card) and **Skip**.
///
/// It knows nothing about how many steps there are or which one comes next.
/// The ViewModel counts the list and decides; this draws what it is handed,
/// which is why adding a feature to the tour is a one-line change somewhere
/// else entirely.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class AppTutorialOverlay extends StatelessWidget {
  const AppTutorialOverlay({
    super.key,
    required this.step,
    required this.stepIndex,
    required this.stepCount,
    required this.isLastStep,
    required this.onNext,
    required this.onSkip,
    required this.onFinish,
  });

  /// The card to draw.
  final TutorialStep step;

  /// Which card this is, counting from zero - the lit dot.
  final int stepIndex;

  /// How many cards there are in total - how many dots.
  final int stepCount;

  /// True on the last card, where the primary button says Finish and Skip is
  /// not offered: at that point the two would do the same thing, and a choice
  /// between two identical buttons is not a choice.
  final bool isLastStep;

  /// Advance one card.
  final VoidCallback onNext;

  /// Leave the tour early. Recorded exactly as finishing is, so it is not
  /// offered again tomorrow.
  final VoidCallback onSkip;

  /// Leave the tour at the end.
  final VoidCallback onFinish;

  /// Diameter of a progress dot.
  static const double _dot = 7;

  /// How much wider the lit dot is drawn, so the current step reads at a
  /// glance without counting.
  static const double _activeDotWidth = 18;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      // Opaque on purpose: the tour sits over a live map, and a tap that
      // slipped past the card would pan it, open a pin, or close a panel
      // underneath a tourist who cannot see what they just did.
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: ColoredBox(
          color: AppColors.scrim,
          child: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppSizes.dialogMaxWidth,
                  ),
                  child: _Card(
                    step: step,
                    stepIndex: stepIndex,
                    stepCount: stepCount,
                    isLastStep: isLastStep,
                    onNext: onNext,
                    onSkip: onSkip,
                    onFinish: onFinish,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.step,
    required this.stepIndex,
    required this.stepCount,
    required this.isLastStep,
    required this.onNext,
    required this.onSkip,
    required this.onFinish,
  });

  final TutorialStep step;
  final int stepIndex;
  final int stepCount;
  final bool isLastStep;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      borderRadius: const BorderRadius.all(Radius.circular(AppRadius.xl)),
      child: SingleChildScrollView(
        // Scrolls rather than overflows: eight cards have to survive a small
        // phone and a large accessibility text size, and one clipped button
        // would strand a tourist inside the tour.
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            TutorialIllustrationView(step: step),
            const SizedBox(height: AppSpacing.lg),
            Text(
              step.title,
              textAlign: TextAlign.center,
              style: AppTextStyles.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              step.message,
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _ProgressDots(index: stepIndex, count: stepCount),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: isLastStep ? onFinish : onNext,
              child: Text(isLastStep ? 'Finish' : 'Next'),
            ),
            if (!isLastStep) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              TextButton(onPressed: onSkip, child: const Text('Skip')),
            ],
          ],
        ),
      ),
    );
  }
}

/// One dot per card, the current one drawn as a lozenge.
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[
      for (int i = 0; i < count; i++)
        Container(
          width: i == index
              ? AppTutorialOverlay._activeDotWidth
              : AppTutorialOverlay._dot,
          height: AppTutorialOverlay._dot,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs / 2),
          decoration: BoxDecoration(
            color: i == index ? AppColors.primary : AppColors.outline,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
    ],
  );
}
