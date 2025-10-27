import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:attendence_management_system/utils/responsive_utils.dart';

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
      fetchFilteredRecords(currentMonthName);
    } else {
      fetchAttendanceHistory();
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
      final workMode = data['workMode'] as String?;
      final isHoliday = data['isHoliday'] == true;
      final holidayName = data['holidayName'] as String?;

      // NEW: Parse breaks array
      final breaks = <_BreakEntry>[];
      if (data['breaks'] != null) {
        final breaksList = data['breaks'] as List;
        for (final breakData in breaksList) {
          final breakMap = breakData as Map<String, dynamic>;
          breaks.add(_BreakEntry(
            startTime: breakMap['startTime'] as Timestamp?,
            endTime: breakMap['endTime'] as Timestamp?,
            description: breakMap['description'] as String? ?? 'Break',
          ));
        }
      }

      final work = _calcDuration(startWork, endWork);

      // Calculate total break duration from all breaks
      Duration totalBreakDuration = Duration.zero;
      for (final brk in breaks) {
        final brkDuration = _calcDuration(brk.startTime, brk.endTime);
        if (brkDuration != null) {
          totalBreakDuration += brkDuration;
        }
      }

      entries.add(
        _DayEntry(
          date: dt,
          workMode: workMode,
          isHoliday: isHoliday,
          holidayName: holidayName,
          startWork: startWork,
          endWork: endWork,
          breaks: breaks,
          workDuration: work,
          breakDuration: totalBreakDuration,
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
        workingDays++;
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
        preferredSize: Size.fromHeight(context.h(14)),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF2E7D32), Color(0xFF388E3C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + context.h(1.5),
            left: context.w(2),
            right: context.w(4),
            bottom: context.h(1.8),
          ),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back,
                    color: Colors.white, size: context.sp(26)),
                onPressed: () => Navigator.of(context).pop(),
              ),
              SizedBox(width: context.w(2.5)),
              Expanded(
                child: Text(
                  'Attendance History',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: context.sp(20),
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
            SizedBox(height: context.h(1.8)),
            _summaryCard(appGreen),
            SizedBox(height: context.h(1.5)),
            _dailyEntriesSection(appGreen),
            SizedBox(height: context.h(3.5)),
          ],
        ),
      ),
    );
  }

  // ---- Summary card ----
  Widget _summaryCard(Color appGreen) {
    final monthTitle = selectedMonth == 'All Records'
        ? 'All Records'
        : selectedMonth;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: context.w(4)),
      padding: EdgeInsets.fromLTRB(
          context.w(4), context.h(2), context.w(4), context.h(2.3)),
      decoration: BoxDecoration(
        color: appGreen,
        borderRadius: BorderRadius.circular(context.w(5.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black26,
              blurRadius: context.w(2.5),
              offset: Offset(0, context.h(0.75)))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monthly Summary',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: context.sp(14),
                  fontWeight: FontWeight.w700)),
          SizedBox(height: context.h(0.75)),
          Text(
            monthTitle,
            style: TextStyle(
                color: Colors.white,
                fontSize: context.sp(22),
                fontWeight: FontWeight.w900),
          ),
          SizedBox(height: context.h(1.8)),
          Wrap(
            spacing: context.w(3),
            runSpacing: context.w(3),
            children: [
              _pill(appGreen, Icons.access_time, 'Total Work',
                  _fmtHMM(_summary.totalWork),
                  filled: true),
              _pill(appGreen, Icons.free_breakfast, 'Total Break',
                  _fmtHMM(_summary.totalBreak)),
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
      padding: EdgeInsets.symmetric(
          horizontal: context.w(3.5), vertical: context.h(1.25)),
      decoration: BoxDecoration(
        color: filled
            ? Colors.white.withOpacity(0.12)
            : Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(context.w(3.5)),
        border: Border.all(color: Colors.white.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: context.sp(18), color: Colors.white),
          SizedBox(width: context.w(2)),
          Text(label,
              style: TextStyle(color: Colors.white, fontSize: context.sp(14))),
          SizedBox(width: context.w(2)),
          Text(value,
              style: TextStyle(
                  color: Colors.white,
                  fontSize: context.sp(14),
                  fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }

  // ---- Daily entries ----
  Widget _dailyEntriesSection(Color appGreen) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: context.w(4)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(context.w(4.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black12,
              blurRadius: context.w(2),
              offset: Offset(0, context.h(0.5)))
        ],
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: EdgeInsets.fromLTRB(
            context.w(4), context.h(1), context.w(4), context.h(1)),
        childrenPadding: EdgeInsets.zero,
        iconColor: appGreen,
        collapsedIconColor: Colors.grey,
        title: Text('Daily entries',
            style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: context.sp(18))),
        subtitle: Text('${_days.length} day(s)',
            style: TextStyle(color: Colors.black54, fontSize: context.sp(14))),
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

  // ---- Day tile (updated with multiple breaks support) ----
  Widget _dayTile(_DayEntry d) {
    const appGreen = Color(0xFF2E7D32);
    final isPast = d.date.isBefore(DateTime.now());

    return Container(
      margin: EdgeInsets.fromLTRB(
          context.w(4), context.h(0.75), context.w(4), context.h(1.5)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(context.w(3.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black12,
              blurRadius: context.w(1.5),
              offset: Offset(0, context.h(0.4)))
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            context.w(3.5), context.h(1.5), context.w(3.5), context.h(1.5)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date + badges
            Row(
              children: [
                Icon(Icons.calendar_today,
                    size: context.sp(16), color: appGreen),
                SizedBox(width: context.w(1.5)),
                Expanded(
                  child: Text(
                    _fmtDate(d.date),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: context.sp(14),
                      color: appGreen,
                    ),
                  ),
                ),
                if (d.isHoliday)
                  _chip(
                      text: d.holidayName ?? "Holiday",
                      icon: Icons.beach_access),
                if (!d.isHoliday &&
                    d.workMode != null &&
                    d.workMode != "Sick") ...[
                  SizedBox(width: context.w(1.5)),
                  _chip(
                    text: d.workMode!,
                    icon: d.workMode == 'Home Office'
                        ? Icons.home_work
                        : Icons.apartment,
                  ),
                ],
                if (d.workMode == 'Sick') ...[
                  SizedBox(width: context.w(1.5)),
                  _chip(
                      text: 'Sick',
                      icon: Icons.add_box,
                      iconColor: Colors.amber),
                ],
              ],
            ),
            SizedBox(height: context.h(1.25)),

            if (!d.isHoliday) ...[
              _row("Start Work", Icons.login, _fmtTime(d.startWork)),

              // Display multiple breaks
              if (d.breaks.isNotEmpty) ...[
                SizedBox(height: context.h(0.75)),
                Container(
                  padding: EdgeInsets.all(context.w(2.5)),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(context.w(2)),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.free_breakfast,
                              size: context.sp(16), color: Colors.orange.shade700),
                          SizedBox(width: context.w(1.5)),
                          Text(
                            'Breaks (${d.breaks.length})',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: context.sp(13),
                              color: Colors.orange.shade900,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: context.h(0.75)),
                      ...d.breaks.map((brk) => Padding(
                        padding: EdgeInsets.symmetric(vertical: context.h(0.25)),
                        child: Row(
                          children: [
                            Container(
                              width: context.w(1),
                              height: context.h(2),
                              decoration: BoxDecoration(
                                color: brk.endTime != null
                                    ? Colors.green.shade400
                                    : Colors.orange.shade400,
                                borderRadius: BorderRadius.circular(context.w(0.5)),
                              ),
                            ),
                            SizedBox(width: context.w(2)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    brk.description,
                                    style: TextStyle(
                                      fontSize: context.sp(12),
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  SizedBox(height: context.h(0.25)),
                                  Text(
                                    '${_fmtTime(brk.startTime)} - ${_fmtTime(brk.endTime)}',
                                    style: TextStyle(
                                      fontSize: context.sp(11),
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (brk.endTime != null && brk.startTime != null)
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: context.w(1.5),
                                  vertical: context.h(0.3),
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(context.w(1.5)),
                                ),
                                child: Text(
                                  _fmtHMM(_calcDuration(brk.startTime, brk.endTime)!),
                                  style: TextStyle(
                                    fontSize: context.sp(10),
                                    fontWeight: FontWeight.w700,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      )).toList(),
                    ],
                  ),
                ),
                SizedBox(height: context.h(0.75)),
              ],

              _row("End Work", Icons.logout, _fmtTime(d.endWork)),
              SizedBox(height: context.h(1)),
              Row(
                children: [
                  Icon(Icons.access_time,
                      size: context.sp(16), color: Colors.grey),
                  SizedBox(width: context.w(1.5)),
                  Expanded(
                    child: Text(
                      "Total Work: ${d.workDuration == null ? '--:--' : _fmtHMM(d.workDuration!)}"
                          "${d.breakDuration != null && d.breakDuration! > Duration.zero ? "  •  Break: ${_fmtHMM(d.breakDuration!)}" : ""}",
                      style: TextStyle(
                        color: Colors.black87.withOpacity(isPast ? 0.9 : 1),
                        fontWeight: FontWeight.w600,
                        fontSize: context.sp(14),
                      ),
                    ),
                  ),
                ],
              ),
            ] else
              Text("No attendance — public holiday",
                  style: TextStyle(
                      color: Colors.black54, fontSize: context.sp(14))),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, IconData icon, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: context.h(0.25)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(children: [
            Icon(icon, size: context.sp(18), color: Colors.grey.shade600),
            SizedBox(width: context.w(1.5)),
            Text(label, style: TextStyle(fontSize: context.sp(14))),
          ]),
          Text(value,
              style:
              TextStyle(fontSize: context.sp(14), color: Colors.black54)),
        ],
      ),
    );
  }

  Widget _chip({
    required String text,
    required IconData icon,
    Color? iconColor,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: context.w(2), vertical: context.h(0.5)),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32).withOpacity(0.08),
        borderRadius: BorderRadius.circular(context.w(5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon,
            size: context.sp(14), color: iconColor ?? const Color(0xFF2E7D32)),
        SizedBox(width: context.w(1)),
        Text(text,
            style: TextStyle(
                fontSize: context.sp(12),
                color: iconColor ?? const Color(0xFF2E7D32))),
      ]),
    );
  }
}

// =========================
// MODELS
// =========================

class _BreakEntry {
  final Timestamp? startTime;
  final Timestamp? endTime;
  final String description;

  _BreakEntry({
    required this.startTime,
    required this.endTime,
    required this.description,
  });
}

class _DayEntry {
  final DateTime date;
  final String? workMode;
  final bool isHoliday;
  final String? holidayName;

  final Timestamp? startWork;
  final Timestamp? endWork;
  final List<_BreakEntry> breaks; // NEW: List of breaks instead of single break

  final Duration? workDuration;
  final Duration? breakDuration; // Total break duration

  _DayEntry({
    required this.date,
    required this.workMode,
    required this.isHoliday,
    required this.holidayName,
    required this.startWork,
    required this.endWork,
    required this.breaks,
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
      offset: Offset(0, context.h(5)),
      itemBuilder: (context) => items
          .map((m) => PopupMenuItem<String>(value: m, child: Text(m)))
          .toList(),
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: context.w(3), vertical: context.h(1)),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.15),
          borderRadius: BorderRadius.circular(context.w(2.5)),
          border: Border.all(color: Colors.white.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.keyboard_arrow_down,
                color: Colors.white, size: context.sp(24)),
            SizedBox(width: context.w(1.5)),
            Text(value,
                style: TextStyle(
                    color: Colors.white,
                    fontSize: context.sp(14),
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}