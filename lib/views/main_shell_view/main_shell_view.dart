import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../view_models/main_shell_view_model.dart';
import '../common_widgets/app_bottom_nav_bar.dart';
import '../dashboard_view/dashboard_view.dart';
import '../food_recognition_view/food_recognition_view.dart';
import '../local_food_list_view/local_food_list_view.dart';

/// The bottom-navigation shell: Home, Camera, Learn.
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
    FoodRecognitionView(),
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
    return ChangeNotifierProvider<MainShellViewModel>.value(
      value: _viewModel,
      child: Consumer<MainShellViewModel>(
        builder: (BuildContext context, MainShellViewModel vm, Widget? _) {
          return Scaffold(
            body: IndexedStack(index: vm.currentIndex, children: _tabs),
            bottomNavigationBar: AppBottomNavBar(
              currentIndex: vm.currentIndex,
              onTabSelected: (int index) {}, // change to func in viewmodel
            ),
          );
        },
      ),
    );
  }
}
