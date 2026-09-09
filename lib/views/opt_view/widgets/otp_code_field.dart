import 'package:flutter/material.dart';

import '../../../app/theme/app_dimensions.dart';

/// Reusable piece of `OtpView`. Placeholder.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values. Promote one to
/// `lib/views/common_widgets/` once a second screen needs it.
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.onChanged,
    // Supabase email OTPs are 6 digits.
    this.codeLength = 6,
  });

  final ValueChanged<String> onChanged;

  /// Number of single-digit boxes.
  final int codeLength;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;

  @override
  void initState() {
    super.initState();
    _controllers = List<TextEditingController>.generate(
      widget.codeLength,
      (_) => TextEditingController(),
    );
    _focusNodes = List<FocusNode>.generate(
      widget.codeLength,
      (_) => FocusNode(),
    );

    // The mock-up highlights the first box on entry (autofocus) so the user
    // can start typing straight away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final TextEditingController controller in _controllers) {
      controller.dispose();
    }
    for (final FocusNode focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      final String digits = value.replaceAll(RegExp(r'\D'), '');
      for (
        int i = index;
        i < widget.codeLength && i - index < digits.length;
        i++
      ) {
        _controllers[i].text = digits[i - index];
      }
    }
    final String code = _controllers
        .map((TextEditingController controller) => controller.text)
        .join();
    widget.onChanged(code);
    if (value.isNotEmpty && index < widget.codeLength - 1) {
      _focusNodes[index + 1].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    // A bold, large-enough digit per box so the code is easy to read and the
    // text stays vertically centred inside each box.
    final TextStyle? digitStyle = Theme.of(
      context,
    ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700);
    return SizedBox(
      height: AppSizes.fieldHeight,
      child: Row(
        children: List<Widget>.generate(widget.codeLength, (int index) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == widget.codeLength - 1 ? 0 : AppSpacing.sm,
              ),
              child: TextField(
                controller: _controllers[index],
                focusNode: _focusNodes[index],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                textInputAction: index == widget.codeLength - 1
                    ? TextInputAction.done
                    : TextInputAction.next,
                maxLength: 1,
                style: digitStyle,
                onChanged: (String value) => _onDigitChanged(index, value),
                decoration: const InputDecoration(
                  counterText: '',
                  contentPadding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
