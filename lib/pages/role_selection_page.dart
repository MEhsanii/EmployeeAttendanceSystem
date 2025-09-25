import 'package:flutter/material.dart';
import 'package:attendence_management_system/pages/loginPage.dart';

enum UserRole { employee, hr, ceo }

class RoleSelectionPage extends StatelessWidget {
  const RoleSelectionPage({super.key});

  static const Color bpgGreen = Color(0xFF2E4A2C); // BPG exact green

  String _getRoleDisplayName(UserRole role) {
    switch (role) {
      case UserRole.ceo:
        return 'CEO';
      case UserRole.hr:
        return 'HR Manager';
      case UserRole.employee:
        return 'Employee';
    }
  }

  IconData _getRoleIcon(UserRole role) {
    switch (role) {
      case UserRole.ceo:
        return Icons.business_center;
      case UserRole.hr:
        return Icons.people_alt;
      case UserRole.employee:
        return Icons.person;
    }
  }

  String _getRoleDescription(UserRole role) {
    switch (role) {
      case UserRole.ceo:
        return 'Full access to all data and approvals';
      case UserRole.hr:
        return 'Manage employees and requests';
      case UserRole.employee:
        return 'Track attendance and apply for leaves';
    }
  }

  void _navigateToLogin(BuildContext context, UserRole role) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LoginPage(selectedRole: role),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: bpgGreen,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: isWeb ? 500 : double.infinity),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/BPGLogo.png',
                    height: 80,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Welcome to BPG',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: bpgGreen,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please select your role to continue',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Role selection cards
                  ...UserRole.values
                      .map((role) => Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 16),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _navigateToLogin(context, role),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: bpgGreen.withOpacity(0.3)),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: bpgGreen.withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Icon(
                                          _getRoleIcon(role),
                                          color: bpgGreen,
                                          size: 28,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _getRoleDisplayName(role),
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: bpgGreen,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _getRoleDescription(role),
                                              style: const TextStyle(
                                                fontSize: 14,
                                                color: Colors.grey,
                                              ),
                                            ),
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
                          ))
                      .toList(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
