import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class TeacherMonitoringPage extends StatefulWidget {
  final String examId;

  const TeacherMonitoringPage({
    super.key,
    required this.examId,
  });

  @override
  State<TeacherMonitoringPage> createState() => _TeacherMonitoringPageState();
}

class _TeacherMonitoringPageState extends State<TeacherMonitoringPage> {
  // Active student connections
  final Map<String, StudentConnection> _studentConnections = {};

  // Currently selected student for detailed view
  String? _selectedStudentId;

  // Stream subscription for student list
  StreamSubscription<QuerySnapshot>? _studentsSubscription;

  // View mode: grid or detailed
  bool _gridView = true;

  // Student data (name, status, completion time, etc.)
  final Map<String, Map<String, dynamic>> _studentData = {};

  // Filter options
  bool _showCompletedExams = false;
  String _searchQuery = '';

  // Sorting option
  String _sortBy = 'name'; // Options: 'name', 'status', 'flagCount'

  @override
  void initState() {
    super.initState();
    _loadActiveStudents();
  }

  void _loadActiveStudents() {
    // Listen for all exam sessions (both active and completed)
    _studentsSubscription = FirebaseFirestore.instance
        .collection('examMonitoring')
        .where('examId', isEqualTo: widget.examId)
        .snapshots()
        .listen((snapshot) {
      // Clear old connections that are no longer in the database
      final activeStudentIds = <String>{};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final studentId = data['studentId'] as String;
        final connectionStatus = data['connectionStatus'] as String;
        final isCompleted = connectionStatus == 'completed' || connectionStatus == 'closed';

        // Store student data for display
        _studentData[studentId] = {
          'name': data['studentName'] ?? 'Student $studentId',
          'status': connectionStatus,
          'completionTime': data['completionTime'],
          'startTime': data['startTime'],
          'flagCount': (data['events'] as List<dynamic>?)
              ?.where((e) => e['type'] == 'flag')
              .length ?? 0,
        };

        activeStudentIds.add(studentId);

        // Only create connections for non-completed exams
        if (!isCompleted && !_studentConnections.containsKey(studentId)) {
          // Create new connection for this student
          _studentConnections[studentId] = StudentConnection(
            studentId: studentId,
            examId: widget.examId,
            onConnectionStateChange: _handleConnectionStateChange,
          );

          // Initialize connection
          _studentConnections[studentId]!.initialize();
        }
      }

      // Remove connections for students no longer in the database
      _studentConnections.removeWhere((id, _) => !activeStudentIds.contains(id));

      // Update UI
      if (mounted) setState(() {});
    });
  }

  void _handleConnectionStateChange(String studentId, String state) {
    // Update UI when connection state changes
    if (mounted) setState(() {});
  }

  void _selectStudent(String studentId) {
    setState(() {
      _selectedStudentId = studentId;
      _gridView = false;
    });
  }

  void _returnToGrid() {
    setState(() {
      _gridView = true;
      _selectedStudentId = null;
    });
  }

  List<String> _getFilteredStudentIds() {
    return _studentData.entries
        .where((entry) {
      final studentData = entry.value;
      final isCompleted = studentData['status'] == 'completed' ||
          studentData['status'] == 'closed';

      // Apply search filter
      final nameMatches = studentData['name'].toString().toLowerCase()
          .contains(_searchQuery.toLowerCase());

      // Apply completion filter
      final showBasedOnCompletion = _showCompletedExams || !isCompleted;

      return nameMatches && showBasedOnCompletion;
    })
        .map((entry) => entry.key)
        .toList()
      ..sort((a, b) {
        final dataA = _studentData[a]!;
        final dataB = _studentData[b]!;

        switch (_sortBy) {
          case 'name':
            return dataA['name'].toString().compareTo(dataB['name'].toString());
          case 'status':
            return dataA['status'].toString().compareTo(dataB['status'].toString());
          case 'flagCount':
            return (dataB['flagCount'] as int).compareTo(dataA['flagCount'] as int);
          default:
            return 0;
        }
      });
  }

  Future<void> _takeSnapshot(String studentId) async {
    try {
      await FirebaseFirestore.instance
          .collection('examMonitoring')
          .doc('${widget.examId}-$studentId')
          .update({
        'snapshotRequested': true,
        'snapshotRequestTime': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Snapshot requested'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to request snapshot: $e'))
      );
    }
  }

  void _flagSuspiciousActivity(String studentId) {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Flag Suspicious Activity'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: 'Describe suspicious behavior...',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final description = textController.text.trim().isEmpty
                  ? 'Suspicious activity'
                  : textController.text;

              // Log the suspicious activity
              await FirebaseFirestore.instance
                  .collection('examMonitoring')
                  .doc('${widget.examId}-$studentId')
                  .update({
                'events': FieldValue.arrayUnion([{
                  'timestamp': FieldValue.serverTimestamp(),
                  'event': 'FLAGGED: $description',
                  'type': 'flag',
                }])
              });

              // Update local data
              if (_studentData.containsKey(studentId)) {
                setState(() {
                  _studentData[studentId]!['flagCount'] =
                      (_studentData[studentId]!['flagCount'] as int) + 1;
                });
              }

              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Activity flagged'))
              );
            },
            child: const Text('Flag'),
          ),
        ],
      ),
    );
  }

  void _sendMessage(String studentId) {
    final textController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Message to Student'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            hintText: 'Enter message...',
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final message = textController.text.trim();
              if (message.isEmpty) {
                return;
              }

              // Send message to student
              await FirebaseFirestore.instance
                  .collection('examMonitoring')
                  .doc('${widget.examId}-$studentId')
                  .update({
                'events': FieldValue.arrayUnion([{
                  'timestamp': FieldValue.serverTimestamp(),
                  'event': 'TEACHER MESSAGE: $message',
                  'type': 'message',
                }]),
                'hasTeacherMessage': true,
              });

              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Message sent'))
              );
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Close all connections
    for (var connection in _studentConnections.values) {
      connection.dispose();
    }

    // Cancel subscriptions
    _studentsSubscription?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Monitoring Exam: ${widget.examId}'),
        leading: _gridView
            ? null
            : IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _returnToGrid,
        ),
        actions: [
          if (_gridView)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    return AlertDialog(
                      title: const Text('Search Students'),
                      content: TextField(
                        onChanged: (value) {
                          setState(() {
                            _searchQuery = value;
                          });
                        },
                        decoration: const InputDecoration(
                          hintText: 'Enter student name',
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _searchQuery = '';
                            });
                            Navigator.pop(context);
                          },
                          child: const Text('Clear'),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          child: const Text('Done'),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
        ],
      ),
      body: _gridView ? _buildGridView() : _buildDetailedView(),
    );
  }

  Widget _buildGridView() {
    final filteredStudentIds = _getFilteredStudentIds();

    if (filteredStudentIds.isEmpty) {
      return const Center(
        child: Text('No students match the current filters'),
      );
    }

    return Column(
      children: [
        if (_searchQuery.isNotEmpty || _showCompletedExams)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                if (_searchQuery.isNotEmpty)
                  Chip(
                    label: Text('Search: $_searchQuery'),
                    onDeleted: () {
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                  ),
                const SizedBox(width: 8),
                if (_showCompletedExams)
                  Chip(
                    label: const Text('Including completed exams'),
                    onDeleted: () {
                      setState(() {
                        _showCompletedExams = false;
                      });
                    },
                  ),
              ],
            ),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(1),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1,
              crossAxisSpacing: 1,
              mainAxisSpacing: 1,
            ),
            itemCount: filteredStudentIds.length,
            itemBuilder: (context, index) {
              final studentId = filteredStudentIds[index];
              final studentData = _studentData[studentId]!;
              final connection = _studentConnections[studentId];
              final isCompleted = studentData['status'] == 'completed' ||
                  studentData['status'] == 'closed';

              return Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(
                    color: studentData['flagCount'] > 0
                        ? Colors.red
                        : Colors.transparent,
                    width: studentData['flagCount'] > 0 ? 2 : 0,
                  ),
                ),
                child: InkWell(
                  onTap: () => _selectStudent(studentId),
                  child: Column(
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8),
                                ),
                              ),
                              child: isCompleted
                                  ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.check_circle_outline,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Exam Completed',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                                  : connection != null && connection.isConnected
                                  ? ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8),
                                ),
                                child: RTCVideoView(
                                  connection.renderer,
                                  objectFit: RTCVideoViewObjectFit
                                      .RTCVideoViewObjectFitCover,
                                ),
                              )
                                  : Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.videocam_off,
                                      color: Colors.white.withOpacity(0.8),
                                      size: 32,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'No Connection',
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (studentData['flagCount'] > 0)
                              Positioned(
                                top: 8,
                                right: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${studentData['flagCount']}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(8),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              studentData['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _getStatusColor(studentData['status']),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _getStatusText(studentData['status']),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              Text(
                'Total: ${filteredStudentIds.length} students',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const Spacer(),
              Text(
                'Active: ${filteredStudentIds.where((id) =>
                _studentData[id]!['status'] != 'completed' &&
                    _studentData[id]!['status'] != 'closed').length}',
                style: TextStyle(
                  color: Colors.green.shade700,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Completed: ${filteredStudentIds.where((id) =>
                _studentData[id]!['status'] == 'completed' ||
                    _studentData[id]!['status'] == 'closed').length}',
                style: TextStyle(
                  color: Colors.blue.shade700,
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Flagged: ${filteredStudentIds.where((id) =>
                _studentData[id]!['flagCount'] > 0).length}',
                style: const TextStyle(
                  color: Colors.red,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailedView() {
    if (_selectedStudentId == null) {
      return const Center(
        child: Text('No student selected'),
      );
    }

    final selectedConnection = _studentConnections[_selectedStudentId];
    final studentData = _studentData[_selectedStudentId] ?? {};
    final isCompleted = studentData['status'] == 'completed' ||
        studentData['status'] == 'closed';

    return Column(
      children: [
        // Main video area - takes up most of the screen
        Expanded(
          flex: 3, // Video area gets 3/4 of vertical space
          child: Container(
            width: double.infinity,
            color: Colors.black,
            child: isCompleted
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.check_circle_outline,
                    size: 64,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Exam Completed',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 24,
                    ),
                  ),
                  if (studentData['completionTime'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'at ${_formatTimestamp(studentData['completionTime'])}',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 16,
                        ),
                      ),
                    ),
                ],
              ),
            )
                : selectedConnection != null && selectedConnection.isConnected
                ? RTCVideoView(
              selectedConnection.renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            )
                : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.videocam_off,
                    size: 64,
                    color: Colors.white.withOpacity(0.6),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No video connection',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 20,
                    ),
                  ),
                  if (selectedConnection != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        selectedConnection.connectionState,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // Information and activity details section below the video
        Expanded(
          flex: 1, // Details area gets 1/4 of vertical space
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                top: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Student info and actions
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: Colors.grey.shade200),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Student info card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            border: Border(
                              bottom: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.blue.shade100,
                                child: Text(
                                  studentData['name']?.toString().substring(0, 1).toUpperCase() ?? 'S',
                                  style: TextStyle(
                                    color: Colors.blue.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      studentData['name'] ?? 'Student $_selectedStudentId',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: _getStatusColor(studentData['status']),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _getStatusText(studentData['status'] ?? 'unknown'),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (studentData['flagCount'] != null &&
                                  studentData['flagCount'] > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${studentData['flagCount']} flags',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Timeline info
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildInfoBox(
                                label: 'Started',
                                value: studentData['startTime'] != null
                                    ? _formatTimestamp(studentData['startTime'])
                                    : 'Unknown',
                                icon: Icons.play_circle_outline,
                              ),
                              _buildInfoBox(
                                label: 'Completed',
                                value: studentData['completionTime'] != null
                                    ? _formatTimestamp(studentData['completionTime'])
                                    : 'In Progress',
                                icon: Icons.check_circle_outline,
                              ),
                            ],
                          ),
                        ),

                        // Action buttons in a row
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildActionButton(
                                icon: Icons.camera_alt,
                                label: 'Snapshot',
                                onPressed: !isCompleted && selectedConnection != null &&
                                    selectedConnection.isConnected
                                    ? () => _takeSnapshot(_selectedStudentId!)
                                    : null,
                              ),
                              _buildActionButton(
                                icon: Icons.flag,
                                label: 'Flag',
                                color: Colors.red,
                                onPressed: !isCompleted
                                    ? () => _flagSuspiciousActivity(_selectedStudentId!)
                                    : null,
                              ),
                              _buildActionButton(
                                icon: Icons.message,
                                label: 'Message',
                                onPressed: !isCompleted
                                    ? () => _sendMessage(_selectedStudentId!)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Activity log section
                Expanded(
                  flex: 3,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Activity Log',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.history,
                              size: 16,
                              color: Colors.grey.shade600,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance
                                .collection('examMonitoring')
                                .doc('${widget.examId}-$_selectedStudentId')
                                .snapshots(),
                            builder: (context, snapshot) {
                              if (!snapshot.hasData) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }

                              final data = snapshot.data!.data() as Map<String, dynamic>?;
                              final events = data?['events'] as List<dynamic>? ?? [];

                              if (events.isEmpty) {
                                return Center(
                                  child: Text(
                                    'No activity recorded',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                );
                              }

                              return ListView.builder(
                                itemCount: events.length,
                                reverse: true,
                                itemBuilder: (context, index) {
                                  final event = events[events.length - 1 - index];
                                  final timestamp = event['timestamp'] as Timestamp?;
                                  final formattedTime = timestamp != null
                                      ? '${timestamp.toDate().hour}:${timestamp.toDate().minute.toString().padLeft(2, '0')}'
                                      : '--:--';

                                  final eventType = event['type']?.toString() ?? '';
                                  final isFlag = eventType == 'flag';
                                  final isMessage = eventType == 'message';
                                  final isSnapshot = event['event'].toString().contains('snapshot');

                                  return Card(
                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                    color: isFlag
                                        ? Colors.red.shade50
                                        : isMessage
                                        ? Colors.blue.shade50
                                        : Colors.white,
                                    child: Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: isFlag
                                                  ? Colors.red.shade100
                                                  : isMessage
                                                  ? Colors.blue.shade100
                                                  : isSnapshot
                                                  ? Colors.green.shade100
                                                  : Colors.grey.shade100,
                                            ),
                                            child: Icon(
                                              isFlag
                                                  ? Icons.flag
                                                  : isMessage
                                                  ? Icons.message
                                                  : isSnapshot
                                                  ? Icons.camera_alt
                                                  : Icons.info_outline,
                                              size: 16,
                                              color: isFlag
                                                  ? Colors.red.shade800
                                                  : isMessage
                                                  ? Colors.blue.shade800
                                                  : isSnapshot
                                                  ? Colors.green.shade800
                                                  : Colors.grey.shade800,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Text(
                                                      formattedTime,
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: Colors.grey.shade700,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                    const Spacer(),
                                                    if (isFlag)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                          horizontal: 6,
                                                          vertical: 2,
                                                        ),
                                                        decoration: BoxDecoration(
                                                          borderRadius: BorderRadius.circular(12),
                                                          color: Colors.red.shade100,
                                                        ),
                                                        child: Text(
                                                          'Flagged',
                                                          style: TextStyle(
                                                            fontSize: 10,
                                                            color: Colors.red.shade800,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  event['event'].toString(),
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: isFlag ? Colors.red.shade800 : null,
                                                    fontWeight: isFlag ? FontWeight.bold : null,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBox({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      width: 130,
      child: Column(
        children: [
          Icon(
            icon,
            size: 16,
            color: Colors.grey.shade600,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(12),
            backgroundColor: color ?? Colors.blue,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade300,
          ),
          child: Icon(icon),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: onPressed != null
                ? (color ?? Colors.blue)
                : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'active':
        return Colors.green;
      case 'idle':
        return Colors.orange;
      case 'completed':
        return Colors.blue;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'active':
        return 'Active';
      case 'idle':
        return 'Idle';
      case 'completed':
        return 'Completed';
      case 'closed':
        return 'Closed';
      default:
        return 'Unknown';
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp is Timestamp) {
      final date = timestamp.toDate();
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    }
    return 'Unknown';
  }
}

/// Manages the WebRTC connection to a single student
class StudentConnection {
  final String studentId;
  final String examId;
  final Function(String, String) onConnectionStateChange;

  // WebRTC objects
  RTCPeerConnection? _peerConnection;
  final RTCVideoRenderer renderer = RTCVideoRenderer();

  // Connection state
  String _connectionState = 'Initializing';
  bool _isConnected = false;
  Timer? _connectionCheckTimer;

  // Firebase references
  late DocumentReference _examSessionRef;

  StudentConnection({
    required this.studentId,
    required this.examId,
    required this.onConnectionStateChange,
  }) {
    _examSessionRef = FirebaseFirestore.instance
        .collection('examSessions')
        .doc('$examId-$studentId');
  }

  String get connectionState => _connectionState;
  bool get isConnected => _isConnected;

  Future<void> initialize() async {
    try {
      // Initialize video renderer
      await renderer.initialize();

      // Configure peer connection
      await _createPeerConnection();

      // Listen for student offers
      _listenForStudentOffer();

      // Start connection check timer
      _startConnectionCheck();
    } catch (e) {
      _updateConnectionState('Error: $e');
    }
  }

  Future<void> _createPeerConnection() async {
    _peerConnection = await createPeerConnection({
      'iceServers': [
        {
          'urls': [
            'stun:stun1.l.google.com:19302',
            'stun:stun2.l.google.com:19302'
          ]
        }
      ],
      'sdpSemantics': 'unified-plan'
    });

    // Set up event handlers
    _peerConnection!.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'video') {
        renderer.srcObject = event.streams[0];
      }
    };

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      _sendIceCandidate(candidate);
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      _updateConnectionState(state.toString().split('.').last);
    };

    _updateConnectionState('Peer connection created');
  }

  void _listenForStudentOffer() {
    _examSessionRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists) return;

      final data = snapshot.data() as Map<String, dynamic>;

      // Handle offer from student
      if (data['type'] == 'offer' && _peerConnection != null) {
        try {
          await _peerConnection!.setRemoteDescription(
              RTCSessionDescription(data['sdp'], data['type'])
          );

          // Create answer
          RTCSessionDescription answer = await _peerConnection!.createAnswer();
          await _peerConnection!.setLocalDescription(answer);

          // Send answer to student
          await _examSessionRef.update({
            'type': 'answer',
            'sdp': answer.sdp,
            'timestamp': FieldValue.serverTimestamp(),
          });

          _updateConnectionState('Answer sent');
        } catch (e) {
          _updateConnectionState('Error handling offer: $e');
        }
      }
    });

    // Listen for ICE candidates from student
    _examSessionRef.collection('candidates').snapshots().listen((snapshot) async {
      for (var doc in snapshot.docs) {
        final data = doc.data();

        if (data['type'] == 'ice-candidate' && _peerConnection != null) {
          try {
            await _peerConnection!.addCandidate(
                RTCIceCandidate(
                  data['candidate'],
                  data['sdpMid'],
                  data['sdpMLineIndex'],
                )
            );
          } catch (e) {
            _updateConnectionState('Error adding ICE candidate: $e');
          }
        }
      }
    });
  }

  Future<void> _sendIceCandidate(RTCIceCandidate candidate) async {
    try {
      await _examSessionRef.collection('teacher-candidates').add({
        'type': 'ice-candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _updateConnectionState('Error sending ICE candidate: $e');
    }
  }

  void _startConnectionCheck() {
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkConnection();
    });
  }

  Future<void> _checkConnection() async {
    if (_peerConnection == null) return;

    try {
      // Get connection stats
      List<StatsReport> statsReports = await _peerConnection!.getStats();
      bool hasActiveConnection = false;

      for (var report in statsReports) {
        if (report.type == 'candidate-pair' && report.values['state'] == 'succeeded') {
          hasActiveConnection = true;
        }
      }

      // Update connection status
      if (hasActiveConnection != _isConnected) {
        _isConnected = hasActiveConnection;
        _updateConnectionState(_isConnected ? 'Connected' : 'Disconnected');
      }
    } catch (e) {
      _updateConnectionState('Error checking connection: $e');
    }
  }

  void _updateConnectionState(String state) {
    _connectionState = state;
    onConnectionStateChange(studentId, state);
  }

  void reconnect() {
    dispose();
    initialize();
  }

  void dispose() {
    _connectionCheckTimer?.cancel();
    _peerConnection?.close();
    renderer.dispose();
    _isConnected = false;
    _updateConnectionState('Closed');
  }
}