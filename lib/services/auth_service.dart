import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _user;

  User? get user => _user;
  bool get isAuthenticated => _user != null;

  AuthService() {
    // Listen to Firebase auth state changes
    _auth.authStateChanges().listen((User? user) {
      _user = user;
      notifyListeners();
    });
  }

  // Sign In with email and password
  Future<String?> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return null; // Null means success
    } on FirebaseAuthException catch (e) {
      return "Auth Error (${e.code}): ${e.message}"; 
    } catch (e) {
      return "Unexpected Error: ${e.toString()}";
    }
  }

  // Register with email and password
  Future<String?> register(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return "Auth Error (${e.code}): ${e.message}";
    } catch (e) {
      return "Unexpected Error: ${e.toString()}";
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
