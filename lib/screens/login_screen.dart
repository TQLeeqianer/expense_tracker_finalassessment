import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import '../utils/ui_helpers.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isLogin = true; // Toggle between Login and Register

  void _submit() async {
    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    
    String? error;
    if (_isLogin) {
      error = await authService.signIn(
        _emailController.text.trim(), 
        _passwordController.text.trim()
      );
    } else {
      if (_nameController.text.trim().isEmpty) {
         setState(() => _isLoading = false);
         UIHelpers.showAlertDialog(context, 'Name Required', 'Please enter your name or a username.');
         return;
      }
      error = await authService.register(
        _nameController.text.trim(),
        _emailController.text.trim(), 
        _passwordController.text.trim()
      );
    }

    setState(() => _isLoading = false);

    if (error != null && mounted) {
      UIHelpers.showAlertDialog(context, 'Authentication Error', error);
    }
  }

  void _showForgotPasswordDialog() {
    final emailCtrl = TextEditingController(text: _emailController.text.trim());
    bool isSending = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Reset Password', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Enter your registered email and we\'ll send you a reset link.',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: isSending
                  ? null
                  : () async {
                      setDialogState(() => isSending = true);
                      final authService = Provider.of<AuthService>(context, listen: false);
                      final error = await authService.sendPasswordResetEmail(emailCtrl.text);
                      if (!ctx.mounted) return;
                      Navigator.pop(ctx);
                      if (!mounted) return;
                      if (error != null) {
                        UIHelpers.showAlertDialog(context, 'Error', error);
                      } else {
                        UIHelpers.showAlertDialog(context, 'Email Sent',
                            'A password reset link has been sent to ${emailCtrl.text.trim()}. Check your inbox.');
                      }
                    },
              child: isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Text('Send Link'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 60),
              // Logo or App Name
              Icon(Icons.account_balance_wallet, 
                size: 80, 
                color: Theme.of(context).colorScheme.primary
              ),
              const SizedBox(height: 20),
              Text(
                _isLogin ? 'Welcome back to Expensix!' : 'Create an Account',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              
              if (!_isLogin) ...[
                TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Full Name or Username',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
              ],
              
              TextField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Email Address',
                  prefixIcon: const Icon(Icons.email),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 24),
              
              _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)
                      ),
                    ),
                    child: Text(_isLogin ? 'Sign In' : 'Sign Up', style: const TextStyle(fontSize: 16)),
                  ),
                  
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                  });
                },
                child: Text(_isLogin
                  ? "Don't have an account? Sign Up"
                  : "Already have an account? Sign In"
                ),
              ),

              if (_isLogin)
                TextButton(
                  onPressed: _showForgotPasswordDialog,
                  child: const Text('Forgot Password?', style: TextStyle(color: Colors.grey)),
                ),

              const SizedBox(height: 40),
              // Temporary bypass button for development UI testing
              TextButton(
                onPressed: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomeScreen()));
                },
                child: const Text("Bypass Login (For UI Testing)", style: TextStyle(color: Colors.grey)),
              )
            ],
          ),
        ),
      ),
    );
  }
}
