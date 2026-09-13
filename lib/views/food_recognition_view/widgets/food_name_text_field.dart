import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../app/theme/app_text_styles.dart';

/// The manual food-name input shared by BOTH recognition popups - the
/// single-result card's "Wrong dish? Type the name" field and the
/// multiple-results fallback ("None of these? Type the food name:").
///
/// One widget so the two fields can never drift: typing STOPS at [maxLength]
/// characters (counter hidden - the amber warning is the feedback) and
/// [warningFor] supplies the live message shown under the field while the
/// typed name gets long. Both values come from the logic layer
/// (`LandmarkSubmissionLogic.maxFoodNameLength` / `foodNameLengthWarning`),
/// surfaced by `FoodRecognitionViewModel` - this widget only renders them.
///
/// The input itself is restricted to LETTERS, DIGITS and SPACES - no special
/// characters (user request, 2026-09-14: "only allow characters, no special
/// characters, numbers are allowed") - see [_FoodNameCharactersFormatter].
class FoodNameTextField extends StatefulWidget {
  const FoodNameTextField({
    super.key,
    required this.controller,
    required this.enabled,
    required this.maxLength,
    required this.warningFor,
    required this.onSubmitted,
    this.hintText = 'e.g. Murtabak',
  });

  final TextEditingController controller;
  final bool enabled;

  /// Hard input cap (TextField maxLength, counter hidden).
  final int maxLength;

  /// Live warning for the current value - null while the name is a normal
  /// length.
  final String? Function(String name) warningFor;

  final VoidCallback onSubmitted;
  final String hintText;

  @override
  State<FoodNameTextField> createState() => _FoodNameTextFieldState();
}

class _FoodNameTextFieldState extends State<FoodNameTextField> {
  String? _warning;

  /// Recomputes on every keystroke; rebuilds only when the message actually
  /// changes (every character in the warn zone changes it, every character
  /// before it does not).
  void _onChanged(String value) {
    final String? warning = widget.warningFor(value);
    if (warning == _warning) return;
    setState(() => _warning = warning);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          maxLength: widget.maxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          // Letters, digits and spaces only - see the formatter's doc.
          inputFormatters: const <TextInputFormatter>[
            _FoodNameCharactersFormatter(),
          ],
          textInputAction: TextInputAction.done,
          onChanged: _onChanged,
          onSubmitted: (_) => widget.onSubmitted(),
          decoration: InputDecoration(
            hintText: widget.hintText,
            isDense: true,
            counterText: '',
          ),
        ),
        if (_warning != null) ...<Widget>[
          const SizedBox(height: AppSpacing.xs),
          Text(
            _warning!,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning),
          ),
        ],
      ],
    );
  }
}

/// Keeps the typed food name to LETTERS, DIGITS and SPACES - no special
/// characters, no punctuation, no emoji (user request, 2026-09-14: "only
/// allow characters, no special characters, numbers are allowed").
///
/// Letters and digits pass in ANY script (the same Unicode property escapes
/// the name rules use), so "Nasi Goreng", "Roti 2 Keping" and "炒粿条" all
/// type fine, while "Nasi@#$!" cannot be entered OR pasted - formatters run
/// on both. A rejected edit returns the surviving text with the caret at
/// the end; an edit that changes nothing is passed through untouched so
/// the selection and any IME composing region are preserved.
class _FoodNameCharactersFormatter extends TextInputFormatter {
  const _FoodNameCharactersFormatter();

  static final RegExp _allowed = RegExp(r'[\p{L}\p{N} ]', unicode: true);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    bool blocked = false;
    final StringBuffer kept = StringBuffer();
    for (final int rune in newValue.text.runes) {
      final String character = String.fromCharCode(rune);
      if (_allowed.hasMatch(character)) {
        kept.write(character);
      } else {
        blocked = true;
      }
    }
    if (!blocked) return newValue;
    final String text = kept.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
