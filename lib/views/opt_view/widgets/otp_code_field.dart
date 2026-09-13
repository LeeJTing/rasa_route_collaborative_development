import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';

/// Six single-digit lookalike boxes driven by ONE hidden text field.
///
/// The six visible boxes are pure decoration; a single invisible `TextField`
/// underneath owns the keyboard and the whole code string, so editing behaves
/// exactly like one input field:
///   * typing appends a digit and the boxes fill left-to-right;
///   * backspace removes the previous digit and keeps going back through every
///     box (no need to tap each box to clear a mistake);
///   * pasting a full code fills all boxes at once;
///   * the slot the next digit lands in is highlighted while focused.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values.
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.onChanged,
    // Supabase email OTPs are 6 digits.
    this.codeLength = 6,
    this.enabled = true,
  });

  final ValueChanged<String> onChanged;

  /// Number of single-digit boxes.
  final int codeLength;

  /// When false the boxes become read-only: the keyboard is dismissed and
  /// backspace can no longer delete a digit.
  ///
  /// The OTP screen clears this while the entered code is being verified, so
  /// the digits on screen keep matching the request that is already in flight
  /// (the backend call cannot be cancelled, so the UI must not contradict it).
  final bool enabled;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode.addListener(_onFocusChanged);
    // The mock-up opens straight into the first box on entry (autofocus) so
    // the tourist can start typing right away.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant OtpCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Locking the field mid-verify: a disabled field cannot hold focus, so
    // drop it explicitly (after the frame, to stay clear of the build phase)
    // and the keyboard closes with it instead of sitting there able to send
    // backspaces at a locked input.
    if (oldWidget.enabled && !widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.unfocus();
      });
      return;
    }
    // Unlocked again (the code was rejected): put the caret back at the end so
    // the tourist can correct the digits straight away, exactly as before the
    // field was locked.
    if (!oldWidget.enabled && widget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _moveCaretToEnd();
        _focusNode.requestFocus();
      });
    }
  }

  void _onFocusChanged() {
    // Single-input caret semantics: whenever focus returns (initial autofocus,
    // a tap on the field), put the caret at the end so the next digit appends
    // and backspace removes the last digit rather than editing mid-string.
    if (_focusNode.hasFocus && mounted) _moveCaretToEnd();
    if (mounted) setState(() {});
  }

  void _moveCaretToEnd() {
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
  }

  void _onCodeChanged(String value) {
    if (!mounted) return;
    setState(() {});
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final String code = _controller.text;
    final TextStyle? digitStyle = Theme.of(
      context,
    ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700);
    final bool focused = _focusNode.hasFocus;
    // The slot the next digit will land in; when full, keep the last box as
    // the highlighted anchor so there is always a visible active slot.
    final int activeIndex = code.length < widget.codeLength
        ? code.length
        : widget.codeLength - 1;

    return SizedBox(
      height: AppSizes.fieldHeight,
      child: Stack(
        children: <Widget>[
          // Visible six boxes - never interactive themselves, taps pass
          // through to the hidden TextField layered on top.
          Row(
            children: List<Widget>.generate(widget.codeLength, (int index) {
              final bool isActive =
                  focused && widget.codeLength > 0 && index == activeIndex;
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: index == widget.codeLength - 1 ? 0 : AppSpacing.sm,
                  ),
                  child: Container(
                    height: AppSizes.fieldHeight,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppRadius.cardRadius,
                      border: Border.all(
                        color: isActive ? AppColors.primary : AppColors.outline,
                        width: isActive ? 1.5 : 1,
                      ),
                    ),
                    child: index < code.length
                        ? Text(
                            code[index],
                            style: digitStyle,
                            textAlign: TextAlign.center,
                          )
                        : null,
                  ),
                ),
              );
            }),
          ),
          // The actual input: invisible, but it owns the focus + keyboard, so
          // typing/backspace/paste all behave like a single text field.
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                // Locked while the code is being verified.
                enabled: widget.enabled,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                maxLength: widget.codeLength,
                style: digitStyle,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.codeLength),
                ],
                onChanged: _onCodeChanged,
                onTap: _moveCaretToEnd,
                decoration: const InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
