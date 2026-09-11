import 'package:flutter/material.dart';

import '../../../app/theme/app_dimensions.dart';
import 'food_name_text_field.dart';

/// The manual "none of these is right" fallback of the recognition popup:
/// a collapsed "Wrong dish? Type the name" link that opens a name field with
/// [Cancel] and [Show this food].
///
/// Shared by the single-result card and the multiple-results card so the
/// fallback looks and behaves the same wherever the tourist lands - it used
/// to be a collapsible link on one and an always-open field with its own
/// label and inline button on the other. Both go through
/// `FoodRecognitionViewModel.enterFoodName`, and both obey the same name
/// length rule via the shared [FoodNameTextField].
class ManualFoodNameEntry extends StatefulWidget {
  const ManualFoodNameEntry({
    super.key,
    required this.onEnterName,
    required this.isProcessing,
    required this.maxNameLength,
    required this.nameWarning,
  });

  /// Called with the typed name when "Show this food" is pressed (or the
  /// keyboard's submit action) - see `FoodRecognitionViewModel.enterFoodName`.
  final ValueChanged<String> onEnterName;

  /// While a name is being resolved the link, the field and both buttons are
  /// disabled.
  final bool isProcessing;

  /// Hard input cap + live length warning, passed straight through to the
  /// shared [FoodNameTextField].
  final int maxNameLength;
  final String? Function(String name) nameWarning;

  @override
  State<ManualFoodNameEntry> createState() => _ManualFoodNameEntryState();
}

class _ManualFoodNameEntryState extends State<ManualFoodNameEntry> {
  final TextEditingController _controller = TextEditingController();
  bool _show = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String name = _controller.text.trim();
    if (name.isEmpty || widget.isProcessing) return;
    widget.onEnterName(name);
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) {
      return Align(
        alignment: Alignment.center,
        child: TextButton.icon(
          onPressed: widget.isProcessing
              ? null
              : () => setState(() => _show = true),
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Wrong dish? Type the name'),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        FoodNameTextField(
          controller: _controller,
          enabled: !widget.isProcessing,
          maxLength: widget.maxNameLength,
          warningFor: widget.nameWarning,
          onSubmitted: _submit,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: widget.isProcessing
                  ? null
                  : () => setState(() => _show = false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: widget.isProcessing ? null : _submit,
              child: const Text('Show this food'),
            ),
          ],
        ),
      ],
    );
  }
}
