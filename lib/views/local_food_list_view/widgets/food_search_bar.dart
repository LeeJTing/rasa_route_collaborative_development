import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';

class FoodSearchBar extends StatelessWidget {
  const FoodSearchBar({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClear,
    required this.maxLength,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
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
        decoration: InputDecoration(
          hintText: 'Search local food...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: controller.text.isNotEmpty
              ? InkWell(
            onTap: onClear,
            customBorder: const CircleBorder(),
            child: const Padding(
              padding: EdgeInsets.all(AppSpacing.xs),
              child: Icon(
                Icons.close,
                size: 18,
                color: AppColors.textSecondary,
              ),
            ),
          )
              : null,
        ),
      ),
    );
  }
}
