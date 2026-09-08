import 'package:flutter/material.dart';

import '../../app/theme/app_dimensions.dart';

/// Vertically centres a short form, and lets it scroll the moment it no
/// longer fits on screen.
///
/// Used by the auth forms (login / OTP). Their columns sit inside a `Scaffold`
/// whose body shrinks when the software keyboard opens
/// (`resizeToAvoidBottomInset`), so a fixed-height `Column` with `Spacer`s
/// overflows the moment there is less room - e.g. the email field is focused,
/// an inline error row appears under it, or the OTP boxes are partially pushed
/// under the keyboard.
///
/// This wrapper instead lays the content out in a scroll view with a minimum
/// height of the viewport: when the content is shorter than the viewport it is
/// centred exactly as before, and when the keyboard/error makes it taller the
/// whole form scrolls so the focused field is never clipped.
///
/// Because the child lives inside a scroll view it must NOT use
/// `Spacer`/`Expanded` children (their height would be unbounded) - use fixed
/// `SizedBox` gaps and `mainAxisAlignment` instead.
class ScrollableCenteredBody extends StatelessWidget {
  const ScrollableCenteredBody({super.key, required this.child});

  /// The centred form column (set `mainAxisAlignment: center` on it).
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return SingleChildScrollView(
          padding: AppSpacing.screenPadding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        );
      },
    );
  }
}
