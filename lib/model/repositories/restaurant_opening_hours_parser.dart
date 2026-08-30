import 'dart:convert';

import '../../domain_model/opening_hour.dart';

/// Converts the Google-sourced JSON stored in `restaurant.opening_hours` into
/// the same domain rows used by submitted landmarks.
class RestaurantOpeningHoursParser {
  const RestaurantOpeningHoursParser();

  List<OpeningHour> parse(String? raw) {
    final String value = raw?.trim() ?? '';
    if (value.isEmpty) return const <OpeningHour>[];
    try {
      final Object? decoded = jsonDecode(value);
      if (decoded is! Map) return const <OpeningHour>[];
      final List<OpeningHour> rows = <OpeningHour>[];
      for (final MapEntry<Object?, Object?> entry in decoded.entries) {
        final Weekday? day = _weekday(entry.key?.toString() ?? '');
        if (day == null) continue;
        rows.addAll(_parseDay(day, entry.value?.toString() ?? ''));
      }
      return List<OpeningHour>.unmodifiable(rows);
    } on FormatException {
      return const <OpeningHour>[];
    }
  }

  List<OpeningHour> _parseDay(Weekday day, String raw) {
    final String value = raw.replaceAll(RegExp(r'[\u00a0\u202f]'), ' ').trim();
    final String lower = value.toLowerCase();
    if (lower == 'closed') {
      return <OpeningHour>[
        OpeningHour(id: 0, day: day, status: DayStatus.closed),
      ];
    }
    if (lower.startsWith('open 24 hours')) {
      return <OpeningHour>[
        OpeningHour(
          id: 0,
          day: day,
          status: DayStatus.open,
          opensAt: 0,
          closesAt: 1440,
        ),
      ];
    }

    final String cleaned = value
        .replaceAll(RegExp(r'hours might differ', caseSensitive: false), '')
        .replaceAll(RegExp(r'holiday hours', caseSensitive: false), '');
    final List<OpeningHour> rows = <OpeningHour>[];
    for (final String segment in cleaned.split(',')) {
      final RegExpMatch? range = RegExp(
        r'^\s*(.+?)\s*[\-–—]\s*(.+?)\s*$',
      ).firstMatch(segment);
      if (range == null) continue;
      final _ClockTime? end = _clockTime(range.group(2) ?? '');
      if (end == null) continue;
      final _ClockTime? start = _clockTime(
        range.group(1) ?? '',
        fallbackMeridiem: end.meridiem,
        rangeEnd: end.minutes,
      );
      if (start == null) continue;
      rows.add(
        OpeningHour(
          id: 0,
          day: day,
          status: DayStatus.open,
          opensAt: start.minutes,
          closesAt: end.minutes,
        ),
      );
    }
    return rows.isEmpty
        ? <OpeningHour>[OpeningHour(id: 0, day: day, status: DayStatus.unknown)]
        : rows;
  }

  _ClockTime? _clockTime(
    String raw, {
    String? fallbackMeridiem,
    int? rangeEnd,
  }) {
    final RegExpMatch? match = RegExp(
      r'^(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$',
      caseSensitive: false,
    ).firstMatch(raw.trim());
    if (match == null) return null;
    final int hour = int.parse(match.group(1)!);
    final int minute = int.parse(match.group(2) ?? '0');
    if (hour < 1 || hour > 12 || minute > 59) return null;
    final String? explicit = match.group(3)?.toLowerCase();
    final String? meridiem = explicit ?? fallbackMeridiem;
    if (meridiem == null) return null;

    int minutes = _minutes(hour, minute, meridiem);
    if (explicit == null && rangeEnd != null) {
      final String opposite = meridiem == 'am' ? 'pm' : 'am';
      final int alternative = _minutes(hour, minute, opposite);
      if (_forwardDuration(alternative, rangeEnd) <
          _forwardDuration(minutes, rangeEnd)) {
        minutes = alternative;
      }
    }
    return _ClockTime(minutes: minutes, meridiem: meridiem);
  }

  int _minutes(int hour, int minute, String meridiem) {
    final int normalizedHour = hour == 12 ? 0 : hour;
    return normalizedHour * 60 + minute + (meridiem == 'pm' ? 720 : 0);
  }

  int _forwardDuration(int start, int end) {
    final int duration = end - start;
    return duration > 0 ? duration : duration + 1440;
  }

  Weekday? _weekday(String raw) {
    final String value = raw.trim().toLowerCase();
    for (final Weekday day in Weekday.values) {
      if (value.startsWith(day.name)) return day;
    }
    return null;
  }
}

class _ClockTime {
  const _ClockTime({required this.minutes, required this.meridiem});

  final int minutes;
  final String meridiem;
}
