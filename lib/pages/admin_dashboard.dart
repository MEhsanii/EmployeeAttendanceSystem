import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:attendence_management_system/pages/role_selection_page.dart';
import 'package:attendence_management_system/pages/employee_history_screen.dart';
import 'package:attendence_management_system/pages/add_employee_screen.dart';
import 'package:attendence_management_system/pages/announcements.dart';
import 'package:attendence_management_system/pages/AttendanceScreen.dart';
import 'package:attendence_management_system/pages/sick.dart';
import 'package:attendence_management_system/pages/vacation.dart';
import 'package:attendence_management_system/pages/home_office.dart';
import 'package:attendence_management_system/utils/responsive_utils.dart';

class AdminDashboard extends StatefulWidget {
  final String userRole; // 'ceo' or 'hr'

  const AdminDashboard({super.key, required this.userRole});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  static const Color bpgGreen = Color(0xFF2E4A2C);
  String? _userName;
  bool _isLoadingName = true;
  String? _currentWorkMode;
  bool _homeOfficeApprovedToday = false;

  bool get isCEO => widget.userRole.toLowerCase() == 'ceo';

  String get dashboardTitle => isCEO ? 'CEO Dashboard' : 'HR Dashboard';
  String get welcomeTitle => isCEO ? 'CEO Portal' : 'HR Manager Portal';
  IconData get dashboardIcon =>
      isCEO ? Icons.business_center : Icons.people_alt;

  String get description => isCEO
      ? 'You have full access to all employee data and can approve pending requests.'
      : 'Manage employee attendance, leave requests, and HR operations.';

  @override
  void initState() {
    super.initState();
    _loadUserName();
    if (!isCEO) {
      _fetchTodayWorkMode();
      _checkHomeOfficeApproval();
    }
  }

  Future<void> _loadUserName() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (doc.exists) {
          final data = doc.data();
          final userName = data?['userName'] as String?;
          setState(() {
            _userName = userName;
            _isLoadingName = false;
          });
        } else {
          setState(() {
            _userName = user.displayName;
            _isLoadingName = false;
          });
        }
      } else {
        setState(() {
          _userName = 'Admin';
          _isLoadingName = false;
        });
      }
    } catch (e) {
      setState(() {
        _userName = 'Admin';
        _isLoadingName = false;
      });
    }
  }

  Future<void> _fetchTodayWorkMode() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('attendance')
          .doc(dateKey)
          .get();

      if (doc.exists && mounted) {
        setState(() {
          _currentWorkMode = doc.data()?['workMode'] as String?;
        });
      }
    } catch (e) {
      print('Error fetching work mode: $e');
    }
  }

  Future<void> _checkHomeOfficeApproval() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final now = DateTime.now();
    final dateId =
        "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";

    try {
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
    }
  }

  Future<void> _changeWorkMode() async {
    if (isCEO) return; // CEO doesn't mark attendance

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final now = DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Build options list
    List<String> options = ['Office'];
    if (_homeOfficeApprovedToday) {
      options.add('Home Office');
    }
    options.add('Sick');

    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Change Work Mode',
            style: TextStyle(fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((mode) {
            final isSelected = mode == _currentWorkMode ||
                (mode == 'Office' && _currentWorkMode == 'Home Office');
            return ListTile(
              leading: Icon(
                mode == 'Office' || mode == 'Home Office'
                    ? (mode == 'Home Office'
                        ? Icons.home_work
                        : Icons.apartment)
                    : Icons.sick,
                color: isSelected ? bpgGreen : Colors.grey,
              ),
              title: Text(mode),
              trailing:
                  isSelected ? const Icon(Icons.check, color: bpgGreen) : null,
              onTap: () => Navigator.pop(context, mode),
            );
          }).toList(),
        ),
      ),
    );

    if (selected == null) return;

    try {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('attendance')
          .doc(dateKey);

      await docRef.set({
        'workMode': selected,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _currentWorkMode = selected;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Work mode changed to $selected'),
            backgroundColor: bpgGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _openRequestsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const _AdminRequestsPage(),
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

  void _navigateToAddEmployee() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddEmployeeScreen(),
      ),
    );
  }

  void _navigateToAnnouncements() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AnnouncementsPage(),
      ),
    );
  }

  void _navigateToAttendance() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MainAttendanceScreen(),
      ),
    );
  }

  void _navigateToSickLeave() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SickScreen(),
      ),
    );
  }

  void _navigateToVacation() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const VacationScreen(),
      ),
    );
  }

  void _navigateToHomeOffice() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const HomeOfficeRequestPage(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          dashboardTitle,
          style: TextStyle(
              color: Colors.white,
              fontSize: context.sp(18),
              fontWeight: FontWeight.bold),
        ),
        backgroundColor: bpgGreen,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert,
                color: Colors.white, size: context.sp(24)),
            onSelected: (value) {
              if (value == 'logout') {
                _signOut();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: context.sp(20)),
                    SizedBox(width: context.w(2)),
                    Text(user?.email ?? 'Profile',
                        style: TextStyle(fontSize: context.sp(14))),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.red, size: context.sp(20)),
                    SizedBox(width: context.w(2)),
                    Text('Logout',
                        style: TextStyle(
                            color: Colors.red, fontSize: context.sp(14))),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF30492D), Color(0xFF4CAF50)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Header Section
                Container(
                  padding: EdgeInsets.all(context.w(6)),
                  child: Container(
                    padding: EdgeInsets.all(context.w(5)),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(context.w(4)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: context.w(2),
                          offset: Offset(0, context.h(0.5)),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Top row with portal title and requests button
                        Row(
                          children: [
                            Icon(
                              dashboardIcon,
                              size: context.sp(40),
                              color: bpgGreen,
                            ),
                            SizedBox(width: context.w(4)),
                            Expanded(
                              child: Text(
                                welcomeTitle,
                                style: TextStyle(
                                  fontSize: context.w(4.5),
                                  fontWeight: FontWeight.bold,
                                  color: bpgGreen,
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _openRequestsPage,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: bpgGreen,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                    horizontal: context.w(4),
                                    vertical: context.h(1.5)),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(context.w(3)),
                                ),
                                elevation: 2,
                              ),
                              icon: Icon(
                                Icons.inbox_rounded,
                                size: context.h(2),
                                color: Color(0xFF4CAF50),
                              ),
                              label: Text('Requests',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: context.h(1.7))),
                            ),
                          ],
                        ),
                        SizedBox(height: context.h(2)),
                        // Full-width description section
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _isLoadingName
                                      ? 'Welcome, Loading...!'
                                      : 'Welcome, ${_userName ?? 'Admin'}!',
                                  style: TextStyle(
                                    fontSize: context.sp(16),
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: context.h(1)),
                            Text(
                              description,
                              style: TextStyle(
                                fontSize: context.sp(14),
                                color: Colors.grey,
                                height: 1.4,
                              ),
                            ),
                            // Work mode indicator for HR
                            if (!isCEO && _currentWorkMode != null) ...[
                              SizedBox(height: context.h(1.5)),
                              InkWell(
                                onTap: _changeWorkMode,
                                borderRadius:
                                    BorderRadius.circular(context.w(2)),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: context.w(3),
                                      vertical: context.h(1)),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: _currentWorkMode == 'Sick'
                                          ? [
                                              Colors.red.shade400,
                                              Colors.red.shade600
                                            ]
                                          : (_currentWorkMode == 'Home Office'
                                              ? [
                                                  Colors.green.shade400,
                                                  Colors.green.shade600
                                                ]
                                              : [
                                                  Colors.blue.shade400,
                                                  Colors.blue.shade600
                                                ]),
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius:
                                        BorderRadius.circular(context.w(2)),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (_currentWorkMode == 'Sick'
                                                ? Colors.red
                                                : (_currentWorkMode ==
                                                        'Home Office'
                                                    ? Colors.green
                                                    : Colors.blue))
                                            .withOpacity(0.3),
                                        blurRadius: context.w(2),
                                        offset: Offset(0, context.h(0.4)),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _currentWorkMode == 'Sick'
                                            ? Icons.sick
                                            : (_currentWorkMode == 'Home Office'
                                                ? Icons.home_work
                                                : Icons.apartment),
                                        color: Colors.white,
                                        size: context.sp(18),
                                      ),
                                      SizedBox(width: context.w(2)),
                                      Text(
                                        'Today: $_currentWorkMode',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: context.sp(14),
                                        ),
                                      ),
                                      SizedBox(width: context.w(1)),
                                      Icon(
                                        Icons.edit,
                                        color: Colors.white,
                                        size: context.sp(14),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Quick Actions Section
                Container(
                  margin: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: isCEO
                      ? Row(
                          children: [
                            Expanded(
                              child: _buildQuickActionCard(
                                title: 'Announcements',
                                subtitle: 'View & Manage Posts',
                                icon: Icons.campaign,
                                color: Colors.orange,
                                onTap: _navigateToAnnouncements,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildQuickActionCard(
                                title: 'Add Employee',
                                subtitle: 'Register New Staff',
                                icon: Icons.person_add,
                                color: Colors.blue,
                                onTap: _navigateToAddEmployee,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            // First row - 3 buttons
                            Row(
                              children: [
                                Expanded(
                                  child: _buildCompactActionCard(
                                    title: 'Announcements',
                                    icon: Icons.campaign,
                                    color: Colors.orange,
                                    onTap: _navigateToAnnouncements,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildCompactActionCard(
                                    title: 'Mark Attendance',
                                    icon: Icons.access_time_filled,
                                    color: Colors.green,
                                    onTap: _navigateToAttendance,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildCompactActionCard(
                                    title: 'Sick Leave',
                                    icon: Icons.sick,
                                    color: Colors.red,
                                    onTap: _navigateToSickLeave,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Second row - 2 buttons
                            Row(
                              children: [
                                Expanded(
                                  child: _buildCompactActionCard(
                                    title: 'Apply Vacation',
                                    icon: Icons.flight_takeoff,
                                    color: Colors.purple,
                                    onTap: _navigateToVacation,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildCompactActionCard(
                                    title: 'Home Office',
                                    icon: Icons.home_work,
                                    color: Colors.teal,
                                    onTap: _navigateToHomeOffice,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),

                // Employees Section
                Container(
                  margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'All Employees',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: bpgGreen,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildEmployeesList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: bpgGreen,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: bpgGreen,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Text('Error: ${snapshot.error}'),
          );
        }

        final employees = snapshot.data?.docs ?? [];

        if (employees.isEmpty) {
          return const Center(
            child: Text(
              'No employees found',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: employees.map((employee) {
            final data = employee.data() as Map<String, dynamic>;
            return _buildEmployeeTile(
              context,
              employeeId: employee.id,
              role: data['role'] ?? 'employee',
              userName: data['userName'] ?? 'Unknown User',
              designation: data['designation'] ?? 'No designation',
              email: data['email'] ?? '',
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildEmployeeTile(
    BuildContext context, {
    required String employeeId,
    required String role,
    required String userName,
    required String designation,
    required String email,
  }) {
    IconData roleIcon;
    Color roleColor;

    switch (role.toLowerCase()) {
      case 'ceo':
        roleIcon = Icons.business_center;
        roleColor = Colors.purple;
        break;
      case 'hr':
        roleIcon = Icons.people_alt;
        roleColor = Colors.blue;
        break;
      case 'employee':
      default:
        roleIcon = Icons.person;
        roleColor = Colors.green;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => EmployeeHistoryScreen(
                  employeeId: employeeId,
                  employeeName: userName,
                  employeeEmail: email,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: bpgGreen.withOpacity(0.2)),
              borderRadius: BorderRadius.circular(12),
              color: Colors.grey.shade50,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: roleColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    roleIcon,
                    color: roleColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: bpgGreen,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: roleColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              role.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: roleColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              designation,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: bpgGreen,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Lightweight internal page to host the requests tabs without creating a separate file
class _AdminRequestsPage extends StatefulWidget {
  const _AdminRequestsPage();
  @override
  State<_AdminRequestsPage> createState() => _AdminRequestsPageState();
}

class _AdminRequestsPageState extends State<_AdminRequestsPage>
    with SingleTickerProviderStateMixin {
  static const Color bpgGreen = Color(0xFF2E4A2C);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8F9FA),
        appBar: AppBar(
          title: const Text('Employee Requests',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: bpgGreen,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            unselectedLabelStyle:
                const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.hourglass_empty, size: 18),
                    const SizedBox(width: 6),
                    const Text('Pending'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, size: 18),
                    const SizedBox(width: 6),
                    const Text('Approved'),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cancel, size: 18),
                    const SizedBox(width: 6),
                    const Text('Declined'),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CombinedRequestsTab(filter: 'pending'),
            _CombinedRequestsTab(filter: 'approved'),
            _CombinedRequestsTab(filter: 'rejected'),
          ],
        ),
      ),
    );
  }
}

class _CombinedRequestsTab extends StatelessWidget {
  final String filter; // 'pending' | 'approved' | 'rejected'
  const _CombinedRequestsTab({required this.filter});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Home Office Requests Section
          Row(
            children: [
              Icon(Icons.home_work, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Home Office Requests',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _HomeOfficeRequestsList(filter: filter),

          const SizedBox(height: 24),

          // Vacation Requests Section
          Row(
            children: [
              Icon(Icons.flight_takeoff,
                  color: Colors.green.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Vacation Requests',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _VacationRequestsList(filter: filter),
        ],
      ),
    );
  }
}

class _HomeOfficeRequestsList extends StatelessWidget {
  final String filter;
  const _HomeOfficeRequestsList({required this.filter});

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date).inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'yesterday';
    if (diff < 7) return '$diff days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final base = FirebaseFirestore.instance.collection('homeOfficeRequests');
    final query = base.orderBy('createdAt', descending: true).limit(100);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snap.data?.docs ?? [];
        final filtered = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final Map<String, dynamic> statusByDate =
              Map<String, dynamic>.from(data['statusByDate'] ?? {});
          return statusByDate.values
              .any((v) => v.toString().toLowerCase() == filter.toLowerCase());
        }).toList();

        if (filtered.isEmpty) {
          return Container(
            height: 80,
            alignment: Alignment.center,
            child: Text(
              'No $filter home office requests',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          );
        }

        return Column(
          children: filtered.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final userEmail = data['userEmail'] ?? '';
            final requestedDates =
                List<String>.from(data['requestedDates'] ?? const []);
            final Map<String, dynamic> statusByDate =
                Map<String, dynamic>.from(data['statusByDate'] ?? {});
            final Map<String, dynamic> reviewsByDate =
                Map<String, dynamic>.from(data['reviewsByDate'] ?? {});
            final employeeNote = (data['note'] ?? '').toString();
            final shownDates =
                requestedDates.where((d) => statusByDate[d] == filter).toList();
            final createdAt = data['createdAt'] as Timestamp?;

            Color statusColor = filter == 'approved'
                ? Colors.green
                : filter == 'rejected'
                    ? Colors.red
                    : Colors.orange;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ExpansionTile(
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child:
                      const Icon(Icons.home_work, color: Colors.blue, size: 18),
                ),
                title: Text(
                  userEmail.isEmpty ? 'Home Office Request' : userEmail,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      '${shownDates.length} day(s) • ${filter.toUpperCase()}',
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                          fontSize: 12),
                    ),
                    if (createdAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Requested ${_formatDate(createdAt.toDate())}',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 11),
                      ),
                    ],
                  ],
                ),
                children: [
                  if (employeeNote.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Employee Note:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            employeeNote,
                            style: TextStyle(
                                color: Colors.blue.shade800, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Show reviewer info for non-pending home office requests
                  if (filter != 'pending') ...[
                    for (final dateId in shownDates)
                      if (reviewsByDate[dateId] != null &&
                          reviewsByDate[dateId]['byName'] != null) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    filter == 'approved'
                                        ? Icons.check_circle
                                        : Icons.cancel,
                                    size: 16,
                                    color: filter == 'approved'
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$dateId - Reviewed by ${reviewsByDate[dateId]['byName']}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.grey.shade700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              if (reviewsByDate[dateId]['note'] != null &&
                                  reviewsByDate[dateId]['note']
                                      .toString()
                                      .isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  reviewsByDate[dateId]['note'].toString(),
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              if (reviewsByDate[dateId]['decidedAt'] !=
                                  null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'on ${DateFormat('MMM d, yyyy').format((reviewsByDate[dateId]['decidedAt'] as Timestamp).toDate())}',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    const SizedBox(height: 12),
                  ],

                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final d in shownDates)
                        _DecisionChip(
                          requestId: doc.id,
                          dateId: d,
                          currentStatus: statusByDate[d] ?? 'pending',
                          review:
                              Map<String, dynamic>.from(reviewsByDate[d] ?? {}),
                        ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _VacationRequestsList extends StatelessWidget {
  final String filter;
  const _VacationRequestsList({required this.filter});

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date).inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'yesterday';
    if (diff < 7) return '$diff days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final base = FirebaseFirestore.instance.collection('vacationRequests');
    final query = base.orderBy('createdAt', descending: true).limit(100);

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 100,
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final docs = snap.data?.docs ?? [];
        final filtered = docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final status = (data['status'] ?? 'pending').toString().toLowerCase();
          return status == filter.toLowerCase();
        }).toList();

        if (filtered.isEmpty) {
          return Container(
            height: 80,
            alignment: Alignment.center,
            child: Text(
              'No $filter vacation requests',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          );
        }

        return Column(
          children: filtered.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final userEmail = data['userEmail'] ?? '';
            final employeeNote = (data['note'] ?? '').toString();
            final createdAt = data['createdAt'] as Timestamp?;
            final startDate = (data['startDate'] as Timestamp?)?.toDate();
            final endDate = (data['endDate'] as Timestamp?)?.toDate();
            final businessDays = data['businessDays'] ?? 0;

            Color statusColor = filter == 'approved'
                ? Colors.green
                : filter == 'rejected'
                    ? Colors.red
                    : Colors.orange;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ExpansionTile(
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                leading: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.flight_takeoff,
                      color: Colors.green, size: 18),
                ),
                title: Text(
                  userEmail.isEmpty ? 'Vacation Request' : userEmail,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 14),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    if (startDate != null && endDate != null)
                      Text(
                        '${DateFormat('MMM d').format(startDate)} - ${DateFormat('MMM d, yyyy').format(endDate)} ($businessDays days)',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      filter.toUpperCase(),
                      style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.w500,
                          fontSize: 12),
                    ),
                    if (createdAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Requested ${_formatDate(createdAt.toDate())}',
                        style: TextStyle(
                            color: Colors.grey.shade600, fontSize: 11),
                      ),
                    ],
                  ],
                ),
                children: [
                  if (employeeNote.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Employee Note:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.green.shade700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            employeeNote,
                            style: TextStyle(
                                color: Colors.green.shade800, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Show reviewer info if request was reviewed
                  if (filter != 'pending' &&
                      data['reviewedByName'] != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                filter == 'approved'
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                size: 16,
                                color: filter == 'approved'
                                    ? Colors.green
                                    : Colors.red,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Reviewed by ${data['reviewedByName']}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          if (data['reviewNote'] != null &&
                              data['reviewNote'].toString().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              data['reviewNote'].toString(),
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (data['reviewedAt'] != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'on ${DateFormat('MMM d, yyyy').format((data['reviewedAt'] as Timestamp).toDate())}',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  _VacationDecisionChip(
                    requestId: doc.id,
                    currentStatus: filter,
                    requestData: data,
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _VacationDecisionChip extends StatefulWidget {
  final String requestId;
  final String currentStatus;
  final Map<String, dynamic> requestData;

  const _VacationDecisionChip({
    required this.requestId,
    required this.currentStatus,
    required this.requestData,
  });

  @override
  State<_VacationDecisionChip> createState() => _VacationDecisionChipState();
}

class _VacationDecisionChipState extends State<_VacationDecisionChip> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.currentStatus == 'approved'
        ? Colors.green
        : widget.currentStatus == 'rejected'
            ? Colors.red
            : Colors.orange;

    final startDate = (widget.requestData['startDate'] as Timestamp?)?.toDate();
    final endDate = (widget.requestData['endDate'] as Timestamp?)?.toDate();
    final dateRange = (startDate != null && endDate != null)
        ? '${DateFormat('MMM d').format(startDate)} - ${DateFormat('MMM d').format(endDate)}'
        : 'Vacation Request';

    // Check if vacation dates have passed (disable status changes)
    final today = DateTime.now();
    final isExpired = startDate != null && startDate.isBefore(today);

    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _isLoading || isExpired
            ? null
            : () async {
                setState(() => _isLoading = true);
                try {
                  await _showVacationDecisionDialog(context, widget.requestId,
                      dateRange, widget.currentStatus);
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLoading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              else
                Icon(
                  widget.currentStatus == 'approved'
                      ? Icons.check_circle
                      : widget.currentStatus == 'rejected'
                          ? Icons.cancel
                          : Icons.hourglass_empty,
                  color: color,
                  size: 18,
                ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateRange,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isExpired ? Colors.grey : color,
                      fontSize: 12,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        widget.currentStatus.toUpperCase(),
                        style: TextStyle(
                          color: isExpired ? Colors.grey : color,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (isExpired) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(EXPIRED)',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 9,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _showVacationDecisionDialog(BuildContext context,
      String requestId, String dateRange, String currentStatus) async {
    final controller = TextEditingController();
    final result = await showDialog<_DecisionResult>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.flight_takeoff, color: Colors.green),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Review Vacation Request',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(dateRange,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add a note (optional):',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Reason for approval/rejection...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.green, width: 2),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                  context, _DecisionResult('rejected', controller.text.trim())),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Decline'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                  context, _DecisionResult('approved', controller.text.trim())),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Approve'),
            ),
          ],
        );
      },
    );
    if (result == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // resolve reviewer display name once (outside transaction)
    String? reviewerName;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data();
      reviewerName = (data != null ? (data['userName'] as String?) : null) ??
          user.displayName;
    } catch (_) {}

    final docRef = FirebaseFirestore.instance
        .collection('vacationRequests')
        .doc(requestId);
    await docRef.update({
      'status': result.status,
      'reviewedBy': user.uid,
      'reviewedByName': reviewerName,
      'reviewNote': result.note,
      'reviewedAt': FieldValue.serverTimestamp(),
    });
  }
}

class _DecisionChip extends StatefulWidget {
  final String requestId;
  final String dateId;
  final String currentStatus; // pending|approved|rejected
  final Map<String, dynamic> review; // {by, byName, note, decidedAt}

  const _DecisionChip({
    required this.requestId,
    required this.dateId,
    required this.currentStatus,
    required this.review,
  });

  @override
  State<_DecisionChip> createState() => _DecisionChipState();
}

class _DecisionChipState extends State<_DecisionChip> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.currentStatus == 'approved'
        ? Colors.green
        : widget.currentStatus == 'rejected'
            ? Colors.red
            : Colors.orange;

    // Check if date has passed (disable status changes)
    final requestDate = DateTime.tryParse(widget.dateId);
    final today = DateTime.now();
    final isExpired = requestDate != null &&
        DateTime(requestDate.year, requestDate.month, requestDate.day)
            .isBefore(DateTime(today.year, today.month, today.day));

    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _isLoading || isExpired
            ? null
            : () async {
                setState(() => _isLoading = true);
                try {
                  await _showDecisionDialog(context, widget.requestId,
                      widget.dateId, widget.currentStatus);
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLoading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                )
              else
                Icon(
                  widget.currentStatus == 'approved'
                      ? Icons.check_circle
                      : widget.currentStatus == 'rejected'
                          ? Icons.cancel
                          : Icons.hourglass_empty,
                  color: color,
                  size: 18,
                ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.dateId,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isExpired ? Colors.grey : color,
                      fontSize: 14,
                    ),
                  ),
                  Row(
                    children: [
                      Text(
                        widget.currentStatus.toUpperCase(),
                        style: TextStyle(
                          color: isExpired ? Colors.grey : color,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (isExpired) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(EXPIRED)',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 9,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _showDecisionDialog(BuildContext context,
      String requestId, String dateId, String currentStatus) async {
    final controller = TextEditingController();
    final result = await showDialog<_DecisionResult>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.event_note, color: Colors.blue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Review Request',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600)),
                    Text(dateId,
                        style: TextStyle(
                            fontSize: 14, color: Colors.grey.shade600)),
                  ],
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add a note (optional):',
                  style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Reason for approval/rejection...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.blue, width: 2),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                  context, _DecisionResult('rejected', controller.text.trim())),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Decline'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => Navigator.pop(
                  context, _DecisionResult('approved', controller.text.trim())),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Approve'),
            ),
          ],
        );
      },
    );
    if (result == null) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // resolve reviewer display name once (outside transaction)
    String? reviewerName;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data();
      reviewerName = (data != null ? (data['userName'] as String?) : null) ??
          user.displayName;
    } catch (_) {}

    final docRef = FirebaseFirestore.instance
        .collection('homeOfficeRequests')
        .doc(requestId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      final data = snap.data() ?? {};
      final Map<String, dynamic> statusByDate =
          Map<String, dynamic>.from(data['statusByDate'] ?? {});
      final Map<String, dynamic> reviewsByDate =
          Map<String, dynamic>.from(data['reviewsByDate'] ?? {});
      statusByDate[dateId] = result.status;
      reviewsByDate[dateId] = {
        'by': user.uid,
        'byEmail': user.email,
        'byName': reviewerName,
        'note': result.note,
        'decidedAt': FieldValue.serverTimestamp(),
      };
      tx.update(docRef, {
        'statusByDate': statusByDate,
        'reviewsByDate': reviewsByDate,
      });

      // mirror to user's subcollection if exists
      final userId = data['userId'] as String?;
      if (userId != null) {
        final userDoc = FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('homeOfficeRequests')
            .doc(requestId);
        tx.update(userDoc, {
          'statusByDate': statusByDate,
          'reviewsByDate': reviewsByDate,
        });
      }
    });
  }
}

class _DecisionResult {
  final String status; // approved|rejected
  final String note;
  _DecisionResult(this.status, this.note);
}
