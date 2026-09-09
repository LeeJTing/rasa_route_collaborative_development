import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_dimensions.dart';

class FoodSearchBar extends StatelessWidget {
  const FoodSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.maxLength,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppSizes.searchFieldHeight,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        inputFormatters: <TextInputFormatter>[
          LengthLimitingTextInputFormatter(maxLength),
        ],
        maxLines: 1,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(
          hintText: 'Search local food...',
          prefixIcon: Icon(Icons.search),
        ),
      ),
    );
  }
}
