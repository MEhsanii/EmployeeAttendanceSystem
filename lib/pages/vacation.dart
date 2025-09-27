// ignore_for_file: unused_local_variable, unused_element, unused_field

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart'; // <-- New import
import '../services/holiday_service.dart'; // <-- add this

Color _statusColor(String status) {
  switch (status) {
    case 'Approved':
      return Colors.green;
    case 'In Review':
    case 'Pending':
      return Colors.orange;
    case 'Rejected':
      return Colors.red;
    default:
      return Colors.grey;
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class VacationScreen extends StatefulWidget {
  const VacationScreen({super.key});

  @override
  State<VacationScreen> createState() => _VacationScreenState();
}

class _VacationScreenState extends State<VacationScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _noteController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isSubmitting = false;
  bool _isCEO = false;

  @override
  void initState() {
    super.initState();
    _detectRole();
    _loadHolidays(); // <-- add
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

// Holidays for current/next year, normalized to date-only
  Set<DateTime> _holidaySet = {};
  bool _holidaysReady = false;

  // ---------- Helpers ----------
  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return _dateOnly(v.toDate());
    if (v is String) return _dateOnly(DateTime.tryParse(v) ?? DateTime(1900));
    return null;
  }

  bool _isInReview(String status) {
    final s = status.toString();
    return s == 'In Review' || s == 'Pending' || s.toLowerCase() == 'pending';
  }

  String _statusLabel(String status) {
    if (status == 'Pending') return 'In Review';
    return status;
  }

  bool _isNotDone(DateTime? end) {
    if (end == null) return false;
    final today = _dateOnly(DateTime.now());
    return !_dateOnly(end).isBefore(today);
  }

  int _businessDaysInclusive(DateTime start, DateTime end,
      {Set<DateTime>? skipDays}) {
    start = _dateOnly(start);
    end = _dateOnly(end);
    if (end.isBefore(start)) return 0;
    int count = 0;
    for (DateTime d = start;
        !d.isAfter(end);
        d = d.add(const Duration(days: 1))) {
      final isWeekend =
          d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
      final isHoliday = (skipDays?.contains(d) ?? false);
      if (!isWeekend && !isHoliday) count++;
    }
    return count;
  }

  int _businessDaysInYear(DateTime start, DateTime end, int year,
      {Set<DateTime>? skipDays}) {
    final startOfYear = DateTime(year, 1, 1);
    final endOfYear = DateTime(year, 12, 31);
    final s =
        _dateOnly(start).isBefore(startOfYear) ? startOfYear : _dateOnly(start);
    final e = _dateOnly(end).isAfter(endOfYear) ? endOfYear : _dateOnly(end);
    if (e.isBefore(s)) return 0;

    // Only skip holidays from this year
    final yearSkip = (skipDays ?? {}).where((d) => d.year == year).toSet();
    return _businessDaysInclusive(s, e, skipDays: yearSkip);
  }

  Future<int> _computeRemainingDays(String userId, int year) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('vacationRequests')
          .where('userId', isEqualTo: userId)
          .get();
      int approved = 0;
      int inReview = 0;
      for (final doc in snap.docs) {
        final d = doc.data();
        final status = (d['status'] ?? 'pending').toString().toLowerCase();
        final start = _toDate(d['startDate']);
        final end = _toDate(d['endDate']);
        if (start == null || end == null) continue;
        final days =
            _businessDaysInYear(start, end, year, skipDays: _holidaySet);
        if (status == 'approved') {
          approved += days;
        } else if (_isInReview(status)) {
          inReview += days;
        }
      }
      const totalPerYear = 25;
      final remaining = totalPerYear - approved - inReview;
      return remaining.clamp(0, totalPerYear);
    } catch (_) {
      return 0;
    }
  }

  // --- NEW: Method to open the custom team range picker ---
  Future<void> _openTeamRangePicker() async {
    final picked = await showModalBottomSheet<_PickedRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => TeamRangePickerSheet(
          initialStart: _startDate,
          initialEnd: _endDate,
          holidays: _holidaySet, // <-- add
        ),
      ),
    );

    if (picked != null && picked.start != null && picked.end != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  Future<void> _loadHolidays() async {
    final now = DateTime.now();
    final years = {
      now.year,
      now.year + 1
    }; // picker only allows future, current + next is enough
    final lists =
        await Future.wait(years.map((y) => HolidayService.holidaysForYear(y)));
    final all = lists.expand((e) => e).toList();

    final s = <DateTime>{};
    for (final h in all) {
      final d = DateTime(h.date.year, h.date.month, h.date.day);
      s.add(d);
    }
    if (mounted) {
      setState(() {
        _holidaySet = s;
        _holidaysReady = true;
      });
    }
  }

  Widget _vacationBalanceCard(User user) {
    final col = FirebaseFirestore.instance.collection('vacationRequests');
    final q = col.where('userId', isEqualTo: user.uid);

    return StreamBuilder<QuerySnapshot>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
              height: 56, child: Center(child: CircularProgressIndicator()));
        }
        final docs = snap.data?.docs ?? [];
        final year = DateTime.now().year;
        int approvedDays = 0;
        int inReviewDays = 0;

        for (final doc in docs) {
          final d = doc.data() as Map<String, dynamic>;
          final rawStatus = (d['status'] ?? 'In Review').toString();
          final status = rawStatus.toLowerCase();
          final start = _toDate(d['startDate']);
          final end = _toDate(d['endDate']);
          if (start == null || end == null) continue;

          final daysInThisYear =
              _businessDaysInYear(start, end, year, skipDays: _holidaySet);

          if (status == 'approved') {
            approvedDays += daysInThisYear;
          } else if (_isInReview(rawStatus)) {
            inReviewDays += daysInThisYear;
          }
        }

        const totalPerYear = 25;
        // Deduct both approved and in-review requests from remaining
        final remaining =
            (totalPerYear - approvedDays - inReviewDays).clamp(0, totalPerYear);

        return Card(
          color: Colors.green.shade50,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.calendar_month, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Vacation Balance (This Year)",
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(
                        "Used (approved): $approvedDays  •  In Review: $inReviewDays",
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Remaining: $remaining / $totalPerYear",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: remaining > 0
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _detectRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final isCeoEmail = (user.email ?? '').toLowerCase() == 'ceo@bpg.com';
    bool isCeoFromDoc = false;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      isCeoFromDoc = (doc.data()?['role'] ?? '') == 'ceo';
    } catch (_) {}
    if (mounted) {
      setState(() => _isCEO = isCeoEmail || isCeoFromDoc);
    }
  }

  Future<void> _submitRequest() async {
    if (_startDate == null || _endDate == null) {
      _showAlert("Incomplete", "Please select a valid vacation date range.");
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Confirm Submission"),
        content: Text(
            "Submit vacation request for ${DateFormat('dd MMM').format(_startDate!)} - ${DateFormat('dd MMM').format(_endDate!)}?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Confirm")),
        ],
      ),
    );
    if (confirm != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showAlert("User Error", "Unable to fetch user. Please re-login.");
      return;
    }

    setState(() => _isSubmitting = true);
    _showLoadingDialog();

    try {
      final workingDays =
          _businessDaysInclusive(_startDate!, _endDate!, skipDays: _holidaySet);

      // Enforce annual limit: deduct both approved and in-review days
      final userId = user.uid;
      final year = DateTime.now().year;
      final remaining = await _computeRemainingDays(userId, year);
      if (workingDays > remaining) {
        Navigator.pop(context); // close loading if opened later
        _showAlert(
            'Limit exceeded',
            'You have $remaining day(s) remaining for this year. '
                'Selected range requires $workingDays business day(s).');
        setState(() => _isSubmitting = false);
        return;
      }

      final request = {
        'userId': user.uid,
        'userEmail': user.email,
        'userDisplayName': user.displayName ?? user.email,
        'note': _noteController.text.trim(),
        'startDate': Timestamp.fromDate(_dateOnly(_startDate!)),
        'endDate': Timestamp.fromDate(_dateOnly(_endDate!)),
        'durationDays': _endDate!.difference(_startDate!).inDays + 1,
        'businessDays': workingDays,
        'status': 'pending', // Changed to match home office pattern
        'submittedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(), // Add for consistency
        // Add review metadata structure for admin actions
        'reviewedBy': null,
        'reviewedByName': null,
        'reviewNote': '',
        'reviewedAt': null,
      };

      await FirebaseFirestore.instance
          .collection('vacationRequests')
          .add(request);
      if (mounted) {
        Navigator.pop(context);
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showAlert("Error", "Something went wrong. Please try again.\n$e");
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _openEditDialog(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    DateTime? start = _toDate(data['startDate']);
    DateTime? end = _toDate(data['endDate']);
    final note = (data['note'] ?? '').toString();

    // Guard: only owners can edit while in review and not past end date.
    final status = (data['status'] ?? 'In Review').toString();
    final notDone = _isNotDone(end);
    if (_isCEO || !_isInReview(status) || !notDone) {
      _showAlert('Not allowed', 'This request can’t be edited.');
      return;
    }

    // Use your new range picker for consistency
    final picked = await showModalBottomSheet<_PickedRange>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (_, controller) => TeamRangePickerSheet(
          initialStart: _startDate,
          initialEnd: _endDate,
          holidays: _holidaySet, // <-- add this
        ),
      ),
    );

    if (picked == null || picked.start == null || picked.end == null) return;

    start = _dateOnly(picked.start!);
    end = _dateOnly(picked.end!);

    final workingDays =
        _businessDaysInclusive(start, end, skipDays: _holidaySet);
    await doc.reference.update({
      'startDate': Timestamp.fromDate(start),
      'endDate': Timestamp.fromDate(end),
      'durationDays': end.difference(start).inDays + 1,
      'businessDays': workingDays,
      'status': 'In Review',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Update Request?'),
        content: Text(
          'Change dates to '
          '${DateFormat('dd MMM').format(start!)} – '
          '${DateFormat('dd MMM').format(end!)} ?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Update')),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await doc.reference.update({
        'startDate': Timestamp.fromDate(start),
        'endDate': Timestamp.fromDate(end),
        'durationDays': end.difference(start).inDays + 1,
        'businessDays': workingDays,
        // stay "In Review" after edits
        'status': 'In Review',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _showAlert('Update failed', '$e');
    }
  }

  Future<void> _confirmDelete(DocumentSnapshot doc,
      {required DateTime? end}) async {
    // Only allow delete if request is still current/future
    if (!_isNotDone(end)) {
      _showAlert('Can’t delete', 'Past requests cannot be deleted.');
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Request?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      await doc.reference.delete();
    } catch (e) {
      _showAlert('Delete failed', '$e');
    }
  }

  Future<void> _confirmApprove(DocumentSnapshot doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve request?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Approve')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await doc.reference.update({
          'status': 'Approved',
          'approvedAt': FieldValue.serverTimestamp(),
          'approvedBy': FirebaseAuth.instance.currentUser?.uid,
        });
      } catch (e) {
        _showAlert('Approve failed', '$e');
      }
    }
  }

  Future<void> _confirmReject(DocumentSnapshot doc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject request?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reject')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await doc.reference.update({
          'status': 'Rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
          'rejectedBy': FirebaseAuth.instance.currentUser?.uid,
        });
      } catch (e) {
        _showAlert('Reject failed', '$e');
      }
    }
  }

  void _showLoadingDialog() {
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Request Submitted"),
        content:
            const Text("Your vacation request has been sent for approval."),
        actions: [
          TextButton(
            onPressed: () {
              // Close only this dialog using its own BuildContext
              Navigator.of(dialogCtx).pop();
              setState(() {
                _startDate = null;
                _endDate = null;
                _noteController.clear();
              });
            },
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  void _showAlert(String title, String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text("OK"))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateText = (_startDate != null && _endDate != null)
        ? "${DateFormat('dd MMM').format(_startDate!)} - ${DateFormat('dd MMM').format(_endDate!)}"
        : "Tap to select vacation dates";
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Vacation Request"),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Submit Your Vacation Request",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            if (_isCEO)
              Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: Text(
                      'CEO view: Approve/Reject employee requests below.',
                      style: TextStyle(color: Colors.green.shade700))),
            const SizedBox(height: 16),
            const Text("Vacation Date Range", style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            InkWell(
              // --- CHANGE: Use the new team picker ---
              onTap: _openTeamRangePicker,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(10)),
                child: Row(children: [
                  const Icon(Icons.date_range),
                  const SizedBox(width: 10),
                  Text(dateText, style: const TextStyle(fontSize: 16)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            const Text("Optional Note", style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            TextFormField(
                controller: _noteController,
                maxLines: 3,
                maxLength: 300,
                decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: "Reason, location, etc.")),
            const SizedBox(height: 18),
            if (user != null && !_isCEO) _vacationBalanceCard(user),
            const SizedBox(height: 30),
            Row(
              children: [
                const Icon(Icons.list_alt, color: Colors.black54),
                const SizedBox(width: 8),
                const Text(
                  "Requests",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const SizedBox(height: 10),
            SizedBox(
              height: 300, // Constrained height for the list
              child: Builder(builder: (context) {
                if (user == null) {
                  return const Center(child: Text("Please log in."));
                }
                final base =
                    FirebaseFirestore.instance.collection('vacationRequests');
                // For non-CEO users, remove ordering to avoid index requirement
                // CEO queries work because they don't have the userId filter
                final Query q = _isCEO
                    ? base.orderBy('createdAt', descending: true).limit(100)
                    : base.where('userId', isEqualTo: user.uid).limit(30);

                return StreamBuilder<QuerySnapshot>(
                  stream: q.snapshots(),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snap.hasError) {
                      // Handle permission errors gracefully
                      final errorMsg = snap.error.toString();
                      if (errorMsg.contains('permission') ||
                          errorMsg.contains(
                              'Missing or insufficient permissions')) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              const Text(
                                "Unable to load your vacation requests",
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "This might be due to missing user data.\nTry submitting a new request.",
                                style: TextStyle(
                                    fontSize: 14, color: Colors.grey.shade600),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      }
                      return Center(child: Text("Error: ${snap.error}"));
                    }
                    final docs = snap.data?.docs ?? [];
                    if (docs.isEmpty) {
                      return const Center(child: Text("No requests yet."));
                    }

                    // Sort docs manually by createdAt for non-CEO users (since we removed orderBy)
                    if (!_isCEO) {
                      docs.sort((a, b) {
                        final aData = a.data() as Map<String, dynamic>;
                        final bData = b.data() as Map<String, dynamic>;
                        final aTime = aData['createdAt'] as Timestamp?;
                        final bTime = bData['createdAt'] as Timestamp?;
                        if (aTime == null && bTime == null) return 0;
                        if (aTime == null) return 1;
                        if (bTime == null) return -1;
                        return bTime.compareTo(aTime); // descending order
                      });
                    }

                    return ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final d = doc.data() as Map<String, dynamic>;

                        final status =
                            _statusLabel((d['status'] ?? 'In Review'));
                        final start = _toDate(d['startDate']);
                        final end = _toDate(d['endDate']);
                        final note = (d['note'] ?? '').toString();
                        final requesterName = (d['userDisplayName'] ??
                                d['userEmail'] ??
                                'Unknown')
                            .toString();

                        String fmt(DateTime? dt) => dt == null
                            ? '-'
                            : DateFormat('dd MMM yyyy').format(dt);

                        final notDone = _isNotDone(end);
                        final bool isMine = (d['userId'] ==
                            user.uid); // <-- new ownership check
                        final bool canEdit = isMine &&
                            !_isCEO &&
                            _isInReview(status) &&
                            notDone; // <-- only mine

                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.beach_access),
                            title: Text("${fmt(start)} → ${fmt(end)}"),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Status: $status"),
                                if (_isCEO) Text("By: $requesterName"),
                                if (note.isNotEmpty) Text("Note: $note"),
                              ],
                            ),
                            trailing: _isCEO
                                ? Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.check_circle),
                                        onPressed: _isInReview(status)
                                            ? () => _confirmApprove(doc)
                                            : null,
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.cancel),
                                        onPressed: _isInReview(status)
                                            ? () => _confirmReject(doc)
                                            : null,
                                      ),
                                    ],
                                  )
                                : (canEdit
                                    ? Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.edit),
                                            onPressed: () =>
                                                _openEditDialog(doc),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete),
                                            onPressed: () =>
                                                _confirmDelete(doc, end: end),
                                          ),
                                        ],
                                      )
                                    : null),
                          ),
                        );
                      },
                    );
                  },
                );
              }),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: (_isSubmitting || _isCEO) ? null : _submitRequest,
              icon: const Icon(Icons.send),
              label: Text(_isCEO
                  ? "Submit Disabled in CEO View"
                  : (_isSubmitting ? "Submitting..." : "Submit Request")),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- ALL NEW WIDGETS FOR THE CUSTOM CALENDAR PICKER ---

class _PickedRange {
  final DateTime? start;
  final DateTime? end;
  _PickedRange(this.start, this.end);
}

class TeamRangePickerSheet extends StatefulWidget {
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final Set<DateTime> holidays; // <-- add

  const TeamRangePickerSheet({
    super.key,
    this.initialStart,
    this.initialEnd,
    required this.holidays, // <-- add
  });

  @override
  State<TeamRangePickerSheet> createState() => _TeamRangePickerSheetState();
}

class _TeamRangePickerSheetState extends State<TeamRangePickerSheet> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

  final Map<DateTime, List<_PersonVacation>> _dayMap = {};

  @override
  void initState() {
    super.initState();
    _rangeStart = widget.initialStart;
    _rangeEnd = widget.initialEnd;
    if (widget.initialStart != null) {
      _focusedDay = widget.initialStart!;
    }
  }

  bool _isHoliday(DateTime d) => widget.holidays.contains(_d(d));

  DateTime _d(DateTime d) => DateTime(d.year, d.month, d.day);
  DateTime _startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);
  DateTime _endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

  Stream<QuerySnapshot> _monthStream(DateTime monthCenter) {
    final start = Timestamp.fromDate(_startOfMonth(monthCenter));
    final end = Timestamp.fromDate(_endOfMonth(monthCenter));
    final col = FirebaseFirestore.instance.collection('vacationRequests');
    return col
        .where('startDate', isLessThanOrEqualTo: end)
        .where('endDate', isGreaterThanOrEqualTo: start)
        .snapshots();
  }

  void _rebuildDayMap(QuerySnapshot snap) {
    _dayMap.clear();
    for (final doc in snap.docs) {
      final d = doc.data() as Map<String, dynamic>;
      final status = (d['status'] ?? '').toString();
      if (!(status == 'Approved' ||
          status == 'In Review' ||
          status == 'Pending')) {
        continue;
      }

      DateTime? s, e;
      final vS = d['startDate'], vE = d['endDate'];
      if (vS is Timestamp) s = vS.toDate();
      if (vS is String) s = DateTime.tryParse(vS);
      if (vE is Timestamp) e = vE.toDate();
      if (vE is String) e = DateTime.tryParse(vE);
      if (s == null || e == null) continue;

      s = _d(s);
      e = _d(e);
      final name =
          (d['userDisplayName'] ?? d['userEmail'] ?? 'Someone').toString();

      for (DateTime cur = s;
          !cur.isAfter(e);
          cur = cur.add(const Duration(days: 1))) {
        final key = _d(cur);
        _dayMap.putIfAbsent(key, () => []);
        _dayMap[key]!
            .add(_PersonVacation(name: name, status: status, start: s, end: e));
      }
    }
    // Use addPostFrameCallback to avoid calling setState during a build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  List<String> _namesForDay(DateTime day) =>
      (_dayMap[_d(day)] ?? []).map((e) => e.initials).toSet().toList();

  List<_PersonVacation> _rangesForSelected() {
    if (_rangeStart == null) return const [];
    // If only start is selected, show conflicts for that single day
    final end = _rangeEnd ?? _rangeStart;
    final set = <_PersonVacation>{};
    for (DateTime cur = _d(_rangeStart!);
        !cur.isAfter(_d(end!));
        cur = cur.add(const Duration(days: 1))) {
      for (final p in (_dayMap[_d(cur)] ?? [])) {
        set.add(p);
      }
    }
    return set.toList();
  }

  @override
  Widget build(BuildContext context) {
    final radius = const Radius.circular(16);

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.only(topLeft: radius, topRight: radius),
        ),
        padding: const EdgeInsets.only(top: 12, left: 12, right: 12, bottom: 8),
        child: Column(
          children: [
            Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 12),
            Row(
              children: [
                const Expanded(
                    child: Text("Select Vacation Range",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600))),
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text("Cancel")),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    StreamBuilder<QuerySnapshot>(
                      stream: _monthStream(_focusedDay),
                      builder: (context, snap) {
                        if (snap.hasData) _rebuildDayMap(snap.data!);

                        return TableCalendar(
                          firstDay: _d(DateTime.now()),
                          lastDay:
                              _d(DateTime.now().add(const Duration(days: 365))),
                          focusedDay: _focusedDay,
                          startingDayOfWeek: StartingDayOfWeek.monday,
                          rangeStartDay: _rangeStart,
                          rangeEndDay: _rangeEnd,
                          rangeSelectionMode: RangeSelectionMode.enforced,
                          onRangeSelected: (s, e, f) => setState(() {
                            _rangeStart = s;
                            _rangeEnd = e;
                            _focusedDay = f;
                          }),
                          onPageChanged: (focused) =>
                              setState(() => _focusedDay = focused),
                          calendarFormat: CalendarFormat.month,
                          availableCalendarFormats: const {
                            CalendarFormat.month: 'Month'
                          },
                          calendarBuilders: CalendarBuilders(
                            markerBuilder: (ctx, day, events) {
                              final people = _dayMap[_d(day)] ?? [];
                              if (people.isEmpty) {
                                return const SizedBox.shrink();
                              }

                              // Up to 3 bubbles; each with its own status color
                              final show = people.take(3).toList();
                              return Padding(
                                padding: const EdgeInsets.only(top: 36),
                                child: Wrap(
                                  spacing: 2,
                                  children: show
                                      .map((p) => _InitialBubble(
                                          p.initials, _statusColor(p.status)))
                                      .toList(),
                                ),
                              );
                            },
                            defaultBuilder: (ctx, day, _) {
                              final isHoliday = _isHoliday(day);
                              final hasPeople = _dayMap.containsKey(_d(day));

                              Widget dayLabel = Text(
                                '${day.day}',
                                style: TextStyle(
                                  color: isHoliday ? Colors.red.shade700 : null,
                                  fontWeight: isHoliday
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                ),
                              );

                              Widget cell = Container(
                                margin: const EdgeInsets.all(6),
                                alignment: Alignment.center,
                                decoration: hasPeople
                                    ? BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        gradient: const LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [
                                            Color(0x11FFA500),
                                            Color(0x08FFA500)
                                          ],
                                        ),
                                      )
                                    : null,
                                child: dayLabel,
                              );

                              if (isHoliday) {
                                return Stack(
                                  children: [
                                    cell,
                                    Positioned(
                                      right: 4,
                                      top: 4,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade50,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          border: Border.all(
                                              color: Colors.red.shade300),
                                        ),
                                        child: const Text('H',
                                            style: TextStyle(fontSize: 9)),
                                      ),
                                    ),
                                  ],
                                );
                              }

                              return cell;
                            },
                          ),
                        );
                      },
                    ),
                    // --- Legend (NEW) ---
                    const SizedBox(height: 8),
                    Row(
                      children: const [
                        _LegendItem(color: Colors.red, label: 'Public holiday'),
                        SizedBox(width: 12),
                        _LegendItem(
                            color: Colors.orange, label: 'Team overlaps'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _ConflictsPanel(vacations: _rangesForSelected()),
                  ],
                ),
              ),
            ),
            // --- Counted days (NEW) ---
            Builder(builder: (_) {
              final counted = (_rangeStart != null && _rangeEnd != null)
                  ? _countBusinessDays(
                      _rangeStart!, _rangeEnd!) // <-- use local helper
                  : 0;

              return Padding(
                padding:
                    const EdgeInsets.only(left: 4, right: 4, bottom: 6, top: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    counted > 0
                        ? "$counted working day${counted == 1 ? '' : 's'} (holidays excluded)"
                        : "Select a start and end date",
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              );
            }),
            const SizedBox(height: 2),

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: (_rangeStart != null && _rangeEnd != null)
                    ? () => Navigator.pop(
                        context, _PickedRange(_rangeStart, _rangeEnd))
                    : null,
                child: const Text("OK"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _countBusinessDays(DateTime start, DateTime end) {
    DateTime s = DateTime(start.year, start.month, start.day);
    DateTime e = DateTime(end.year, end.month, end.day);
    if (e.isBefore(s)) return 0;

    int count = 0;
    for (DateTime d = s; !d.isAfter(e); d = d.add(const Duration(days: 1))) {
      final isWeekend =
          d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
      final isHoliday =
          widget.holidays.contains(DateTime(d.year, d.month, d.day));
      if (!isWeekend && !isHoliday) count++;
    }
    return count;
  }
}

class _PersonVacation {
  final String name;
  final String status;
  final DateTime start;
  final DateTime end;
  const _PersonVacation(
      {required this.name,
      required this.status,
      required this.start,
      required this.end});
  String get initials {
    final parts =
        name.split(RegExp(r'[\s@._-]+')).where((s) => s.isNotEmpty).toList();
    if (parts.isEmpty) return "?";
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  bool operator ==(Object other) =>
      other is _PersonVacation &&
      other.name == name &&
      other.start == start &&
      other.end == end &&
      other.status == status;
  @override
  int get hashCode => Object.hash(name, start, end, status);
}

class _InitialBubble extends StatelessWidget {
  final String text;
  final Color color;
  const _InitialBubble(this.text, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.6)),
        color: color.withOpacity(0.10),
      ),
      child: Text(text, style: const TextStyle(fontSize: 10)),
    );
  }
}

class _ConflictsPanel extends StatelessWidget {
  final List<_PersonVacation> vacations;
  const _ConflictsPanel({required this.vacations});

  @override
  Widget build(BuildContext context) {
    if (vacations.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(10)),
        child: const Text("No overlaps in the selected range 🎉"),
      );
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Overlapping vacations",
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...vacations.take(8).map((v) => Text(
                "• ${v.name}   ${DateFormat('dd MMM').format(v.start)}–${DateFormat('dd MMM').format(v.end)}   (${v.status})",
                style: const TextStyle(fontSize: 12),
              )),
          if (vacations.length > 8)
            Text("+ ${vacations.length - 8} more…",
                style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}
