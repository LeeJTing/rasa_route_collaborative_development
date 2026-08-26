import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/view_models/main_shell_view_model.dart';
import 'package:rasa_route_collaborative_development/views/common_widgets/app_bottom_nav_bar.dart';

void main() {
  group('main shell navigation', () {
    test('destination indexes match the two IndexedStack children', () {
      expect(AppBottomNavTab.values, hasLength(MainShellViewModel.tabCount));
      expect(AppBottomNavTab.home.index, 0);
      expect(AppBottomNavTab.learn.index, 1);
    });

    test('learn can be selected and out-of-range indexes are ignored', () {
      final MainShellViewModel viewModel = MainShellViewModel();

      viewModel.selectTab(AppBottomNavTab.learn.index);
      expect(viewModel.currentIndex, 1);

      viewModel.selectTab(MainShellViewModel.tabCount);
      expect(viewModel.currentIndex, 1);
    });
  });
}
