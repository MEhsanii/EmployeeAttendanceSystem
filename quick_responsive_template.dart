// Quick Responsive Conversion Template
// Use this as a reference when converting files to responsive design

import 'package:flutter/material.dart';
import 'package:attendence_management_system/utils/responsive_utils.dart';

// ============================================================================
// BEFORE & AFTER EXAMPLES
// ============================================================================

class ResponsiveExample extends StatelessWidget {
  const ResponsiveExample({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ===== EXAMPLE 1: AppBar =====
      appBar: AppBar(
        // BEFORE: title: Text('Title', style: TextStyle(fontSize: 20))
        title: Text('Title', style: TextStyle(fontSize: context.sp(20))),
      ),

      body: SingleChildScrollView(
        child: Column(
          children: [
            // ===== EXAMPLE 2: Vertical Spacing =====
            // BEFORE: SizedBox(height: 16)
            SizedBox(height: context.h(2)),

            // ===== EXAMPLE 3: Container with padding =====
            Container(
              // BEFORE: margin: EdgeInsets.symmetric(horizontal: 20, vertical: 16)
              margin: EdgeInsets.symmetric(
                horizontal: context.w(5),
                vertical: context.h(2),
              ),
              // BEFORE: padding: EdgeInsets.all(16)
              padding: EdgeInsets.all(context.w(4)),
              decoration: BoxDecoration(
                color: Colors.white,
                // BEFORE: borderRadius: BorderRadius.circular(12)
                borderRadius: BorderRadius.circular(context.w(3)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    // BEFORE: blurRadius: 8, offset: Offset(0, 4)
                    blurRadius: context.w(2),
                    offset: Offset(0, context.h(0.5)),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // ===== EXAMPLE 4: Text with responsive font =====
                  // BEFORE: Text('Hello', style: TextStyle(fontSize: 18))
                  Text(
                    'Hello',
                    style: TextStyle(
                      fontSize: context.sp(18),
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  // BEFORE: SizedBox(height: 8)
                  SizedBox(height: context.h(1)),

                  // ===== EXAMPLE 5: Icon with size =====
                  // BEFORE: Icon(Icons.star, size: 24)
                  Icon(Icons.star, size: context.sp(24)),

                  SizedBox(height: context.h(2)),

                  // ===== EXAMPLE 6: Button =====
                  ElevatedButton(
                    // BEFORE: padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12)
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.w(6),
                        vertical: context.h(1.5),
                      ),
                      // BEFORE: shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(context.w(2)),
                      ),
                    ),
                    onPressed: () {},
                    // BEFORE: child: Text('Button', style: TextStyle(fontSize: 16))
                    child: Text(
                      'Button',
                      style: TextStyle(fontSize: context.sp(16)),
                    ),
                  ),

                  SizedBox(height: context.h(2)),

                  // ===== EXAMPLE 7: Row with spacing =====
                  Row(
                    children: [
                      // BEFORE: Icon(Icons.info, size: 20)
                      Icon(Icons.info, size: context.sp(20)),
                      // BEFORE: SizedBox(width: 8)
                      SizedBox(width: context.w(2)),
                      // BEFORE: Text('Info', style: TextStyle(fontSize: 14))
                      Text(
                        'Info',
                        style: TextStyle(fontSize: context.sp(14)),
                      ),
                    ],
                  ),

                  SizedBox(height: context.h(2)),

                  // ===== EXAMPLE 8: Card =====
                  Card(
                    // BEFORE: margin: EdgeInsets.all(12)
                    margin: EdgeInsets.all(context.w(3)),
                    // BEFORE: shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(context.w(4)),
                    ),
                    child: Padding(
                      // BEFORE: padding: EdgeInsets.all(16)
                      padding: EdgeInsets.all(context.w(4)),
                      child: Text(
                        'Card Content',
                        // BEFORE: style: TextStyle(fontSize: 14)
                        style: TextStyle(fontSize: context.sp(14)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: context.h(3)),

            // ===== EXAMPLE 9: Image with height =====
            // BEFORE: Image.asset('assets/logo.png', height: 100)
            Image.asset('assets/logo.png', height: context.h(12)),

            SizedBox(height: context.h(2)),

            // ===== EXAMPLE 10: ListTile =====
            ListTile(
              // BEFORE: leading: Icon(Icons.person, size: 28)
              leading: Icon(Icons.person, size: context.sp(28)),
              title: Text(
                'Title',
                // BEFORE: style: TextStyle(fontSize: 16)
                style: TextStyle(fontSize: context.sp(16)),
              ),
              subtitle: Text(
                'Subtitle',
                // BEFORE: style: TextStyle(fontSize: 14)
                style: TextStyle(fontSize: context.sp(14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// QUICK REFERENCE CHEAT SHEET
// ============================================================================

/*
╔═══════════════════════════════════════════════════════════════════════════╗
║                    RESPONSIVE CONVERSION CHEAT SHEET                      ║
╚═══════════════════════════════════════════════════════════════════════════╝

HEIGHTS (Vertical Spacing & Dimensions):
  8  → context.h(1)
  16 → context.h(2)
  24 → context.h(3)
  32 → context.h(4)
  40 → context.h(5)
  48 → context.h(6)
  64 → context.h(8)
  80 → context.h(10)
  100 → context.h(12)

WIDTHS (Horizontal Spacing & Dimensions):
  8  → context.w(2)
  12 → context.w(3)
  16 → context.w(4)
  20 → context.w(5)
  24 → context.w(6)
  32 → context.w(8)
  40 → context.w(10)

FONT SIZES & ICON SIZES:
  10 → context.sp(10)
  12 → context.sp(12)
  14 → context.sp(14)
  16 → context.sp(16)
  18 → context.sp(18)
  20 → context.sp(20)
  22 → context.sp(22)
  24 → context.sp(24)
  28 → context.sp(28)
  32 → context.sp(32)

BORDER RADIUS:
  4  → context.w(1)
  8  → context.w(2)
  12 → context.w(3)
  16 → context.w(4)
  20 → context.w(5)
  24 → context.w(6)

REMEMBER:
  - Remove 'const' when using context-based values
  - Heights → context.h()
  - Widths → context.w()
  - Fonts/Icons → context.sp()
  - Border radius (circular) → context.w()
*/
