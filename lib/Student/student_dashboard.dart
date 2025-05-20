import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../Provider/student_auth.dart';
import 'exam_instruction.dart';

class Studentpage extends StatefulWidget {
  const Studentpage({super.key});

  @override
  State<Studentpage> createState() => _StudentpageState();
}

class _StudentpageState extends State<Studentpage> {
  final TextEditingController examKeyController = TextEditingController();
  bool isLoading = false;



  @override
  void dispose() {
    examKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          "Student Dashboard",
          style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.blue.shade700, Colors.indigo.shade800],
            ),
          ),
        ),

      ),
      drawer: _buildDrawer(context),
      body: RefreshIndicator(
        onRefresh: () async {
          setState(() {});
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top curved container with greeting
              Container(
                width: double.infinity,
                padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 40),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.blue.shade700, Colors.indigo.shade800],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('students')
                          .doc(FirebaseAuth.instance.currentUser?.uid)
                          .get(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Text(
                            'Welcome to ExamHub!',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          );
                        }
                        final name = snapshot.data?.data() is Map<String, dynamic>
                            ? (snapshot.data?.data() as Map<String, dynamic>)['name'] ?? 'Student'
                            : 'Student';

                        return Text(
                          'Hello, $name!',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Access your exams with ease',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.blue.shade50,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 25),


              // Exam Key Entry Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 4,
                  shadowColor: Colors.blue.withOpacity(0.2),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.key, color: Colors.blue.shade700, size: 28),
                            const SizedBox(width: 12),
                            const Text(
                              'Enter Exam Code',
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: examKeyController,
                          style: const TextStyle(fontSize: 18),
                          decoration: InputDecoration(
                            hintText: 'Enter your 6-digit exam code',
                            filled: true,
                            fillColor: Colors.grey.shade100,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            prefixIcon: Icon(Icons.vpn_key_outlined, color: Colors.blue.shade800),
                            suffixIcon: IconButton(
                              icon: Icon(Icons.clear, color: Colors.grey.shade600),
                              onPressed: () => examKeyController.clear(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : () => _attemptExamEntry(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: isLoading
                                ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: Colors.white,
                              ),
                            )
                                : const Text(
                              'Enter Exam',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 25),


            ],
          ),
        ),
      ),
    );
  }


  Future<void> _attemptExamEntry(BuildContext context) async {
    final key = examKeyController.text.trim();

    if (key.isEmpty) {
      _showSnackBar('Please enter a valid exam code', isError: true);
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // Query for exam with matching key
      final querySnapshot = await FirebaseFirestore.instance
          .collection('exams')
          .where('examKey', isEqualTo: key)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final examDoc = querySnapshot.docs.first;
        final examData = examDoc.data();
        final examId = examDoc.id;

        // Get current user
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          _showSnackBar('User not authenticated', isError: true);
          return;
        }

        // Check if student is allowed to take this exam
        final allowedStudents = examData['allowedStudents'] as List<dynamic>?;
        if (allowedStudents != null && !allowedStudents.contains(user.uid)) {
          _showSnackBar('You are not authorized to take this exam', isError: true);
          return;
        }

        // Check if the student has already submitted this exam
        final submissionQuery = await FirebaseFirestore.instance
            .collection('exam_submissions')
            .where('examId', isEqualTo: examId)
            .where('userId', isEqualTo: user.uid)
            .get();

        if (submissionQuery.docs.isNotEmpty) {
          _showSnackBar('You have already submitted this exam', isError: true);
          return;
        }

        // Get current time
        final now = DateTime.now().millisecondsSinceEpoch;

        // Get exam timestamp from Firestore
        final examTimestamp = examData['examTimestamp'] as int;

        // Parse duration string to get exam end time
        final durationStr = examData['duration'] as String; // Format: "2h 30m"
        final hours = int.parse(durationStr.split('h')[0]);
        final minutes = int.parse(durationStr.split('h')[1].trim().split('m')[0]);
        final durationMillis = (hours * 60 * 60 + minutes * 60) * 1000;

        final examEndTime = examTimestamp + durationMillis;

        // Calculate time differences in minutes
        final minsUntilExam = (examTimestamp - now) / (1000 * 60);
        final minsSinceExamStarted = (now - examTimestamp) / (1000 * 60);

        // Case 1: Exam completed
        if (now > examEndTime) {
          _showSnackBar('This exam has already ended', isError: true);
        }
        // Case 2: Exam is upcoming but within 15 min window - allow instructions only
        else if (minsUntilExam <= 15 && minsUntilExam > 0) {
          _showSnackBar('Exam will start in ${minsUntilExam.ceil()} minutes', isSuccess: true);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ExamInstructionsPage(
                examId: examId,
                examData: examData,
                canStartExam: false,
                message: 'Exam will start in ${minsUntilExam.ceil()} minutes',
              ),
            ),
          );
        }
        // Case 3: Exam is ongoing but within 10 min late window - allow full access
        else if (minsSinceExamStarted <= 10 && minsSinceExamStarted > 0) {
          _showSnackBar('Exam access granted!', isSuccess: true);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ExamInstructionsPage(
                examId: examId,
                examData: examData,
                canStartExam: true,
                message: 'Exam is in progress. You can start now.',

              ),
            ),
          );
        }
        // Case 4: Exam is ongoing but past 10 min window - deny access
        else if (minsSinceExamStarted > 10 && now < examEndTime) {
          _showSnackBar('You are more than 10 minutes late. Entry denied.', isError: true);
        }
        // Case 5: Exam hasn't started yet and not within 15 min window
        else if (minsUntilExam > 15) {
          final hours = (minsUntilExam / 60).floor();
          final mins = (minsUntilExam % 60).ceil();
          final timeMsg = hours > 0
              ? '$hours hour${hours > 1 ? 's' : ''} and $mins minute${mins > 1 ? 's' : ''}'
              : '$mins minute${mins > 1 ? 's' : ''}';

          _showSnackBar(
              'Exam will start in $timeMsg. You can enter 15 minutes before the start time.',
              isWarning: true
          );
        }
      } else {
        // Key is invalid
        _showSnackBar('Invalid exam code. Please check and try again.', isError: true);
      }
    } catch (e) {
      // Handle error
      _showSnackBar('Error validating exam code: $e', isError: true);
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  void _showSnackBar(String message, {bool isError = false, bool isSuccess = false, bool isWarning = false}) {
    Color backgroundColor;

    if (isError) {
      backgroundColor = Colors.red.shade700;
    } else if (isSuccess) {
      backgroundColor = Colors.green.shade700;
    } else if (isWarning) {
      backgroundColor = Colors.orange.shade700;
    } else {
      backgroundColor = Colors.blue.shade700;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final authProvider = Provider.of<StudentAuthProvider>(context, listen: false);
    final user = authProvider.currentUser;

    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 16,
              bottom: 16,
              left: 16,
              right: 16,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.blue.shade700, Colors.indigo.shade800],
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, size: 40, color: Colors.blue.shade800),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.displayName ?? "Student",
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        user?.email ?? "student@example.com",
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue.shade50,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          _buildDrawerItem(Icons.dashboard_outlined, "Dashboard", () {
            Navigator.pop(context);
          }, isActive: true),
          _buildDrawerItem(Icons.history_outlined, "Exam History", () {
            Navigator.pop(context);
            // Navigate to exam history
          }),
          _buildDrawerItem(Icons.analytics_outlined, "Performance", () {
            Navigator.pop(context);
            // Navigate to performance analytics
          }),

          _buildDrawerItem(Icons.logout_outlined, "Logout", () async {
            await Provider.of<StudentAuthProvider>(context, listen: false).signOut(context);
          }, textColor: Colors.red.shade700),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, VoidCallback onTap, {bool isActive = false, Color? textColor}) {
    return ListTile(
      leading: Icon(
          icon,
          color: isActive ? Colors.blue.shade700 : textColor ?? Colors.grey.shade700
      ),
      title: Text(
          title,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? Colors.blue.shade700 : textColor ?? Colors.grey.shade800,
          )
      ),
      onTap: onTap,
      tileColor: isActive ? Colors.blue.shade50 : null,
      shape: isActive
          ? RoundedRectangleBorder(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      )
          : null,
    );
  }
}