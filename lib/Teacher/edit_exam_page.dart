import 'package:examnow/Teacher/question_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class EditExamPage extends StatefulWidget {
  final String? examId;
  final Map<String, dynamic>? examData;

  const EditExamPage({
    super.key,
    this.examId,
    this.examData,
  });

  @override
  EditExamPageState createState() => EditExamPageState();
}

class EditExamPageState extends State<EditExamPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _subjectController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _timeController = TextEditingController();
  int _durationHours = 1;
  int _durationMinutes = 0;
  int _questionCount = 10;
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _selectedTime = TimeOfDay.now();
  final List<String> _allQuestionTypes = ['Multiple Choice', 'True/False', 'Short Answer'];
  List<String> _selectedQuestionTypes = ['Multiple Choice', 'True/False'];
  List<Map<String, dynamic>> _questions = [];

  @override
  void initState() {
    super.initState();
    if (widget.examData != null) {
      _loadExistingExamData();
    }
  }

  void _loadExistingExamData() {
    final examData = widget.examData!;

    _titleController.text = examData['title'] ?? '';
    _subjectController.text = examData['subject'] ?? '';
    _descriptionController.text = examData['description'] ?? '';
    _dateController.text = examData['date'] ?? '';
    _timeController.text = examData['time'] ?? '';

    // Parse duration
    final durationStr = examData['duration'] ?? '1h 0m';
    final durationRegExp = RegExp(r'(\d+)h\s+(\d+)m');
    final match = durationRegExp.firstMatch(durationStr);
    if (match != null) {
      _durationHours = int.parse(match.group(1) ?? '1');
      _durationMinutes = int.parse(match.group(2) ?? '0');
    }

    // Parse date and time
    _selectedDate = _parseDateString(examData['date']) ??
        DateTime.now().add(const Duration(days: 1));
    _selectedTime = _parseTimeString(examData['time']) ?? TimeOfDay.now();

    // Load question types
    if (examData['settings'] != null &&
        examData['settings']['questionTypes'] != null) {
      _selectedQuestionTypes = List<String>.from(
          examData['settings']['questionTypes']);
    }

    // Load question count
    _questionCount = examData['questionCount'] ?? 10;

    // Load questions if available
    if (examData['questions'] != null) {
      _questions = List<Map<String, dynamic>>.from(examData['questions']);
    }
  }

  DateTime? _parseDateString(String? dateStr) {
    try {
      if (dateStr == null || dateStr.isEmpty) return null;
      return DateFormat('MMM dd, yyyy').parse(dateStr);
    } catch (e) {
      return null;
    }
  }

  TimeOfDay? _parseTimeString(String? timeStr) {
    try {
      if (timeStr == null || timeStr.isEmpty) return null;
      final format = DateFormat('h:mm a');
      final dateTime = format.parse(timeStr);
      return TimeOfDay(hour: dateTime.hour, minute: dateTime.minute);
    } catch (e) {
      return null;
    }
  }

  String _formatTimeOfDay(TimeOfDay timeOfDay) {
    final now = DateTime.now();
    final dateTime = DateTime(
        now.year, now.month, now.day, timeOfDay.hour, timeOfDay.minute);
    return DateFormat('h:mm a').format(dateTime);
  }

  String _generateExamKey() {
    const uuid = Uuid();
    return uuid.v4().substring(0, 6).toUpperCase();
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat('MMM dd, yyyy').format(picked);
      });
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );

    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
        _timeController.text = _formatTimeOfDay(picked);
      });
    }
  }

  Future<void> _saveExam() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isLoading = true);

      try {
        // Calculate timestamp from date and time
        final DateTime examDateTime = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          _selectedTime.hour,
          _selectedTime.minute,
        );

        // Calculate total duration in minutes
        final totalDurationInMinutes = (_durationHours * 60) + _durationMinutes;

        // Create or update exam data
        final Map<String, dynamic> examData = {
          "title": _titleController.text.trim(),
          "subject": _subjectController.text.trim(),
          "description": _descriptionController.text.trim(),
          "date": DateFormat('MMM dd, yyyy').format(_selectedDate),
          "time": _formatTimeOfDay(_selectedTime),
          "examTimestamp": examDateTime.millisecondsSinceEpoch,
          "duration": "${_durationHours}h ${_durationMinutes}m",
          "durationMinutes": totalDurationInMinutes,
          "questionCount": _questionCount,
          "settings": {
            "questionTypes": _selectedQuestionTypes,
          },
          "questions": _questions,
          "lastModified": FieldValue.serverTimestamp(),
        };

        // If creating new exam, add these fields
        if (widget.examId == null) {
          examData["createdBy"] = FirebaseFirestore.instance.collection('users').doc('user.uid');
          examData["createdAt"] = FieldValue.serverTimestamp();
          examData["examKey"] = _generateExamKey();
          examData["status"] = "draft";
        }

        if (widget.examId != null) {
          // Update existing exam
          await FirebaseFirestore.instance
              .collection('exams')
              .doc(widget.examId)
              .update(examData);
        } else {
          // Create new exam
          await FirebaseFirestore.instance
              .collection('exams')
              .add(examData);
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.examId == null
              ? 'Exam created successfully!'
              : 'Exam updated successfully!')),
        );

        Navigator.pop(context);
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving exam: $e')),
        );
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToQuestionEditor() async {
    if (widget.examId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please save the exam first')),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuestionEditorPage(
          examId: widget.examId!,
          examTitle: _titleController.text,
          allowedQuestionTypes: _selectedQuestionTypes,
          targetQuestionCount: _questionCount,
        ),
      ),
    );

    // Refresh question data when returning from the question editor
    final examDoc = await FirebaseFirestore.instance
        .collection('exams')
        .doc(widget.examId)
        .get();

    if (examDoc.exists && mounted) {
      setState(() {
        if (examDoc.data()?["questions"] != null) {
          _questions = List<Map<String, dynamic>>.from(examDoc.data()!["questions"]);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.examId == null ? 'Create Exam' : 'Edit Exam',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: Colors.blue.shade800,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isLoading ? null : _saveExam,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Exam Details',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _titleController,
                        decoration: const InputDecoration(
                          labelText: 'Exam Title',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter exam title';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _subjectController,
                        decoration: const InputDecoration(
                          labelText: 'Subject',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter subject';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Date & Time',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _dateController,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Date',
                                border: OutlineInputBorder(),
                                suffixIcon: Icon(Icons.calendar_today),
                              ),
                              onTap: _selectDate,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please select date';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _timeController,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Time',
                                border: OutlineInputBorder(),
                                suffixIcon: Icon(Icons.access_time),
                              ),
                              onTap: _selectTime,
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please select time';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Duration',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _durationHours,
                              decoration: const InputDecoration(
                                labelText: 'Hours',
                                border: OutlineInputBorder(),
                              ),
                              items: List.generate(5, (index) => index)
                                  .map((hours) => DropdownMenuItem<int>(
                                value: hours,
                                child: Text('$hours hour${hours != 1 ? 's' : ''}'),
                              ))
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _durationHours = value!;
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _durationMinutes,
                              decoration: const InputDecoration(
                                labelText: 'Minutes',
                                border: OutlineInputBorder(),
                              ),
                              items: [0, 15, 30, 45]
                                  .map((mins) => DropdownMenuItem<int>(
                                value: mins,
                                child: Text('$mins min'),
                              ))
                                  .toList(),
                              onChanged: (value) {
                                setState(() {
                                  _durationMinutes = value!;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Question Settings',
                        style: GoogleFonts.poppins(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Question Count',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Slider(
                        value: _questionCount.toDouble(),
                        min: 5,
                        max: 50,
                        divisions: 9,
                        label: _questionCount.toString(),
                        onChanged: (value) {
                          setState(() {
                            _questionCount = value.round();
                          });
                        },
                      ),
                      Text(
                        '$_questionCount questions',
                        style: GoogleFonts.poppins(),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Question Types',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: _allQuestionTypes.map((type) {
                          final isSelected = _selectedQuestionTypes.contains(type);
                          return FilterChip(
                            label: Text(type),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedQuestionTypes.add(type);
                                } else {
                                  if (_selectedQuestionTypes.length > 1) {
                                    _selectedQuestionTypes.remove(type);
                                  }
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Questions (${_questions.length}/$_questionCount)',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.edit),
                            label: const Text('Manage'),
                            onPressed: widget.examId != null ? _navigateToQuestionEditor : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade700,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (widget.examId == null)
                        const Text(
                          'Save the exam first to manage questions',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      if (_questions.isEmpty && widget.examId != null)
                        const Text(
                          'No questions added yet. Click "Manage" to add questions.',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      if (_questions.isNotEmpty)
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _questions.length > 3 ? 3 : _questions.length,
                          itemBuilder: (context, index) {
                            final question = _questions[index];
                            return ListTile(
                              title: Text(
                                '${index + 1}. ${question['text'] ?? 'Question ${index + 1}'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                'Type: ${question['type'] ?? 'Unknown'}',
                                style: GoogleFonts.poppins(fontSize: 12),
                              ),
                            );
                          },
                        ),
                      if (_questions.length > 3)
                        Center(
                          child: TextButton(
                            onPressed: _navigateToQuestionEditor,
                            child: const Text('View all questions'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: Text(
                    widget.examId == null ? 'Create Exam' : 'Save Changes',
                  ),
                  onPressed: _saveExam,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subjectController.dispose();
    _descriptionController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }
}