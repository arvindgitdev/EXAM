import 'package:examnow/Teacher/question_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';


class ViewExamQuestionsPage extends StatefulWidget {
  final String examId;
  final String examTitle;

  const ViewExamQuestionsPage({
    Key? key,
    required this.examId,
    required this.examTitle,
  }) : super(key: key);

  @override
  State<ViewExamQuestionsPage> createState() => _ViewExamQuestionsPageState();
}

class _ViewExamQuestionsPageState extends State<ViewExamQuestionsPage> {
  bool _isLoading = true;
  String _errorMessage = '';
  List<Map<String, dynamic>> _questions = [];
  Map<String, dynamic>? _examData;

  @override
  void initState() {
    super.initState();
    _loadExamData();
  }

  Future<void> _loadExamData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final examDoc = await FirebaseFirestore.instance
          .collection("exams")
          .doc(widget.examId)
          .get();

      if (!examDoc.exists) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Exam not found. It may have been deleted.';
        });
        return;
      }

      final data = examDoc.data() as Map<String, dynamic>;

      setState(() {
        _examData = data;
        _questions = List<Map<String, dynamic>>.from(data['questions'] ?? []);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error loading questions: ${e.toString()}';
      });
    }
  }

  Future<void> _refreshQuestions() async {
    await _loadExamData();
  }

  void _navigateToQuestionEditor() {
    // This would navigate to your QuestionEditorPage
    // You would pass the required parameters based on your existing code
    final allowedTypes = (_examData?['settings']?['questionTypes'] as List<dynamic>?)?.cast<String>() ??
        ['Multiple Choice', 'True/False', 'Short Answer'];

    final targetCount = _examData?['questionCount'] ?? 10;

    // Here you would navigate to your question editor
     Navigator.push(
       context,
      MaterialPageRoute(
         builder: (context) => QuestionEditorPage(
           examId: widget.examId,
           examTitle: widget.examTitle,
           allowedQuestionTypes: allowedTypes,
          targetQuestionCount: targetCount,
         ),
       ),
     ).then((_) => _refreshQuestions());

    // For now, just show a message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Navigating to question editor')),
    );
  }

  Future<void> _deleteQuestion(int index) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Delete Question',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Are you sure you want to delete this question? This action cannot be undone.',
          style: GoogleFonts.poppins(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      setState(() => _isLoading = true);

      // Remove the question from the list
      List<Map<String, dynamic>> updatedQuestions = List.from(_questions);
      updatedQuestions.removeAt(index);

      // Update Firestore document
      await FirebaseFirestore.instance
          .collection("exams")
          .doc(widget.examId)
          .update({
        'questions': updatedQuestions,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Question deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );

      // Refresh the questions
      await _refreshQuestions();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error deleting question: ${e.toString()}';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete question: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Questions: ${widget.examTitle}',
          style: GoogleFonts.poppins(
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _refreshQuestions,
            tooltip: 'Refresh Questions',
          ),
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.white),
            onPressed: _navigateToQuestionEditor,
            tooltip: 'Edit All Questions',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? _buildErrorView()
          : _buildQuestionsView(),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToQuestionEditor,
        backgroundColor: Colors.blue.shade700,
        tooltip: 'Edit Questions',
        child: const Icon(Icons.edit, color: Colors.white),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 60, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            'Error',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                color: Colors.red.shade700,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            onPressed: _refreshQuestions,
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionsView() {
    if (_questions.isEmpty) {
      return _buildEmptyQuestionsView();
    }

    return RefreshIndicator(
      onRefresh: _refreshQuestions,
      child: Column(
        children: [
          // Exam summary header
          _buildExamSummary(),

          // Question list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _questions.length,
              itemBuilder: (context, index) {
                return _buildQuestionCard(index, _questions[index]);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExamSummary() {
    final status = _examData?['status'] ?? 'draft';
    final date = _examData?['date'] ?? '';
    final time = _examData?['time'] ?? '';
    final duration = _examData?['duration'] ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            offset: const Offset(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.date_range,
                size: 16,
                color: Colors.blue.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                "$date at $time",
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getStatusColor(status),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.timer,
                size: 16,
                color: Colors.blue.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                "Duration: $duration",
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                Icons.help_outline,
                size: 16,
                color: Colors.blue.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                "${_questions.length} of ${_examData?['questionCount'] ?? 0} questions",
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _questions.length >= (_examData?['questionCount'] ?? 0)
                      ? Colors.green.shade700
                      : Colors.orange.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'draft':
        return Colors.grey.shade600;
      case 'active':
        return Colors.green.shade600;
      case 'completed':
        return Colors.blue.shade600;
      default:
        return Colors.grey.shade600;
    }
  }

  Widget _buildEmptyQuestionsView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.help_outline,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            "No Questions Added Yet",
            style: GoogleFonts.poppins(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "Add questions to your exam by clicking the edit button below",
              style: GoogleFonts.poppins(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            icon: const Icon(Icons.add),
            label: Text('Add Questions', style: GoogleFonts.poppins()),
            onPressed: _navigateToQuestionEditor,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionCard(int index, Map<String, dynamic> question) {
    final questionText = question['text'] ?? 'No question text';
    final questionType = question['type'] ?? 'Multiple Choice';

    // Get color and icon based on question type
    final Color cardColor;
    final IconData typeIcon;

    switch (questionType) {
      case 'Multiple Choice':
        cardColor = Colors.blue.shade50;
        typeIcon = Icons.radio_button_checked;
        break;
      case 'True/False':
        cardColor = Colors.green.shade50;
        typeIcon = Icons.check_circle_outline;
        break;
      case 'Short Answer':
        cardColor = Colors.orange.shade50;
        typeIcon = Icons.short_text;
        break;
      default:
        cardColor = Colors.grey.shade100;
        typeIcon = Icons.help_outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: cardColor.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Question header with number and type
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Text(
                    "${index + 1}",
                    style: GoogleFonts.poppins(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Row(
                  children: [
                    Icon(typeIcon, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      questionType,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _deleteQuestion(index),
                  tooltip: "Delete question",
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Question text
            Text(
              questionText,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // Display based on question type
            if (questionType == 'Multiple Choice')
              _buildMultipleChoiceOptions(question),

            if (questionType == 'True/False')
              _buildTrueFalseOptions(question),

            if (questionType == 'Short Answer')
              _buildShortAnswerDisplay(question),
          ],
        ),
      ),
    );
  }

  Widget _buildMultipleChoiceOptions(Map<String, dynamic> question) {
    final options = question['options'] as List<dynamic>? ?? [];
    final correctIndex = question['correctOptionIndex'] as int? ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Options:',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(options.length, (i) {
          final option = options[i];
          final isCorrect = i == correctIndex;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isCorrect ? Colors.green.shade50 : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCorrect ? Colors.green.shade300 : Colors.grey.shade300,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${String.fromCharCode(65 + i)}.',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w500,
                    color: isCorrect ? Colors.green.shade700 : Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    option.toString(),
                    style: GoogleFonts.poppins(
                      color: isCorrect ? Colors.green.shade700 : null,
                    ),
                  ),
                ),
                if (isCorrect)
                  Icon(
                    Icons.check_circle,
                    color: Colors.green.shade600,
                    size: 18,
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTrueFalseOptions(Map<String, dynamic> question) {
    final isTrue = question['correctAnswer'] == 'True';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Options:',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isTrue ? Colors.green.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isTrue ? Colors.green.shade300 : Colors.grey.shade300,
            ),
          ),
          child: Row(
            children: [
              Text(
                'True',
                style: GoogleFonts.poppins(
                  color: isTrue ? Colors.green.shade700 : null,
                ),
              ),
              const Spacer(),
              if (isTrue)
                Icon(
                  Icons.check_circle,
                  color: Colors.green.shade600,
                  size: 18,
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: !isTrue ? Colors.green.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: !isTrue ? Colors.green.shade300 : Colors.grey.shade300,
            ),
          ),
          child: Row(
            children: [
              Text(
                'False',
                style: GoogleFonts.poppins(
                  color: !isTrue ? Colors.green.shade700 : null,
                ),
              ),
              const Spacer(),
              if (!isTrue)
                Icon(
                  Icons.check_circle,
                  color: Colors.green.shade600,
                  size: 18,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShortAnswerDisplay(Map<String, dynamic> question) {
    final correctAnswer = question['correctAnswer'] ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Correct Answer:',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.shade300),
          ),
          child: Text(
            correctAnswer,
            style: GoogleFonts.poppins(
              color: Colors.green.shade700,
            ),
          ),
        ),
      ],
    );
  }
}