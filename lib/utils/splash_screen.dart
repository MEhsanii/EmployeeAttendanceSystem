import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:attendence_management_system/utils/responsive_utils.dart';

import '../pages/role_selection_page.dart';
import '../pages/work_mode_selection_page.dart';
import '../pages/admin_dashboard.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutExpo,
    );

    _controller.forward();
    _navigateBasedOnAuth();
  }

  Future<void> _navigateBasedOnAuth() async {
    // Keep the splash visible briefly for the animation/logo
    await Future.delayed(const Duration(seconds: 3));

    final user = FirebaseAuth.instance.currentUser;

    if (!mounted) return;

    if (user == null) {
      // No user logged in, go to role selection
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RoleSelectionPage()),
      );
      return;
    }

    // User is logged in, check their role and navigate accordingly
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      String? userRole;
      if (userDoc.exists) {
        userRole = userDoc.data()?['role'] as String?;
      }

      if (!mounted) return;

      Widget nextPage;
      switch (userRole?.toLowerCase()) {
        case 'ceo':
          nextPage = const AdminDashboard(userRole: 'ceo');
          break;
        case 'hr':
          nextPage = const AdminDashboard(userRole: 'hr');
          break;
        case 'employee':
        default:
          nextPage = const WorkModeSelectionPage();
          break;
      }

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => nextPage),
      );
    } catch (e) {
      // If there's an error getting the role, default to role selection
      print('Error getting user role: $e');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const RoleSelectionPage()),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2E4A2C),
      body: Center(
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/BPGLogo.png',
                height: context.h(22),
              ),
              SizedBox(height: context.h(7.5)),
              CircularProgressIndicator(
                color: Colors.white70,
                strokeWidth: context.w(0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
