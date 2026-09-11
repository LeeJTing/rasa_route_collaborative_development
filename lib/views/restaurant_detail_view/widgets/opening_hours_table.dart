import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimensions.dart';
import '../../../domain_model/opening_hour.dart';

/// Reusable piece of `RestaurantDetailView`. Placeholder.
///
/// Widgets in a `widgets/` folder are driven entirely by constructor
/// parameters and callbacks - they never read a ViewModel themselves, and they
/// style from the theme rather than raw values. Promote one to
/// `lib/views/common_widgets/` once a second screen needs it.
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
    return '${_timeLabel(hours.opensAt!)} - ${_timeLabel(hours.closesAt!)}';
  }

  String _timeLabel(int minutes) {
    if (minutes >= 1440) return '12:00 AM';
    final int hour = minutes ~/ 60;
    final int minute = minutes % 60;
    final String period = hour >= 12 ? 'PM' : 'AM';
    final int displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $period';
  }
}
