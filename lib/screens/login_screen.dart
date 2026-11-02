import 'package:flutter/material.dart';

import '../api.dart';
import '../config.dart';
import '../session.dart';
import '../theme.dart';

/// Design screen 1: warm background, gold logomark, serif name, brown button.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSignedIn, this.notice});
  final void Function(Session) onSignedIn;
  final String? notice; // e.g. "Your session ended"

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  late String? _error = widget.notice;
  bool _busy = false;
  bool _show = false;

  Future<void> _signIn() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Enter your username and password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final login = await ApiClient(apiBaseUrl).login(_user.text.trim(), _pass.text);
      final session = await SessionStore.save(login);
      widget.onSignedIn(session);
    } on ApiException catch (e) {
      setState(() => _error = e.status == 401 ? 'Wrong username or password' : e.message);
    } catch (e) {
      // Signed in, but the phone could not keep the login (e.g. secure storage).
      setState(() => _error = 'Could not finish signing in: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: surfaceWarm,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Image.asset('assets/brand/logo.png', height: 150, semanticLabel: 'Vriksha Studio'),
                const SizedBox(height: 10),
                const Text('Staff sign in', style: TextStyle(color: textMuted)),
                const SizedBox(height: 24),
                TextField(
                  controller: _user,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: !_show,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    suffixIcon: TextButton(
                      onPressed: () => setState(() => _show = !_show),
                      child: Text(_show ? 'Hide' : 'Show'),
                    ),
                  ),
                  onSubmitted: (_) => _signIn(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: badRed)),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _busy ? null : _signIn,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Sign in'),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Staff desk · v1', style: TextStyle(fontSize: 12, color: textMuted)),
              ]),
            ),
          ),
        ),
      );
}
