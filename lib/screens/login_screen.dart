import 'package:flutter/material.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';

/// Design screen 1: warm background, gold logomark, serif name, brown button.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onSignedIn});
  final void Function(Session) onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    SessionStore.lastServer().then((v) {
      if (mounted && _server.text.isEmpty && v != null) _server.text = v;
    });
  }

  Future<void> _signIn() async {
    final url = _server.text.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      setState(() => _error = 'The server address must start with http:// or https://');
      return;
    }
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Enter your username and password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final login = await ApiClient(url).login(_user.text.trim(), _pass.text);
      final session = await SessionStore.save(url, login);
      widget.onSignedIn(session);
    } on ApiException catch (e) {
      setState(() => _error = e.status == 401 ? 'Wrong username or password' : e.message);
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
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(color: brandGold, shape: BoxShape.circle),
                ),
                const SizedBox(height: 14),
                Text('Vriksha Studio', style: serif(34, color: brandBrown)),
                const Text('Staff sign in', style: TextStyle(color: textMuted)),
                const SizedBox(height: 24),
                TextField(
                  controller: _server,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Server address',
                    hintText: 'https://shop.example.com',
                  ),
                ),
                const SizedBox(height: 12),
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
                const Text('Vriksha Capture · v1', style: TextStyle(fontSize: 12, color: textMuted)),
              ]),
            ),
          ),
        ),
      );
}
