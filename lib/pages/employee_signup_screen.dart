import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendence_management_system/pages/work_mode_selection_page.dart';
import 'package:attendence_management_system/pages/role_selection_page.dart';

class EmployeeSignupScreen extends StatefulWidget {
  final String invitationId;

  const EmployeeSignupScreen({super.key, required this.invitationId});

  @override
  State<EmployeeSignupScreen> createState() => _EmployeeSignupScreenState();
}

class _EmployeeSignupScreenState extends State<EmployeeSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isLoading = false;
  bool _isObscure1 = true;
  bool _isObscure2 = true;

  Map<String, dynamic>? _invitationData;

  static const Color bpgGreen = Color(0xFF2E4A2C);

  @override
  void initState() {
    super.initState();
    _loadInvitationData();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadInvitationData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('employeeInvitations')
          .doc(widget.invitationId)
          .get();

      if (!doc.exists) {
        if (mounted) {
          _showErrorAndNavigateBack('Invitation not found or has expired');
        }
        return;
      }

      final data = doc.data()!;
      final expiresAt = data['expiresAt'] as Timestamp?;
      final status = data['status'] as String?;

      if (status != 'pending') {
        if (mounted) {
          _showErrorAndNavigateBack('This invitation has already been used');
        }
        return;
      }

      if (expiresAt != null && expiresAt.toDate().isBefore(DateTime.now())) {
        if (mounted) {
          _showErrorAndNavigateBack('This invitation has expired');
        }
        return;
      }

      setState(() {
        _invitationData = data;
      });
    } catch (e) {
      if (mounted) {
        _showErrorAndNavigateBack('Error loading invitation: ${e.toString()}');
      }
    }
  }

  void _showErrorAndNavigateBack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const RoleSelectionPage()),
    );
  }

  Future<void> _completeSignup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final email = _invitationData!['email'] as String;

      // Create Firebase Auth user
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: _passwordController.text.trim(),
      );

      final user = credential.user;
      if (user == null) {
        throw Exception('Failed to create user account');
      }

      // Save user data to Firestore
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'userName': _invitationData!['userName'],
        'email': email,
        'role': _invitationData!['role'],
        'designation': _invitationData!['designation'],
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': _invitationData!['createdBy'],
        'invitationAcceptedAt': FieldValue.serverTimestamp(),
      });

      // Mark invitation as accepted
      await FirebaseFirestore.instance
          .collection('employeeInvitations')
          .doc(widget.invitationId)
          .update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'acceptedByUid': user.uid,
        'acceptedByEmail': email,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created successfully! Welcome aboard!'),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate to employee dashboard
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const WorkModeSelectionPage()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error creating account: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_invitationData == null) {
      return Scaffold(
        backgroundColor: bpgGreen,
        body: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Scaffold(
      backgroundColor: bpgGreen,
      appBar: AppBar(
        title: const Text(
          'Complete Your Registration',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: bpgGreen,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
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
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/BPGLogo.png',
                    height: 60,
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'Welcome, ${_invitationData!['userName']}!',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: bpgGreen,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'You\'ve been invited as ${_invitationData!['role'].toString().toUpperCase()} - ${_invitationData!['designation']}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _invitationData!['email'],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: bpgGreen,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Password field
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _isObscure1,
                    decoration: InputDecoration(
                      labelText: 'Create Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isObscure1 ? Icons.visibility_off : Icons.visibility,
                          color: bpgGreen,
                        ),
                        onPressed: () {
                          setState(() {
                            _isObscure1 = !_isObscure1;
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
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please create a password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Confirm Password field
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _isObscure2,
                    decoration: InputDecoration(
                      labelText: 'Confirm Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isObscure2 ? Icons.visibility_off : Icons.visibility,
                          color: bpgGreen,
                        ),
                        onPressed: () {
                          setState(() {
                            _isObscure2 = !_isObscure2;
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
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 30),

                  // Complete Registration button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _completeSignup,
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
                              'Complete Registration',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
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
