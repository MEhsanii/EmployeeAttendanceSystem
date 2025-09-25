import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// =========================
// History Screen
// =========================
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // ---- OLD model you used (kept) ----
  List<Map<String, dynamic>> attendanceLogs = [];
  List<Map<String, dynamic>> vacationRequests = [];
  bool isLoading = true;

  // ---- Month picker (kept list, feel free to expand) ----
  String selectedMonth = 'All Records';
  final List<String> months = const [
    'All Records',
    'January 2025',
    'February 2025',
    'March 2025',
    'April 2025',
    'May 2025',
    'June 2025',
    'July 2025',
    'August 2025',
    'September 2025',
    'October 2025',
    'November 2025',
    'December 2025',
  ];

  // ---- NEW: derived objects used by the new UI ----
  List<_DayEntry> _days = [];
  _MonthSummary _summary = _MonthSummary.zero();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final currentMonthName = DateFormat('MMMM yyyy').format(now);
    if (months.contains(currentMonthName)) {
      selectedMonth = currentMonthName;
      fetchFilteredRecords(currentMonthName); // <- old fetch, kept
    } else {
      fetchAttendanceHistory(); // <- old fetch, kept
    }
  }

  // =========================
  // FETCHING (YOUR OLD LOGIC)
  // =========================

  Future<void> fetchAttendanceHistory() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final uid = user.uid;

      // Attendance
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('attendance')
          .orderBy('createdAt', descending: true)
          .limit(150)
          .get();

      // Vacations
      final vacationSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('vacationRequests')
          .orderBy('createdAt', descending: true)
          .get();

      final fetchedAttendance = snapshot.docs.map((doc) {
        return {'date': doc.id, 'data': doc.data()};
      }).toList();

      final fetchedVacations = vacationSnapshot.docs
          .map((doc) => {'id': doc.id, 'data': doc.data()})
          .toList();

      attendanceLogs = fetchedAttendance;
      vacationRequests = fetchedVacations;

      // NEW: build day entries + summary from fetchedAttendance (ALL RECORDS)
      _rebuildDaysAndSummary(attendanceLogs, monthFilter: null);

      setState(() => isLoading = false);
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> fetchFilteredRecords(String monthName) async {
    try {
      setState(() => isLoading = true);

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final uid = user.uid;

      // Pull everything once (as you had), then filter by doc.id month.
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('attendance')
          .get();

      final all = snapshot.docs
          .map((doc) => {'date': doc.id, 'data': doc.data()})
          .toList();

      // NEW: build day entries + summary using a month filter
      _rebuildDaysAndSummary(all,
          monthFilter: DateFormat('MMMM yyyy').parse(monthName));

      setState(() => isLoading = false);
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  // =========================
  // BUILD DERIVED DATA
  // =========================

  /// Converts raw attendance maps to [_DayEntry]s and computes [_MonthSummary].
  /// If [monthFilter] is null, we include *all* records (for "All Records").
  void _rebuildDaysAndSummary(List<Map<String, dynamic>> raw,
      {DateTime? monthFilter}) {
    final entries = <_DayEntry>[];

    for (final m in raw) {
      final id = m['date'] as String;
      final data = (m['data'] as Map<String, dynamic>?) ?? {};
      final dt = DateTime.tryParse(id);
      if (dt == null) continue;

      // Filter by month if provided
      if (monthFilter != null) {
        if (dt.year != monthFilter.year || dt.month != monthFilter.month) {
          continue;
        }
      }

      final startWork = data['startWork'] as Timestamp?;
      final endWork = data['endWork'] as Timestamp?;
      final startBreak = data['startBreak'] as Timestamp?;
      final endBreak = data['endBreak'] as Timestamp?;
      final workMode = data['workMode'] as String?;
      final isHoliday = data['isHoliday'] == true;
      final holidayName = data['holidayName'] as String?;

      final work = _calcDuration(
          startWork, endWork); // gross work (as per your old screen)
      final brk = _calcDuration(startBreak, endBreak);

      entries.add(
        _DayEntry(
          date: dt,
          workMode: workMode,
          isHoliday: isHoliday,
          holidayName: holidayName,
          startWork: startWork,
          endWork: endWork,
          startBreak: startBreak,
          endBreak: endBreak,
          workDuration: work,
          breakDuration: brk,
        ),
      );
    }

    // Sort newest first
    entries.sort((a, b) => b.date.compareTo(a.date));

    // Compute summary
    final summary = _summarize(entries);

    setState(() {
      _days = entries;
      _summary = summary;
    });
  }

  // =========================
  // HELPERS (time, format)
  // =========================

  Duration? _calcDuration(Timestamp? a, Timestamp? b) {
    if (a == null || b == null) return null;
    final diff = b.toDate().difference(a.toDate());
    if (diff.isNegative) return null;
    return diff;
  }

  String _fmtHMM(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return '${h}h ${m}m';
    // If you like 0h -> 0h 0m, keep as-is; otherwise conditionally hide zeros
  }

  String _fmtTime(Timestamp? ts) {
    if (ts == null) return '--:--';
    final dt = ts.toDate();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _fmtDate(DateTime d) => DateFormat('EEE, d MMM yyyy').format(d);

  // =========================
  // SUMMARY LOGIC
  // =========================

  _MonthSummary _summarize(List<_DayEntry> days) {
    var totalWork = Duration.zero;
    var totalBreak = Duration.zero;
    int workingDays = 0;
    int office = 0;
    int home = 0;
    int sick = 0;
    int holidays = 0;

    for (final d in days) {
      if (d.isHoliday) {
        holidays++;
        continue;
      }

      // Count work modes
      if (d.workMode == 'Sick') sick++;
      if (d.workMode == 'Office') office++;
      if (d.workMode == 'Home Office') home++;

      // Summations
      if (d.workDuration != null) {
        totalWork += d.workDuration!;
        workingDays++; // treat a day with recorded work as a working day
      }
      if (d.breakDuration != null) totalBreak += d.breakDuration!;
    }

    final avg = (workingDays > 0)
        ? Duration(minutes: (totalWork.inMinutes / workingDays).round())
        : Duration.zero;

    return _MonthSummary(
      totalWork: totalWork,
      totalBreak: totalBreak,
      averagePerDay: avg,
      workingDays: workingDays,
      officeDays: office,
      homeOfficeDays: home,
      sickDays: sick,
      holidayDays: holidays,
    );
  }

  // =========================
  // UI
  // =========================

  @override
  Widget build(BuildContext context) {
    const appGreen = Color(0xFF2E7D32);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6F3),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(112),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2E7D32), Color(0xFF388E3C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 12,
            left: 8,
            right: 16,
            bottom: 14,
          ),
          child: Row(
            children: [
              IconButton(
                icon:
                    const Icon(Icons.arrow_back, color: Colors.white, size: 26),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Attendance History',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              // Month dropdown
              _MonthDropdown(
                value: selectedMonth,
                items: months,
                onChanged: (val) {
                  setState(() => selectedMonth = val);
                  if (val == 'All Records') {
                    fetchAttendanceHistory();
                  } else {
                    fetchFilteredRecords(val);
                  }
                },
              ),
            ],
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => selectedMonth == 'All Records'
                  ? fetchAttendanceHistory()
                  : fetchFilteredRecords(selectedMonth),
              child: ListView(
                children: [
                  const SizedBox(height: 14),
                  _summaryCard(appGreen),
                  const SizedBox(height: 12),
                  _dailyEntriesSection(appGreen),
                  const SizedBox(height: 28),
                ],
              ),
            ),
    );
  }

  // ---- Summary card ----
  Widget _summaryCard(Color appGreen) {
    final monthTitle = selectedMonth == 'All Records'
        ? 'All Records'
        : selectedMonth; // e.g., "August 2025"

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: appGreen,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 6))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Monthly Summary',
              style: TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            monthTitle,
            style: const TextStyle(
                color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _pill(appGreen, Icons.access_time, 'Total Work',
                  _fmtHMM(_summary.totalWork),
                  filled: true),
              //_pill(appGreen, Icons.free_breakfast, 'Total Break',
              //_fmtHMM(_summary.totalBreak)),
              _pill(appGreen, Icons.event, 'Working Days',
                  '${_summary.workingDays}'),
              _pill(appGreen, Icons.av_timer, 'Avg / Day',
                  _fmtHMM(_summary.averagePerDay)),
              _pill(appGreen, Icons.apartment, 'Office',
                  '${_summary.officeDays}'),
              _pill(appGreen, Icons.home_work, 'Home Office',
                  '${_summary.homeOfficeDays}'),
              _pill(appGreen, Icons.add_box, 'Sick', '${_summary.sickDays}'),
              _pill(appGreen, Icons.beach_access, 'Holidays',
                  '${_summary.holidayDays}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(Color appGreen, IconData icon, String label, String value,
      {bool filled = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: filled
            ? Colors.white.withOpacity(0.12)
            : Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white)),
          const SizedBox(width: 8),
          Text(value,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  // ---- Daily entries ----
  Widget _dailyEntriesSection(Color appGreen) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))
        ],
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        childrenPadding: EdgeInsets.zero,
        iconColor: appGreen,
        collapsedIconColor: Colors.grey,
        title: const Text('Daily entries',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        subtitle: Text('${_days.length} day(s)',
            style: const TextStyle(color: Colors.black54)),
        children: _days.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.fromLTRB(18, 0, 18, 16),
                  child: Text('No entries for this period.',
                      style: TextStyle(color: Colors.black54)),
                )
              ]
            : _days.map(_dayTile).toList(),
      ),
    );
  }

  // ---- Day tile (your last version with Sick/Holiday support) ----
  Widget _dayTile(_DayEntry d) {
    const appGreen = Color(0xFF2E7D32);
    final isPast = d.date.isBefore(DateTime.now());

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date + badges
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: appGreen),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _fmtDate(d.date),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: appGreen,
                    ),
                  ),
                ),
                if (d.isHoliday)
                  _chip(
                      text: d.holidayName ?? "Holiday",
                      icon: Icons.beach_access),
                if (!d.isHoliday && d.workMode != null) ...[
                  const SizedBox(width: 6),
                  _chip(
                    text: d.workMode!,
                    icon: d.workMode == 'Home Office'
                        ? Icons.home_work
                        : Icons.apartment,
                  ),
                ],
                if (d.workMode == 'Sick') ...[
                  const SizedBox(width: 6),
                  _chip(text: 'Sick', icon: Icons.add_box),
                ],
              ],
            ),
            const SizedBox(height: 10),

            if (!d.isHoliday) ...[
              _row("Start Work", Icons.login, _fmtTime(d.startWork)),
              _row("Start Break", Icons.coffee, _fmtTime(d.startBreak)),
              _row("End Break", Icons.coffee_outlined, _fmtTime(d.endBreak)),
              _row("End Work", Icons.logout, _fmtTime(d.endWork)),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    "Total Work: ${d.workDuration == null ? '--:--' : _fmtHMM(d.workDuration!)}"
                    "${d.breakDuration != null ? "  •  Break: ${_fmtHMM(d.breakDuration!)}" : ""}",
                    style: TextStyle(
                      color: Colors.black87.withOpacity(isPast ? 0.9 : 1),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ] else
              const Text("No attendance — public holiday",
                  style: TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, IconData icon, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Icon(icon, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 14)),
          ]),
          Text(value,
              style: const TextStyle(fontSize: 14, color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _chip({required String text, required IconData icon}) {
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

// =========================
// MODELS
// =========================

class _DayEntry {
  final DateTime date;
  final String? workMode; // 'Office', 'Home Office', 'Sick', etc.
  final bool isHoliday;
  final String? holidayName;

  final Timestamp? startWork;
  final Timestamp? endWork;
  final Timestamp? startBreak;
  final Timestamp? endBreak;

  final Duration? workDuration; // endWork - startWork
  final Duration? breakDuration; // endBreak - startBreak

  _DayEntry({
    required this.date,
    required this.workMode,
    required this.isHoliday,
    required this.holidayName,
    required this.startWork,
    required this.endWork,
    required this.startBreak,
    required this.endBreak,
    required this.workDuration,
    required this.breakDuration,
  });
}

class _MonthSummary {
  final Duration totalWork;
  final Duration totalBreak;
  final Duration averagePerDay;
  final int workingDays;
  final int officeDays;
  final int homeOfficeDays;
  final int sickDays;
  final int holidayDays;

  const _MonthSummary({
    required this.totalWork,
    required this.totalBreak,
    required this.averagePerDay,
    required this.workingDays,
    required this.officeDays,
    required this.homeOfficeDays,
    required this.sickDays,
    required this.holidayDays,
  });

  factory _MonthSummary.zero() => const _MonthSummary(
        totalWork: Duration.zero,
        totalBreak: Duration.zero,
        averagePerDay: Duration.zero,
        workingDays: 0,
        officeDays: 0,
        homeOfficeDays: 0,
        sickDays: 0,
        holidayDays: 0,
      );
}

// =========================
// Month Dropdown (top right)
// =========================
class _MonthDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const _MonthDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Select month',
      initialValue: value,
      onSelected: onChanged,
      offset: const Offset(0, 40),
      itemBuilder: (context) => items
          .map((m) => PopupMenuItem<String>(value: m, child: Text(m)))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.keyboard_arrow_down, color: Colors.white),
            const SizedBox(width: 6),
            Text(value,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
