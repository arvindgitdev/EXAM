import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class TeacherResultsPage extends StatefulWidget {
  final String examId;

  const TeacherResultsPage({super.key, required this.examId});

  @override
  TeacherResultsPageState createState() => TeacherResultsPageState();
}

class TeacherResultsPageState extends State<TeacherResultsPage> {
  bool _isLoading = true;
  Map<String, dynamic>? _examDetails;
  List<Map<String, dynamic>> _students = [];
  int _totalSubmissions = 0;

  @override
  void initState() {
    super.initState();
    _fetchExamDetails();
  }

  Future<void> _fetchExamDetails() async {
    setState(() => _isLoading = true);

    try {
      // Fetch exam details
      final examDoc = await FirebaseFirestore.instance
          .collection('exams')
          .doc(widget.examId)
          .get();

      if (examDoc.exists) {
        _examDetails = examDoc.data();

        // Fetch student submissions
        final submissionsSnapshot = await FirebaseFirestore.instance
            .collection('exam_submissions')
            .where('examId', isEqualTo: widget.examId)
            .get();

        _students = submissionsSnapshot.docs
            .map((doc) => {...doc.data(), 'id': doc.id})
            .toList();

        // Sort students by score in descending order
        _students.sort((a, b) => (b['score'] ?? 0).compareTo(a['score'] ?? 0));

        // Set total number of submissions
        _totalSubmissions = _students.length;
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading results: $e'))
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Color _getScoreColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.blue;
    if (score >= 40) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Exam Results",
          style: GoogleFonts.poppins(
            fontSize: 20,
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
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildStudentsList(),
    );
  }

  Widget _buildStudentsList() {
    if (_students.isEmpty) {
      return const Center(
        child: Text('No student submissions yet'),
      );
    }

    return Column(
      children: [
        _buildExamInfoCard(),
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Total Submissions: $_totalSubmissions',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _students.length,
            itemBuilder: (context, index) {
              final student = _students[index];
              return _buildStudentCard(student, index + 1);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildExamInfoCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _examDetails?['title'] ?? 'Unknown Exam',
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _examDetails?['subject'] ?? 'Unknown Subject',
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoItem(Icons.date_range, 'Date',
                    _examDetails?['date'] ?? 'Unknown'),
                _buildInfoItem(Icons.access_time, 'Time',
                    _examDetails?['time'] ?? 'Unknown'),
                _buildInfoItem(Icons.timer, 'Duration',
                    _examDetails?['duration'] ?? 'Unknown'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: Colors.blue.shade700, size: 20),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student, int rank) {
    final score = student['score'] ?? 0.0;
    // Check both 'name' and 'studentName' fields
    final studentName = student['name'] ?? student['studentName'] ??
        'Unknown Student';

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: _getScoreColor(score),
          child: Text(
            '${score.toInt()}%',
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$rank',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                studentName,
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          'Submitted: ${student['submissionTime'] ?? 'Unknown'}',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey.shade600,
          ),
        ),
        children: [
          _buildStudentAnswers(student),
        ],
      ),
    );
  }

  // Enhanced question text extraction method
  String _getQuestionText(dynamic question) {
    // First try "questionText" field (as in the original code)
    if (question is Map && question.containsKey('questionText')) {
      return question['questionText'].toString();
    }

    // Try "text" field (as mentioned in your issue)
    if (question is Map && question.containsKey('text')) {
      return question['text'].toString();
    }

    // For any other format (direct string or other structure)
    if (question is String) {
      return question;
    }

    return 'Unknown Question';
  }

  Widget _buildStudentAnswers(Map<String, dynamic> student) {
    final answers = student['answers'];
    final questions = _examDetails?['questions'] as List? ?? [];

    if (answers == null || questions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text('No answers available'),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: questions.length,
      itemBuilder: (context, index) {
        final question = index < questions.length ? questions[index] : null;
        if (question == null) return const SizedBox.shrink();

        // Get student answer based on data structure (handles both List and Map formats)
        dynamic studentAnswerData;
        if (answers is List && index < answers.length) {
          studentAnswerData = answers[index];
        } else if (answers is Map) {
          studentAnswerData = answers[index.toString()];
        }

        if (studentAnswerData == null) {
          return _buildAnswerItem(
            index,
            question,
            'No answer provided',
            false,
          );
        }

        // Extract the actual answer value and check if correct
        String studentAnswerValue = '';
        bool isCorrect = false;

        // Handle case where studentAnswerData is a Map with 'answer' and possibly 'isCorrect' fields
        if (studentAnswerData is Map) {
          // Extract the answer value
          studentAnswerValue =
              studentAnswerData['answer']?.toString() ?? 'No answer';

          // Determine if the answer is correct
          if (studentAnswerData.containsKey('isCorrect') &&
              studentAnswerData['isCorrect'] is bool) {
            // Use the explicit isCorrect flag if available
            isCorrect = studentAnswerData['isCorrect'];
          } else if (question is Map) {
            // Compare with the correct answer if isCorrect flag isn't available
            final correctAnswer = _getCorrectAnswer(question);
            if (correctAnswer.isNotEmpty) {
              isCorrect = studentAnswerValue.trim().toLowerCase() ==
                  correctAnswer.trim().toLowerCase();
            }
          }
        }
        // Handle case where studentAnswerData is a direct answer value
        else {
          studentAnswerValue = studentAnswerData.toString();
          if (question is Map) {
            final correctAnswer = _getCorrectAnswer(question);
            if (correctAnswer.isNotEmpty) {
              isCorrect = studentAnswerValue.trim().toLowerCase() ==
                  correctAnswer.trim().toLowerCase();
            }
          }
        }

        return _buildAnswerItem(index, question, studentAnswerValue, isCorrect);
      },
    );
  }

  // Helper method to extract correct answer from question with different structures
  String _getCorrectAnswer(Map<dynamic, dynamic> question) {
    if (question.containsKey('correctAnswer')) {
      return question['correctAnswer'].toString();
    }

    // Try alternative field names
    if (question.containsKey('correct_answer')) {
      return question['correct_answer'].toString();
    }

    if (question.containsKey('answer')) {
      return question['answer'].toString();
    }

    return '';
  }

  Widget _buildAnswerItem(int index, dynamic question, String studentAnswer,
      bool isCorrect) {
    final questionText = _getQuestionText(question);
    final correctAnswer = question is Map ? _getCorrectAnswer(question) : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCorrect ? Colors.green.withOpacity(0.1) : Colors.red
            .withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCorrect ? Colors.green.withOpacity(0.3) : Colors.red
              .withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Q${index + 1}: $questionText',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Student\'s answer: ',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
              Expanded(
                child: Text(
                  studentAnswer,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                isCorrect ? Icons.check_circle : Icons.cancel,
                color: isCorrect ? Colors.green : Colors.red,
                size: 16,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Correct answer: ',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: Colors.grey.shade700,
                ),
              ),
              Expanded(
                child: Text(
                  correctAnswer.isNotEmpty ? correctAnswer : 'Not available',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}