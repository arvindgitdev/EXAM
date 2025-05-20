import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

class WebRTCExamHandler {
  // WebRTC connections
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;

  // Firebase connection
  final String examId;
  final String studentId;
  final Function(String) onError;
  final Function() onConnectionEstablished;

  // Connection status
  bool _isConnected = false;
  Timer? _connectionCheckTimer;

  // Stats tracking
  int _connectionDropCount = 0;

  // Firebase references
  late DocumentReference _examSessionRef;
  late DocumentReference _monitoringRef;

  WebRTCExamHandler({
    required this.examId,
    required this.studentId,
    required this.onError,
    required this.onConnectionEstablished,
  }) {
    _examSessionRef = FirebaseFirestore.instance.collection('examSessions').doc('$examId-$studentId');
    _monitoringRef = FirebaseFirestore.instance.collection('examMonitoring').doc('$examId-$studentId');
  }

  Future<void> initialize() async {
    try {
      // 1. Check required permissions
      if (!await _checkPermissions()) {
        onError('Camera and microphone permissions are required for exam monitoring');
        return;
      }

      // 2. Create monitoring document in Firestore
      await _initializeMonitoringDocument();

      // 3. Initialize WebRTC
      await _initializeWebRTC();

      // 4. Start connection check timer
      _startConnectionCheck();

      // Listen for proctor signaling
      _listenForSignalingMessages();
    } catch (e) {
      onError('Failed to initialize monitoring: $e');
    }
  }

  Future<bool> _checkPermissions() async {
    // Request camera and microphone permissions
    final cameraStatus = await Permission.camera.request();
    final microphoneStatus = await Permission.microphone.request();

    return cameraStatus.isGranted && microphoneStatus.isGranted;
  }

  Future<void> _initializeMonitoringDocument() async {
    await _monitoringRef.set({
      'studentId': studentId,
      'examId': examId,
      'startTime': FieldValue.serverTimestamp(),
      'connectionStatus': 'initializing',
      'events': [],
      'iceConnectionState': 'new',
    });
  }

  Future<void> _initializeWebRTC() async {
    try {
      // Create peer connection
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

      // Get local media stream
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 320},
          'height': {'ideal': 240}
        }
      });

      // Add tracks to peer connection
      _localStream!.getTracks().forEach((track) {
        _peerConnection!.addTrack(track, _localStream!);
      });

      // Set up event handlers
      _setupPeerConnectionEventHandlers();

      // Create offer
      await _createAndSetLocalOffer();
    } catch (e) {
      await _logEvent('WebRTC initialization error: $e');
      onError('Failed to start camera: $e');
    }
  }

  void _setupPeerConnectionEventHandlers() {
    // ICE candidate events
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      _sendIceCandidate(candidate);
    };

    // Connection state changes
    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      _updateIceConnectionState(state.toString().split('.').last);
    };

    // Error handling
    _peerConnection!.onSignalingState = (RTCSignalingState state) {
      _logEvent('Signaling state change: ${state.toString().split('.').last}');
    };
  }

  Future<void> _createAndSetLocalOffer() async {
    try {
      // Create offer
      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      // Send offer to server
      await _examSessionRef.set({
        'type': 'offer',
        'sdp': offer.sdp,
        'studentId': studentId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      _logEvent('Offer created and sent to server');
    } catch (e) {
      _logEvent('Error creating offer: $e');
      onError('Failed to create connection offer: $e');
    }
  }

  void _listenForSignalingMessages() {
    // Listen for answer from proctor
    _examSessionRef.snapshots().listen((snapshot) async {
      if (!snapshot.exists) return;

      final data = snapshot.data() as Map<String, dynamic>;

      // Handle answer from proctor
      if (data['type'] == 'answer' && _peerConnection != null) {
        try {
          await _peerConnection!.setRemoteDescription(
              RTCSessionDescription(data['sdp'], data['type'])
          );
          _logEvent('Proctor answer received and set');
        } catch (e) {
          _logEvent('Error setting remote description: $e');
        }
      }

      // Handle ICE candidates from proctor
      if (data['type'] == 'ice-candidate' && _peerConnection != null) {
        try {
          await _peerConnection!.addCandidate(
              RTCIceCandidate(
                data['candidate'],
                data['sdpMid'],
                data['sdpMLineIndex'],
              )
          );
          _logEvent('ICE candidate added from proctor');
        } catch (e) {
          _logEvent('Error adding ICE candidate: $e');
        }
      }
    });
  }

  Future<void> _sendIceCandidate(RTCIceCandidate candidate) async {
    try {
      await _examSessionRef.collection('candidates').add({
        'type': 'ice-candidate',
        'studentId': studentId,
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _logEvent('Error sending ICE candidate: $e');
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


      // Updated way to get stats
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

        if (_isConnected) {
          onConnectionEstablished();
          _logEvent('Proctor connection established');
        } else {
          _connectionDropCount++;
          _logEvent('Proctor connection dropped (count: $_connectionDropCount)');
        }

        await _monitoringRef.update({
          'connectionStatus': _isConnected ? 'connected' : 'disconnected',
          'connectionDropCount': _connectionDropCount,
          'lastConnectionCheck': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      _logEvent('Error checking connection: $e');
    }
  }

  Future<void> _updateIceConnectionState(String state) async {

    await _monitoringRef.update({
      'iceConnectionState': state,
      'lastIceUpdate': FieldValue.serverTimestamp(),
    });

    _logEvent('ICE connection state changed to: $state');
  }

  Future<void> _logEvent(String event) async {
    debugPrint('WebRTC Monitoring: $event');

    try {
      await _monitoringRef.update({
        'events': FieldValue.arrayUnion([{
          'timestamp': FieldValue.serverTimestamp(),
          'event': event,
        }])
      });
    } catch (e) {
      debugPrint('Failed to log monitoring event: $e');
    }
  }

  Future<void> captureSnapshot() async {
    if (_peerConnection == null || _localStream == null) return;

    try {
      // On real implementation, this would save a snapshot to Firebase storage
      // and log the event in the monitoring document
      _logEvent('Snapshot requested');
    } catch (e) {
      _logEvent('Error capturing snapshot: $e');
    }
  }

  void dispose() {
    _connectionCheckTimer?.cancel();

    // Close media streams
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();

    // Close peer connection
    _peerConnection?.close();

    // Update monitoring status
    _monitoringRef.update({
      'connectionStatus': 'closed',
      'endTime': FieldValue.serverTimestamp(),
    });
  }
}