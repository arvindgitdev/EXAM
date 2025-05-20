import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Student/student_login.dart';
import '../Teacher/teacher_login.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Stack(
          children: [
            Center(
              child: Image.asset(
                "assets/icon/icon.png",
              ),
            ),
            Align(
              alignment: const Alignment(0.0, 0.7), // Adjust this to move the button
              child: ElevatedButton(
                onPressed: () {
                  _showUserTypeDialog(context);
                },
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  backgroundColor: Colors.black,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Continue With ExamNow",
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward, color: Colors.white),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserTypeDialog(BuildContext context) {
    String? selectedUserType;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Select User Type"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: const Text("Teacher"),
                value: "Teacher",
                groupValue: selectedUserType,
                onChanged: (String? value) async {
                  selectedUserType = value;
                  await _storeUserType("Teacher");
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TeacherLogin(),
                    ),
                  );
                },
              ),
              RadioListTile<String>(
                title: const Text("Student"),
                value: "Student",
                groupValue: selectedUserType,
                onChanged: (String? value) async {
                  selectedUserType = value;
                  await _storeUserType("Student");
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const StudentLogin(),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
  Future<void> _storeUserType(String userType) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('userType', userType);
  }
}
