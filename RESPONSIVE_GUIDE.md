# Responsive Design Implementation Guide

## Overview

This guide shows how to make the entire Flutter app responsive using the `ResponsiveUtils` extension.

## Import Required

Add this import to every page:

```dart
import 'package:attendence_management_system/utils/responsive_utils.dart';
```

## Conversion Rules

### 1. Heights → context.h(percentage)

**Fixed height → Responsive height**

```dart
// Before
SizedBox(height: 16)
padding: EdgeInsets.only(top: 12)
PreferredSize(preferredSize: Size.fromHeight(112))

// After
SizedBox(height: context.h(2))          // 2% of screen height
padding: EdgeInsets.only(top: context.h(1.5))
PreferredSize(preferredSize: Size.fromHeight(context.h(14)))
```

### 2. Widths → context.w(percentage)

**Fixed width → Responsive width**

```dart
// Before
SizedBox(width: 10)
padding: EdgeInsets.symmetric(horizontal: 16)
margin: EdgeInsets.symmetric(horizontal: 20)

// After
SizedBox(width: context.w(2.5))
padding: EdgeInsets.symmetric(horizontal: context.w(4))
margin: EdgeInsets.symmetric(horizontal: context.w(5))
```

### 3. Font Sizes → context.sp(size)

**Fixed font → Responsive font**

```dart
// Before
TextStyle(fontSize: 20)
TextStyle(fontSize: 16)
Icon(Icons.add, size: 24)

// After
TextStyle(fontSize: context.sp(20))
TextStyle(fontSize: context.sp(16))
Icon(Icons.add, size: context.sp(24))
```

### 4. Border Radius → context.w() for horizontal curves

```dart
// Before
BorderRadius.circular(12)
borderRadius: BorderRadius.circular(20)

// After
BorderRadius.circular(context.w(3))
borderRadius: BorderRadius.circular(context.w(5))
```

## Common Conversions Cheat Sheet

| Fixed Value  | Percentage | Responsive Code |
| ------------ | ---------- | --------------- |
| height: 8    | ~1%        | context.h(1)    |
| height: 16   | ~2%        | context.h(2)    |
| height: 24   | ~3%        | context.h(3)    |
| height: 40   | ~5%        | context.h(5)    |
| width: 8     | ~2%        | context.w(2)    |
| width: 16    | ~4%        | context.w(4)    |
| width: 24    | ~6%        | context.w(6)    |
| width: 40    | ~10%       | context.w(10)   |
| fontSize: 12 | -          | context.sp(12)  |
| fontSize: 16 | -          | context.sp(16)  |
| fontSize: 20 | -          | context.sp(20)  |
| fontSize: 24 | -          | context.sp(24)  |

## Example: Before & After

### Before (Static)

```dart
Container(
  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(12),
  ),
  child: Text(
    'Hello',
    style: TextStyle(fontSize: 18),
  ),
)
```

### After (Responsive)

```dart
Container(
  margin: EdgeInsets.symmetric(horizontal: context.w(4), vertical: context.h(2.5)),
  padding: EdgeInsets.all(context.w(4)),
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(context.w(3)),
  ),
  child: Text(
    'Hello',
    style: TextStyle(fontSize: context.sp(18)),
  ),
)
```

## Files to Update

1. ✅ utils/responsive_utils.dart (Created)
2. ✅ pages/history.dart (In Progress)
3. ⏳ pages/admin_dashboard.dart
4. ⏳ pages/loginPage.dart
5. ⏳ pages/AttendanceScreen.dart
6. ⏳ pages/work_mode_selection_page.dart
7. ⏳ pages/role_selection_page.dart
8. ⏳ utils/splash_screen.dart
9. ⏳ pages/announcements.dart
10. ⏳ pages/vacation.dart
11. ⏳ pages/sick.dart
12. ⏳ pages/home_office.dart
13. ⏳ pages/holidays.dart
14. ⏳ pages/editing.dart
15. ⏳ pages/employee_history_screen.dart
16. ⏳ pages/employee_signup_screen.dart
17. ⏳ pages/add_employee_screen.dart

## Quick Tips

- Use `context.h()` for anything related to vertical spacing or height
- Use `context.w()` for anything related to horizontal spacing or width
- Use `context.sp()` for all text sizes and icon sizes
- For buttons: width uses `context.w()`, height uses `context.h()`
- For padding/margin: horizontal uses `context.w()`, vertical uses `context.h()`

## Testing

Test on different screen sizes:

- Small phone (iPhone SE): 375x667
- Regular phone (iPhone 11): 414x896
- Large phone: 428x926
- Tablet: 768x1024

The app should scale proportionally across all devices!
