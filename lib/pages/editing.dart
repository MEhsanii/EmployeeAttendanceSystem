import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class EditAttendanceScreen extends StatefulWidget {
  final String dateKey; // e.g. "2025-07-21"
  final String fieldKey; // e.g. "startWork"

  const EditAttendanceScreen({
    super.key,
    required this.dateKey,
    required this.fieldKey,
  });

  @override
  State<EditAttendanceScreen> createState() => _EditAttendanceScreenState();
}

class _EditAttendanceScreenState extends State<EditAttendanceScreen> {
  TimeOfDay? selectedTime;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadExistingTime();
  }

  Future<void> loadExistingTime() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('attendance')
        .doc(widget.dateKey)
        .get();

    if (doc.exists) {
      final data = doc.data()!;
      final ts = data[widget.fieldKey] as Timestamp?;
      if (ts != null) {
        final dt = ts.toDate();
        selectedTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
      }
    }

    setState(() => isLoading = false);
  }

  Future<void> selectTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: selectedTime ?? TimeOfDay.now(),
    );

    if (picked != null) {
      setState(() {
        selectedTime = picked; // ✅ Update UI immediately
      });
    }
  }

 Future<void> saveChanges() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final dateParts = widget.dateKey.split('-');
  final year = int.parse(dateParts[0]);
  final month = int.parse(dateParts[1]);
  final day = int.parse(dateParts[2]);

  if (selectedTime == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please pick a time before saving')),
    );
    return;
  }

  final fullDateTime = DateTime(year, month, day, selectedTime!.hour, selectedTime!.minute);

  print('Saving field: ${widget.fieldKey}');
  print('Time: $fullDateTime');
  print('Path: users/${user.uid}/attendance/${widget.dateKey}');

  final docRef = FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('attendance')
      .doc(widget.dateKey);

  final docSnapshot = await docRef.get();

  await docRef.set({
    widget.fieldKey: Timestamp.fromDate(fullDateTime),
    'createdAt': docSnapshot.exists
        ? (docSnapshot.data()?['createdAt'] ?? FieldValue.serverTimestamp())
        : FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Attendance updated successfully')),
    );
    Navigator.pop(context);
  }
}

  String formatTime(TimeOfDay? time) {
    if (time == null) return '--:--';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    const bpgGreen = Color(0xFF2E4A2C);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Attendance'),
        backgroundColor: bpgGreen,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    child: ListTile(
                      title: Text(_getLabelForField(widget.fieldKey)),
                      trailing: Text(formatTime(selectedTime)),
                      onTap: () => selectTime(context),
                    ),
                  ),
                  const SizedBox(height: 30),
                  ElevatedButton.icon(
                    onPressed: selectedTime != null ? saveChanges : null,
                    icon: const Icon(Icons.save, color: Colors.white),
                    label: const Text(
                      'Save Changes',
                      style: TextStyle(color: Colors.white), // ✅ Force text to white
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: bpgGreen,
                      disabledBackgroundColor: Colors.grey, // ✅ If no time selected, grey out
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  String _getLabelForField(String key) {
    switch (key) {
      case 'startWork':
        return 'Start Work';
      case 'startBreak':
        return 'Start Break';
      case 'endBreak':
        return 'End Break';
      case 'endWork':
        return 'End Work';
      default:
        return 'Unknown';
    }
  }
}
