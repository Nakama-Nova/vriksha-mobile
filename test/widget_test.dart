import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vriksha_capture/screens/login_screen.dart';
import 'package:vriksha_capture/screens/scans_screen.dart';
import 'package:vriksha_capture/theme.dart';
import 'package:vriksha_capture/widgets.dart';

void main() {
  testWidgets('login asks for user and password only, with no server address', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: brandTheme(), home: LoginScreen(onSignedIn: (_) {})));
    expect(find.text('Server address'), findsNothing);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter your username and password'), findsOneWidget);
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
