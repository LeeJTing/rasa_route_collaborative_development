import 'package:flutter/material.dart';

import '../../../app/theme/app_dimensions.dart';

class FoodSearchBar extends StatelessWidget {
  const FoodSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.searchFieldHeight,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          hintText: 'Search local food...',
          prefixIcon: Icon(Icons.search),
        ),
      ),
    );
  }
}
