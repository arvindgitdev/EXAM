import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class QuestionEditorPage extends StatefulWidget {
  final String examId;
  final String examTitle;
  final List<String> allowedQuestionTypes;
  final int targetQuestionCount;

  const QuestionEditorPage({
    super.key,
    required this.examId,
    required this.examTitle,
    required this.allowedQuestionTypes,
    required this.targetQuestionCount,
  });

  @override
  QuestionEditorPageState createState() => QuestionEditorPageState();
}

class QuestionEditorPageState extends State<QuestionEditorPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _questions = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExistingQuestions();
  }

  Future<void> _loadExistingQuestions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final examDoc = await FirebaseFirestore.instance
          .collection("exams")
          .doc(widget.examId)
          .get();

      if (examDoc.exists && examDoc.data()?["questions"] != null) {
        final questionsList = examDoc.data()?["questions"] as List<dynamic>;
        setState(() {
          _questions = questionsList.cast<Map<String, dynamic>>();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error loading questions: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveQuestions() async {
    setState(() {
      _isSaving = true;
    });

    try {
      await FirebaseFirestore.instance
          .collection("exams")
          .doc(widget.examId)
          .update({
        "questions": _questions,
        "lastUpdated": FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Questions saved successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error saving questions: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _addQuestion() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => QuestionFormBottomSheet(
        allowedQuestionTypes: widget.allowedQuestionTypes,
      ),
    );

    if (result != null) {
      setState(() {
        _questions.add(result);
      });

      // Auto-save when a new question is added
      await _saveQuestions();
    }
  }

  Future<void> _editQuestion(int index) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => QuestionFormBottomSheet(
        questionData: _questions[index],
        allowedQuestionTypes: widget.allowedQuestionTypes,
      ),
    );

    if (result != null) {
      setState(() {
        _questions[index] = result;
      });

      // Auto-save when a question is edited
      await _saveQuestions();
    }
  }

  void _deleteQuestion(int index) {
    setState(() {
      _questions.removeAt(index);
    });

    // Auto-save when a question is deleted
    _saveQuestions();
  }

  void _reorderQuestions(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _questions.removeAt(oldIndex);
      _questions.insert(newIndex, item);
    });

    // Auto-save after reordering
    _saveQuestions();
  }



  Widget _buildQuestionCard(int index, Map<String, dynamic> question) {
    final Color cardColor;
    final IconData typeIcon;

    switch (question['type']) {
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
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      color: cardColor,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: cardColor.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        leading: CircleAvatar(
          backgroundColor: Colors.white,
          child: Text(
            "${index + 1}",
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade800,
            ),
          ),
        ),
        title: Text(
          question['text'] as String,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w500,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Icon(typeIcon, size: 16),
            const SizedBox(width: 4),
            Text(
              question['type'] as String,
              style: GoogleFonts.poppins(
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.blue),
              onPressed: () => _editQuestion(index),
              tooltip: "Edit question",
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteQuestion(index),
              tooltip: "Delete question",
            ),
          ],
        ),
        onTap: () => _editQuestion(index),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Edit Questions",
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isSaving ? null : _saveQuestions,
            tooltip: "Save questions",
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Header with exam info
          Container(
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
                Text(
                  widget.examTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.help_outline,
                          size: 16,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            "${_questions.length} of ${widget.targetQuestionCount} questions",
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: _questions.length >= widget.targetQuestionCount
                                  ? Colors.green.shade700
                                  : Colors.orange.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          Icons.category,
                          size: 16,
                          color: Colors.blue.shade700,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            "Types: ${widget.allowedQuestionTypes.join(', ')}",
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                )

              ],
            ),
          ),

          // Question list
          Expanded(
            child: _questions.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.help_outline,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "No questions yet",
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text("Add Your First Question"),
                    onPressed: _addQuestion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            )
                : ReorderableListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _questions.length,
              onReorder: _reorderQuestions,
              itemBuilder: (context, index) {
                // Here's the fix: Each child of ReorderableListView needs a key
                return KeyedSubtree(
                  key: ValueKey(index), // Using index as key
                  child: _buildQuestionCard(
                    index,
                    _questions[index],
                  ),
                );
              },
            ),
          ),

          // Add question button at bottom
          if (_questions.isNotEmpty)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(
                      "Add Question",
                      style: GoogleFonts.poppins(),
                    ),
                    onPressed: _addQuestion,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class QuestionFormBottomSheet extends StatefulWidget {
  final Map<String, dynamic>? questionData;
  final List<String> allowedQuestionTypes;

  const QuestionFormBottomSheet({
    super.key,
    this.questionData,
    required this.allowedQuestionTypes,
  });

  @override
  QuestionFormBottomSheetState createState() => QuestionFormBottomSheetState();
}

class QuestionFormBottomSheetState extends State<QuestionFormBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _questionTextController = TextEditingController();

  String _selectedType = 'Multiple Choice';
  final List<TextEditingController> _optionControllers = [];
  int _correctOptionIndex = 0;
  final TextEditingController _correctAnswerController = TextEditingController();
  bool _isTrue = true;

  @override
  void initState() {
    super.initState();

    // Set default type to the first allowed type
    if (widget.allowedQuestionTypes.isNotEmpty) {
      _selectedType = widget.allowedQuestionTypes.first;
    }

    // Initialize option controllers for multiple choice
    _resetOptionControllers();

    // If editing existing question, populate the form
    if (widget.questionData != null) {
      _populateForm();
    }
  }

  void _resetOptionControllers() {
    // Clear any existing controllers
    for (var controller in _optionControllers) {
      controller.dispose();
    }
    _optionControllers.clear();

    // Create 4 default option controllers for multiple choice
    if (_selectedType == 'Multiple Choice') {
      for (int i = 0; i < 4; i++) {
        _optionControllers.add(TextEditingController());
      }
    }
  }

  void _populateForm() {
    final questionData = widget.questionData!;

    _questionTextController.text = questionData['text'] as String;
    _selectedType = questionData['type'] as String;

    switch (_selectedType) {
      case 'Multiple Choice':
        final options = questionData['options'] as List<dynamic>;
        _resetOptionControllers();

        for (int i = 0; i < options.length && i < _optionControllers.length; i++) {
          _optionControllers[i].text = options[i] as String;
        }

        _correctOptionIndex = questionData['correctOptionIndex'] as int;
        break;

      case 'True/False':
        _isTrue = questionData['correctAnswer'] == 'True';
        break;

      case 'Short Answer':
        _correctAnswerController.text = questionData['correctAnswer'] as String;
        break;
    }
  }

  Map<String, dynamic> _getQuestionData() {
    final Map<String, dynamic> questionData = {
      'text': _questionTextController.text.trim(),
      'type': _selectedType,
    };

    switch (_selectedType) {
      case 'Multiple Choice':
        questionData['options'] = _optionControllers
            .map((controller) => controller.text.trim())
            .toList();
        questionData['correctOptionIndex'] = _correctOptionIndex;
        break;

      case 'True/False':
        questionData['correctAnswer'] = _isTrue ? 'True' : 'False';
        break;

      case 'Short Answer':
        questionData['correctAnswer'] = _correctAnswerController.text.trim();
        break;
    }

    return questionData;
  }

  @override
  void dispose() {
    _questionTextController.dispose();
    for (var controller in _optionControllers) {
      controller.dispose();
    }
    _correctAnswerController.dispose();
    super.dispose();
  }

  Widget _buildQuestionTypeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Question Type",
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: widget.allowedQuestionTypes.map((type) {
            return ChoiceChip(
              label: Text(type),
              selected: _selectedType == type,
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _selectedType = type;
                    if (type == 'Multiple Choice') {
                      _resetOptionControllers();
                    }
                  });
                }
              },
              backgroundColor: Colors.grey.shade200,
              selectedColor: Colors.blue.shade200,
              labelStyle: GoogleFonts.poppins(
                color: _selectedType == type
                    ? Colors.blue.shade900
                    : Colors.black87,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMultipleChoiceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Options",
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        ...List.generate(_optionControllers.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Radio<int>(
                  value: index,
                  groupValue: _correctOptionIndex,
                  onChanged: (value) {
                    setState(() {
                      _correctOptionIndex = value!;
                    });
                  },
                  activeColor: Colors.blue.shade700,
                ),
                Expanded(
                  child: TextFormField(
                    controller: _optionControllers[index],
                    decoration: InputDecoration(
                      labelText: "Option ${index + 1}",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return "Please enter option ${index + 1}";
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
          );
        }),
        Text(
          "* Select the radio button next to the correct answer",
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  Widget _buildTrueFalseSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Correct Answer",
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: RadioListTile<bool>(
                title: Text(
                  "True",
                  style: GoogleFonts.poppins(),
                ),
                value: true,
                groupValue: _isTrue,
                onChanged: (value) {
                  setState(() {
                    _isTrue = value!;
                  });
                },
                activeColor: Colors.blue.shade700,
              ),
            ),
            Expanded(
              child: RadioListTile<bool>(
                title: Text(
                  "False",
                  style: GoogleFonts.poppins(),
                ),
                value: false,
                groupValue: _isTrue,
                onChanged: (value) {
                  setState(() {
                    _isTrue = value!;
                  });
                },
                activeColor: Colors.blue.shade700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildShortAnswerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Correct Answer",
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _correctAnswerController,
          decoration: InputDecoration(
            labelText: "Correct Answer",
            hintText: "Enter the expected response",
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return "Please enter the correct answer";
            }
            return null;
          },
        ),
        const SizedBox(height: 4),
        Text(
          "* Student answer must match exactly (case insensitive)",
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Center(
                child: Text(
                  widget.questionData == null ? "Add Question" : "Edit Question",
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade800,
                  ),
                ),
              ),
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  width: 100,
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.blue.shade200,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Question text
              TextFormField(
                controller: _questionTextController,
                decoration: InputDecoration(
                  labelText: "Question Text",
                  hintText: "Enter your question here",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                maxLines: 3,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return "Please enter the question text";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 20),

              // Question type
              _buildQuestionTypeSection(),
              const SizedBox(height: 20),

              // Type-specific sections
              if (_selectedType == 'Multiple Choice') _buildMultipleChoiceSection(),
              if (_selectedType == 'True/False') _buildTrueFalseSection(),
              if (_selectedType == 'Short Answer') _buildShortAnswerSection(),

              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        "Cancel",
                        style: GoogleFonts.poppins(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          Navigator.pop(context, _getQuestionData());
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        widget.questionData == null ? "Add" : "Update",
                        style: GoogleFonts.poppins(),
                      ),
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
}