import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_dimensions.dart';
import '../../domain_model/submitted_landmark.dart';
import '../../view_models/landmark_history_view_model.dart';
import '../common_widgets/app_top_bar.dart';
import '../common_widgets/async_message.dart';
import 'widgets/landmark_history_tile.dart';

/// My contributions screen - every submitted landmark the signed-in tourist
/// has added, newest first. One tourist can add MANY landmarks, so this is a
/// plain scrolling list; tapping a tile opens the full place-detail screen
/// (the same one the map's "View Landmark" button opens).
///
///   * the ViewModel is built in `initState` with `XViewModel()` - a View knows
///     its ViewModel and nothing else, and nothing is passed in;
///   * it is published to this screen's subtree with a
///     `ChangeNotifierProvider` declared by this View and nobody else;
///   * it is disposed with the screen.
class LandmarkHistoryView extends StatefulWidget {
  const LandmarkHistoryView({super.key});

  @override
  State<LandmarkHistoryView> createState() => _LandmarkHistoryViewState();
}

class _LandmarkHistoryViewState extends State<LandmarkHistoryView> {
  late final LandmarkHistoryViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = LandmarkHistoryViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<LandmarkHistoryViewModel>.value(
      value: _viewModel,
      child: Scaffold(
        appBar: const AppTopBar(title: 'My contributions'),
        body: SafeArea(
          child: Consumer<LandmarkHistoryViewModel>(
            builder:
                (
                  BuildContext context,
                  LandmarkHistoryViewModel viewModel,
                  Widget? _,
                ) {
                  if (viewModel.isBusy) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (viewModel.hasError) {
                    return AsyncMessage(
                      icon: Icons.error_outline,
                      title: "Couldn't load your landmarks",
                      message: viewModel.errorMessage,
                      actionLabel: 'Retry',
                      onAction: viewModel.load,
                    );
                  }
                  if (viewModel.landmarks.isEmpty) {
                    return const AsyncMessage(
                      icon: Icons.place_outlined,
                      title: 'No submitted landmarks yet',
                      message: 'Landmarks you add will appear here.',
                    );
                  }
                  return ListView.builder(
                    padding: AppSpacing.screenPadding,
                    itemCount: viewModel.landmarks.length,
                    itemBuilder:
                        (BuildContext context, int index) {
                          final SubmittedLandmark landmark =
                              viewModel.landmarks[index];
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: LandmarkHistoryTile(
                              landmark: landmark,
                              onTap: () => viewModel.openLandmark(landmark),
                            ),
                          );
                        },
                  );
                },
          ),
        ),
      ),
    );
  }
}
