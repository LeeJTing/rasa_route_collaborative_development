import 'package:flutter/material.dart';

import '../../../app/theme/app_dimensions.dart';
import '../../../view_models/landmark_place_detail_view_model.dart';

/// Bottom sheet for reporting an incorrect submitted-landmark pin - the
/// landmark counterpart of `ReportRestaurantSheet` on the catalogue
/// restaurant detail screen. The tourist picks one reason, then submits;
/// the reason is passed to [onSubmit] and this sheet pops with `true`.
class ReportLandmarkSheet extends StatefulWidget {
  const ReportLandmarkSheet({
    super.key,
    required this.landmarkName,
    required this.onSubmit,
  });

  final String landmarkName;
  final Future<void> Function(LandmarkReportReason reason) onSubmit;

  @override
  State<ReportLandmarkSheet> createState() => _ReportLandmarkSheetState();
}

class _ReportLandmarkSheetState extends State<ReportLandmarkSheet> {
  LandmarkReportReason? _selectedReason;
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
              'Report Landmark',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Tell us what is incorrect about ${widget.landmarkName}.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            RadioGroup<LandmarkReportReason>(
              groupValue: _selectedReason,
              onChanged: (LandmarkReportReason? value) {
                if (!_submitting) setState(() => _selectedReason = value);
              },
              child: Column(
                children: LandmarkReportReason.values
                    .map(
                      (LandmarkReportReason reason) => RadioListTile(
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
    final LandmarkReportReason? reason = _selectedReason;
    if (reason == null) return;
    setState(() => _submitting = true);
    await widget.onSubmit(reason);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  String _reasonLabel(LandmarkReportReason reason) => switch (reason) {
    LandmarkReportReason.noLongerExists => 'Restaurant No Longer Exists',
    LandmarkReportReason.incorrectName => 'Incorrect Restaurant Name',
    LandmarkReportReason.incorrectLocation => 'Incorrect Location',
    LandmarkReportReason.incorrectOperatingHours => 'Incorrect Operating Hours',
    LandmarkReportReason.incorrectInformation =>
      'Incorrect Landmark Information',
  };
}
