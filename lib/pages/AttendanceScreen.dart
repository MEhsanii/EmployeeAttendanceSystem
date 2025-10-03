import 'package:attendence_management_system/pages/editing.dart';
import 'package:attendence_management_system/pages/work_mode_selection_page.dart';
import 'package:attendence_management_system/pages/admin_dashboard.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// -------------------------
/// Main Attendance (logging only)
/// -------------------------
class MainAttendanceScreen extends StatelessWidget {
  const MainAttendanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // No bottom nav, no tabs — just the logging screen
    return const StaticWorkScreen();
  }
}

/// -------------------------
/// Logging Screen (Today View)
/// -------------------------
class StaticWorkScreen extends StatefulWidget {
  const StaticWorkScreen({super.key});

  @override
  State<StaticWorkScreen> createState() => _StaticWorkScreenState();
}

class _StaticWorkScreenState extends State<StaticWorkScreen>
    with WidgetsBindingObserver {
  Map<String, Timestamp?> timestamps = {
    'startWork': null,
    'startBreak': null,
    'endBreak': null,
    'endWork': null,
  };

  String? _currentWorkMode;
  bool _homeOfficeApprovedToday = false;
  String? _userRole; // Track user role for navigation

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    fetchTimestamps();
    _checkHomeOfficeApproval();
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

  Future<void> _checkHomeOfficeApproval() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final now = DateTime.now();
    final dateId =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    try {
      // Check in the global homeOfficeRequests collection
      final querySnapshot = await FirebaseFirestore.instance
          .collection('homeOfficeRequests')
          .where('userId', isEqualTo: user.uid)
          .get();

      bool isApproved = false;
      for (final doc in querySnapshot.docs) {
        final data = doc.data();
        final statusByDate =
        Map<String, dynamic>.from(data['statusByDate'] ?? {});
        if (statusByDate[dateId] == 'approved') {
          isApproved = true;
          break;
        }
      }

      if (mounted) {
        setState(() => _homeOfficeApprovedToday = isApproved);
      }
    } catch (e) {
      print('Error checking home office approval: $e');
      if (mounted) {
        setState(() => _homeOfficeApprovedToday = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      fetchTimestamps();
    }
  }

  Future<void> fetchTimestamps() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final now = DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('attendance')
        .doc(dateKey)
        .get();

    if (doc.exists && mounted) {
      final data = doc.data() ?? {};
      setState(() {
        timestamps = {
          'startWork': data['startWork'],
          'startBreak': data['startBreak'],
          'endBreak': data['endBreak'],
          'endWork': data['endWork'],
        };
        _currentWorkMode = data['workMode'];
      });
    }
  }

  Future<void> setWorkMode(String mode) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('attendance')
        .doc(dateKey);

    try {
      await docRef.set({
        'workMode': mode,
        'createdAt': Timestamp.now(),
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _currentWorkMode = mode;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Work mode set to $mode')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error setting work mode: $e')),
        );
      }
    }
  }

  Future<void> handleButton(String action, BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not logged in')),
      );
      return;
    }

    final uid = user.uid;
    final now = DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('attendance')
        .doc(dateKey);

    try {
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists && docSnapshot.data()!.containsKey(action)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You have already recorded $action today')),
        );
        return;
      }

      final ts = Timestamp.now();

      await docRef.set({
        action: ts,
        'createdAt': ts,
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() {
        timestamps[action] = ts;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$action recorded at ${formatTimestamp(ts)}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  String formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '--:--';
    final dt = timestamp.toDate();
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  // Handle back button press (both AppBar and phone hardware button)
  Future<bool> _handleBackPress() async {
    _navigateBack(context);
    return false; // Prevent default back behavior
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    const appGreen = Color(0xFF2E7D32);
    final now = DateTime.now();

    return WillPopScope(
      onWillPop: _handleBackPress,
      child: Scaffold(
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
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 26),
                  onPressed: () => _navigateBack(context),
                ),
                const Expanded(
                  child: Text(
                    'Attendance Tracker',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withOpacity(0.25)),
                  ),
                  child: Text(
                    "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}",
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: SingleChildScrollView(
            child: Column(
              children: [
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.today, size: 16, color: appGreen),
                      const SizedBox(width: 6),
                      Text(
                        "Today • ${_weekdayName(now.weekday)}, ${_monthNameLong(now.month)} ${now.day}",
                        style: const TextStyle(
                          color: appGreen,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _currentWorkMode != 'Office'
                                ? () => setWorkMode('Office')
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _currentWorkMode == 'Office'
                                  ? Colors.blue.shade600
                                  : Colors.white,
                              foregroundColor: _currentWorkMode == 'Office'
                                  ? Colors.white
                                  : Colors.blue.shade700,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              elevation: 1,
                            ),
                            icon: Icon(
                              _currentWorkMode == 'Office'
                                  ? Icons.check_circle
                                  : Icons.apartment,
                              size: 14,
                            ),
                            label: Text(
                              'Office',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          ElevatedButton.icon(
                            onPressed: (_homeOfficeApprovedToday &&
                                _currentWorkMode != 'Home Office')
                                ? () => setWorkMode('Home Office')
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                              _currentWorkMode == 'Home Office'
                                  ? Colors.green.shade600
                                  : (_homeOfficeApprovedToday
                                  ? Colors.green.shade600
                                  : Colors.grey.shade400),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              elevation: _homeOfficeApprovedToday ? 1 : 0,
                            ),
                            icon: Icon(
                              _currentWorkMode == 'Home Office'
                                  ? Icons.check_circle
                                  : Icons.home_work,
                              size: 14,
                            ),
                            label: Text(
                              _homeOfficeApprovedToday ? 'Home' : 'Home',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // Current work mode indicator
                if (_currentWorkMode != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: _currentWorkMode == 'Sick'
                            ? [Colors.red.shade400, Colors.red.shade600]
                            : (_currentWorkMode == 'Home Office'
                            ? [
                          Colors.green.shade400,
                          Colors.green.shade600
                        ]
                            : [Colors.blue.shade400, Colors.blue.shade600]),
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: (_currentWorkMode == 'Sick'
                              ? Colors.red
                              : (_currentWorkMode == 'Home Office'
                              ? Colors.green
                              : Colors.blue))
                              .withOpacity(0.4),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            _currentWorkMode == 'Sick'
                                ? Icons.sick
                                : (_currentWorkMode == 'Home Office'
                                ? Icons.home_work
                                : Icons.apartment),
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Working Mode: $_currentWorkMode',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],

                _buildActionCard('Start Work', 'startWork'),
                _buildActionCard('Start Break', 'startBreak'),
                _buildActionCard('End Break', 'endBreak'),
                _buildActionCard('End Work', 'endWork'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionCard(String label, String key) {
    const appGreen = Color(0xFF2E7D32);
    final ts = timestamps[key];
    final isRecorded = ts != null;

    final icon = _iconFor(key);
    final subtitle = _subtitleFor(key);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              color: Colors.black12, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER ROW: badge + full-width text (no controls on the right)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
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
                  child: Icon(icon, color: appGreen, size: 26),
                ),
                const SizedBox(width: 12),
                // Title + subtitle + time get the whole remaining width
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: Colors.black54.withOpacity(0.9),
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.access_time,
                              size: 16, color: Colors.grey),
                          const SizedBox(width: 6),
                          Text(
                            "Time: ${formatTimestamp(ts)}",
                            style: const TextStyle(
                                fontSize: 14, color: Colors.black54),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // CONTROLS ROW: pills on the left, Record button on the right
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _StatusPill(
                      text: isRecorded
                          ? "Started at ${formatTimestamp(ts)}"
                          : "Pending",
                      color: isRecorded ? const Color(0xFF9E9E9E) : appGreen,
                      lightText: isRecorded,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed:
                  isRecorded ? null : () => handleButton(key, context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isRecorded ? Colors.grey : appGreen,
                    disabledBackgroundColor: Colors.grey,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    isRecorded ? 'Recorded' : 'Record',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            // EDIT aligned to the right
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  String todayKey() {
                    final n = DateTime.now();
                    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
                  }

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => EditAttendanceScreen(
                        dateKey: todayKey(),
                        fieldKey: key,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit'),
                style: TextButton.styleFrom(
                  foregroundColor: appGreen,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateBack(BuildContext context) {
    // If user is HR or CEO, navigate back to admin dashboard
    final role = _userRole?.toLowerCase();
    if (role != null && (role == 'hr' || role == 'ceo')) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AdminDashboard(userRole: role),
        ),
      );
    } else {
      // Employee - navigate to work mode selection using pushReplacement
      Navigator.of(context).pushReplacement(_createSlideTransition());
    }
  }

  Route _createSlideTransition() {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) =>
      const WorkModeSelectionPage(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(-1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;

        final tween =
        Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
        final offsetAnimation = animation.drive(tween);

        return SlideTransition(position: offsetAnimation, child: child);
      },
    );
  }

  // Helpers for icons, subtitles, names
  IconData _iconFor(String key) {
    switch (key) {
      case 'startWork':
        return Icons.play_arrow_rounded;
      case 'startBreak':
        return Icons.free_breakfast_rounded;
      case 'endBreak':
        return Icons.coffee_maker_outlined;
      case 'endWork':
      default:
        return Icons.stop_rounded;
    }
  }

  String _subtitleFor(String key) {
    switch (key) {
      case 'startWork':
        return "Begin your workday";
      case 'startBreak':
        return "Log the start of your break";
      case 'endBreak':
        return "End your break";
      case 'endWork':
      default:
        return "Finish your workday";
    }
  }

  String _monthNameLong(int m) => const [
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

  String _weekdayName(int w) =>
      const ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][w - 1];
}

/// Simple "pill" chip used for status/started-at labels.
class _StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final bool lightText;
  const _StatusPill({
    required this.text,
    required this.color,
    this.lightText = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(lightText ? 1.0 : 0.12),
        borderRadius: BorderRadius.circular(999),
        border: lightText ? null : Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: lightText ? Colors.white : color,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}