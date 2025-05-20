import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Screens/login_page.dart';
import '../Teacher/teacher_dashboard.dart';

class TeacherAuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  /// 🔥 Sign Up with Email & Password (Teachers only)
  Future<void> signUpWithEmail(String email, String password, BuildContext context) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = userCredential.user;

      if (user != null) {
        await _firestore.collection("teachers").doc(user.uid).set({
          'teacherId': user.uid,
          'email': email,
          'userType': 'Teacher',
          'createdAt': FieldValue.serverTimestamp(),
        });

        await _saveLoginState();

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const AdminDashboard()),
              (route) => false,
        );

        notifyListeners();
      }
    } catch (e) {
      _showSnackbar(context, "Error: ${e.toString()}");
    }
  }

  /// 🔑 Sign In with Email & Password (Teachers only)
  Future<void> signInWithEmail(String email, String password, BuildContext context) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      User? user = userCredential.user;

      if (user != null) {
        DocumentSnapshot teacherDoc = await _firestore.collection('teachers').doc(user.uid).get();

        if (teacherDoc.exists && teacherDoc['userType'] == 'Teacher') {
          await _saveLoginState();

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const AdminDashboard()),
                (route) => false,
          );

          notifyListeners();
        } else {
          _showSnackbar(context, "Access denied: Only teachers can log in.");
        }
      }
    } catch (e) {
      _showSnackbar(context, "Error: ${e.toString()}");
    }
  }

  /// 🔵 Google Sign-In (Teachers only)
  Future<void> signInWithGoogle(BuildContext context) async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential = await _auth.signInWithCredential(credential);
      User? user = userCredential.user;

      if (user != null) {
        DocumentReference teacherRef = _firestore.collection('teachers').doc(user.uid);
        DocumentSnapshot teacherDoc = await teacherRef.get();

        if (teacherDoc.exists) {
          String userType = teacherDoc['userType'] ?? "";

          if (userType != 'Teacher') {
            _showSnackbar(context, "Access denied: Only teachers can log in.");
            return;
          }
        } else {
          await teacherRef.set({
            'teacherId': user.uid,
            'name': user.displayName ?? "No Name",
            'email': user.email ?? "No Email",
            'photoUrl': user.photoURL ?? "",
            'userType': 'Teacher',
            'createdAt': FieldValue.serverTimestamp(),
            'lastLoginAt': FieldValue.serverTimestamp(),
          });
        }

        await _saveLoginState();

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const AdminDashboard()),
              (route) => false,
        );

        notifyListeners();
      }
    } catch (e) {
      _showSnackbar(context, "Error: ${e.toString()}");
    }
  }

  /// 🚪 Sign Out
  Future<void> signOut(BuildContext context) async {
    try {
      await _auth.signOut();
      await GoogleSignIn().signOut();

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      _showSnackbar(context, "Signed out successfully");

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
      );

      notifyListeners();
    } catch (e) {
      _showSnackbar(context, "Error signing out: ${e.toString()}");
    }
  }

  /// 🔐 Save Login State
  Future<void> _saveLoginState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isLoggedIn', true);
    await prefs.setString('userType', 'Teacher');
  }

  /// 🔔 Show Snackbar
  void _showSnackbar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
