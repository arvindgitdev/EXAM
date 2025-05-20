import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:examnow/Teacher/result_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../Provider/teacher_auth.dart';
import 'create_exam.dart';
import 'edit_exam_page.dart'; // Import the edit exam page
import 'view_exam_questions.dart'; // Import the view questions page
import 'teacher_monitoring_page.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  AdminDashboardState createState() => AdminDashboardState();
}

class AdminDashboardState extends State<AdminDashboard> with SingleTickerProviderStateMixin {
  late Timer _timer;
  Key _streamBuilderKey = UniqueKey();
  TabController? _tabController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        setState(() {
          _streamBuilderKey = UniqueKey();
        });
      }
    });
  }

  Future<void> _refreshData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _streamBuilderKey = UniqueKey();
      });
    }

    // Add a small delay to show the refresh indicator
    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _navigateToCreateExam() {
    // Navigate to CreateExamPage
    Navigator.push(context, MaterialPageRoute(builder: (context) => CreateExamPage()));
  }

  // Navigate to edit exam page
  void _navigateToEditExam(String examId, Map<String, dynamic> examData) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => EditExamPage(examId: examId, examData: examData)
        )
    );
  }

  // Navigate to view exam questions page
  void _navigateToViewQuestions(String examId, String examTitle) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => ViewExamQuestionsPage(examId: examId, examTitle: examTitle)
        )
    );
  }

  // Add navigation to monitoring page
  void _navigateToMonitorExam(String examId) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => TeacherMonitoringPage(examId: examId)
        )
    );
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Monitoring exam: $examId"))
    );
  }

  // Delete exam confirmation dialog
  void _showDeleteConfirmation(String examId, String examTitle) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete Exam',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Are you sure you want to delete this exam?',
              style: GoogleFonts.poppins(),
            ),
            const SizedBox(height: 8),
            Text(
              examTitle,
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'This action cannot be undone.',
              style: GoogleFonts.poppins(
                fontStyle: FontStyle.italic,
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              try {
                // Show loading indicator
                _showLoadingDialog('Deleting exam...');

                // Delete the exam from Firestore
                await FirebaseFirestore.instance
                    .collection("exams")
                    .doc(examId)
                    .delete();

                // Also delete related collections (questions, submissions, etc.)
                await _deleteExamRelatedData(examId);

                // Hide loading dialog
                Navigator.pop(context);

                // Show success message
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Exam '$examTitle' deleted successfully"),
                    backgroundColor: Colors.green,
                  ),
                );

                // Refresh the dashboard data
                _refreshData();
              } catch (e) {
                // Hide loading dialog if showing
                if (Navigator.canPop(context)) {
                  Navigator.pop(context);
                }

                // Show error message
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text("Failed to delete exam: ${e.toString()}"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text(
              'Delete',
              style: GoogleFonts.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // Delete related data (questions, submissions, etc.)
  Future<void> _deleteExamRelatedData(String examId) async {
    // Delete all questions
    final questionsSnapshot = await FirebaseFirestore.instance
        .collection("exams")
        .doc(examId)
        .collection("questions")
        .get();

    for (var doc in questionsSnapshot.docs) {
      await doc.reference.delete();
    }

    // Delete all submissions if they exist
    final submissionsSnapshot = await FirebaseFirestore.instance
        .collection("exams")
        .doc(examId)
        .collection("submissions")
        .get();

    for (var doc in submissionsSnapshot.docs) {
      await doc.reference.delete();
    }

    // Delete any results if they exist
    final resultsSnapshot = await FirebaseFirestore.instance
        .collection("results")
        .where("examId", isEqualTo: examId)
        .get();

    for (var doc in resultsSnapshot.docs) {
      await doc.reference.delete();
    }
  }

  // Show loading dialog
  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              message,
              style: GoogleFonts.poppins(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<TeacherAuthProvider>(context, listen: false);
    final user = authProvider.currentUser;

    return Scaffold(
      appBar: _buildAppBar(),
      drawer: _buildDrawer(),
      body: _buildBody(user),
      floatingActionButton: _buildCreateExamButton(),
    );
  }

  Widget _buildBody(user) {
    return RefreshIndicator(
      onRefresh: _refreshData,
      child: StreamBuilder<QuerySnapshot>(
        key: _streamBuilderKey,
        stream: FirebaseFirestore.instance
            .collection("exams")
            .where("createdBy", isEqualTo: user?.uid)
            .orderBy("examTimestamp", descending: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting || _isLoading) {
            return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text("Loading your exams...", style: TextStyle(color: Colors.grey))
                  ],
                )
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          List<DocumentSnapshot> ongoingExams = [];
          List<DocumentSnapshot> upcomingExams = [];
          List<DocumentSnapshot> completedExams = [];
          DateTime now = DateTime.now();

          for (var doc in snapshot.data!.docs) {
            Map<String, dynamic> examData = doc.data() as Map<String, dynamic>;
            int examTimestamp = examData["examTimestamp"] is int
                ? examData["examTimestamp"]
                : int.tryParse(examData["examTimestamp"].toString()) ?? 0;

            String durationString = examData["duration"] ?? "1h 0m";
            RegExp regex = RegExp(r"(\d+)h (\d+)m");
            Match? match = regex.firstMatch(durationString);

            int durationHours = match != null ? int.parse(match.group(1)!) : 1;
            int durationMinutes = match != null ? int.parse(match.group(2)!) : 0;
            int duration = (durationHours * 60) + durationMinutes;

            DateTime examDateTime = DateTime.fromMillisecondsSinceEpoch(examTimestamp);

            if (examDateTime.isBefore(now) && examDateTime.add(Duration(minutes: duration)).isAfter(now)) {
              ongoingExams.add(doc);
            } else if (examDateTime.isAfter(now)) {
              upcomingExams.add(doc);
            } else if (examDateTime.add(Duration(minutes: duration)).isBefore(now)) {
              completedExams.add(doc);
            }
          }

          return Column(
            children: [
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController!,
                  children: [
                    _buildExamsList("Current", ongoingExams, Colors.green, true, false),
                    _buildExamsList("Upcoming", upcomingExams, Colors.blue, true, true),
                    _buildExamsList("Completed", completedExams, Colors.grey, false, false),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade700, Colors.blue.shade900],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController!,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withOpacity(0.7),
        indicator: const UnderlineTabIndicator(
          borderSide: BorderSide(width: 3.0, color: Colors.white),
          insets: EdgeInsets.symmetric(horizontal: 36.0),
        ),
        labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        tabs: const [
          Tab(
            icon: Icon(Icons.assignment),
            text: "Current",
          ),
          Tab(
            icon: Icon(Icons.schedule),
            text: "Upcoming",
          ),
          Tab(
            icon: Icon(Icons.check_circle),
            text: "Completed",
          ),
        ],
      ),
    );
  }

  Widget _buildExamsList(String title, List<DocumentSnapshot> exams, Color color, bool showExamKey, bool allowEditing) {
    if (exams.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
                title == "Current" ? Icons.assignment_outlined :
                title == "Upcoming" ? Icons.schedule_outlined : Icons.check_circle_outline,
                size: 80,
                color: Colors.grey.shade400
            ),
            const SizedBox(height: 16),
            Text(
              "No $title exams",
              style: GoogleFonts.poppins(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text(
              title == "Current" ? "Exams that are happening right now will appear here" :
              title == "Upcoming" ? "Your scheduled exams will appear here" :
              "Exams that have been completed will appear here",
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: exams.length,
      itemBuilder: (context, index) => _buildExamCard(exams[index], color, showExamKey, allowEditing),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: Text(
        "Teacher Dashboard",
        style: GoogleFonts.poppins(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.blue.shade700, Colors.blue.shade900],
          ),
        ),
      ),
      centerTitle: true,
      elevation: 4,

    );
  }

  Widget _buildCreateExamButton() {
    return FloatingActionButton.extended(
      onPressed: _navigateToCreateExam,
      icon: const Icon(Icons.add),
      label: const Text("Create Exam"),
      backgroundColor: Colors.blue.shade700,
      elevation: 6,
    );
  }

  Widget _buildExamCard(DocumentSnapshot exam, Color color, bool showExamKey, bool allowEditing) {
    Map<String, dynamic> examData = exam.data() as Map<String, dynamic>;
    String examId = exam.id;
    String formattedExamKey = examData["examKey"] ?? _generateExamKey(examId);
    String examTitle = examData["title"] ?? "Unknown Title";

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shadowColor: color.withOpacity(0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () {
          // Navigate to view exam details
          _navigateToViewQuestions(examId, examTitle);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title and Subject area
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [color.withOpacity(0.8), color],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(Icons.quiz, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          examTitle,
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          examData["subject"] ?? "No subject specified",
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // More options
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) {
                      if (value == 'details') {
                        // Navigate to view exam questions
                        _navigateToViewQuestions(examId, examTitle);
                      } else if (value == 'edit') {
                        // Navigate to edit exam
                        _navigateToEditExam(examId, examData);
                      } else if (value == 'delete') {
                        // Show delete confirmation only for upcoming exams
                        if (allowEditing) {
                          _showDeleteConfirmation(examId, examTitle);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("Cannot delete ${allowEditing ? 'upcoming' : 'this'} exam"))
                          );
                        }
                      } else if (value == 'monitor') {
                        // Navigate to monitoring page
                        _navigateToMonitorExam(examId);
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'details',
                        child: Row(
                          children: [
                            Icon(Icons.question_answer, size: 18),
                            SizedBox(width: 8),
                            Text('View Questions'),
                          ],
                        ),
                      ),
                      if (showExamKey && !allowEditing)
                        const PopupMenuItem(
                          value: 'monitor',
                          child: Row(
                            children: [
                              Icon(Icons.visibility, size: 18),
                              SizedBox(width: 8),
                              Text('Monitor Exam'),
                            ],
                          ),
                        ),
                      if (allowEditing)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 18),
                              SizedBox(width: 8),
                              Text('Edit Exam'),
                            ],
                          ),
                        ),
                      if (allowEditing)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_outline, size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Delete', style: TextStyle(color: Colors.red)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 16),

              // Info area
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Date & Time column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.event, size: 16, color: color),
                            const SizedBox(width: 8),
                            Text(
                              examData["date"] ?? "Unknown Date",
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.access_time, size: 16, color: color),
                            const SizedBox(width: 8),
                            Text(
                              examData["time"] ?? "Unknown Time",
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Duration & Questions column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.timer, size: 16, color: color),
                            const SizedBox(width: 8),
                            Text(
                              examData["duration"] ?? "Unknown Duration",
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.help_outline, size: 16, color: color),
                            const SizedBox(width: 8),
                            Text(
                              "${examData["questionCount"] ?? "?"} Questions",
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // Exam key (if applicable)
              if (showExamKey) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.key, size: 20, color: Colors.amber),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Exam Key: $formattedExamKey",
                          style: GoogleFonts.poppins(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: formattedExamKey));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Exam Key copied to clipboard")),
                          );
                        },
                        tooltip: "Copy to clipboard",
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 16),
                      IconButton(
                        icon: const Icon(Icons.share, size: 20),
                        onPressed: () {
                          Share.share("Use this Exam Key to join the exam: $formattedExamKey");
                        },
                        tooltip: "Share exam key",
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ],

              // Action buttons
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (allowEditing) ...[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit),
                      label: const Text("Edit"),
                      onPressed: () {
                        // Navigate to edit exam
                        _navigateToEditExam(examId, examData);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (showExamKey && !allowEditing) ...[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.visibility),
                      label: const Text("Monitor"),
                      onPressed: () {
                        // Navigate to monitoring page
                        _navigateToMonitorExam(examId);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: color,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  ElevatedButton.icon(
                    icon: allowEditing
                        ? const Icon(Icons.question_answer)
                        : const Icon(Icons.description),
                    label: Text(allowEditing ? "Questions" : "Results"),
                    onPressed: () {
                      if (allowEditing) {
                        // Navigate to view questions
                        _navigateToViewQuestions(examId, examTitle);
                      } else {
                        // Navigate to results page
                        Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => TeacherResultsPage(examId: examId))
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    final authProvider = Provider.of<TeacherAuthProvider>(context, listen: false);
    final user = authProvider.currentUser;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(
              user?.displayName ?? "Teacher",
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 18,
              ),
            ),
            accountEmail: Text(
              user?.email ?? "teacher@example.com",
              style: GoogleFonts.poppins(),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                (user?.displayName?.isNotEmpty == true ? user!.displayName![0] : "T"),
                style: GoogleFonts.poppins(fontSize: 24, color: Colors.blue.shade800),
              ),
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade700, Colors.blue.shade900],
              ),
            ),
          ),
          _buildDrawerItem(Icons.dashboard, "Dashboard", () {
            Navigator.pop(context);
          }, isSelected: true),
          _buildDrawerItem(Icons.add_box, "Create Exam", () {
            Navigator.pop(context);
            _navigateToCreateExam();
          }),
          _buildDrawerItem(Icons.visibility, "Monitor Exams", () {
            Navigator.pop(context);
            // Show a dialog to enter exam ID to monitor
            _showMonitoringDialog();
          }),
          _buildDrawerItem(Icons.question_answer, "Exams", () {
            Navigator.pop(context);
            // Navigate to question bank
          }),

          _buildDrawerItem(Icons.logout, "Logout", () async {
            await Provider.of<TeacherAuthProvider>(context, listen: false).signOut(context);
          }, color: Colors.red),
        ],
      ),
    );
  }

  // Show monitoring dialog
  void _showMonitoringDialog() {
    final TextEditingController examIdController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Monitor Exam',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Enter the Exam ID you want to monitor:',
              style: GoogleFonts.poppins(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: examIdController,
              decoration: InputDecoration(
                hintText: 'Exam ID',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.vpn_key),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: GoogleFonts.poppins(),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final examId = examIdController.text.trim();
              if (examId.isNotEmpty) {
                Navigator.pop(context);
                _navigateToMonitorExam(examId);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please enter a valid Exam ID"))
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
            ),
            child: Text(
              'Monitor',
              style: GoogleFonts.poppins(),
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildDrawerItem(IconData icon, String title, Function() onTap, {Color? color, bool isSelected = false}) {
    return ListTile(
      leading: Icon(icon, color: color ?? (isSelected ? Colors.blue.shade700 : Colors.grey.shade700)),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          color: color ?? (isSelected ? Colors.blue.shade700 : Colors.black87),
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      onTap: onTap,
      tileColor: isSelected ? Colors.blue.shade50 : null,
    );
  }

  String _generateExamKey(String examId) {
    const characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random();
    String examKey = '';
    for (int i = 0; i < 6; i++) {
      examKey += characters[random.nextInt(characters.length)];
    }
    return examKey;
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/images/empty_exams.png',
            height: 150,
            width: 150,
            errorBuilder: (context, error, stackTrace) => Icon(
              Icons.assignment_outlined,
              size: 100,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "No Exams Created Yet",
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              "Create your first exam by clicking the button below",
              style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text("Create New Exam"),
            onPressed: _navigateToCreateExam,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              backgroundColor: Colors.blue.shade700,
              textStyle: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}