import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vriksha_capture/kit.dart';
import 'package:vriksha_capture/config.dart';
import 'package:vriksha_capture/modules.dart';
import 'package:vriksha_capture/screens/home_shell.dart';
import 'package:vriksha_capture/session.dart';
import 'package:vriksha_capture/theme.dart';

Session as_(String role) => Session('https://shop.test', 't', 'u', role);

void main() {
  test('each role sees the same screens as the desktop sidebar', () {
    final ids = modules.map((m) => m.id).toList();
    Set<String> seen(String role) => {for (final id in ids) if (as_(role).allows(id)) id};
    expect(seen('owner'), ids.toSet());
    expect(seen('manager'), ids.toSet()..remove('staff'));
    expect(seen('sales').intersection({'reports', 'lab', 'materials', 'purchases', 'staff', 'wages', 'expenses', 'profit'}), isEmpty);
    expect(seen('sales'), containsAll(['bill', 'buyers', 'history', 'workforce']));
    expect(seen('achari'), {'home', 'stock', 'workforce', 'lab', 'wages'});
    expect(seen('worker'), {'home', 'stock', 'workforce', 'lab', 'wages'});
    expect(as_('worker').canSell, isFalse);
  });

  test('money and dates read like the desktop', () {
    expect(rupees(1234.5), '₹1,234.50');
    expect(rupees('1000000'), '₹1,000,000.00');
    expect(rupees(-5), '-₹5.00');
    expect(rupees(null), '₹0.00');
    expect(rupees(1200, dp: 0), '₹1,200');
    expect(niceDate(DateTime(2026, 3, 5)), '05 Mar 2026');
  });

  test('periods match the desktop', () {
    final now = DateTime(2026, 3, 15);
    expect(periodRange('month', now), ('2026-03-01', '2026-03-15'));
    expect(periodRange('last_month', now), ('2026-02-01', '2026-02-28'));
    expect(periodRange('year', now), ('2026-01-01', '2026-03-15'));
    expect(periodRange('all', now), (null, null));
    expect(periodRange('last_month', DateTime(2026, 1, 10)), ('2025-12-01', '2025-12-31'));
  });

  test('the server address is fixed in the app, not typed at sign-in', () {
    expect(apiBaseUrl, startsWith('https://'));
  });

  test('client ids look like uuids and differ', () {
    final a = newClientId(), b = newClientId();
    expect(a, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(a, isNot(b));
  });

  testWidgets('a form refuses a missing required field, then returns typed values', (tester) async {
    Map<String, Object?>? result;
    await tester.pumpWidget(MaterialApp(
      theme: brandTheme(),
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () async => result = await showForm(c, 'Add expense', const [
            F('category', 'Heading', required: true),
            F('amount', 'Amount', kind: K.money, required: true),
            F('notes', 'Note'),
          ]),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Heading: please fill this in.'), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Heading *'), 'Shop rent');
    await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '0');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Amount: please fill this in.'), findsOneWidget); // zero is not an amount

    await tester.enterText(find.widgetWithText(TextField, 'Amount *'), '1500.5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(result, {'category': 'Shop rent', 'amount': 1500.5, 'notes': null});
  });

  testWidgets('the sidebar lists the desktop screens for the role and switches screens', (tester) async {
    var out = 0;
    await tester.pumpWidget(MaterialApp(
      theme: brandTheme(),
      home: HomeShell(session: as_('sales'), onSignOut: () => out++),
    ));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Staff desk · u'), findsOneWidget);
    for (final label in ['Home', 'New Bill', 'Stock', 'Buyers', 'Bill History', 'Workforce']) {
      expect(find.textContaining(label), findsWidgets, reason: label);
    }
    expect(find.textContaining('Profit'), findsNothing); // hidden from sales, as on the desktop
    expect(find.textContaining('Reports'), findsNothing);
    await tester.tap(find.textContaining('Buyers'));
    await tester.pumpAndSettle();
    expect(find.text('Buyers'), findsOneWidget); // the screen's own title
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Sign Out'));
    expect(out, 1);
  });
}
