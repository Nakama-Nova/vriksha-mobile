import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/login_screen.dart';
import 'screens/home_shell.dart';
import 'session.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // The fonts are SIL Open Font License: list them on the Licences page.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
      ['Cormorant Garamond'],
      await rootBundle.loadString('assets/fonts/OFL-CormorantGaramond.txt'),
    );
    yield LicenseEntryWithLineBreaks(
      ['Inter'],
      await rootBundle.loadString('assets/fonts/OFL-Inter.txt'),
    );
  });
  runApp(const CaptureApp());
}

class CaptureApp extends StatelessWidget {
  const CaptureApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Vriksha Capture',
        theme: brandTheme(),
        home: const _Gate(),
      );
}

/// Signed in already? Go to the scans; otherwise ask for the login.
class _Gate extends StatefulWidget {
  const _Gate();
  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  late Future<Session?> _session = SessionStore.load();

  void _signedIn(Session s) => setState(() => _session = Future.value(s));

  Future<void> _signOut() async {
    await SessionStore.clear();
    setState(() => _session = Future.value(null));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Session?>(
        future: _session,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          final s = snap.data;
          return s == null
              ? LoginScreen(onSignedIn: _signedIn)
              : HomeShell(session: s, onSignOut: _signOut);
        },
      );
}
