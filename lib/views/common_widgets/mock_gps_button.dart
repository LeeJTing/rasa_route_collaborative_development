import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../domain_model/tourist_location.dart';
import 'app_dialog.dart';

/// Presenter tool (dev builds, Android only): teleports the OS-level GPS to a
/// chosen spot - or nudges it by [nudgeMetres] - so the app can be demoed
/// "at" a restaurant (or just outside its range) without moving the device.
///
/// Used by the dashboard and the capture screen; both drive the SAME
/// `MockLocationService` singleton, so a mock set on one screen is live on
/// the other. That is what makes the 50 m same-restaurant demo a one-tap
/// affair: capture the first dish, tap "North 60 m" here, capture the next -
/// the second capture is refused.
///
/// Requires Android Developer Options > "Select mock location app" to point
/// at this app; callers hide the button when the platform cannot mock or the
/// build is `prod`.
///
/// Tapping the button always opens the picker; while a mock is live the
/// picker also offers "Stop mock" - so a new latitude/longitude can be set
/// WITHOUT stopping the mock first.
class MockGpsButton extends StatelessWidget {
  const MockGpsButton({
    super.key,
    required this.isActive,
    required this.onSetMock,
    required this.onStopMock,
    this.fromLocation,
  });

  /// Whether a mock is live right now - the button then offers "Stop mock".
  final bool isActive;

  /// Teleports the OS GPS. Returns an error message, or null on success.
  final Future<String?> Function(double latitude, double longitude) onSetMock;

  /// Clears the mock and resumes real fixes.
  final Future<void> Function() onStopMock;

  /// The fix the "walk N m" chips move FROM - the screen's current (mock or
  /// real) location. Null or unknown hides that section.
  final TouristLocation? fromLocation;

  /// How far one nudge chip moves the mock: just past the 50 m
  /// same-restaurant limit, so a single tap demos the rule being enforced.
  /// North then South lands exactly back where the demo started.
  static const double nudgeMetres = 60;

  /// Preset Malaysian spots, GROUPED BY STATE so the picker shows one
  /// section per state and demoing "same dish, different state" is two taps
  /// (user request, 2026-09-13). The LAST group holds the spots the app must
  /// refuse to treat as restaurant locations - kept apart so they can never
  /// be mistaken for a normal demo spot.
  static const List<
    ({String state, List<({String label, double lat, double lon})> spots})
  >
  presetGroups =
      <({String state, List<({String label, double lat, double lon})> spots})>[
        (
          state: 'Kuala Lumpur',
          spots: <({String label, double lat, double lon})>[
            (label: 'KL', lat: 3.1390, lon: 101.6869),
            (label: 'Setapak', lat: 3.1930, lon: 101.7120),
            (label: 'Cheras', lat: 3.0833, lon: 101.7500),
            (label: 'Ampang', lat: 3.1500, lon: 101.7600),
            (label: 'Wangsa Maju', lat: 3.2005, lon: 101.7310),
            (label: 'Kepong', lat: 3.2150, lon: 101.6400),
            (label: 'Mont Kiara', lat: 3.1660, lon: 101.6530),
            (label: 'Bangsar', lat: 3.1290, lon: 101.6700),
            (label: 'Bukit Bintang', lat: 3.1466, lon: 101.7110),
            (label: 'Chow Kit', lat: 3.1700, lon: 101.6980),
            (label: 'Sri Petaling', lat: 3.0700, lon: 101.6900),
            (label: 'Sentul', lat: 3.1800, lon: 101.6900),
          ],
        ),
        (
          state: 'Selangor',
          spots: <({String label, double lat, double lon})>[
            (label: 'Subang Jaya', lat: 3.0567, lon: 101.5853),
            (label: 'Petaling Jaya', lat: 3.1073, lon: 101.6067),
            (label: 'Shah Alam', lat: 3.0733, lon: 101.5185),
            (label: 'Klang', lat: 3.0449, lon: 101.4455),
            (label: 'Puchong', lat: 3.0324, lon: 101.6176),
            (label: 'Kajang', lat: 2.9930, lon: 101.7872),
            (label: 'Seri Kembangan', lat: 3.0220, lon: 101.7060),
            (label: 'Cyberjaya', lat: 2.9213, lon: 101.6559),
            (label: 'Bangi', lat: 2.9500, lon: 101.7550),
            (label: 'Rawang', lat: 3.3213, lon: 101.5767),
          ],
        ),
        (
          state: 'Johor',
          spots: <({String label, double lat, double lon})>[
            (label: 'Johor Bahru', lat: 1.4927, lon: 103.7414),
            (label: 'Iskandar Puteri', lat: 1.4276, lon: 103.6295),
            (label: 'Skudai', lat: 1.5350, lon: 103.6550),
            (label: 'Kulai', lat: 1.6562, lon: 103.6034),
            (label: 'Batu Pahat', lat: 1.8548, lon: 102.9327),
            (label: 'Muar', lat: 2.0450, lon: 102.5686),
            (label: 'Kluang', lat: 2.0303, lon: 103.3162),
            (label: 'Segamat', lat: 2.5097, lon: 102.8148),
          ],
        ),
        (
          state: 'Other states',
          spots: <({String label, double lat, double lon})>[
            (label: 'Penang', lat: 5.4141, lon: 100.3288),
            (label: 'Kota Kinabalu', lat: 5.9804, lon: 116.0735),
            (label: 'Kuching', lat: 1.5535, lon: 110.3593),
          ],
        ),
        (
          state: 'Refusal tests',
          spots: <({String label, double lat, double lon})>[
            (label: 'Outside MY', lat: 1.3521, lon: 103.8198),
            (label: 'At sea', lat: 3.0, lon: 100.2),
          ],
        ),
      ];

  /// [latitude]/[longitude] moved by [northMetres]/[eastMetres] (negative =
  /// south/west). A degree of longitude is shorter than a degree of latitude
  /// away from the equator, hence the cos() term; the 0.01 floor only guards
  /// the poles. Pure, so it is unit-tested.
  static ({double lat, double lon}) offsetBy(
    double latitude,
    double longitude, {
    double northMetres = 0,
    double eastMetres = 0,
  }) {
    const double metresPerDegreeLatitude = 111320;
    final double cosine = math.cos(latitude * math.pi / 180).abs();
    return (
      lat: latitude + northMetres / metresPerDegreeLatitude,
      lon:
          longitude +
          eastMetres / (metresPerDegreeLatitude * math.max(cosine, 0.01)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: isActive
          ? 'GPS mock: move or stop (dev)'
          : 'Mock GPS: set lat/lon or walk 60 m (dev)',
      style: isActive
          ? IconButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            )
          : null,
      icon: Icon(isActive ? Icons.location_off : Icons.my_location),
      // Always the picker. While a mock is live it also offers "Stop mock",
      // so new latitude/longitude can be set WITHOUT stopping the mock first.
      onPressed: () => _openPicker(context),
    );
  }

  /// One line describing the fix the picker's chips work from.
  String _currentFixCaption(TouristLocation? from) {
    if (from == null || !from.isKnown) {
      return 'No known fix yet - pick a preset or set lat/lon.';
    }
    final String coords =
        '${from.latitude.toStringAsFixed(5)}, '
        '${from.longitude.toStringAsFixed(5)}';
    return isActive ? 'Current mock: $coords' : 'Current fix: $coords';
  }

  Future<void> _openPicker(BuildContext context) async {
    final TouristLocation? from = fromLocation;
    final bool canNudge = from != null && from.isKnown;
    final _MockGpsChoice? choice = await showModalBottomSheet<_MockGpsChoice>(
      context: context,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Mock GPS (dev)', style: AppTextStyles.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(_currentFixCaption(from), style: AppTextStyles.bodySmall),
              const SizedBox(height: AppSpacing.md),
              // One section per state, then the tools (set lat/lon, walk,
              // stop). Scrolls, because the district list is now taller than
              // a phone sheet.
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (final ({
                            String state,
                            List<({String label, double lat, double lon})>
                            spots,
                          })
                          group
                          in presetGroups) ...<Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: Text(
                            group.state,
                            style: AppTextStyles.titleSmall,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: <Widget>[
                            for (final ({String label, double lat, double lon})
                                p
                                in group.spots)
                              ActionChip(
                                label: Text(p.label),
                                onPressed: () => Navigator.pop(
                                  sheetContext,
                                  _MockGpsChoice.preset(p.lat, p.lon),
                                ),
                              ),
                          ],
                        ),
                      ],
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: Text('Tools', style: AppTextStyles.titleSmall),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          ActionChip(
                            avatar: const Icon(
                              Icons.edit_location_alt_outlined,
                              size: 18,
                            ),
                            label: const Text('Set lat/lon…'),
                            onPressed: () => Navigator.pop(
                              sheetContext,
                              const _MockGpsChoice.custom(),
                            ),
                          ),
                          if (canNudge) ...<Widget>[
                            SizedBox(
                              width: double.infinity,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.sm,
                                ),
                                child: Text(
                                  'Walk ${nudgeMetres.round()} m from here '
                                  '(demos the 50 m rule)',
                                  style: AppTextStyles.titleSmall,
                                ),
                              ),
                            ),
                            ActionChip(
                              label: const Text('North'),
                              onPressed: () => Navigator.pop(
                                sheetContext,
                                const _MockGpsChoice.nudge(
                                  northMetres: nudgeMetres,
                                ),
                              ),
                            ),
                            ActionChip(
                              label: const Text('South'),
                              onPressed: () => Navigator.pop(
                                sheetContext,
                                const _MockGpsChoice.nudge(
                                  northMetres: -nudgeMetres,
                                ),
                              ),
                            ),
                            ActionChip(
                              label: const Text('East'),
                              onPressed: () => Navigator.pop(
                                sheetContext,
                                const _MockGpsChoice.nudge(
                                  eastMetres: nudgeMetres,
                                ),
                              ),
                            ),
                            ActionChip(
                              label: const Text('West'),
                              onPressed: () => Navigator.pop(
                                sheetContext,
                                const _MockGpsChoice.nudge(
                                  eastMetres: -nudgeMetres,
                                ),
                              ),
                            ),
                          ],
                          if (isActive)
                            ActionChip(
                              avatar: const Icon(Icons.location_off, size: 18),
                              label: const Text('Stop mock'),
                              onPressed: () => Navigator.pop(
                                sheetContext,
                                const _MockGpsChoice.stop(),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;

    if (choice.isStop) {
      await onStopMock();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('GPS mock stopped (dev)')));
      return;
    }

    // "Set lat/lon…" closes the sheet and opens the coordinate dialog in its
    // place (prefilled with the current fix); a preset is used as-is; a nudge
    // is applied to the screen's current fix, so North then South lands back
    // on the same spot.
    final ({double lat, double lon}) spot;
    if (choice.isCustom) {
      final ({double lat, double lon})? custom =
          await showDialog<({double lat, double lon})>(
            context: context,
            builder: (_) => _CustomCoordinatesDialog(
              initialLatitude: canNudge ? from.latitude : null,
              initialLongitude: canNudge ? from.longitude : null,
            ),
          );
      if (custom == null || !context.mounted) return;
      spot = custom;
    } else if (choice.isNudge && canNudge) {
      spot = offsetBy(
        from.latitude,
        from.longitude,
        northMetres: choice.northMetres,
        eastMetres: choice.eastMetres,
      );
    } else {
      spot = (lat: choice.latitude, lon: choice.longitude);
    }

    final String? error = await onSetMock(spot.lat, spot.lon);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ??
              'GPS mocked (dev): ${spot.lat.toStringAsFixed(5)}, '
                  '${spot.lon.toStringAsFixed(5)}',
        ),
      ),
    );
  }
}

/// What the mock-GPS picker sheet hands back: a preset spot, a custom
/// coordinate request (the sheet closes and a small dialog opens), a
/// relative nudge from the screen's current fix, or a stop request.
class _MockGpsChoice {
  const _MockGpsChoice.preset(this.latitude, this.longitude)
    : isCustom = false,
      isNudge = false,
      isStop = false,
      northMetres = 0,
      eastMetres = 0;

  const _MockGpsChoice.custom()
    : latitude = 0,
      longitude = 0,
      isCustom = true,
      isNudge = false,
      isStop = false,
      northMetres = 0,
      eastMetres = 0;

  const _MockGpsChoice.nudge({this.northMetres = 0, this.eastMetres = 0})
    : latitude = 0,
      longitude = 0,
      isCustom = false,
      isNudge = true,
      isStop = false;

  const _MockGpsChoice.stop()
    : latitude = 0,
      longitude = 0,
      isCustom = false,
      isNudge = false,
      isStop = true,
      northMetres = 0,
      eastMetres = 0;

  final double latitude;
  final double longitude;
  final bool isCustom;
  final bool isNudge;
  final bool isStop;
  final double northMetres;
  final double eastMetres;
}

/// The coordinate dialog behind the picker's "Set lat/lon…" chip - the way
/// the presenter tool jumps to a spot the presets don't cover. Uses the
/// shared [AppDialog] frame (rounded card, centred badge/heading, stacked
/// full-width actions) so it matches every other dialog in the flow, and it
/// is PREFILLED with the screen's current fix so the presenter edits real
/// numbers instead of typing them from scratch. Validates ranges (latitude
/// -90..90, longitude -180..180) before returning the typed pair.
class _CustomCoordinatesDialog extends StatefulWidget {
  const _CustomCoordinatesDialog({this.initialLatitude, this.initialLongitude});

  /// The fix to prefill the fields with; null leaves them empty.
  final double? initialLatitude;
  final double? initialLongitude;

  @override
  State<_CustomCoordinatesDialog> createState() =>
      _CustomCoordinatesDialogState();
}

class _CustomCoordinatesDialogState extends State<_CustomCoordinatesDialog> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _latitudeController = TextEditingController(
    text: widget.initialLatitude?.toStringAsFixed(5) ?? '',
  );
  late final TextEditingController _longitudeController = TextEditingController(
    text: widget.initialLongitude?.toStringAsFixed(5) ?? '',
  );

  @override
  void dispose() {
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.pop(context, (
      lat: double.parse(_latitudeController.text.trim()),
      lon: double.parse(_longitudeController.text.trim()),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.edit_location_alt_outlined,
      title: 'Mock GPS coordinates',
      message:
          'Type the latitude and longitude to teleport the test GPS to '
          '(dev tool).',
      extra: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              controller: _latitudeController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Latitude',
                hintText: 'e.g. 3.1390',
              ),
              validator: (String? value) {
                final double? lat = double.tryParse((value ?? '').trim());
                if (lat == null || lat < -90 || lat > 90) {
                  return 'Latitude must be a number between -90 and 90.';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _longitudeController,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Longitude',
                hintText: 'e.g. 101.6869',
              ),
              validator: (String? value) {
                final double? lon = double.tryParse((value ?? '').trim());
                if (lon == null || lon < -180 || lon > 180) {
                  return 'Longitude must be a number between -180 and 180.';
                }
                return null;
              },
              onFieldSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        ElevatedButton(onPressed: _submit, child: const Text('Mock GPS')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
