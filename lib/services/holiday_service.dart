import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class Holiday {
  final DateTime date;
  final String name;
  final bool companyDayOff;
  Holiday({required this.date, required this.name, this.companyDayOff = false});
}

class HolidayService {
  static Map<int, List<Holiday>>? _cache; // year -> holidays

  static Future<void> _ensureLoaded() async {
    if (_cache != null) return;
    final raw = await rootBundle.loadString('assets/holidays_at.json');
    final map = json.decode(raw) as Map<String, dynamic>;
    final tmp = <int, List<Holiday>>{};
    for (final entry in map.entries) {
      final year = int.parse(entry.key);
      final list = (entry.value as List).map((e) {
        final date = DateTime.parse(e['date'] as String);
        return Holiday(
          date: date,
          name: e['name'] as String,
          companyDayOff: (e['companyDayOff'] as bool?) ?? false,
        );
      }).toList()
        ..sort((a, b) => a.date.compareTo(b.date));
      tmp[year] = list;
    }
    _cache = tmp;
  }

  static Future<List<Holiday>> holidaysForYear(int year) async {
    await _ensureLoaded();
    return List<Holiday>.from(_cache?[year] ?? const []);
  }

  static Future<Holiday?> holidayOn(DateTime day) async {
    await _ensureLoaded();
    final y = day.year;
    final list = _cache?[y] ?? const [];
    final d = DateTime(day.year, day.month, day.day);
    for (final h in list) {
      final hd = DateTime(h.date.year, h.date.month, h.date.day);
      if (hd == d) return h;
    }
    return null;
  }

  static Future<Holiday?> nextHolidayFrom(DateTime from) async {
    await _ensureLoaded();
    final all = [
      ...?_cache?[from.year],
      ...?_cache?[from.year + 1], // look into next year as a convenience
    ]..sort((a, b) => a.date.compareTo(b.date));
    final today = DateTime(from.year, from.month, from.day);
    for (final h in all) {
      final hd = DateTime(h.date.year, h.date.month, h.date.day);
      if (!hd.isBefore(today)) return h;
    }
    return null;
  }
}
