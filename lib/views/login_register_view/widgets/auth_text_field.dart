import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';

/// Reusable piece of `LoginRegisterView`. Placeholder.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values. Promote one to
/// `lib/views/common_widgets/` once a second screen needs it.
class AuthTextField extends StatelessWidget {
  const AuthTextField({super.key, required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.done,
      autofillHints: const <String>[AutofillHints.email],
      decoration: InputDecoration(
        hintText: 'abc@example.com',
        // The auth mock-up draws the email field as a pill, not the app's
        // default 12px-cornered field - same tokens, different radius.
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.authPillRadius),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.authPillRadius),
          borderSide: const BorderSide(
            color: AppColors.primary,
            width: AppSizes.borderWidthStrong,
          ),
        ),
      ),
    );
  }
}
