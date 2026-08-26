import 'package:flutter/material.dart';

/// Reusable piece of `LoginRegisterView`. Placeholder.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values. Promote one to
/// `lib/views/common_widgets/` once a second screen needs it.
class AuthTextField extends StatelessWidget {
  const AuthTextField({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
