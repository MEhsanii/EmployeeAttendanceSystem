import 'package:flutter/material.dart';

/// Responsive utility extension to make the app responsive across all screen sizes
extension ResponsiveUtils on BuildContext {
  /// Get screen height
  double get height => MediaQuery.of(this).size.height;

  /// Get screen width
  double get width => MediaQuery.of(this).size.width;

  /// Get responsive height (percentage of screen height)
  double h(double percentage) => height * (percentage / 100);

  /// Get responsive width (percentage of screen width)
  double w(double percentage) => width * (percentage / 100);

  /// Get responsive font size based on screen width
  double sp(double size) =>
      width * (size / 414); // 414 is base width (iPhone 11 Pro)

  /// Check if device is tablet
  bool get isTablet => width >= 768;

  /// Check if device is mobile
  bool get isMobile => width < 768;
}
