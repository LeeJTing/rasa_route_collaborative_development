import 'package:flutter/material.dart';

import '../dashboard_view/dashboard_view.dart';
import '../food_recognition_view/food_recognition_view.dart';
import '../local_food_list_view/local_food_list_view.dart';

class MainShellView extends StatefulWidget {
  const MainShellView({super.key});

  @override
  State<MainShellView> createState() => _MainShellViewState();
}

class _MainShellViewState extends State<MainShellView> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    DashboardView(),
    FoodRecognitionView(),
    LocalFoodListView(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8E7),

      // --------------------------------------------------
      // Page Content
      // --------------------------------------------------
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),

      // --------------------------------------------------
      // Bottom Navigation Bar
      // --------------------------------------------------
      bottomNavigationBar: Container(
        height: 74,
        decoration: const BoxDecoration(
          color: Color(0xFFFFEDBE),
        ),
        child: Row(
          children: [
            // ----------------------------------------------
            // HOME
            // ----------------------------------------------
            Expanded(
              child: _buildNavItem(
                index: 0,
                icon: Icons.home_outlined,
                selectedIcon: Icons.home,
                label: 'Home',
              ),
            ),

            // ----------------------------------------------
            // CAMERA
            // ----------------------------------------------
            Expanded(
              child: GestureDetector(
                onTap: () => _onItemTapped(1),
                child: Center(
                  child: Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9700),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFFFF8E7),
                        width: 3,
                      ),
                    ),
                    child: const Icon(
                      Icons.camera_alt_outlined,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ),
            ),

            // ----------------------------------------------
            // LEARN
            // ----------------------------------------------
            Expanded(
              child: _buildNavItem(
                index: 2,
                icon: Icons.search_outlined,
                selectedIcon: Icons.search,
                label: 'Learn',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
  }) {
    final bool isSelected = _currentIndex == index;

    const orange = Color(0xFFFF9700);
    const grey = Color(0xFF7F91A8);

    return InkWell(
      onTap: () => _onItemTapped(index),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSelected ? selectedIcon : icon,
            size: 25,
            color: isSelected ? orange : grey,
          ),

          const SizedBox(height: 3),

          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected
                  ? FontWeight.w600
                  : FontWeight.w400,
              color: isSelected ? orange : grey,
            ),
          ),
        ],
      ),
    );
  }
}
