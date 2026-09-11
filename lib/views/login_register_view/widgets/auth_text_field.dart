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
  const AuthTextField({super.key, required this.onChanged, this.errorText});

  final ValueChanged<String> onChanged;

  /// Inline validation message shown under the field (and which turns the
  /// border red). Null hides the error state.
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final bool hasError = errorText != null && errorText!.isNotEmpty;
    final OutlineInputBorder border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.authPillRadius),
      borderSide: BorderSide(
        color: hasError ? AppColors.error : AppColors.outline,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          onChanged: onChanged,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          autofillHints: const <String>[AutofillHints.email],
          decoration: InputDecoration(
            hintText: 'abc@example.com',
            // The auth mock-up draws the email field as a pill, not the app's
            // default 12px-cornered field - same tokens, different radius.
            enabledBorder: border,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.authPillRadius),
              borderSide: BorderSide(
                color: hasError ? AppColors.error : AppColors.primary,
                width: AppSizes.borderWidthStrong,
              ),
            ),
            errorText: hasError ? errorText : null,
            errorStyle: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.error),
            errorMaxLines: 2,
          ),
        ),
      ],
    );
  }
}
