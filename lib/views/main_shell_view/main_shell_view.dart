import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routing/app_routes.dart';
import '../../domain_model/app_tutorial.dart';
import '../../view_models/main_shell_view_model.dart';
import '../common_widgets/app_bottom_nav_bar.dart';
import '../dashboard_view/dashboard_view.dart';
import '../local_food_list_view/local_food_list_view.dart';
import 'widgets/app_tutorial_overlay.dart';

/// The bottom-navigation shell: Home and Learn tabs, with the camera in the
/// middle of the bar opening as a full-screen route (so the camera screen
/// shows only its capture button, never this bottom bar).
///
/// Uses [IndexedStack] rather than swapping children so each tab keeps its
/// scroll position and its own ViewModel while the user moves between them.
///
/// It is also where the guided walkthrough appears (REQ107). The shell is the
/// first screen a signed-in tourist lands on and it outlives both tabs, which
/// is what the tour needs: it describes the app, not any one screen.
class MainShellView extends StatefulWidget {
  const MainShellView({super.key});

  @override
  State<MainShellView> createState() => _MainShellViewState();
}

class _MainShellViewState extends State<MainShellView> {
  late final MainShellViewModel _viewModel;

  static const List<Widget> _tabs = <Widget>[
    DashboardView(),
    LocalFoodListView(),
  ];

  @override
  void initState() {
    super.initState();
    _viewModel = MainShellViewModel();
    _viewModel.onInit();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(_tabs.length == MainShellViewModel.tabCount);
    return ChangeNotifierProvider<MainShellViewModel>.value(
      value: _viewModel,
      child: Consumer<MainShellViewModel>(
        builder: (BuildContext context, MainShellViewModel vm, Widget? _) {
          final TutorialStep? tutorialStep = vm.tutorialStep;

          // The tour sits OVER the shell rather than inside its body, so it
          // covers the bottom bar too - a walkthrough of the map that leaves
          // the navigation live invites a tap that walks away from it.
          // `StackFit.expand` because the Scaffold underneath must still be
          // given the whole screen.
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Scaffold(
                body: IndexedStack(index: vm.currentIndex, children: _tabs),
                bottomNavigationBar: AppBottomNavBar(
                  currentIndex: vm.currentIndex,
                  onTabSelected: vm.selectTab,
                  // The camera opens as a full-screen route (no bottom bar) -
                  // see AppBottomNavBar.onCameraPressed.
                  onCameraPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.foodRecognition),
                ),
              ),
              if (tutorialStep != null)
                AppTutorialOverlay(
                  step: tutorialStep,
                  stepIndex: vm.tutorialStepIndex,
                  stepCount: vm.tutorialStepCount,
                  isLastStep: vm.isLastTutorialStep,
                  onNext: vm.showNextTutorialStep,
                  onSkip: vm.skipTutorial,
                  onFinish: vm.finishTutorial,
                ),
            ],
          );
        },
      ),
    );
  }
}
