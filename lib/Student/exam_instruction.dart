import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';

import 'exam_page.dart';


class ExamInstructionsPage extends StatefulWidget {
  final String examId;
  final Map<String, dynamic> examData;
  final bool canStartExam;
  final String? message;

  const ExamInstructionsPage({
    super.key,
    required this.examId,
    required this.examData,
    required this.canStartExam,
    this.message,
  });

  @override
  State<ExamInstructionsPage> createState() => _ExamInstructionsPageState();
}

class _ExamInstructionsPageState extends State<ExamInstructionsPage> {
  bool isLoading = false;
  bool agreementChecked = false;
  bool cameraPermissionGranted = false;
  bool microphonePermissionGranted = false;
  late int remainingTimeInSeconds;
  late DateTime examStartTime;
  late DateTime examEndTime;
  Timer? _countdownTimer;
  String countdownMessage = "";
  bool isExamLive = false;

  @override
  void initState() {
    super.initState();

    // Calculate exam start and end times
    final examTimestamp = widget.examData['examTimestamp'] as int;
    examStartTime = DateTime.fromMillisecondsSinceEpoch(examTimestamp);

    // Parse duration string to get exam end time
    final durationStr = widget.examData['duration'] as String; // Format: "2h 30m"
    final hours = int.parse(durationStr.split('h')[0]);
    final minutes = int.parse(durationStr.split('h')[1].trim().split('m')[0]);
    final durationSeconds = (hours * 60 * 60) + (minutes * 60);

    examEndTime = examStartTime.add(Duration(seconds: durationSeconds));

    // Check if exam is already live
    final now = DateTime.now();
    if (now.isAfter(examStartTime)) {
      isExamLive = true;
      countdownMessage = "Exam is live now!";
      remainingTimeInSeconds = 0;
    } else {
      remainingTimeInSeconds = examStartTime.difference(now).inSeconds;
      _updateCountdownMessage();
    }

    // Start countdown timer
    _startCountdownTimer();

    // Check if permissions are already granted
    _checkPermissions();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdownTimer() {
    // Set up timer to update countdown every second
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (remainingTimeInSeconds > 0) {
          remainingTimeInSeconds--;
          _updateCountdownMessage();
        } else {
          isExamLive = true;
          countdownMessage = "Exam is live now!";
        }
      });
    });
  }

  void _updateCountdownMessage() {
    final minutes = remainingTimeInSeconds ~/ 60;
    final seconds = remainingTimeInSeconds % 60;
    countdownMessage = "Your exam will start in ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";
  }

  Future<void> _checkPermissions() async {
    final cameraStatus = await Permission.camera.status;
    final microphoneStatus = await Permission.microphone.status;

    setState(() {
      cameraPermissionGranted = cameraStatus.isGranted;
      microphonePermissionGranted = microphoneStatus.isGranted;
    });
  }

  Future<void> _requestPermissions() async {
    setState(() {
      isLoading = true;
    });

    // Request camera permission
    if (!cameraPermissionGranted) {
      final cameraStatus = await Permission.camera.request();
      setState(() {
        cameraPermissionGranted = cameraStatus.isGranted;
      });
    }

    // Request microphone permission
    if (!microphonePermissionGranted) {
      final microphoneStatus = await Permission.microphone.request();
      setState(() {
        microphonePermissionGranted = microphoneStatus.isGranted;
      });
    }

    setState(() {
      isLoading = false;
    });

    // Show status message
    if (cameraPermissionGranted && microphonePermissionGranted) {
      _showSnackBar('Permissions granted successfully!', isSuccess: true);
    } else {
      _showSnackBar(
          'Please grant camera and microphone permissions to proceed with the exam',
          isWarning: true
      );
    }
  }

  void _startExam() {
    if (!agreementChecked) {
      _showSnackBar('Please agree to the exam rules before proceeding', isWarning: true);
      return;
    }

    if (!cameraPermissionGranted || !microphonePermissionGranted) {
      _showSnackBar('Camera and microphone permissions are required', isWarning: true);
      return;
    }
    // Actual exam page navigation would look something like:

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StudentExamPage(
          examId: widget.examId,
          examTitle: widget.examData['title'] ?? 'Exam',
        ),
      ),
    );

  }

  void _showSnackBar(String message, {bool isError = false, bool isSuccess = false, bool isWarning = false}) {
    Color backgroundColor;

    if (isError) {
      backgroundColor = Colors.red.shade700;
        }
    else if (isSuccess) {
      backgroundColor = Colors.green.shade700;
      }
    else if (isWarning) {
      backgroundColor = Colors.orange.shade700;
     }
    else {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          "Exam Instructions",
          style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
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
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Exam Info Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
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
                  Text(
                    widget.examData['title'] ?? 'Exam',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildExamInfoItem(
                    Icons.calendar_today_outlined,
                    'Date',
                    DateFormat('EEEE, MMMM d, yyyy').format(examStartTime),
                  ),
                  const SizedBox(height: 10),
                  _buildExamInfoItem(
                    Icons.access_time_outlined,
                    'Time',
                    DateFormat('h:mm a').format(examStartTime),
                  ),
                  const SizedBox(height: 10),
                  _buildExamInfoItem(
                    Icons.timer_outlined,
                    'Duration',
                    widget.examData['duration'] ?? '1h 0m',
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isExamLive ? Colors.green.withOpacity(0.2) : Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: isExamLive ? Colors.green.withOpacity(0.3) : Colors.white.withOpacity(0.3),
                          width: 1
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                            isExamLive ? Icons.check_circle_outline : Icons.alarm,
                            color: Colors.white
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            countdownMessage,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Instructions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Instructions Title
                  Row(
                    children: [
                      Icon(Icons.description_outlined, color: Colors.blue.shade800, size: 28),
                      const SizedBox(width: 10),
                      Text(
                        "Instructions",
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Instructions Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildInstructionItem(
                            '1',
                            'This exam requires camera and microphone access for proctoring.',
                          ),
                          const SizedBox(height: 16),
                          _buildInstructionItem(
                            '2',
                            'You must remain in view of your camera throughout the exam.',
                          ),
                          const SizedBox(height: 16),
                          _buildInstructionItem(
                            '3',
                            'No other applications should be open during the exam.',
                          ),
                          const SizedBox(height: 16),
                          _buildInstructionItem(
                            '4',
                            'Once started, the exam timer cannot be paused.',
                          ),
                          const SizedBox(height: 16),
                          _buildInstructionItem(
                            '5',
                            'All answers are automatically saved as you progress.',
                          ),

                          // Custom instructions from exam data
                          if (widget.examData['instructions'] != null) ...[
                            const Divider(height: 32),
                            Text(
                              "Additional Instructions:",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue.shade800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.examData['instructions'] as String,
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade800,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Permissions Section
                  Row(
                    children: [
                      Icon(Icons.security_outlined, color: Colors.blue.shade800, size: 28),
                      const SizedBox(width: 10),
                      Text(
                        "Required Permissions",
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Permissions Card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildPermissionItem(
                            Icons.camera_alt_outlined,
                            'Camera',
                            'Required for proctoring and identity verification',
                            cameraPermissionGranted,
                          ),
                          const SizedBox(height: 16),
                          _buildPermissionItem(
                            Icons.mic_outlined,
                            'Microphone',
                            'Required for audio proctoring during the exam',
                            microphonePermissionGranted,
                          ),
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _requestPermissions,
                              icon: const Icon(Icons.perm_device_information),
                              label: Text(
                                cameraPermissionGranted && microphonePermissionGranted
                                    ? "Permissions Granted"
                                    : "Grant Permissions",
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: cameraPermissionGranted && microphonePermissionGranted
                                    ? Colors.green.shade600
                                    : Colors.blue.shade700,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Agreement Checkbox
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Checkbox(
                            value: agreementChecked,
                            activeColor: Colors.blue.shade700,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            onChanged: (bool? value) {
                              setState(() {
                                agreementChecked = value ?? false;
                              });
                            },
                          ),
                          Expanded(
                            child: Text(
                              "I have read and agree to follow all exam rules and understand that any violation may result in disqualification.",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade300,
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.blue.shade700,
                  side: BorderSide(color: Colors.blue.shade700),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "Go Back",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ElevatedButton(
                onPressed: (widget.canStartExam || isExamLive) ? _startExam : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  disabledBackgroundColor: Colors.blue.shade200,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  (widget.canStartExam || isExamLive) ? "Start Exam" : "Not Available",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExamInfoItem(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.white.withOpacity(0.8), size: 18),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInstructionItem(String number, String instruction) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.blue.shade700,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            instruction,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade800,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionItem(IconData icon, String permission, String description, bool isGranted) {
    return Row(
      children: [
        Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: isGranted ? Colors.green.shade50 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: isGranted ? Colors.green.shade600 : Colors.grey.shade500,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    permission,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isGranted)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        "Granted",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}