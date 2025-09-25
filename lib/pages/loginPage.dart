import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// ignore: unused_import
import 'package:attendence_management_system/pages/AttendanceScreen.dart';
import 'package:attendence_management_system/pages/work_mode_selection_page.dart';
import 'package:attendence_management_system/pages/role_selection_page.dart';
import 'package:attendence_management_system/pages/ceo_dashboard.dart';
import 'package:attendence_management_system/pages/hr_dashboard.dart';

class LoginPage extends StatefulWidget {
  final UserRole selectedRole;

  const LoginPage({super.key, required this.selectedRole});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isObscure = true;
  bool _isLoading = false;

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

  String _getRoleString(UserRole role) {
    switch (role) {
      case UserRole.ceo:
        return 'ceo';
      case UserRole.hr:
        return 'hr';
      case UserRole.employee:
        return 'employee';
    }
  }

  Future<void> signIn() async {
    setState(() => _isLoading = true);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // Check user role in Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .get();

      String? userRole;
      if (userDoc.exists) {
        userRole = userDoc.data()?['role'] as String?;
      }

      // Validate if the user's role matches the selected role
      final expectedRole = _getRoleString(widget.selectedRole);

      if (userRole?.toLowerCase() != expectedRole) {
        // Sign out the user since role doesn't match
        await FirebaseAuth.instance.signOut();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'No ${_getRoleDisplayName(widget.selectedRole)} found with these credentials.'),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      // Role matches, navigate to appropriate screen
      if (context.mounted) {
        Widget nextPage;
        switch (widget.selectedRole) {
          case UserRole.ceo:
            nextPage = const CEODashboard();
            break;
          case UserRole.hr:
            nextPage = const HRDashboard();
            break;
          case UserRole.employee:
            nextPage = const WorkModeSelectionPage();
            break;
        }

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => nextPage),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login Failed: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 600;

    return Scaffold(
      backgroundColor: bpgGreen,
      appBar: AppBar(
        backgroundColor: bpgGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _getRoleDisplayName(widget.selectedRole),
          style: const TextStyle(color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints:
                BoxConstraints(maxWidth: isWeb ? 400 : double.infinity),
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
                  Text(
                    'Login as ${_getRoleDisplayName(widget.selectedRole)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: bpgGreen,
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Email field
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      prefixIcon: const Icon(Icons.email_outlined),
                      labelStyle: const TextStyle(color: bpgGreen),
                      prefixIconColor: bpgGreen,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: bpgGreen),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: bpgGreen, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 20),

                  // Password field
                  TextField(
                    controller: _passwordController,
                    obscureText: _isObscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isObscure ? Icons.visibility_off : Icons.visibility,
                          color: bpgGreen,
                        ),
                        onPressed: () {
                          setState(() {
                            _isObscure = !_isObscure;
                          });
                        },
                      ),
                      labelStyle: const TextStyle(color: bpgGreen),
                      prefixIconColor: bpgGreen,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: bpgGreen),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: bpgGreen, width: 2),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 30),

                  // Login button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : signIn,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: bpgGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            )
                          : const Text(
                              'Login',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                letterSpacing: 1,
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
