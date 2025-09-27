import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:cloud_firestore/cloud_firestore.dart';

class Holiday {
  final DateTime date;
  final String name;
  final bool companyDayOff;
  Holiday({required this.date, required this.name, this.companyDayOff = false});
}

class HolidayService {
  static final CollectionReference<Map<String, dynamic>> _col =
      FirebaseFirestore.instance.collection('holidays').withConverter(
            fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
            toFirestore: (data, _) => data,
          );

  // Cache per year
  static final Map<int, List<Holiday>> _cache = <int, List<Holiday>>{};

  static Future<List<Holiday>> holidaysForYear(int year) async {
    if (_cache.containsKey(year)) {
      return List<Holiday>.from(_cache[year]!);
    }

    final query =
        await _col.where('year', isEqualTo: year).orderBy('date').get();

    final list = query.docs.map((doc) {
      final data = doc.data();
      final ts = data['date'];
      final DateTime date =
          ts is Timestamp ? ts.toDate() : DateTime.parse(ts as String);
      return Holiday(
        date: DateTime(date.year, date.month, date.day),
        name: data['name'] as String,
        companyDayOff: (data['companyDayOff'] as bool?) ?? false,
      );
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    _cache[year] = list;
    return List<Holiday>.from(list);
  }

  static Future<Holiday?> holidayOn(DateTime day) async {
    final list = await holidaysForYear(day.year);
    final d = DateTime(day.year, day.month, day.day);
    for (final h in list) {
      final hd = DateTime(h.date.year, h.date.month, h.date.day);
      if (hd == d) return h;
    }
    return null;
  }

  static Future<Holiday?> nextHolidayFrom(DateTime from) async {
    final current = await holidaysForYear(from.year);
    final nextYear = await holidaysForYear(from.year + 1);
    final all = [...current, ...nextYear]
      ..sort((a, b) => a.date.compareTo(b.date));
    final today = DateTime(from.year, from.month, from.day);
    for (final h in all) {
      final hd = DateTime(h.date.year, h.date.month, h.date.day);
      if (!hd.isBefore(today)) return h;
    }
    return null;
  }

  // One-time seeding from bundled asset if collection is empty
  static Future<void> seedFromAssetIfEmpty() async {
    final exists = await _col.limit(1).get();
    if (exists.docs.isNotEmpty) return; // already seeded

    final raw = await rootBundle.loadString('assets/holidays_at.json');
    final map = json.decode(raw) as Map<String, dynamic>;
    final batch = FirebaseFirestore.instance.batch();

    for (final entry in map.entries) {
      final year = int.parse(entry.key);
      final items = entry.value as List<dynamic>;
      for (final e in items) {
        final dateStr = e['date'] as String;
        final name = e['name'] as String;
        final company = (e['companyDayOff'] as bool?) ?? false;
        final date = DateTime.parse(dateStr);
        final docId =
            '${year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}-${name.replaceAll(' ', '_')}';
        final ref = _col.doc(docId);
        batch.set(ref, {
          'name': name,
          'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
          'companyDayOff': company,
          'year': year,
        });
      }
    }

    await batch.commit();

    // Clear cache so subsequent reads go to Firestore and cache fresh data
    _cache.clear();
  }

  // _assertAdmin removed during temporary open seeding
}
