import 'package:flutter/material.dart';
import '../services/holiday_service.dart';

class HolidaysScreen extends StatefulWidget {
  const HolidaysScreen({super.key});

  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = DateTime.now().year;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F3),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            const SizedBox(width: 8),
            const Text("Public Holidays "),
            const SizedBox(width: 6),
            _YearPickerChip(
              year: _year,
              onChange: (y) => setState(() => _year = y),
            ),
          ],
        ),
        // actions: [
        //   // Debug-only seeding trigger
        //   if (!bool.fromEnvironment('dart.vm.product'))
        //     IconButton(
        //       icon: const Icon(Icons.cloud_upload, color: Colors.white),
        //       tooltip: 'Seed holidays from asset',
        //       onPressed: () async {
        //         ScaffoldMessenger.of(context).showSnackBar(
        //           const SnackBar(content: Text('Seeding holidays...')),
        //         );
        //         try {
        //           await HolidayService.seedFromAssetIfEmpty();
        //           setState(() {});
        //           ScaffoldMessenger.of(context).showSnackBar(
        //             const SnackBar(content: Text('Holidays seeded.')),
        //           );
        //         } catch (e) {
        //           ScaffoldMessenger.of(context).showSnackBar(
        //             SnackBar(content: Text('Seed failed: $e')),
        //           );
        //         }
        //       },
        //     ),
        // ],
      ),
      body: FutureBuilder<List<Holiday>>(
        future: HolidayService.holidaysForYear(_year),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          if (all.isEmpty) {
            return const Center(
                child: Text('No holidays found for this year.'));
          }

          // Group by month
          final byMonth = <int, List<Holiday>>{};
          for (final h in all) {
            byMonth.putIfAbsent(h.date.month, () => []).add(h);
          }

          // Build flat list of sections + items
          final items = <_RowItem>[];
          items.add(_RowItem.nextCard); // index 0 -> next holiday card

          for (var m = 1; m <= 12; m++) {
            final list = byMonth[m] ?? const <Holiday>[];
            if (list.isEmpty) continue;
            items.add(_RowItem.header(month: m)); // month header
            for (final h in list) {
              items.add(_RowItem.entry(h));
            }
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final item = items[index];

              // 1) Next holiday card
              if (item.type == _RowType.next) {
                return FutureBuilder<Holiday?>(
                  future: HolidayService.nextHolidayFrom(
                    DateTime(_year == now.year ? now.year : _year, now.month,
                        now.day),
                  ),
                  builder: (context, snap) {
                    if (!snap.hasData) return const SizedBox.shrink();
                    final h = snap.data!;
                    final from = DateTime(now.year, now.month, now.day);
                    final target =
                        DateTime(h.date.year, h.date.month, h.date.day);
                    final days = target.difference(from).inDays;

                    return Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2E7D32), Color(0xFF388E3C)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                              color: Colors.black26,
                              blurRadius: 8,
                              offset: Offset(0, 4)),
                        ],
                      ),
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.event_available,
                              color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Next holiday",
                                    style: TextStyle(color: Colors.white70)),
                                const SizedBox(height: 4),
                                Text(
                                  h.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "${_weekday(h.date.weekday)}, ${_month(h.date.month)} ${h.date.day}"
                                  " • ${days <= 0 ? "Today" : days == 1 ? "In 1 day" : "In $days days"}",
                                  style: const TextStyle(
                                      color: Colors.white, height: 1.3),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              }

              // 2) Month header
              if (item.type == _RowType.header) {
                return Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4, left: 2),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          "${_month(item.month!)} $_year",
                          style: const TextStyle(
                            color: Color(0xFF1B5E20),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const Expanded(
                          child: Divider(
                              thickness: 0.6,
                              indent: 12,
                              color: Color(0xFFBDBDBD))),
                    ],
                  ),
                );
              }

              // 3) Holiday tile
              final h = item.holiday!;
              final isPast = DateTime(h.date.year, h.date.month, h.date.day)
                  .isBefore(DateTime(now.year, now.month, now.day));
              final isWeekend = h.date.weekday == DateTime.saturday ||
                  h.date.weekday == DateTime.sunday;

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(
                        color: Colors.black12,
                        blurRadius: 6,
                        offset: Offset(0, 3))
                  ],
                ),
                child: ListTile(
                  leading: _DateBadge(date: h.date),
                  title: Text(
                    h.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Colors.black87.withOpacity(isPast ? 0.6 : 1.0),
                    ),
                  ),
                  subtitle: Text(
                    "${_weekday(h.date.weekday)}, ${_monthShort(h.date.month)} ${h.date.day}",
                    style: TextStyle(
                      color: Colors.black54.withOpacity(isPast ? 0.7 : 0.9),
                    ),
                  ),
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      if (h.companyDayOff)
                        const _Chip(text: "Company", icon: Icons.work_outline),
                      if (isWeekend)
                        const _Chip(text: "Weekend", icon: Icons.weekend),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ----- helpers / small widgets -----

  static String _month(int m) => const [
        "January",
        "February",
        "March",
        "April",
        "May",
        "June",
        "July",
        "August",
        "September",
        "October",
        "November",
        "December"
      ][m - 1];

  static String _monthShort(int m) => const [
        "Jan",
        "Feb",
        "Mar",
        "Apr",
        "May",
        "Jun",
        "Jul",
        "Aug",
        "Sep",
        "Oct",
        "Nov",
        "Dec"
      ][m - 1];

  static String _weekday(int w) => const [
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
        "Sunday"
      ][w - 1];
}

enum _RowType { next, header, entry }

class _RowItem {
  final _RowType type;
  final int? month;
  final Holiday? holiday;

  const _RowItem._(this.type, {this.month, this.holiday});
  static const nextCard = _RowItem._(_RowType.next);
  static _RowItem header({required int month}) =>
      _RowItem._(_RowType.header, month: month);
  static _RowItem entry(Holiday h) => _RowItem._(_RowType.entry, holiday: h);
}

class _DateBadge extends StatelessWidget {
  final DateTime date;
  const _DateBadge({required this.date});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFFE8F5E9), Color(0xFFDDEFD9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              date.day.toString().padLeft(2, '0'),
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: Color(0xFF2E7D32),
              ),
            ),
            Text(
              _HolidaysScreenState._monthShort(date.month),
              style: const TextStyle(fontSize: 11, color: Color(0xFF2E7D32)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final IconData icon;
  const _Chip({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32).withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: const Color(0xFF2E7D32)),
        const SizedBox(width: 4),
        Text(text,
            style: const TextStyle(fontSize: 12, color: Color(0xFF2E7D32))),
      ]),
    );
  }
}

class _YearPickerChip extends StatelessWidget {
  final int year;
  final ValueChanged<int> onChange;
  const _YearPickerChip({required this.year, required this.onChange});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().year;
    final choices = [now - 1, now, now + 1]; // simple range; extend if needed

    return PopupMenuButton<int>(
      initialValue: year,
      onSelected: onChange,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => [
        for (final y in choices)
          PopupMenuItem<int>(
            value: y,
            child: Text(
              y.toString(),
              style: TextStyle(
                fontWeight: y == year ? FontWeight.w800 : FontWeight.w500,
                color: const Color(0xFF1B5E20),
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(year.toString(),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            const Icon(Icons.expand_more, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
