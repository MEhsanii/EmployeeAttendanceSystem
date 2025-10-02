import 'package:flutter/material.dart';
import 'package:attendence_management_system/pages/loginPage.dart';
import 'package:attendence_management_system/pages/employee_signup_screen.dart';
import 'package:attendence_management_system/utils/responsive_utils.dart';

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

  void _showInvitationDialog(BuildContext context) {
    final TextEditingController invitationController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.mail, color: Colors.blue, size: 28),
            const SizedBox(width: 12),
            const Text('Join with Invitation'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter your invitation ID to set up your account:',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: invitationController,
              decoration: InputDecoration(
                labelText: 'Invitation ID',
                hintText: 'Enter invitation ID',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(context.w(2)),
                ),
                prefixIcon: const Icon(Icons.key),
              ),
            ),
            SizedBox(height: context.h(2)),
            Container(
              padding: EdgeInsets.all(context.w(3)),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(context.w(2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.blue, size: context.sp(20)),
                  SizedBox(width: context.w(2)),
                  Expanded(
                    child: Text(
                      'This ID was provided by your administrator',
                      style: TextStyle(
                          fontSize: context.sp(12), color: Colors.blue),
                    ),
                  ),
                ],
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
            onPressed: () {
              final invitationId = invitationController.text.trim();
              if (invitationId.isNotEmpty) {
                Navigator.pop(context);
                // Navigate to employee signup screen with invitation ID
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EmployeeSignupScreen(
                      invitationId: invitationId,
                    ),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
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
            constraints: BoxConstraints(
                maxWidth: isWeb ? context.w(120) : double.infinity),
            child: Container(
              padding: EdgeInsets.all(context.w(6)),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(context.w(5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: context.w(3),
                    offset: Offset(0, context.h(0.75)),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/BPGLogo.png',
                    height: context.h(10),
                  ),
                  SizedBox(height: context.h(3)),
                  Text(
                    'Welcome to BPG',
                    style: TextStyle(
                      fontSize: context.sp(22),
                      fontWeight: FontWeight.bold,
                      color: bpgGreen,
                    ),
                  ),
                  SizedBox(height: context.h(1)),
                  Text(
                    'Please select your role to continue',
                    style: TextStyle(
                      fontSize: context.sp(16),
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: context.h(4)),

                  // Role selection cards
                  ...UserRole.values
                      .map((role) => Container(
                            width: double.infinity,
                            margin: EdgeInsets.only(bottom: context.h(2)),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => _navigateToLogin(context, role),
                                borderRadius:
                                    BorderRadius.circular(context.w(3)),
                                child: Container(
                                  padding: EdgeInsets.all(context.w(5)),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: bpgGreen.withOpacity(0.3)),
                                    borderRadius:
                                        BorderRadius.circular(context.w(3)),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(context.w(3)),
                                        decoration: BoxDecoration(
                                          color: bpgGreen.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                              context.w(2.5)),
                                        ),
                                        child: Icon(
                                          _getRoleIcon(role),
                                          color: bpgGreen,
                                          size: context.sp(28),
                                        ),
                                      ),
                                      SizedBox(width: context.w(4)),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _getRoleDisplayName(role),
                                              style: TextStyle(
                                                fontSize: context.sp(18),
                                                fontWeight: FontWeight.bold,
                                                color: bpgGreen,
                                              ),
                                            ),
                                            SizedBox(height: context.h(0.5)),
                                            Text(
                                              _getRoleDescription(role),
                                              style: TextStyle(
                                                fontSize: context.sp(14),
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        color: bpgGreen,
                                        size: context.sp(16),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ))
                      .toList(),

                  // Join with Invitation option
                  SizedBox(height: context.h(1)),
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: context.w(4)),
                        child: Text(
                          'OR',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: context.sp(14),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      Expanded(child: Divider(color: Colors.grey.shade300)),
                    ],
                  ),
                  SizedBox(height: context.h(1)),

                  Container(
                    width: double.infinity,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _showInvitationDialog(context),
                        borderRadius: BorderRadius.circular(context.w(3)),
                        child: Container(
                          padding: EdgeInsets.all(context.w(5)),
                          decoration: BoxDecoration(
                            border:
                                Border.all(color: Colors.blue.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(context.w(3)),
                            color: Colors.blue.withOpacity(0.05),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(context.w(3)),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius:
                                      BorderRadius.circular(context.w(2.5)),
                                ),
                                child: Icon(
                                  Icons.mail,
                                  color: Colors.blue,
                                  size: context.sp(28),
                                ),
                              ),
                              SizedBox(width: context.w(4)),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Join with Invitation',
                                      style: TextStyle(
                                        fontSize: context.sp(18),
                                        fontWeight: FontWeight.bold,
                                        color: Colors.blue,
                                      ),
                                    ),
                                    SizedBox(height: context.h(0.5)),
                                    Text(
                                      'Have an invitation ID? Set up your account here',
                                      style: TextStyle(
                                        fontSize: context.sp(14),
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios,
                                color: Colors.blue,
                                size: context.sp(16),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
