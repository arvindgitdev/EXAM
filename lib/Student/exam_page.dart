
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:examnow/Student/student_dashboard.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Import WebRTC handler
import 'webrtc_exam_handler.dart';

class StudentExamPage extends StatefulWidget {
  final String examId;
  final String examTitle;

  const StudentExamPage({
    super.key,
    required this.examId,
    required this.examTitle,
  });

  @override
  StudentExamPageState createState() => StudentExamPageState();
}

class StudentExamPageState extends State<StudentExamPage> with WidgetsBindingObserver {
  bool _isLoading = true;
  List<Map<String, dynamic>> _questions = [];
  final Map<String, Map<String, dynamic>> _studentAnswers = {}; // Changed to store question data with answers
  int _currentQuestionIndex = 0;
  bool _examSubmitted = false;
  bool _isSubmitting = false;

  // For short answer questions
  final Map<int, TextEditingController> _answerControllers = {};

  // Timer for auto-saving answers
  Timer? _autoSaveTimer;

  // WebRTC monitoring
  WebRTCExamHandler? _webrtcHandler;
  bool _isMonitoringActive = false;

  // For monitoring
  int _appBackgroundCount = 0;

  // Time tracking
  DateTime? _examStartTime;
  Timer? _examTimeTimer;
  int _remainingTimeInSeconds = 0;
  int _totalExamTimeInMinutes = 0;

  // Student information
  String _studentName = "";
  String _studentEmail = "";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchStudentInfo();
    _initializeExam();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSaveTimer?.cancel();
    _examTimeTimer?.cancel();
    _webrtcHandler?.dispose();

    // Dispose text controllers to prevent memory leaks
    _answerControllers.forEach((_, controller) => controller.dispose());

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _handleAppBackground();
    } else if (state == AppLifecycleState.resumed) {
      _resumeMonitoring();
    }
  }

  // Fetch student information from Firebase Auth and Firestore
  Future<void> _fetchStudentInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Get display name from Firebase Auth
        _studentEmail = user.email ?? "";

        if (user.displayName != null && user.displayName!.isNotEmpty) {
          _studentName = user.displayName!;
        } else {
          // If display name is not available in Auth, try to fetch from Firestore
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (userDoc.exists) {
            final userData = userDoc.data();
            _studentName = userData?['fullName'] ??
                userData?['name'] ??
                userData?['displayName'] ??
                _studentEmail.split('@')[0]; // Fallback to email username
          } else {
            _studentName = _studentEmail.split('@')[0]; // Fallback to email username
          }
        }

        debugPrint('Student info loaded: $_studentName ($_studentEmail)');
      }
    } catch (e) {
      debugPrint('Error fetching student info: $e');
    }
  }

  Future<void> _initializeExam() async {
    setState(() => _isLoading = true);

    try {
      // Load exam data
      final examDoc = await FirebaseFirestore.instance.collection("exams").doc(widget.examId).get();
      if (!examDoc.exists) {
        _showErrorAndNavigateBack("Exam not found");
        return;
      }

      final examData = examDoc.data()!;
      final user = FirebaseAuth.instance.currentUser;

      // Get exam time limit and exam schedule information
      // Read the time limit properly - ensure it's converted to int
      // If timeLimit is specified as a string, integer, or double, it will be properly handled
      var timeLimit = examData['timeLimit'];
      if (timeLimit is String) {
        _totalExamTimeInMinutes = int.tryParse(timeLimit) ?? 60;
      } else if (timeLimit is int) {
        _totalExamTimeInMinutes = timeLimit;
      } else if (timeLimit is double) {
        _totalExamTimeInMinutes = timeLimit.toInt();
      } else {
        // Fallback default
        _totalExamTimeInMinutes = 60;
        debugPrint("Warning: Invalid timeLimit format in database. Using default 60 minutes.");
      }

      // Debug print to confirm the time limit is being read correctly
      debugPrint('Exam time limit: $_totalExamTimeInMinutes minutes');

      final examStartDateTime = examData['scheduledStartTime'] != null
          ? (examData['scheduledStartTime'] as Timestamp).toDate()
          : null;
      final examEndDateTime = examData['scheduledEndTime'] != null
          ? (examData['scheduledEndTime'] as Timestamp).toDate()
          : null;

      // Load questions first
      if (examData['questions'] != null) {
        _questions = (examData['questions'] as List<dynamic>).cast<Map<String, dynamic>>();
      }

      // Check if student already has an ongoing attempt
      final attemptDoc = await FirebaseFirestore.instance
          .collection("exam_submissions")
          .where("examId", isEqualTo: widget.examId)
          .where("userId", isEqualTo: user?.uid)
          .where("isCompleted", isEqualTo: false)
          .limit(1)
          .get();

      if (attemptDoc.docs.isNotEmpty) {
        // Resume existing attempt
        final attemptData = attemptDoc.docs.first.data();
        final savedAnswers = attemptData['answers'] as Map<String, dynamic>?;

        if (savedAnswers != null) {
          savedAnswers.forEach((key, value) {
            // Convert stored answers to our new format
            if (value is Map<String, dynamic>) {
              _studentAnswers[key] = value;
            } else {
              // Handle legacy format (just the answer value)
              final questionIndex = int.tryParse(key);
              if (questionIndex != null && questionIndex < _questions.length) {
                final questionData = _questions[questionIndex];
                _studentAnswers[key] = {
                  'answer': value,
                  'questionText': questionData['text'],
                  'questionType': questionData['type'],
                };
              }
            }

            // Set up text controllers for short answer questions
            final questionIndex = int.tryParse(key);
            if (questionIndex != null) {
              final questionData = _questions[questionIndex];
              if (questionData['type'] == 'Short Answer') {
                final answer = _studentAnswers[key]?['answer'] as String? ?? '';
                _answerControllers[questionIndex] = TextEditingController(text: answer);
              }
            }
          });
        }

        // Calculate remaining time precisely based on when they started
        final startTime = (attemptData['startTime'] as Timestamp).toDate();
        _examStartTime = startTime;

        // If allocatedTimeInSeconds is stored in the attempt, use that value instead
        // This ensures we're using the original time allocation
        if (attemptData['allocatedTimeInSeconds'] != null && attemptData['allocatedTimeInSeconds'] is int) {
          final totalAllocatedSeconds = attemptData['allocatedTimeInSeconds'] as int;
          final elapsedSeconds = DateTime.now().difference(startTime).inSeconds;
          _remainingTimeInSeconds = totalAllocatedSeconds - elapsedSeconds;
        } else {
          // Calculate elapsed time
          final elapsedSeconds = DateTime.now().difference(startTime).inSeconds;
          // Calculate remaining time based on their actual start time
          _remainingTimeInSeconds = (_totalExamTimeInMinutes * 60) - elapsedSeconds;

          // If using scheduled end time, calculate based on that instead
          if (examEndDateTime != null) {
            final secondsUntilEnd = examEndDateTime.difference(DateTime.now()).inSeconds;
            // Use the smaller value between time-based calculation and scheduled end
            _remainingTimeInSeconds = secondsUntilEnd < _remainingTimeInSeconds
                ? secondsUntilEnd
                : _remainingTimeInSeconds;
          }
        }

        // Ensure no negative time
        if (_remainingTimeInSeconds < 0) _remainingTimeInSeconds = 0;

        // Update the student information if it wasn't available when we first created the submission
        if (_studentName.isNotEmpty && (attemptData['studentName'] == null || attemptData['studentName'].isEmpty)) {
          await attemptDoc.docs.first.reference.update({
            'studentName': _studentName,
            'studentEmail': _studentEmail,
          });
        }
      } else {
        // Create new attempt - use current time as start time
        _examStartTime = DateTime.now();

        // Calculate remaining time for a new attempt
        if (examEndDateTime != null) {
          // If there's a scheduled end time, use time until then
          final secondsUntilEnd = examEndDateTime.difference(_examStartTime!).inSeconds;
          // Use the smaller value between allocated time and time until scheduled end
          _remainingTimeInSeconds = secondsUntilEnd < (_totalExamTimeInMinutes * 60)
              ? secondsUntilEnd
              : (_totalExamTimeInMinutes * 60);
        } else {
          // Otherwise use the full allocated time
          _remainingTimeInSeconds = _totalExamTimeInMinutes * 60;
        }

        // Ensure no negative time
        if (_remainingTimeInSeconds < 0) _remainingTimeInSeconds = 0;

        debugPrint('Setting exam time to: $_remainingTimeInSeconds seconds');

        // Create the attempt record with student name and email
        await FirebaseFirestore.instance.collection("exam_submissions").add({
          'examId': widget.examId,
          'examTitle': widget.examTitle,
          'userId': user?.uid,
          'studentName': _studentName,
          'studentEmail': _studentEmail,
          'startTime': Timestamp.fromDate(_examStartTime!),
          'isCompleted': false,
          'answers': {},
          'monitoringEvents': [],
          'allocatedTimeInSeconds': _remainingTimeInSeconds, // Store the allocated time
          'examTimeInMinutes': _totalExamTimeInMinutes, // Also store the exam time in minutes for reference
        });

        // Set up text controllers for short answer questions
        for (int i = 0; i < _questions.length; i++) {
          if (_questions[i]['type'] == 'Short Answer') {
            _answerControllers[i] = TextEditingController();
          }
        }
      }

      // Start exam timer
      _startExamTimer();

      // Start WebRTC monitoring
      await _initializeWebRTCMonitoring();

      // Set up auto-save timer (every 30 seconds)
      _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _saveAnswers();
      });

    } catch (e) {
      _showErrorAndNavigateBack("Error loading exam: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _startExamTimer() {
    _examTimeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingTimeInSeconds > 0) {
          _remainingTimeInSeconds--;
        } else {
          _examTimeTimer?.cancel();
          _submitExam(timeExpired: true);
        }
      });
    });
  }

  Future<void> _initializeWebRTCMonitoring() async {
    final user = FirebaseAuth.instance.currentUser;
    try {
      _webrtcHandler = WebRTCExamHandler(
        examId: widget.examId,
        studentId: user!.uid,
        onError: (String errorMessage) {
          _logMonitoringEvent('WebRTC Error: $errorMessage');
        },
        onConnectionEstablished: () {
          setState(() => _isMonitoringActive = true);
        },
      );
      await _webrtcHandler!.initialize();
    } catch (e) {
      _logMonitoringEvent("Error initializing WebRTC monitoring: $e");
    }
  }

  Future<void> _resumeMonitoring() async {
    if (_webrtcHandler == null) {
      await _initializeWebRTCMonitoring();
    }
  }

  void _handleAppBackground() {
    _appBackgroundCount++;
    _logMonitoringEvent("App backgrounded (count: $_appBackgroundCount)");
    _saveAnswers();

    if (_appBackgroundCount >= 2) {
      _submitExam(forcedExit: true);
    }
  }

  Future<void> _logMonitoringEvent(String event) async {
    final user = FirebaseAuth.instance.currentUser;
    try {
      final attemptQuery = await FirebaseFirestore.instance
          .collection("exam_submissions")
          .where("examId", isEqualTo: widget.examId)
          .where("userId", isEqualTo: user?.uid)
          .where("isCompleted", isEqualTo: false)
          .limit(1)
          .get();

      if (attemptQuery.docs.isNotEmpty) {
        await attemptQuery.docs.first.reference.update({
          'monitoringEvents': FieldValue.arrayUnion([
            {
              'timestamp': Timestamp.now(),
              'event': event,
              'questionIndex': _currentQuestionIndex,
            }
          ])
        });
      }
    } catch (e) {
      debugPrint("Failed to log monitoring event: $e");
    }
  }

  Future<void> _saveAnswers() async {
    if (_studentAnswers.isEmpty || _examSubmitted) return;

    final user = FirebaseAuth.instance.currentUser;
    try {
      final attemptQuery = await FirebaseFirestore.instance
          .collection("exam_submissions")
          .where("examId", isEqualTo: widget.examId)
          .where("userId", isEqualTo: user?.uid)
          .where("isCompleted", isEqualTo: false)
          .limit(1)
          .get();

      if (attemptQuery.docs.isNotEmpty) {
        await attemptQuery.docs.first.reference.update({
          'answers': _studentAnswers,
          'lastSaved': Timestamp.now(),
        });
      }
    } catch (e) {
      debugPrint("Failed to save answers: $e");
    }
  }

  Future<void> _submitExam({bool timeExpired = false, bool forcedExit = false}) async {
    if (_examSubmitted || _isSubmitting) return;

    setState(() => _isSubmitting = true);
    final user = FirebaseAuth.instance.currentUser;

    try {
      final attemptQuery = await FirebaseFirestore.instance
          .collection("exam_submissions")
          .where("examId", isEqualTo: widget.examId)
          .where("userId", isEqualTo: user?.uid)
          .where("isCompleted", isEqualTo: false)
          .limit(1)
          .get();

      if (attemptQuery.docs.isNotEmpty) {
        final now = DateTime.now();
        await attemptQuery.docs.first.reference.update({
          'answers': _studentAnswers,
          'isCompleted': true,
          'submissionTime': Timestamp.now(),
          'endTime': Timestamp.now(),
          'timeSpentInSeconds': _examStartTime != null ? now.difference(_examStartTime!).inSeconds : null,
          'submissionReason': timeExpired ? 'time_expired' : forcedExit ? 'forced_exit' : 'normal',
          // Ensure student information is included
          'studentName': _studentName,
          'studentEmail': _studentEmail,
          // Add formatted submission timestamp for easier reading
          'submissionTimestamp': now.toString(),
        });

        setState(() {
          _examSubmitted = true;
          _isSubmitting = false;
        });

        // Show completion dialog
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: Text(
                timeExpired ? "Time's Up!" : "Exam Submitted",
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
              ),
              content: Text(
                timeExpired
                    ? "Your exam time has expired. Your answers have been submitted automatically."
                    : forcedExit
                    ? "You left the exam twice. Your answers have been submitted automatically."
                    : "Your exam has been submitted successfully.",
                style: GoogleFonts.poppins(),
              ),
              actions: [
                TextButton(
                  child: Text("Return to Dashboard", style: GoogleFonts.poppins(color: Colors.blue)),
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const Studentpage()),
                          (route) => false,
                    );
                  },
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isSubmitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to submit exam: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _goToNextQuestion() {
    _saveAnswers();  // Auto-save when moving to next question
    if (_currentQuestionIndex < _questions.length - 1) {
      setState(() => _currentQuestionIndex++);
    } else {
      _confirmSubmitExam();
    }
  }

  void _goToPreviousQuestion() {
    _saveAnswers();  // Auto-save when moving to previous question
    if (_currentQuestionIndex > 0) {
      setState(() => _currentQuestionIndex--);
    }
  }

  void _confirmSubmitExam() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Submit Exam?", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
          "Are you sure you want to submit your exam? You cannot change your answers after submission.",
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            child: Text("Cancel", style: GoogleFonts.poppins(color: Colors.grey)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: Text("Submit", style: GoogleFonts.poppins(color: Colors.white)),
            onPressed: () {
              Navigator.of(context).pop();
              _submitExam();
            },
          ),
        ],
      ),
    );
  }

  void _showErrorAndNavigateBack(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text("Error", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(message, style: GoogleFonts.poppins()),
        actions: [
          TextButton(
            child: Text("Return", style: GoogleFonts.poppins(color: Colors.blue)),
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }

  void _updateStudentAnswer(dynamic answer) {
    final currentQuestionStr = _currentQuestionIndex.toString();
    final currentQuestion = _questions[_currentQuestionIndex];

    setState(() {
      _studentAnswers[currentQuestionStr] = {
        'answer': answer,
        'questionText': currentQuestion['text'],
        'questionType': currentQuestion['type'],
        // For multiple choice, also store the option text
        if (currentQuestion['type'] == 'Multiple Choice' && answer is int &&
            currentQuestion['options'] is List &&
            (currentQuestion['options'] as List).length > answer)
          'selectedOptionText': (currentQuestion['options'] as List)[answer],
      };
    });

    _saveAnswers();  // Auto-save when answer is updated
  }

  Widget _buildQuestionContent() {
    if (_questions.isEmpty) {
      return Center(child: Text("No questions available", style: GoogleFonts.poppins(fontSize: 18)));
    }

    final question = _questions[_currentQuestionIndex];
    final questionType = question['type'] as String;
    final questionText = question['text'] as String;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Question ${_currentQuestionIndex + 1} of ${_questions.length}",
          style: GoogleFonts.poppins(fontSize: 14, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Text(
          questionText,
          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 24),

        if (questionType == 'Multiple Choice')
          _buildMultipleChoiceQuestion(question),
        if (questionType == 'True/False')
          _buildTrueFalseQuestion(question),
        if (questionType == 'Short Answer')
          _buildShortAnswerQuestion(question),
      ],
    );
  }

  Widget _buildMultipleChoiceQuestion(Map<String, dynamic> question) {
    final options = question['options'] as List<dynamic>;
    final currentQuestionStr = _currentQuestionIndex.toString();
    final selectedOption = _studentAnswers[currentQuestionStr]?['answer'] as int?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(options.length, (index) {
        return RadioListTile<int>(
          title: Text(options[index] as String, style: GoogleFonts.poppins(fontSize: 16)),
          value: index,
          groupValue: selectedOption,
          onChanged: (value) => _updateStudentAnswer(value),
          activeColor: Colors.blue.shade700,
          contentPadding: EdgeInsets.zero,
        );
      }),
    );
  }

  Widget _buildTrueFalseQuestion(Map<String, dynamic> question) {
    final currentQuestionStr = _currentQuestionIndex.toString();
    final selectedOption = _studentAnswers[currentQuestionStr]?['answer'] as bool?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadioListTile<bool>(
          title: Text('True', style: GoogleFonts.poppins(fontSize: 16)),
          value: true,
          groupValue: selectedOption,
          onChanged: (value) => _updateStudentAnswer(value),
          activeColor: Colors.blue.shade700,
          contentPadding: EdgeInsets.zero,
        ),
        RadioListTile<bool>(
          title: Text('False', style: GoogleFonts.poppins(fontSize: 16)),
          value: false,
          groupValue: selectedOption,
          onChanged: (value) => _updateStudentAnswer(value),
          activeColor: Colors.blue.shade700,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _buildShortAnswerQuestion(Map<String, dynamic> question) {
    // Use or create a controller for this question
    if (!_answerControllers.containsKey(_currentQuestionIndex)) {
      final currentQuestionStr = _currentQuestionIndex.toString();
      final savedAnswer = _studentAnswers[currentQuestionStr]?['answer'] as String? ?? '';
      _answerControllers[_currentQuestionIndex] = TextEditingController(text: savedAnswer);
    }

    return TextField(
      controller: _answerControllers[_currentQuestionIndex],
      onChanged: (value) => _updateStudentAnswer(value),
      maxLines: 5,
      decoration: InputDecoration(
        hintText: 'Enter your answer here...',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      style: GoogleFonts.poppins(fontSize: 16),
    );
  }

  String _formatTimeRemaining() {
    final minutes = (_remainingTimeInSeconds / 60).floor();
    final seconds = _remainingTimeInSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildNavigationButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        ElevatedButton.icon(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          label: Text('Previous', style: GoogleFonts.poppins(color: Colors.white)),
          onPressed: _currentQuestionIndex > 0 ? _goToPreviousQuestion : null,
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700),
        ),
        ElevatedButton.icon(
          icon: Icon(
            _currentQuestionIndex < _questions.length - 1 ? Icons.arrow_forward : Icons.check,
            color: Colors.white,
          ),
          label: Text(
            _currentQuestionIndex < _questions.length - 1 ? 'Next' : 'Finish',
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          onPressed: _goToNextQuestion,
          style: ElevatedButton.styleFrom(
            backgroundColor: _currentQuestionIndex < _questions.length - 1 ? Colors.blue.shade700 : Colors.green.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionNavigator() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      height: 50,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _questions.length,
        itemBuilder: (context, index) {
          final hasAnswer = _studentAnswers.containsKey(index.toString());
          return GestureDetector(
            onTap: () {
              setState(() {
                _currentQuestionIndex = index;
              });
              _saveAnswers();
            },
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: _currentQuestionIndex == index
                    ? Colors.blue.shade800
                    : hasAnswer
                    ? Colors.green.shade200
                    : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _currentQuestionIndex == index ? Colors.blue.shade800 : Colors.grey,
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  '${index + 1}',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _currentQuestionIndex == index ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (!_examSubmitted) {
          return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Exit Exam?', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
              content: Text('Are you sure? This will count as leaving the exam.', style: GoogleFonts.poppins()),
              actions: [
                TextButton(
                  child: Text('Stay', style: GoogleFonts.poppins(color: Colors.blue)),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: Text('Exit', style: GoogleFonts.poppins(color: Colors.white)),
                  onPressed: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ) ?? false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.examTitle, style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          backgroundColor: Colors.blue.shade800,
          foregroundColor: Colors.white,
          actions: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: _remainingTimeInSeconds < 300 ? Colors.red.shade100 : Colors.blue.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.timer,
                      color: _remainingTimeInSeconds < 300 ? Colors.red : Colors.blue.shade800, size: 18),
                  const SizedBox(width: 4),
                  Text(_formatTimeRemaining(),
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        color: _remainingTimeInSeconds < 300 ? Colors.red : Colors.blue.shade800,
                      )),
                ],
              ),
            ),
            if (_isMonitoringActive)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(right: 8),
                child: const Icon(Icons.videocam, color: Colors.green, size: 20),
              ),
            // Add exam progress indicator
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.only(right: 12),
              child: Tooltip(
                message: "Your exam progress",
                child: Badge(
                  label: Text(
                    "${_studentAnswers.length}/${_questions.length}",
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 12),
                  ),
                  child: const Icon(Icons.assignment_turned_in, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _examSubmitted
            ? Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 64),
              const SizedBox(height: 24),
              Text("Exam Submitted",
                  style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: Text("Return to Dashboard",
                    style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        )
            : Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Add question navigator
              _buildQuestionNavigator(),
              Expanded(
                child: SingleChildScrollView(
                  child: _buildQuestionContent(),
                ),
              ),
              const SizedBox(height: 24),
              _buildNavigationButtons(),
            ],
          ),
        ),
      ),
    );
  }
}