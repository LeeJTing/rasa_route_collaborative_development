import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../domain_model/opening_hour.dart';

/// A place's opening hours, grouped by day and shown in a FIXED
/// Monday-to-Sunday order with ONE day label per day - a day with several
/// ranges (e.g. a midday closure) stacks them right-aligned under its single
/// label, so nothing drifts and no day can appear twice.
///
/// Shared by the restaurant detail and the submitted-landmark detail pages
/// (promoted out of `restaurant_detail_view` when the second page needed the
/// same table - the codebase convention). The repository read has already
/// merged overnight tails back into the day that owns them (see
/// `OpeningHoursRows`), so an overnight period simply reads
/// "10:00 AM - 2:00 AM" - no "(next day)" mark.
class OpeningHoursTable extends StatelessWidget {
  const OpeningHoursTable({super.key, required this.openingHours});

  final List<OpeningHour> openingHours;

  @override
  Widget build(BuildContext context) {
    if (openingHours.isEmpty) {
      return Text(
        'Opening hours are not available yet.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
      );
    }

    final Map<Weekday, List<OpeningHour>> byDay =
        <Weekday, List<OpeningHour>>{};
    for (final OpeningHour hours in openingHours) {
      byDay.putIfAbsent(hours.day, () => <OpeningHour>[]).add(hours);
    }

    return Column(
      children: <Widget>[
        for (final Weekday day in Weekday.values)
          if (byDay[day] case final List<OpeningHour> ranges)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(child: Text(_dayLabel(day))),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        for (final OpeningHour range in ranges)
                          Text(_hoursLabel(range), textAlign: TextAlign.end),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  String _dayLabel(Weekday day) => switch (day) {
    Weekday.monday => 'Monday',
    Weekday.tuesday => 'Tuesday',
    Weekday.wednesday => 'Wednesday',
    Weekday.thursday => 'Thursday',
    Weekday.friday => 'Friday',
    Weekday.saturday => 'Saturday',
    Weekday.sunday => 'Sunday',
  };

  String _hoursLabel(OpeningHour hours) {
    if (hours.status == DayStatus.closed) return 'Closed';
    if (hours.status == DayStatus.unknown) return 'Hours not known';
    if (hours.opensAt == null || hours.closesAt == null) {
      return 'Hours unavailable';
    }
    if (hours.opensAt == 0 && hours.closesAt == 1440) {
      return 'Open 24 hours';
    }
    return '${_timeLabel(hours.opensAt!)} - ${_timeLabel(hours.closesAt!)}';
  }

  String _timeLabel(int minutes) {
    // 1440 (24:00) is midnight; an overnight close is encoded past 1440
    // (1560 = 02:00 the next day - see `OpeningHoursRows`) and reads as its
    // own time, the way Google Maps shows "10:00 AM - 2:00 AM".
    final int normalized = minutes % 1440;
    final int hour = normalized ~/ 60;
    final int minute = normalized % 60;
    final String period = hour >= 12 ? 'PM' : 'AM';
    final int displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }
}
