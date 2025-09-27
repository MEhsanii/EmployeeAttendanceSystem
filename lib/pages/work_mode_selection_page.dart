import 'package:attendence_management_system/pages/AttendanceScreen.dart';
import 'package:attendence_management_system/pages/loginPage.dart';
import 'package:attendence_management_system/pages/role_selection_page.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:attendence_management_system/pages/announcements.dart';
import 'package:attendence_management_system/pages/vacation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:attendence_management_system/pages/sick.dart';
import 'package:attendence_management_system/pages/holidays.dart';
import '/services/holiday_service.dart'; // add import
import 'package:attendence_management_system/pages/history.dart';
import 'package:attendence_management_system/pages/home_office.dart';

class WorkModeSelectionPage extends StatefulWidget {
  const WorkModeSelectionPage({super.key});

  @override
  State<WorkModeSelectionPage> createState() => _WorkModeSelectionPageState();
}

class _WorkModeSelectionPageState extends State<WorkModeSelectionPage> {
  String? _selectedWorkMode;
  bool _isLoading = true;

// NEW:
  bool _isTodayHoliday = false;
  String? _todayHolidayName;
  // Expansion state persistence
  bool _expWorkMode = true;
  bool _expLeave = false;
  bool _expOthers = true;

  final String _vacationModeTitle = "Apply for Vacation";

  bool _homeOfficeApprovedToday = false;

  Future<void> _checkHomeOfficeApprovedToday() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final now = DateTime.now();
    final dateId =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('approvedHomeOffice')
        .doc(dateId)
        .get();

    if (mounted) {
      setState(() => _homeOfficeApprovedToday = snap.exists);
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchSelectedWorkMode();
    _loadExpansionState();
    _checkTodayHoliday(); // NEW
    _checkHomeOfficeApprovedToday(); // NEW
  }

  Future<void> _loadExpansionState() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _expWorkMode = p.getBool('exp_work_mode') ?? _expWorkMode;
      _expLeave = p.getBool('exp_leave') ?? _expLeave;
      _expOthers = p.getBool('exp_others') ?? _expOthers;
    });
  }

  Future<void> _saveExpansionState() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('exp_work_mode', _expWorkMode);
    await p.setBool('exp_leave', _expLeave);
    await p.setBool('exp_others', _expOthers);
  }

  Future<void> _fetchSelectedWorkMode() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    final today = DateTime.now();
    final dateId =
        "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('attendance')
        .doc(dateId)
        .get();

    if (doc.exists && doc.data()!['workMode'] != null) {
      setState(() {
        _selectedWorkMode = doc['workMode'];
      });
    }

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _saveWorkMode(BuildContext context, String mode) async {
    if (mode == _vacationModeTitle) return;
    // NEW: block if holiday
    if (_isTodayHoliday) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  "Today is a holiday: ${_todayHolidayName ?? '—'}. Attendance is disabled.")),
        );
      }
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final today = DateTime.now();
    final dateId =
        "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('attendance')
        .doc(dateId)
        .set({
      'workMode': mode,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    setState(() {
      _selectedWorkMode = mode;
    });
  }

  void _handleWorkModeSelection(String mode) async {
    if (_selectedWorkMode == null && mode != _vacationModeTitle) {
      await _saveWorkMode(context, mode);
    }

    if (mode == _vacationModeTitle) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const VacationScreen()),
      );
    }
  }

  void _goToMainAttendanceScreen() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MainAttendanceScreen()),
    );
  }

  void _goToAnnouncements() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AnnouncementsPage(),
      ),
    );
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionPage()),
      (route) => false,
    );
  }

  Future<void> _checkTodayHoliday() async {
    final today = DateTime.now();
    final h = await HolidayService.holidayOn(today);
    if (h != null) {
      setState(() {
        _isTodayHoliday = true;
        _todayHolidayName = h.name;
        _selectedWorkMode = "Holiday"; // reflect in UI
      });
      await _saveHolidayAttendanceIfNeeded(h); // write to Firestore once
    }
  }

  Future<void> _saveHolidayAttendanceIfNeeded(Holiday h) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final dateId =
        "${h.date.year}-${h.date.month.toString().padLeft(2, '0')}-${h.date.day.toString().padLeft(2, '0')}";

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('attendance')
        .doc(dateId);

    final snap = await ref.get();
    if (snap.exists && (snap.data()?['isHoliday'] == true)) {
      // already recorded as holiday
      return;
    }
    await ref.set({
      'workMode': 'Holiday',
      'holidayName': h.name,
      'isHoliday': true,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _openAccountSheet() {
    final user = FirebaseAuth.instance.currentUser;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(user?.email ?? 'Account'),
              subtitle: const Text('Logged in'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {/* TODO: push settings */},
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title:
                  const Text('Sign out', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _signOut();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(User? user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Good day!",
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                if (user?.email != null)
                  Text("Signed in as ${user!.email}",
                      style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          InkWell(
            onTap: _openAccountSheet,
            borderRadius: BorderRadius.circular(22),
            child: CircleAvatar(
              radius: 22,
              backgroundColor: Colors.white.withOpacity(0.15),
              child: const Icon(Icons.person, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 0, // hides default AppBar
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF30492D), Color(0xFF4CAF50)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          top: true,
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white))
              : Column(
                  children: [
                    const SizedBox(height: kToolbarHeight + 16),
                    _header(user),
                    const SizedBox(height: 20),

// ▼▼▼ ADD THIS BANNER ▼▼▼
                    if (_isTodayHoliday)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF2E7D32),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              const Icon(Icons.beach_access,
                                  color: Colors.white),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  "Today is a public holiday: ${_todayHolidayName ?? 'Holiday'}.\nAttendance is disabled.",
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
// ▲▲▲ END BANNER ▲▲▲

                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: _buildSlideDownMenus(),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildSlideDownMenus() {
    final isSomethingSelected = _selectedWorkMode != null;
    final disableAllWorkTiles = _isTodayHoliday; // NEW

    return Column(
      children: [
        // Work Mode
        _expansionCard(
          title: "Work Mode",
          icon: Icons.work_outline,
          initiallyExpanded: _expWorkMode,
          onChanged: (v) {
            setState(() => _expWorkMode = v);
            _saveExpansionState();
          },
          children: [
            _buildMenuTile(
              label: _selectedWorkMode ?? "Office",
              icon: Icons.apartment,
              disabled: disableAllWorkTiles &&
                  (isSomethingSelected),
              onTap: () => _handleWorkModeSelection("Office"),
              selected: _selectedWorkMode != "",
            ),
            _buildMenuTile(
              label: "Request Home Office",
              icon: Icons.home_work,
              // was: disableAllWorkTiles || (isSomethingSelected && _selectedWorkMode != "Home Office"),
              disabled: disableAllWorkTiles, // ✅ always tappable unless holiday
              onTap: () async {
                // If today is approved AND no work mode saved yet → select "Home Office"
                // if (_homeOfficeApprovedToday && _selectedWorkMode == null) {
                //   await _saveWorkMode(context, "Home Office");
                //   _handleWorkModeSelection("Home Office");
                //   return;
                // }

                // Otherwise (already selected Office/Sick OR not approved today) → open request page
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const HomeOfficeRequestPage()),
                );
              },
              selected: false,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Leave - Sick only
        _expansionCard(
          title: "Leave",
          icon: Icons.event_available_outlined,
          initiallyExpanded: _expLeave,
          onChanged: (v) {
            setState(() => _expLeave = v);
            _saveExpansionState();
          },

          children: [

            _buildMenuTile(
              label: "Sick",
              icon: Icons.sick,
              disabled: disableAllWorkTiles ||
                  (isSomethingSelected && _selectedWorkMode != "Sick"),
              onTap: () => _handleWorkModeSelection("Sick"),
              selected: _selectedWorkMode == "Sick",
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Public Holidays in its own section
        _expansionCard(
          title: "Public Holidays",
          icon: Icons.beach_access,
          initiallyExpanded: false, // collapsed by default
          onChanged: (_) {},
          children: [
            ListTile(
              leading: const Icon(Icons.beach_access, color: Color(0xFF2E7D32)),
              title: const Text(
                "Holidays List",
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.black87),
              ),
              trailing: const Icon(Icons.arrow_forward_ios,
                  size: 16, color: Colors.grey),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const HolidaysScreen()),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Others (unchanged)
        // Others (unchanged)
        _expansionCard(
          title: "Others",
          icon: Icons.more_horiz,
          initiallyExpanded: _expOthers,
          onChanged: (v) {
            setState(() => _expOthers = v);
            _saveExpansionState();
          },
          children: [
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text(
                "Attendance History",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const HistoryScreen()),
                );
              },
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.flight_takeoff),
              title: const Text(
                "Apply for Vacation",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const VacationScreen()),
                );
              },
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.campaign),
              title: const Text(
                "To the Announcements",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: _goToAnnouncements,
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            ),
          ],
        ),
      ],
    );
  }

  Widget _expansionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
    required bool initiallyExpanded,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 4)),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<String>('tile_$title'),
          maintainState: true,
          initiallyExpanded: initiallyExpanded,
          onExpansionChanged: onChanged,
          leading: Icon(icon, color: const Color(0xFF2E7D32)),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          iconColor: const Color(0xFF2E7D32),
          collapsedIconColor: Colors.grey,
          childrenPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          children: children,
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool disabled = false,
    bool selected = false,
  }) {
    return IgnorePointer(
      ignoring: disabled, // <-- actually blocks taps
      child: Opacity(
        opacity: disabled ? 0.5 : 1.0,
        child: ListTile(
          leading: Icon(
            icon,
            color: const Color(0xFF2E7D32),
          ),
          title: Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          tileColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          trailing: Icon(
            selected ? Icons.check_circle : Icons.arrow_forward_ios,
            color: selected ? const Color(0xFF2E7D32) : Colors.grey,
            size: selected ? 20 : 16,
          ),
          onTap: () async {
            // ✅ use the callback provided by the caller
            onTap();

            // Keep your post-tap navigation behavior based on "selected"
            if (selected) {
              if (label == "Sick") {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SickScreen()),
                );
              } else {
                _goToMainAttendanceScreen();
              }
            }
          },
        ),
      ),
    );
  }
}
