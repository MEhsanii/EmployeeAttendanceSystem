import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:attendence_management_system/pages/admin_dashboard.dart';

class SickScreen extends StatefulWidget {
  const SickScreen({super.key});

  @override
  State<SickScreen> createState() => _SickScreenState();
}

class _SickScreenState extends State<SickScreen> {
  // ---- THEME ----
  static const _brand = Color(0xFF2E7D32);
  static const _brandSoft = Color(0xFFE8F5E9);

  late DateTime _currentMonth;
  final _refreshKey = GlobalKey<RefreshIndicatorState>();
  String? _userRole;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
    _fetchUserRole();
  }

  Future<void> _fetchUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _userRole = doc.data()?['role'] as String?;
        });
      }
    } catch (e) {
      print('Error fetching user role: $e');
    }
  }

  // ---- DATE HELPERS ----
  DateTime _startOfMonth(DateTime m) => DateTime(m.year, m.month, 1);

  DateTime _startOfNextMonth(DateTime m) => (m.month == 12)
      ? DateTime(m.year + 1, 1, 1)
      : DateTime(m.year, m.month + 1, 1);

  void _prevMonth() => setState(() {
        _currentMonth =
            DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
      });

  void _nextMonth() {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1);
    if (_currentMonth.isBefore(thisMonth)) {
      setState(() {
        _currentMonth =
            DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
      });
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 3, 1); // limit picker range (3y back)
    final last = DateTime(now.year, now.month);

    final DateTime? picked = await showDatePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDate: _currentMonth,
      helpText: 'Select any date in the month',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context)
              .copyWith(colorScheme: ColorScheme.fromSeed(seedColor: _brand)),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _currentMonth = DateTime(picked.year, picked.month, 1);
      });
    }
  }

  // ---- QUERY ----
  Stream<QuerySnapshot<Map<String, dynamic>>> _monthSickStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Stream<QuerySnapshot<Map<String, dynamic>>>.empty();
    }

    final start = _startOfMonth(_currentMonth);
    final end = _startOfNextMonth(_currentMonth);

    // Requires composite index: workMode ASC, createdAt DESC (or ASC if you flip the orderBy)
    return FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('attendance')
        .where('workMode', isEqualTo: 'Sick')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('createdAt', isLessThan: Timestamp.fromDate(end))
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  // If Firestore returns a "failed-precondition" about missing index, try to parse the console link.
  String? _extractIndexLink(Object error) {
    final text = error.toString();
    final start = text.indexOf('https://console.firebase.google.com');
    if (start == -1) return null;
    // Grab until whitespace
    final end = text.indexOf(' ', start);
    return (end == -1) ? text.substring(start) : text.substring(start, end);
  }

  void _navigateBack(BuildContext context) {
    final role = _userRole?.toLowerCase();
    if (role != null && (role == 'hr' || role == 'ceo')) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AdminDashboard(userRole: role),
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _markTodayAsSick(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('attendance')
          .doc(dateKey);

      // Check if already marked for today
      final docSnapshot = await docRef.get();
      if (docSnapshot.exists) {
        final currentMode = docSnapshot.data()?['workMode'];
        if (currentMode == 'Sick') {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Today is already marked as Sick'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
      }

      await docRef.set({
        'workMode': 'Sick',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Today marked as Sick'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        // Refresh the list
        setState(() {});
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final monthTitle = DateFormat.yMMMM().format(_currentMonth);

    return Scaffold(
      appBar: AppBar(
          title: const Text("Sick Leave"),
          backgroundColor: Colors.green.shade700,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _navigateBack(context),
          ),
          actions: [
            // Button to mark today as sick
            InkWell(
              onTap: user != null ? () => _markTodayAsSick(context) : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: EdgeInsets.only(right: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.red.shade400, Colors.red.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sick,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Mark as Sick',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    // IconButton(
                    //   icon: const Icon(Icons.add_circle_outline),
                    //   tooltip: 'Mark Today as Sick',
                    //   onPressed:
                    //       user != null ? () => _markTodayAsSick(context) : null,
                    // ),
                  ],
                ),
              ),
            ),
          ]),
      body: user == null
          ? _SignedOutState(onSignInTap: () {
              Navigator.of(context).pop();
            })
          : Column(
              children: [
                const SizedBox(height: 16),

                // Month selector row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _NavChip(icon: Icons.chevron_left, onTap: _prevMonth),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _pickMonth,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              monthTitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ),
                      _NavChip(
                        icon: Icons.chevron_right,
                        onTap: _nextMonth,
                        enabled: _isBeforeThisMonth(_currentMonth),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // Month-wise record
                Expanded(
                  child: RefreshIndicator(
                    key: _refreshKey,
                    color: _brand,
                    onRefresh: () async {
                      // Force a rebuild; StreamBuilder will re-listen automatically.
                      setState(() {});
                    },
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _monthSickStream(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        if (snapshot.hasError) {
                          final link = _extractIndexLink(snapshot.error!);
                          return _ErrorState(
                            message: "Couldn't load sick records.",
                            errorDetails: snapshot.error.toString(),
                            indexLink: link,
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];

                        // Normalize to DateTimes; support missing createdAt by parsing doc.id (YYYY-MM-DD)
                        final items = docs
                            .map((d) => _dateFromDoc(d))
                            .whereType<DateTime>()
                            .toList()
                          ..sort(); // oldest -> newest (we'll reverse if we want)

                        final count = items.length;

                        if (count == 0) {
                          return ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(16),
                            children: [
                              _SummaryCard(count: 0, monthTitle: monthTitle),
                              const SizedBox(height: 16),
                              _EmptyState(
                                title: 'No sick days this month',
                                subtitle: 'Nice! Stay healthy 💪',
                              ),
                            ],
                          );
                        }

                        return ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          children: [
                            _SummaryCard(count: count, monthTitle: monthTitle),
                            const SizedBox(height: 12),
                            ...items.reversed.map((dt) => _SickTile(date: dt)),
                            const SizedBox(height: 24),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  bool _isBeforeThisMonth(DateTime m) {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1);
    return m.isBefore(thisMonth);
  }

  DateTime? _dateFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    try {
      final ts = d.data()['createdAt'] as Timestamp?;
      if (ts != null) return ts.toDate();

      // Fallback to ID parsing: "YYYY-MM-DD"
      final parts = d.id.split('-');
      if (parts.length == 3) {
        return DateTime(
            int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      }
    } catch (_) {}
    return null;
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.sentiment_satisfied_alt, size: 48, color: Colors.grey),
        const SizedBox(height: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.black54,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

// ======= SMALL, REUSABLE WIDGETS =======

class _SummaryCard extends StatelessWidget {
  final int count;
  final String monthTitle;

  const _SummaryCard({required this.count, required this.monthTitle});

  @override
  Widget build(BuildContext context) {
    final big = max(32.0, 28.0 + min(10, count).toDouble()); // playful size
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 24,
            backgroundColor: _SickScreenState._brandSoft,
            child: Icon(Icons.calendar_month, color: _SickScreenState._brand),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("$count",
                    style:
                        TextStyle(fontSize: big, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(
                  "sick day${count == 1 ? '' : 's'} in $monthTitle",
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SickTile extends StatelessWidget {
  final DateTime date;

  const _SickTile({required this.date});

  @override
  Widget build(BuildContext context) {
    final title = DateFormat('EEE, d MMM yyyy').format(date);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))
        ],
      ),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: _SickScreenState._brandSoft,
          child: Icon(Icons.sick, color: _SickScreenState._brand),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: const Text('Marked Sick'),
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  const _NavChip(
      {required this.icon, required this.onTap, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: enabled ? Colors.white : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(10),
          boxShadow: const [
            BoxShadow(
                color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
          ],
        ),
        padding: const EdgeInsets.all(6),
        child: Icon(icon,
            size: 24, color: enabled ? _SickScreenState._brand : Colors.grey),
      ),
    );
  }
}

class _SignedOutState extends StatelessWidget {
  final VoidCallback onSignInTap;

  const _SignedOutState({required this.onSignInTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_person, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('You are signed out.', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: onSignInTap, child: const Text('Sign in'))
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final String errorDetails;
  final String? indexLink;

  const _ErrorState({
    required this.message,
    required this.errorDetails,
    this.indexLink,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
        const SizedBox(height: 12),
        Text(message,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 8),
        Text(errorDetails,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54)),
        if (indexLink != null) ...[
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.open_in_new),
              onPressed: () {
                // We can't open URLs from here in all environments, but on device this works:
                // launchUrlString(indexLink!)
                // If you want this, add url_launcher to pubspec and call launchUrlString.
              },
              label: const Text('Open Firebase Console to Create Index'),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tip: Create a composite index for fields: workMode (ASC) + createdAt (DESC).',
            textAlign: TextAlign.center,
          ),
        ],
      ],
    );
  }
}
