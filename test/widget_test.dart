import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vriksha_capture/screens/login_screen.dart';
import 'package:vriksha_capture/theme.dart';

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
}
