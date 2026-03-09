import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

const _cDark  = Color(0xFF0E5A66);
const _cMid   = Color(0xFF1FA2A8);
const _cMint  = Color(0xFFD9F7F0);

String _friendlyAuthError(Object e) {
  final raw = e.toString().toLowerCase();
  if (e is AuthException) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials') || msg.contains('invalid_credentials')) {
      return 'Incorrect email or password.';
    }
    if (msg.contains('email not confirmed')) {
      return 'Please check your email and confirm your account.';
    }
    if (msg.contains('user already registered') || msg.contains('already been registered')) {
      return 'An account with this email already exists. Try signing in.';
    }
    if (msg.contains('invalid email') || msg.contains('not a valid email')) {
      return 'Please enter a valid email address.';
    }
    if (msg.contains('weak password') || msg.contains('too short')) {
      return 'Password is too weak. Use at least 6 characters.';
    }
    if (msg.contains('rate limit') || msg.contains('too many requests')) {
      return 'Too many attempts. Please wait a moment and try again.';
    }
    if (msg.contains('network') || msg.contains('socket') || msg.contains('connection')) {
      return 'Network error. Please check your connection.';
    }
    // Return the original message cleaned up
    return e.message;
  }
  if (raw.contains('network') || raw.contains('socket') || raw.contains('connection')) {
    return 'Network error. Please check your connection.';
  }
  if (raw.contains('cancelled') || raw.contains('canceled')) {
    return ''; // user cancelled, no error to show
  }
  return 'Something went wrong. Please try again.';
}

class AuthScreen extends StatefulWidget {
  final VoidCallback onAuthSuccess;
  const AuthScreen({super.key, required this.onAuthSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _isSignUp = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitEmail() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please enter email and password.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      if (_isSignUp) {
        await SupabaseService.signUpWithEmail(email, pass);
      } else {
        await SupabaseService.signInWithEmail(email, pass);
      }
      if (SupabaseService.isLoggedIn) {
        widget.onAuthSuccess();
      } else {
        setState(() {
          _error = _isSignUp
              ? 'Account created. Please sign in.'
              : 'Sign in failed. Please try again.';
          _loading = false;
        });
      }
    } catch (e) {
      final msg = _friendlyAuthError(e);
      setState(() {
        _error = msg.isNotEmpty ? msg : null;
        _loading = false;
      });
    }
  }

  Future<void> _signInGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      await SupabaseService.signInWithGoogle();
      if (SupabaseService.isLoggedIn) widget.onAuthSuccess();
    } catch (e) {
      final msg = _friendlyAuthError(e);
      setState(() {
        _error = msg.isNotEmpty ? msg : null;
        _loading = false;
      });
    }
  }

  Future<void> _signInApple() async {
    setState(() { _loading = true; _error = null; });
    try {
      await SupabaseService.signInWithApple();
      if (SupabaseService.isLoggedIn) widget.onAuthSuccess();
    } catch (e) {
      final msg = _friendlyAuthError(e);
      setState(() {
        _error = msg.isNotEmpty ? msg : null;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                Image.asset(
                  'assets/images/fulllogo.jpg',
                  width: 180,
                ),
                const SizedBox(height: 12),
                Text(_isSignUp ? 'Create your account' : 'Welcome back',
                    style: const TextStyle(fontSize: 14, color: Colors.black54)),
                const SizedBox(height: 32),

                // Email
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
                const SizedBox(height: 12),

                // Password
                TextField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                  onSubmitted: (_) => _submitEmail(),
                ),
                const SizedBox(height: 16),

                // Error
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13), textAlign: TextAlign.center),
                  ),

                // Submit
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: _cDark,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _loading ? null : _submitEmail,
                    child: _loading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_isSignUp ? 'Sign Up' : 'Sign In', style: const TextStyle(fontSize: 15)),
                  ),
                ),
                const SizedBox(height: 12),

                // Toggle sign up / sign in
                TextButton(
                  onPressed: _loading ? null : () => setState(() { _isSignUp = !_isSignUp; _error = null; }),
                  child: Text(
                    _isSignUp ? 'Already have an account? Sign In' : "Don't have an account? Sign Up",
                    style: const TextStyle(color: _cMid, fontSize: 13),
                  ),
                ),

                const SizedBox(height: 20),
                const Row(children: [
                  Expanded(child: Divider()),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: Colors.black38, fontSize: 13))),
                  Expanded(child: Divider()),
                ]),
                const SizedBox(height: 20),

                // Google
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      side: const BorderSide(color: Colors.black26),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _loading ? null : _signInGoogle,
                    icon: const Text('G', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.red)),
                    label: const Text('Continue with Google'),
                  ),
                ),
                const SizedBox(height: 10),

                // Apple (iOS only)
                if (Platform.isIOS)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.black87,
                        side: const BorderSide(color: Colors.black26),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _loading ? null : _signInApple,
                      icon: const Icon(Icons.apple, size: 20),
                      label: const Text('Continue with Apple'),
                    ),
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
