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
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        return "Incorrect email or password. Please try again.";
      } else if (e.code == 'invalid-email') {
        return "The email format is invalid.";
      } else if (e.code == 'user-disabled') {
        return "This account has been disabled. Please contact support.";
      }
      return "Login failed: ${e.message}"; 
    } catch (e) {
      return "Something went wrong. Please check your connection and try again.";
    }
  }

  // Register with email and password
  Future<String?> register(String name, String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      
      // Update the user's profile with their name
      if (credential.user != null) {
        await credential.user!.updateDisplayName(name);
        await credential.user!.reload();
        _user = _auth.currentUser; // Refresh local user state with the new name
        notifyListeners();
      }
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'weak-password') {
        return "Your password is too weak. Please use at least 6 characters.";
      } else if (e.code == 'email-already-in-use') {
        return "This email is already registered. Please sign in instead.";
      } else if (e.code == 'invalid-email') {
        return "The email format is invalid.";
      }
      return "Registration failed: ${e.message}";
    } catch (e) {
      return "Something went wrong. Please check your connection and try again.";
    }
  }

  /// Sends a Firebase password-reset email. Returns null on success, error string on failure.
  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') return 'No account found with this email.';
      if (e.code == 'invalid-email') return 'The email format is invalid.';
      return 'Failed to send reset email: ${e.message}';
    } catch (e) {
      return 'Something went wrong. Please try again.';
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}
