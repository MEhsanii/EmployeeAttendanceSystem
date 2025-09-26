import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/intl.dart';

class HomeOfficeRequestPage extends StatefulWidget {
  const HomeOfficeRequestPage({super.key});

  @override
  State<HomeOfficeRequestPage> createState() => _HomeOfficeRequestPageState();
}

class _HomeOfficeRequestPageState extends State<HomeOfficeRequestPage> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  final Set<DateTime> _selectedDays = {};
  final _noteCtrl = TextEditingController();
  bool _submitting = false;
  DateTime _focusedDay = DateTime.now();
  final _fmt = DateFormat('yyyy-MM-dd');

  // Track existing requests by date and their status
  final Map<String, String> _existingRequests =
      {}; // dateId -> status (pending/approved/rejected)
  bool _loadingExistingRequests = true;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _noteCtrl.addListener(() => setState(() {})); // updates the counter text
    _loadExistingRequests();
  }

  Future<void> _loadExistingRequests() async {
    final user = _auth.currentUser;
    if (user == null) {
      setState(() => _loadingExistingRequests = false);
      return;
    }

    try {
      final snapshot = await _db
          .collection('users')
          .doc(user.uid)
          .collection('homeOfficeRequests')
          .get();

      _existingRequests.clear();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final requestedDates = List<String>.from(data['requestedDates'] ?? []);
        final statusByDate =
            Map<String, dynamic>.from(data['statusByDate'] ?? {});

        for (final dateId in requestedDates) {
          final status = statusByDate[dateId] ?? 'pending';
          _existingRequests[dateId] = status;
        }
      }
    } catch (e) {
      print('Error loading existing requests: $e');
    } finally {
      if (mounted) {
        setState(() => _loadingExistingRequests = false);
      }
    }
  }

  String? _getDateStatus(DateTime date) {
    final dateId = _fmt.format(date);
    return _existingRequests[dateId];
  }

  // ---- Helpers --------------------------------------------------------------

  bool _isSelectable(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final earliest = today.add(const Duration(days: 1)); // >= tomorrow
    final d = DateTime(day.year, day.month, day.day);

    // Check if date is in the future
    if (d.isBefore(earliest)) return false;

    // Check if date already has a request
    final status = _getDateStatus(d);
    return status == null; // Only selectable if no existing request
  }

  void _onDayTapped(DateTime day, DateTime focusedDay) {
    setState(() {
      _focusedDay = focusedDay;
      if (!_isSelectable(day)) return;
      final d = DateTime(day.year, day.month, day.day);
      if (_selectedDays.contains(d)) {
        _selectedDays.remove(d);
      } else {
        _selectedDays.add(d);
      }
    });
  }

  List<String> get _selectedDateIds =>
      _selectedDays.map((d) => _fmt.format(d)).toList()..sort();

  Future<void> _submit() async {
    if (_submitting || _selectedDays.isEmpty) return;
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _submitting = true);

    try {
      final requested = _selectedDateIds;
      final payload = {
        'userId': user.uid,
        'userEmail': user.email,
        'createdAt': FieldValue.serverTimestamp(),
        'requestedDates': requested,
        'statusByDate': {for (final d in requested) d: 'pending'},
        'note': _noteCtrl.text.trim(),
        // store review metadata per date after admin action
        'reviewsByDate': <String, dynamic>{},
      };

      final topRef = _db.collection('homeOfficeRequests').doc();
      final userRef = _db
          .collection('users')
          .doc(user.uid)
          .collection('homeOfficeRequests')
          .doc(topRef.id);

      await _db.runTransaction((tx) async {
        tx.set(topRef, payload);
        tx.set(userRef, payload);
      });

      if (!mounted) return;

      // (optional) keep or remove this SnackBar
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(content: Text('Request submitted. You’ll be notified once reviewed.')),
      // );

      // ✅ instead of Navigator.pop(context); do this:
      setState(() {
        _selectedDays.clear();
        _noteCtrl.clear();
      });

      // Refresh existing requests to show newly submitted ones
      await _loadExistingRequests();

      showModalBottomSheet(
        context: context,
        showDragHandle: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 36),
                const SizedBox(height: 8),
                const Text(
                  'Home Office request sent!',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'You’ll be notified once it’s reviewed.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context), // close sheet
                        child: const Text('Close'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context); // close sheet
                          // Optionally jump to "My Requests" page:
                          // Navigator.push(context, MaterialPageRoute(builder: (_) => const MyHomeOfficeRequestsPage()));
                        },
                        child: const Text('OK'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submission failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Same soft surfaces you used on Vacation
    const surfaceBg = Color(0xFFF3F6F3); // page background
    const cardGreen = Color(0xFFE8F5E9); // green-ish card bg
    const pillBorder = Color(0xFFB2DFDB); // light teal border

    // Give the calendar a predictable height so the rest fits
    final calHeight = MediaQuery.of(context).size.height * 0.42;
    final canSubmit = _selectedDays.isNotEmpty && !_submitting;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor == Colors.white
          ? surfaceBg
          : theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Home Office Request'), // ✅ correct title
        backgroundColor: Colors.green.shade700, // match Vacation
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loadingExistingRequests
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading existing requests...'),
                ],
              ),
            )
          : Column(
              children: [
                // Everything scrolls except the bottom button
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Guidance banner (same tone as Vacation)
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Select one or more days (min. 24 hours in advance).',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),

                        // Calendar with fixed height (prevents overflow)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: SizedBox(
                            height: calHeight,
                            child: TableCalendar(
                              firstDay: DateTime.now(),
                              lastDay:
                                  DateTime.now().add(const Duration(days: 365)),
                              focusedDay: _focusedDay,
                              calendarFormat: CalendarFormat.month,
                              headerStyle: HeaderStyle(
                                titleCentered: true,
                                titleTextStyle: theme.textTheme.titleMedium ??
                                    const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600),
                                formatButtonVisible: true,
                                leftChevronIcon: Icon(Icons.chevron_left,
                                    color: cs.onSurface.withOpacity(0.7)),
                                rightChevronIcon: Icon(Icons.chevron_right,
                                    color: cs.onSurface.withOpacity(0.7)),
                              ),
                              daysOfWeekStyle: DaysOfWeekStyle(
                                weekdayStyle: theme.textTheme.labelMedium ??
                                    const TextStyle(fontSize: 12),
                                weekendStyle: theme.textTheme.labelMedium ??
                                    const TextStyle(fontSize: 12),
                              ),
                              calendarStyle: CalendarStyle(
                                todayDecoration: BoxDecoration(
                                  color: cs.primary.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                selectedDecoration: BoxDecoration(
                                  color: cs.primary.withOpacity(0.35),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              selectedDayPredicate: (day) {
                                final d =
                                    DateTime(day.year, day.month, day.day);
                                return _selectedDays.contains(d);
                              },
                              onDaySelected: _onDayTapped,
                              calendarBuilders: CalendarBuilders(
                                defaultBuilder: (context, day, _) {
                                  final status = _getDateStatus(day);
                                  final allowed = _isSelectable(day);

                                  Color? backgroundColor;
                                  Color? textColor;

                                  if (status != null) {
                                    // Date has an existing request
                                    switch (status) {
                                      case 'approved':
                                        backgroundColor = Colors.green;
                                        textColor = Colors.white;
                                        break;
                                      case 'rejected':
                                        backgroundColor = Colors.red;
                                        textColor = Colors.white;
                                        break;
                                      case 'pending':
                                      default:
                                        backgroundColor = Colors.orange;
                                        textColor = Colors.white;
                                        break;
                                    }
                                  } else if (!allowed) {
                                    // Past dates or invalid dates
                                    textColor = cs.onSurface.withOpacity(0.35);
                                  } else {
                                    // Available dates
                                    textColor = cs.onSurface;
                                  }

                                  return Container(
                                    margin: const EdgeInsets.all(4),
                                    decoration: backgroundColor != null
                                        ? BoxDecoration(
                                            color: backgroundColor,
                                            shape: BoxShape.circle,
                                          )
                                        : null,
                                    child: Center(
                                      child: Text(
                                        '${day.day}',
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          color: textColor,
                                          fontWeight: backgroundColor != null
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                selectedBuilder: (context, day, _) {
                                  // Override selected builder to maintain status colors for selected days
                                  final status = _getDateStatus(day);
                                  if (status != null) {
                                    Color backgroundColor;
                                    switch (status) {
                                      case 'approved':
                                        backgroundColor = Colors.green.shade700;
                                        break;
                                      case 'rejected':
                                        backgroundColor = Colors.red.shade700;
                                        break;
                                      case 'pending':
                                      default:
                                        backgroundColor =
                                            Colors.orange.shade700;
                                        break;
                                    }

                                    return Container(
                                      margin: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: backgroundColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 2),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${day.day}',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    );
                                  } else {
                                    // Default selected style for new selections
                                    return Container(
                                      margin: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: cs.primary.withOpacity(0.35),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${day.day}',
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(
                                            color: cs.onSurface,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ),
                        ),

                        // Color Legend
                        if (!_loadingExistingRequests)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Color Legend:',
                                    style: theme.textTheme.titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 16,
                                              height: 16,
                                              decoration: const BoxDecoration(
                                                color: Colors.green,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            const Text('Approved',
                                                style: TextStyle(fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 16,
                                              height: 16,
                                              decoration: const BoxDecoration(
                                                color: Colors.orange,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            const Text('Pending',
                                                style: TextStyle(fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 16,
                                              height: 16,
                                              decoration: const BoxDecoration(
                                                color: Colors.red,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            const Text('Rejected',
                                                style: TextStyle(fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                        if (_selectedDays.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Wrap(
                              spacing: 8,
                              children: _selectedDateIds
                                  .map(
                                    (d) => Chip(
                                      label: Text(d,
                                          style: theme.textTheme.labelLarge),
                                      shape: StadiumBorder(
                                          side: BorderSide(
                                              color:
                                                  pillBorder.withOpacity(0.7))),
                                      backgroundColor: Colors.white,
                                    ),
                                  )
                                  .toList(),
                            ),
                          ),

                        // Optional Note (same look as Vacation)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Text('Optional Note',
                              style: theme.textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: TextField(
                            controller: _noteCtrl,
                            maxLength: 300,
                            minLines: 2,
                            maxLines: 4,
                            style: theme.textTheme.bodyMedium,
                            decoration: InputDecoration(
                              hintText: 'Reason, location, etc.',
                              hintStyle: theme.textTheme.bodyMedium
                                  ?.copyWith(color: Colors.black45),
                              filled: true,
                              fillColor: Colors.white,
                              counterText: '',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: pillBorder.withOpacity(0.8)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(color: cs.primary),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 16, right: 16),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '${_noteCtrl.text.length}/300',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: Colors.black45),
                            ),
                          ),
                        ),

                        // Monthly Summary (same green card vibe)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: _MonthlySummaryCard(
                            userId: _auth.currentUser?.uid,
                            bg: cardGreen,
                            pillBorder: pillBorder,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Submit button pinned at the bottom
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton.icon(
                      onPressed: canSubmit ? _submit : null,
                      icon: const Icon(Icons.send),
                      label:
                          Text(_submitting ? 'Submitting…' : 'Submit Request'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _MonthlySummaryCard extends StatelessWidget {
  final String? userId;
  final Color bg;
  final Color pillBorder;
  const _MonthlySummaryCard({
    required this.userId,
    required this.bg,
    required this.pillBorder,
  });

  bool _isInCurrentMonth(String ymd) {
    if (ymd.length < 7) return false;
    final now = DateTime.now();
    final prefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    return ymd.startsWith(prefix);
  }

  @override
  Widget build(BuildContext context) {
    if (userId == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    final stream = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('homeOfficeRequests')
        .orderBy('createdAt', descending: true)
        .limit(150) // a little headroom
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        int pending = 0, approved = 0, rejected = 0;

        // NEW: collect the date strings per status (this month only)
        final List<String> requestedDays = [];
        final List<String> approvedDays = [];
        final List<String> rejectedDays = [];

        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final requested =
                List<String>.from(data['requestedDates'] ?? const []);
            final status =
                Map<String, dynamic>.from(data['statusByDate'] ?? const {});
            for (final d in requested) {
              if (!_isInCurrentMonth(d)) continue;
              requestedDays.add(d);

              final s = (status[d] ?? 'pending') as String;
              if (s == 'approved') {
                approved++;
                approvedDays.add(d);
              } else if (s == 'rejected') {
                rejected++;
                rejectedDays.add(d);
              } else {
                pending++;
              }
            }
          }
        }

        final totalRequested = pending + approved + rejected;

        // small helper to render a titled chip list
        Widget chipGroup(String title, List<String> days,
            {IconData? icon, Color? iconColor}) {
          if (days.isEmpty) return const SizedBox.shrink();
          days.sort(); // nice order
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null)
                      Icon(icon, size: 16, color: iconColor ?? Colors.black54),
                    if (icon != null) const SizedBox(width: 6),
                    Text(title,
                        style: theme.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: days
                      .map((d) => Chip(
                            label: Text(d),
                            backgroundColor: Colors.white,
                            shape: StadiumBorder(
                              side: BorderSide(color: pillBorder),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Home Office (This Month)',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatPill(
                      label: 'Requested',
                      value: totalRequested.toString(),
                      pillBorder: pillBorder),
                  const SizedBox(width: 10),
                  _StatPill(
                      label: 'Approved',
                      value: approved.toString(),
                      pillBorder: pillBorder),
                  const SizedBox(width: 10),
                  _StatPill(
                      label: 'Rejected',
                      value: rejected.toString(),
                      pillBorder: pillBorder),
                ],
              ),

              // NEW: show the actual days below the stats
              chipGroup('Requested Days', requestedDays,
                  icon: Icons.event_note, iconColor: Colors.black54),
              chipGroup('Approved Days', approvedDays,
                  icon: Icons.check_circle, iconColor: Colors.green),
              chipGroup('Rejected Days', rejectedDays,
                  icon: Icons.cancel, iconColor: Colors.red),
            ],
          ),
        );
      },
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final Color pillBorder;
  const _StatPill(
      {required this.label, required this.value, required this.pillBorder});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: pillBorder),
        ),
        child: Column(
          children: [
            Text(value,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
