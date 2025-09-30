import 'package:attendence_management_system/pages/AttendanceScreen.dart';
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
              "🎉 Happy ${_todayHolidayName ?? 'Holiday'}! Enjoy your day off!",
              style: const TextStyle(fontSize: 16),
            ),
            backgroundColor: const Color(0xFF2E7D32),
            duration: const Duration(seconds: 3),
          ),
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
    // If a mode is already selected, taps only navigate and do NOT change mode.
    if (_selectedWorkMode != null) {
      if (mode == "Sick") {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SickScreen()),
        );
      } else if (mode == "Office") {
        _goToMainAttendanceScreen();
      }
      return;
    }

    // Initial selection when nothing is chosen yet: persist then navigate.
    await _saveWorkMode(context, mode);

    if (mode == "Sick") {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const SickScreen()),
      );
    } else if (mode == "Office") {
      _goToMainAttendanceScreen();
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
    // final today = DateTime(DateTime.now().year, 1, 1);
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
                                  "🎉 Happy ${_todayHolidayName ?? 'Holiday'}! 🎉\nEnjoy your day off!",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
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
            _buildWorkModeCard(
              label:
                  _selectedWorkMode == "Home Office" ? "Home Office" : "Office",
              icon: _selectedWorkMode == "Home Office"
                  ? Icons.home_work
                  : Icons.apartment,
              workMode: "Office",
              disabled: disableAllWorkTiles,
            ),
            const SizedBox(height: 8),
            _buildWorkModeCard(
              label: "Sick",
              icon: Icons.sick,
              workMode: "Sick",
              disabled: disableAllWorkTiles,
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Leave - Sick only
        _expansionCard(
          title: "Requests",
          icon: Icons.event_available_outlined,
          initiallyExpanded: _expLeave,
          onChanged: (v) {
            setState(() => _expLeave = v);
            _saveExpansionState();
          },
          children: [
            _buildMenuTile(
              label: "Request Home Office",
              icon: Icons.home_work,
              disabled: false,
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

  Widget _buildWorkModeCard({
    required String label,
    required IconData icon,
    required String workMode,
    bool disabled = false,
  }) {
    final isSelected = (workMode == "Office" &&
            (_selectedWorkMode == "Office" ||
                _selectedWorkMode == "Home Office")) ||
        (workMode == "Sick" && _selectedWorkMode == "Sick");
    final canSelectHomeOffice = workMode == "Office" &&
        _homeOfficeApprovedToday &&
        _selectedWorkMode == null;

    return IgnorePointer(
      ignoring: disabled,
      child: Opacity(
        opacity: disabled ? 0.5 : 1.0,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            leading: Icon(
              icon,
              color:
                  isSelected ? const Color(0xFF2E7D32) : Colors.grey.shade600,
              size: 28,
            ),
            title: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isSelected ? const Color(0xFF2E7D32) : Colors.black87,
                fontSize: 16,
              ),
            ),
            subtitle: canSelectHomeOffice
                ? const Text(
                    "Home office available",
                    style: TextStyle(
                      color: Color(0xFF2E7D32),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : null,
            trailing: isSelected
                ? const Icon(
                    Icons.check_circle,
                    color: Color(0xFF2E7D32),
                    size: 24,
                  )
                : const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.grey,
                    size: 16,
                  ),
            onTap: () => _handleWorkModeSelection(workMode),
            onLongPress: () async {
              // Long-press lets user update mode later on
              if (workMode == "Office") {
                await _saveWorkMode(context, "Office");
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Work mode set to Office')),
                );
              } else if (workMode == "Sick") {
                // Set Sick without navigation; tap will navigate
                if (_selectedWorkMode != "Sick") {
                  await _saveWorkMode(context, "Sick");
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Work mode set to Sick')),
                  );
                }
              }
            },
          ),
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
      ignoring: disabled,
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
          onTap: onTap,
        ),
      ),
    );
  }
}
