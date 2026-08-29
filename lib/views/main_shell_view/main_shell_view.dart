import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/routing/app_routes.dart';
import '../../view_models/main_shell_view_model.dart';
import '../common_widgets/app_bottom_nav_bar.dart';
import '../dashboard_view/dashboard_view.dart';
import '../local_food_list_view/local_food_list_view.dart';

/// The bottom-navigation shell: Home and Learn tabs, with the camera in the
/// middle of the bar opening as a full-screen route (so the camera screen
/// shows only its capture button, never this bottom bar).
///
/// Uses [IndexedStack] rather than swapping children so each tab keeps its
/// scroll position and its own ViewModel while the user moves between them.
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
          return Scaffold(
            body: IndexedStack(index: vm.currentIndex, children: _tabs),
            bottomNavigationBar: AppBottomNavBar(
              currentIndex: vm.currentIndex,
              onTabSelected: vm.selectTab,
              // The camera opens as a full-screen route (no bottom bar) -
              // see AppBottomNavBar.onCameraPressed.
              onCameraPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.foodRecognition),
            ),
          );
        },
      ),
    );
  }
}
