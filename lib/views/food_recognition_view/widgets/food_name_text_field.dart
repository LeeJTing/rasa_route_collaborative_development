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
