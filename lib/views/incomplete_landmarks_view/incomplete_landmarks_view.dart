import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../domain_model/landmark_draft.dart';
import '../../view_models/incomplete_landmarks_view_model.dart';
import '../common_widgets/app_dialog.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/async_message.dart';
import '../common_widgets/continue_draft_dialog.dart';

/// "Incomplete Submissions" - every saved (incomplete) Add-New-Landmark form
/// the signed-in tourist has, newest first.
///
/// A draft is kept for 24 hours from its last save; the list is the place to
/// continue one (tapping a card re-opens the form pre-filled) or delete it
/// (swiping a card left reveals the delete action, exactly like the Favourite
/// Food cards - and the FIRST card plays a one-time swipe hint so the action
/// is never invisible). Reached from the profile's "Incomplete Submissions"
/// link.
///
///   * the ViewModel is built in `initState` with `XViewModel()` - a View knows
///     its ViewModel and nothing else, and nothing is passed in;
///   * it is published to this screen's subtree with a
///     `ChangeNotifierProvider` declared by this View and nobody else;
///   * it is disposed with the screen.
class IncompleteLandmarksView extends StatefulWidget {
  const IncompleteLandmarksView({super.key});

  @override
  State<IncompleteLandmarksView> createState() =>
      _IncompleteLandmarksViewState();
}

class _IncompleteLandmarksViewState extends State<IncompleteLandmarksView> {
  late final IncompleteLandmarksViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = IncompleteLandmarksViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  /// Deleting throws away the form AND its photos - ask first, and say so
  /// plainly. Returns true only when the tourist confirmed. Uses the shared
  /// `AppDialog` frame, so it matches every other modal in this flow.
  Future<bool> _confirmDiscard(LandmarkDraft draft) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) => AppDialog(
        icon: Icons.delete_outline,
        title: 'Delete this incomplete submission?',
        message:
            'The form and its photos will be deleted, and it cannot be '
            'recovered.',
        actions: <Widget>[
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<IncompleteLandmarksViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'Incomplete Submissions'),
        body: SafeArea(
          child: Consumer<IncompleteLandmarksViewModel>(
            builder:
                (
                  BuildContext context,
                  IncompleteLandmarksViewModel viewModel,
                  Widget? _,
                ) {
                  if (viewModel.isBusy) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (viewModel.hasError) {
                    return AsyncMessage(
                      icon: Icons.error_outline,
                      title: "Couldn't load your incomplete submissions",
                      message: viewModel.errorMessage,
                      actionLabel: 'Retry',
                      onAction: viewModel.load,
                    );
                  }
                  if (viewModel.drafts.isEmpty) {
                    return const AsyncMessage(
                      icon: Icons.assignment_outlined,
                      title: 'No incomplete submissions',
                      message:
                          'If you leave the Add New Landmark form before '
                          'finishing it, you can save it and continue here.',
                    );
                  }
                  return ListView(
                    padding: AppSpacing.screenPadding,
                    children: <Widget>[
                      // The delete action lives behind a swipe, so it is
                      // TAUGHT: this reminder up top, plus the swipe hint
                      // the first card plays below.
                      const _SwipeHintBanner(),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'An incomplete submission is kept for 24 hours after '
                        'its last save. Continue one while you are at the '
                        'restaurant.',
                        style: AppTextStyles.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      for (
                        int index = 0;
                        index < viewModel.drafts.length;
                        index++
                      )
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: _SwipeableDraftTile(
                            key: ValueKey<int>(viewModel.drafts[index].id),
                            draft: viewModel.drafts[index],
                            // Only the first card plays the one-time hint.
                            hint: index == 0,
                            onTap: () =>
                                viewModel.openDraft(viewModel.drafts[index]),
                            onConfirmDiscard: () =>
                                _confirmDiscard(viewModel.drafts[index]),
                            onDiscard: () =>
                                viewModel.discardDraft(viewModel.drafts[index]),
                          ),
                        ),
                    ],
                  );
                },
          ),
        ),
      ),
    );
  }
}

/// A one-line reminder at the top of the list: deleting is a SWIPE, and a
/// swipe leaves nothing on screen until it happens - so it is taught here
/// (and by the first card's hint animation), never discovered by accident.
class _SwipeHintBanner extends StatelessWidget {
  const _SwipeHintBanner();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: const BoxDecoration(
      color: AppColors.bannerInfoBackground,
      borderRadius: AppRadius.cardRadius,
    ),
    child: Row(
      children: <Widget>[
        const Icon(Icons.swipe_left, color: AppColors.bannerInfoIcon),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            'Swipe a card left to delete it - or tap it to continue '
            'editing.',
            style: AppTextStyles.bodySmall.copyWith(
              color: AppColors.bannerInfoText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

/// One draft row with the SAME swipe-to-delete the Favourite Food cards use:
/// swipe left, the orange panel with the bin appears, let go and (after the
/// confirmation) the submission is deleted.
///
/// [hint] plays a one-time nudge on the first card - it slides left, holds
/// the delete panel in view for a beat, slides back - because the action is
/// otherwise invisible until the tourist happens to swipe.
class _SwipeableDraftTile extends StatefulWidget {
  const _SwipeableDraftTile({
    super.key,
    required this.draft,
    required this.hint,
    required this.onTap,
    required this.onConfirmDiscard,
    required this.onDiscard,
  });

  final LandmarkDraft draft;
  final bool hint;
  final VoidCallback onTap;

  /// Asked before the delete - true lets the dismissal complete.
  final Future<bool> Function() onConfirmDiscard;
  final VoidCallback onDiscard;

  @override
  State<_SwipeableDraftTile> createState() => _SwipeableDraftTileState();
}

class _SwipeableDraftTileState extends State<_SwipeableDraftTile>
    with SingleTickerProviderStateMixin {
  /// How far the hint slides the card - enough to uncover the delete icon.
  static const double _hintReveal = 64;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  /// Out, hold, back - deliberately slow and unmissable, and never far
  /// enough to look like a full dismiss.
  late final Animation<double> _offset =
      TweenSequence<double>(<TweenSequenceItem<double>>[
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: 0,
            end: -_hintReveal,
          ).chain(CurveTween(curve: Curves.easeOut)),
          weight: 30,
        ),
        TweenSequenceItem<double>(
          tween: ConstantTween<double>(-_hintReveal),
          weight: 40,
        ),
        TweenSequenceItem<double>(
          tween: Tween<double>(
            begin: -_hintReveal,
            end: 0,
          ).chain(CurveTween(curve: Curves.easeIn)),
          weight: 30,
        ),
      ]).animate(_controller);

  @override
  void initState() {
    super.initState();
    if (widget.hint) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _playHint());
    }
  }

  /// Plays after a beat, so the list has visibly settled first - and never
  /// when the platform asks for reduced motion.
  Future<void> _playHint() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    await _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // The panel the swipe (and the hint) uncovers - the same orange +
        // white bin the favourite cards reveal.
        const Positioned.fill(child: _DeletePanel()),
        Dismissible(
          key: ValueKey<int>(widget.draft.id),
          direction: DismissDirection.endToStart,
          confirmDismiss: (_) => widget.onConfirmDiscard(),
          onDismissed: (_) => widget.onDiscard(),
          // The panel above IS the visible background; Dismissible's own is
          // left transparent so the hint and a real swipe look identical.
          background: const SizedBox.shrink(),
          child: AnimatedBuilder(
            animation: _offset,
            builder: (BuildContext context, Widget? child) =>
                Transform.translate(
                  offset: Offset(_offset.value, 0),
                  child: child,
                ),
            child: _DraftTile(draft: widget.draft, onTap: widget.onTap),
          ),
        ),
      ],
    );
  }
}

/// The delete action a swipe reveals - identical to the favourite cards'.
class _DeletePanel extends StatelessWidget {
  const _DeletePanel();

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.centerRight,
    padding: const EdgeInsets.only(right: AppSpacing.lg),
    decoration: const BoxDecoration(
      color: AppColors.primary,
      borderRadius: AppRadius.cardRadius,
    ),
    child: const Icon(Icons.delete, color: AppColors.onPrimary),
  );
}

/// One saved incomplete submission: photo, name (or "Untitled"), where it
/// got to, and how long it still has. The delete action is NOT a button on
/// the card any more - it is revealed by swiping the card left (see
/// [_SwipeableDraftTile]), the same gesture the Favourite Food cards use.
class _DraftTile extends StatelessWidget {
  const _DraftTile({required this.draft, required this.onTap});

  final LandmarkDraft draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final String name = draft.restaurantName.trim().isEmpty
        ? 'Untitled landmark'
        : draft.restaurantName.trim();
    final LandmarkDraftFood? primary = draft.primaryFood;
    final List<String> facts = <String>[
      // The VARIANT when one was recorded ("Cendol Jagung"), else the dish
      // name - two drafts of the same dish that differ only by variant must
      // not read as the same row here (see [continueDraftDishLabel]).
      if (primary != null) continueDraftDishLabel(draft),
      'Saved ${_relativeTime(draft.updatedAt)}',
      'Expires in ${_remaining(draft)}',
    ];

    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.cardRadius,
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _DraftThumbnail(url: draft.thumbnailPhoto?.url),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      style: AppTextStyles.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    for (final String fact in facts)
                      Text(fact, style: AppTextStyles.bodySmall),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Tap to continue this form',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _relativeTime(DateTime time) {
    final Duration elapsed = DateTime.now().difference(time);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
    if (elapsed.inHours < 24) return '${elapsed.inHours} h ago';
    return '${elapsed.inDays} d ago';
  }

  static String _remaining(LandmarkDraft draft) {
    final Duration left = draft.timeUntilExpiry;
    if (left.inHours >= 1) {
      final int hours = left.inHours;
      final int minutes = left.inMinutes % 60;
      return minutes == 0 ? '$hours h' : '$hours h $minutes min';
    }
    if (left.inMinutes >= 1) return '${left.inMinutes} min';
    return 'less than a minute';
  }
}

/// The draft's photo, or an empty placeholder frame - same square shape the
/// other list tiles use.
class _DraftThumbnail extends StatelessWidget {
  const _DraftThumbnail({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final String? imageUrl = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: imageUrl == null
          ? const SizedBox(
              width: AppSizes.avatarLg,
              height: AppSizes.avatarLg,
              child: ColoredBox(color: AppColors.surfaceVariant),
            )
          : Image.network(
              imageUrl,
              width: AppSizes.avatarLg,
              height: AppSizes.avatarLg,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox(
                width: AppSizes.avatarLg,
                height: AppSizes.avatarLg,
                child: ColoredBox(color: AppColors.surfaceVariant),
              ),
            ),
    );
  }
}
