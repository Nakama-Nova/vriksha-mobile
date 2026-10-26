import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vriksha_capture/screens/login_screen.dart';
import 'package:vriksha_capture/screens/more_screen.dart';
import 'package:vriksha_capture/screens/scans_screen.dart';
import 'package:vriksha_capture/session.dart';
import 'package:vriksha_capture/theme.dart';
import 'package:vriksha_capture/widgets.dart';

void main() {
  testWidgets('login asks for the server, user and password and checks the address', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: brandTheme(), home: LoginScreen(onSignedIn: (_) {})));
    expect(find.text('Server address'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Server address'), 'shop.example.com');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('The server address must start with http:// or https://'), findsOneWidget);
  });

  designTests();
}

void designTests() {
  testWidgets('login follows the design: logomark name, Show toggle, brown sign-in', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: brandTheme(), home: LoginScreen(onSignedIn: (_) {})));
    expect(find.text('Vriksha Studio'), findsOneWidget);
    expect(find.text('Staff sign in'), findsOneWidget);
    expect(find.text('Show'), findsOneWidget);
    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(find.text('Hide'), findsOneWidget);
  });

  testWidgets('More shows who is signed in and signs out', (tester) async {
    var out = 0;
    await tester.pumpWidget(MaterialApp(
      theme: brandTheme(),
      home: MoreScreen(session: Session('https://shop.test', 't', 'asha', 'achari'), onSignOut: () => out++),
    ));
    expect(find.text('More'), findsOneWidget);
    expect(find.text('asha'), findsOneWidget);
    expect(find.text('achari'), findsOneWidget);
    expect(find.text('https://shop.test'), findsOneWidget);
    await tester.tap(find.text('Sign out'));
    expect(out, 1);
  });

  testWidgets('status chips use the design colours', (tester) async {
    expect(chipColor('uploaded'), brandGold);
    expect(chipColor('processing'), brandBrown);
    expect(chipColor('done'), okGreen);
    expect(chipColor('failed'), badRed);
    expect(chipColor('cancelled'), textMuted);
    await tester.pumpWidget(const MaterialApp(home: StatusChip('Waiting', brandGold)));
    expect(find.text('Waiting'), findsOneWidget);
  });
}
