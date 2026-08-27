import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';

/// The three-slot bottom bar from the Figma mock-up: two labelled items either
/// side of a raised circular camera button.
///
/// Used by `MainShellView`, which owns the selected index. This widget takes
/// that index and a callback and nothing else — it has no idea a ViewModel
/// exists, which is what lets it live in `common_widgets/`.
///
/// ```dart
/// Scaffold(
///   body: IndexedStack(index: vm.currentIndex, children: tabs),
///   bottomNavigationBar: AppBottomNavBar(
///     currentIndex: vm.currentIndex,
///     onTabSelected: vm.selectTab,
///   ),
/// )
/// ```
///
/// The destination order is fixed by [AppBottomNavTab]. The camera is not a
/// destination: it opens a route and therefore must never consume a tab index.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    required this.onCameraPressed,
  });

  /// Index of the selected tab. See [AppBottomNavTab].
  final int currentIndex;

  final ValueChanged<int> onTabSelected;

  /// Opens the camera. Unlike the two labelled tabs, the camera is a
  /// momentary action, not a selectable destination - it pushes a full-screen
  /// route (so the bottom bar is not visible on the camera screen, which
  /// should show only its own capture button).
  final VoidCallback onCameraPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(color: AppColors.surfaceVariant),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppSizes.bottomNavHeight,
          child: Row(
            children: <Widget>[
              Expanded(
                child: _NavItem(
                  icon: Icons.home_outlined,
                  selectedIcon: Icons.home,
                  label: 'Home',
                  isSelected: currentIndex == AppBottomNavTab.home.index,
                  onTap: () => onTabSelected(AppBottomNavTab.home.index),
                ),
              ),
              Expanded(child: _CameraButton(onTap: onCameraPressed)),
              Expanded(
                child: _NavItem(
                  icon: Icons.search_outlined,
                  selectedIcon: Icons.search,
                  label: 'Learn',
                  isSelected: currentIndex == AppBottomNavTab.learn.index,
                  onTap: () => onTabSelected(AppBottomNavTab.learn.index),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The shell's indexed destinations. Use `AppBottomNavTab.learn.index` rather
/// than a literal index. The camera action is intentionally absent.
enum AppBottomNavTab { home, learn }

/// One labelled destination.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = isSelected
        ? AppColors.primary
        : AppColors.textSecondary;

    return Semantics(
      selected: isSelected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              isSelected ? selectedIcon : icon,
              size: AppSizes.navIconSize,
              color: color,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              style: isSelected
                  ? AppTextStyles.labelMediumSelected
                  : AppTextStyles.labelMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// The raised circular camera button in the middle of the bar. Opens the
/// camera as a full-screen route (via [AppBottomNavBar.onCameraPressed]) - an
/// action, not a selectable tab, so it never shows a selected state.
class _CameraButton extends StatelessWidget {
  const _CameraButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Identify a dish',
      child: GestureDetector(
        onTap: onTap,
        child: Center(
          child: Container(
            width: AppSizes.navFabDiameter,
            height: AppSizes.navFabDiameter,
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.background, width: 3),
            ),
            child: const Icon(
              Icons.camera_alt_outlined,
              color: AppColors.onPrimary,
              size: 30,
            ),
          ),
        ),
      ),
    );
  }
}
