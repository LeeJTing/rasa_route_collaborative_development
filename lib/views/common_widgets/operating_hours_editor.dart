import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_text_styles.dart';
import '../../domain_model/opening_hour.dart';

/// Shared operating-hours editor used by BOTH the Add-Landmark form and the
/// report page's "Operating hours are wrong" correction - promoted out of
/// `add_landmark_view.dart` when the second screen needed the same control
/// (the codebase convention: promote a widget when a second screen needs it).
///
/// Every day has a three-way [DayStatus] (Open / Unknown / Closed) - see
/// `OpeningHour`'s doc for why "Unknown" is a real answer, not just a UI
/// decoration. Only Open gets editable time dropdowns - Unknown has no time to
/// show, so it's rendered dimmed with no interaction, same as Closed.
///
/// A day can have more than one `OpeningHour` row when Open (e.g. a midday
/// closure: "12:00-14:00" then "15:00-20:00") - this directly mirrors the
/// real `OpeningHours` table, where each row independently carries its own
/// `(day, status, opening_time, closing_time)`, rather than a day-level
/// object wrapping a list. Each row gets its own line; the "+" at the end
/// of the last one adds another.
class OperatingHoursEditor extends StatelessWidget {
  const OperatingHoursEditor({
    super.key,
    required this.operatingHours,
    required this.onStatusChanged,
    required this.onRangeTimeChanged,
    required this.onAddRange,
    required this.onRemoveRange,
    this.onCopyMondayToAll,
    this.title = 'Operating Hours',
    this.helperText,
  });

  final Map<Weekday, List<OpeningHour>> operatingHours;
  final void Function(Weekday day, DayStatus status) onStatusChanged;
  final void Function(
    Weekday day,
    int rangeIndex,
    bool isOpeningTime,
    int minutes,
  )
  onRangeTimeChanged;
  final void Function(Weekday day) onAddRange;
  final void Function(Weekday day, int rangeIndex) onRemoveRange;

  /// Optional "copy Monday to all weekdays" shortcut - Add Landmark shows it;
  /// the report screen hides it (a correction usually touches specific days,
  /// and bulk-copying could accidentally "change" days the tourist did not
  /// mean to report).
  final VoidCallback? onCopyMondayToAll;

  /// Card title (defaults to "Operating Hours").
  final String title;

  /// Optional helper line under the card title, e.g. the report screen's
  /// "Only correct the days that are wrong".
  final String? helperText;

  static const Map<Weekday, String> _dayLabels = <Weekday, String>{
    Weekday.monday: 'Mon',
    Weekday.tuesday: 'Tue',
    Weekday.wednesday: 'Wed',
    Weekday.thursday: 'Thu',
    Weekday.friday: 'Fri',
    Weekday.saturday: 'Sat',
    Weekday.sunday: 'Sun',
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (onCopyMondayToAll != null)
              Row(
                children: <Widget>[
                  Expanded(child: Text(title, style: AppTextStyles.titleSmall)),
                  // Flexible + ellipsis so the long button label never
                  // overflows the card's right edge on narrow screens.
                  Flexible(
                    child: TextButton(
                      onPressed: onCopyMondayToAll,
                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                      child: Text(
                        'Copy Monday to All Weekdays',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(
                          decoration: TextDecoration.underline,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else
              Text(title, style: AppTextStyles.titleSmall),
            if (helperText != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                helperText!,
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            // Column headers, precisely aligned with the actual
            // opening/closing dropdowns on each day row below - both share
            // the exact same widths (AppSizes.timeDropdownWidth for each
            // dropdown, an invisible dash the same width as the real "-"
            // separator), so this isn't just an approximate lineup.
            Row(
              children: <Widget>[
                const SizedBox(
                  width:
                      AppSizes.shortDayLabelWidth +
                      AppSizes.compactCheckboxSize +
                      AppSpacing.sm +
                      AppSizes.openLabelSlotWidth,
                ),
                SizedBox(
                  width: AppSizes.timeDropdownWidth,
                  child: Text('Opening', style: AppTextStyles.detailLabel),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: AppSizes.timeDropdownWidth,
                  child: Text('Closing', style: AppTextStyles.detailLabel),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final Weekday day in Weekday.values)
              OperatingHoursDayRow(
                label: _dayLabels[day]!,
                rows: operatingHours[day] ?? const <OpeningHour>[],
                onStatusChanged: (DayStatus status) =>
                    onStatusChanged(day, status),
                onRangeTimeChanged:
                    (int rangeIndex, bool isOpeningTime, int minutes) =>
                        onRangeTimeChanged(
                          day,
                          rangeIndex,
                          isOpeningTime,
                          minutes,
                        ),
                onAddRange: () => onAddRange(day),
                onRemoveRange: (int rangeIndex) =>
                    onRemoveRange(day, rangeIndex),
              ),
          ],
        ),
      ),
    );
  }
}

class OperatingHoursDayRow extends StatelessWidget {
  const OperatingHoursDayRow({
    super.key,
    required this.label,
    required this.rows,
    required this.onStatusChanged,
    required this.onRangeTimeChanged,
    required this.onAddRange,
    required this.onRemoveRange,
  });

  final String label;

  /// This day's `OpeningHour` rows - always at least one (a Closed/Unknown
  /// day has exactly one, with null times; an Open day can have more).
  final List<OpeningHour> rows;
  final ValueChanged<DayStatus> onStatusChanged;
  final void Function(int rangeIndex, bool isOpeningTime, int minutes)
  onRangeTimeChanged;
  final VoidCallback onAddRange;
  final ValueChanged<int> onRemoveRange;

  /// Cycles Closed -> Unknown -> Open -> Closed - one tap on the toggle
  /// advances to the next state.
  static DayStatus _nextStatus(DayStatus current) {
    switch (current) {
      case DayStatus.closed:
        return DayStatus.unknown;
      case DayStatus.unknown:
        return DayStatus.open;
      case DayStatus.open:
        return DayStatus.closed;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Every row shares the same status (the ViewModel keeps it that way),
    // so the first row's status stands for the whole day - there's no
    // separate day-level status field to read now that OpeningHour rows
    // mirror the real table directly.
    final DayStatus status = rows.isNotEmpty
        ? rows.first.status
        : DayStatus.closed;

    // One compact toggle (dash/?/check) instead of three separate
    // checkboxes - tapping it cycles Closed -> Unknown -> Open. That frees
    // up the row to also hold the opening/closing time dropdowns directly
    // alongside the day label. Each row gets its own line; "+" trails the
    // last one to add another, "x" removes one once there's more than one.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: AppSizes.shortDayLabelWidth,
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(label, style: AppTextStyles.operatingHoursLabel),
            ),
          ),
          DayStatusToggle(
            status: status,
            onTap: () => onStatusChanged(_nextStatus(status)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: status == DayStatus.open
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      for (int i = 0; i < rows.length; i++)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: i < rows.length - 1 ? AppSpacing.xs : 0,
                          ),
                          // Every row uses the same fixed column widths, so a
                          // newly added row lines up exactly with the rows
                          // above it, and the Opening/Closing boxes sit under
                          // their header titles.
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              // "Open" label - fixed slot, only on the first
                              // row (empty on later rows keeps columns stable).
                              SizedBox(
                                width: AppSizes.openLabelSlotWidth,
                                child: i == 0
                                    ? Text(
                                        'Open',
                                        style: AppTextStyles.bodySmall,
                                      )
                                    : null,
                              ),
                              TimeDropdownField(
                                minutes: rows[i].opensAt,
                                onChanged: (int m) =>
                                    onRangeTimeChanged(i, true, m),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              TimeDropdownField(
                                minutes: rows[i].closesAt,
                                onChanged: (int m) =>
                                    onRangeTimeChanged(i, false, m),
                              ),
                              // Action: "+" on the first row (add another
                              // range), "x" on the rest (remove). Right-aligned
                              // in a flexible slot so it always lines up and
                              // never overflows.
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: i == 0
                                      ? InkWell(
                                          onTap: onAddRange,
                                          child: const Icon(
                                            Icons.add_circle_outline,
                                            size: AppSizes.addRangeIconSize,
                                            color: AppColors.primary,
                                          ),
                                        )
                                      : InkWell(
                                          onTap: () => onRemoveRange(i),
                                          child: const Icon(
                                            Icons.close,
                                            size: AppSizes.addRangeIconSize,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  )
                : Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      status == DayStatus.unknown
                          ? 'Hours not known'
                          : 'Closed',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Opening/closing time selector - a dropdown list of every 15-minute mark
/// from "00:00" through "24:00" inclusive ("24:00" is its own distinct
/// option, meaning "open until midnight," not the same slot as "00:00").
/// Replaces the old wheel-style `showTimePicker` dialog - the tourist picks
/// straight from the fixed list instead.
class TimeDropdownField extends StatelessWidget {
  const TimeDropdownField({
    super.key,
    required this.minutes,
    required this.onChanged,
  });

  /// Minutes since midnight (0-1440). 1440 itself is the "24:00" option.
  final int? minutes;
  final ValueChanged<int> onChanged;

  static const int _stepMinutes = 15;
  static const int _maxMinutes = 24 * 60; // 1440 = "24:00"

  static String _label(int totalMinutes) {
    if (totalMinutes >= _maxMinutes) return '24:00';
    final int hour = totalMinutes ~/ 60;
    final int minute = totalMinutes % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// Rounds to the nearest valid dropdown entry - guards against a stored
  /// value that doesn't land exactly on a 15-minute mark (DropdownButton
  /// throws if its value doesn't match one of its items exactly).
  static int? _snap(int? value) {
    if (value == null) return null;
    final int snapped = ((value / _stepMinutes).round()) * _stepMinutes;
    return snapped.clamp(0, _maxMinutes);
  }

  @override
  Widget build(BuildContext context) {
    // Fixed-width box so it never resizes when the selected time changes
    // ("00:00" vs "24:00" etc.) - the DropdownButton fills it via isExpanded.
    return Container(
      width: AppSizes.timeDropdownWidth,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.timeChipBackground,
        border: Border.all(color: AppColors.textPrimary, width: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _snap(minutes),
          isDense: true,
          isExpanded: true, // Fills the fixed-width container above instead
          // of sizing to its own content, so the arrow
          // sits at the container's true right edge.
          iconSize: AppSizes.compactCheckboxIconSize,
          style: AppTextStyles.bodySmall,
          hint: Text('--:--', style: AppTextStyles.bodySmall),
          items: <DropdownMenuItem<int>>[
            for (int m = 0; m <= _maxMinutes; m += _stepMinutes)
              DropdownMenuItem<int>(value: m, child: Text(_label(m))),
          ],
          onChanged: (int? value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

/// A single compact toggle standing in for the day's status - a dash for
/// Closed (default), a question mark for Unknown, a checkmark for Open.
/// Tapping cycles through all three (see `OperatingHoursDayRow`) rather than
/// showing three separate checkboxes side by side, so the row has room left
/// for the opening/closing time fields next to it.
class DayStatusToggle extends StatelessWidget {
  const DayStatusToggle({super.key, required this.status, required this.onTap});

  final DayStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    late final Widget glyph;
    switch (status) {
      case DayStatus.open:
        glyph = const Icon(
          Icons.check,
          size: AppSizes.compactCheckboxIconSize,
          color: AppColors.textPrimary,
        );
      case DayStatus.unknown:
        glyph = Text(
          '?',
          style: AppTextStyles.operatingHoursLabel.copyWith(
            color: AppColors.textPrimary,
          ),
        );
      case DayStatus.closed:
        glyph = const Icon(
          Icons.remove,
          size: AppSizes.compactCheckboxIconSize,
          color: AppColors.textSecondary,
        );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xs),
      child: Container(
        width: AppSizes.compactCheckboxSize,
        height: AppSizes.compactCheckboxSize,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.cardBorderWarm,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: glyph,
      ),
    );
  }
}
