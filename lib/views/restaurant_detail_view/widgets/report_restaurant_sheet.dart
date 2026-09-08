import 'package:flutter/material.dart';

import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/restaurant_report_reason.dart';

class ReportRestaurantSheet extends StatefulWidget {
  const ReportRestaurantSheet({
    super.key,
    required this.restaurantName,
    required this.onSubmit,
  });

  final String restaurantName;
  final Future<void> Function(RestaurantReportReason reason) onSubmit;

  @override
  State<ReportRestaurantSheet> createState() => _ReportRestaurantSheetState();
}

class _ReportRestaurantSheetState extends State<ReportRestaurantSheet> {
  RestaurantReportReason? _selectedReason;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Report Restaurant',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Tell us what is incorrect about ${widget.restaurantName}.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            RadioGroup<RestaurantReportReason>(
              groupValue: _selectedReason,
              onChanged: (RestaurantReportReason? value) {
                if (!_submitting) setState(() => _selectedReason = value);
              },
              child: Column(
                children: RestaurantReportReason.values
                    .map(
                      (RestaurantReportReason reason) => RadioListTile(
                        value: reason,
                        enabled: !_submitting,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_reasonLabel(reason)),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _selectedReason == null || _submitting
                        ? null
                        : _submit,
                    child: _submitting
                        ? const SizedBox.square(
                            dimension: AppSpacing.lg,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Submit Report'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final RestaurantReportReason? reason = _selectedReason;
    if (reason == null) return;
    setState(() => _submitting = true);
    await widget.onSubmit(reason);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  String _reasonLabel(RestaurantReportReason reason) => switch (reason) {
    RestaurantReportReason.noLongerExists => 'Restaurant No Longer Exists',
    RestaurantReportReason.incorrectOperatingHours =>
      'Incorrect Operating Hours',
    RestaurantReportReason.incorrectLocation => 'Incorrect Location',
    RestaurantReportReason.listedLocalFoodUnavailable =>
      'Listed Local Food Not Available',
    RestaurantReportReason.incorrectInformation =>
      'Incorrect Restaurant Information',
  };
}
