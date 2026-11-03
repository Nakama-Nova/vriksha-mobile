import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vriksha_capture/kit.dart';
import 'package:vriksha_capture/config.dart';
import 'package:vriksha_capture/modules.dart';
import 'package:vriksha_capture/screens/budgets_screen.dart';
import 'package:vriksha_capture/screens/orders_screen.dart';
import 'package:vriksha_capture/screens/places_screen.dart';
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

  test('the side panel has the desktop\'s order, headings and names', () {
    final bySection = <String?, List<String>>{};
    for (final m in modules) {
      (bySection[m.section] ??= []).add(m.label);
    }
    expect(bySection[null], ['Home']);
    expect(bySection['Selling'], ['New Bill', 'Bill History', 'Orders', 'Buyers']);
    expect(bySection['Stock and buying'], ['Stock', 'Materials', 'Purchases', 'Places']);
    expect(bySection['Workshop'], ['3D Lab']);
    expect(bySection['People and pay'], ['Attendance', 'Wages', 'Staff']);
    expect(bySection['Money'], ['Expenses', 'Profit', 'Budgets', 'Reports']);
  });

  test('budgets: owner and manager look, nobody else; the rest of the desktop rules', () {
    expect(as_('owner').allows('budgets'), isTrue);
    expect(as_('manager').allows('budgets'), isTrue);
    for (final r in ['sales', 'achari', 'artisan', 'worker']) {
      expect(as_(r).allows('budgets'), isFalse, reason: r);
    }
    expect(as_('manager').allows('restoration'), isFalse);
    expect(as_('manager').allows('designs'), isFalse);
    expect(as_('artisan').allows('restoration'), isTrue);
    expect(as_('artisan').allows('designs'), isTrue);
    expect(as_('achari').allows('machines'), isTrue);
    expect(as_('worker').allows('machines'), isFalse);
    expect(as_('sales').allows('machines'), isFalse);
  });

  test('orders: sellers see them, the workshop roles do not', () {
    for (final r in ['owner', 'manager', 'sales']) {
      expect(as_(r).allows('orders'), isTrue, reason: r);
    }
    for (final r in ['achari', 'artisan', 'worker']) {
      expect(as_(r).allows('orders'), isFalse, reason: r);
    }
  });

  test('places: owner, manager and sales look; the workshop roles do not', () {
    for (final r in ['owner', 'manager', 'sales']) {
      expect(as_(r).allows('places'), isTrue, reason: r);
    }
    for (final r in ['achari', 'artisan', 'worker']) {
      expect(as_(r).allows('places'), isFalse, reason: r);
    }
  });

  test('places: quantities, names and what a stock row is about', () {
    expect(qtyText('2'), '2');
    expect(qtyText(2.5), '2.5');
    expect(qtyText('10.00'), '10');
    expect(qtyText('100'), '100');
    expect(qtyText(0), '0');
    expect(qtyText('0.25'), '0.25');
    final places = [{'id': 'a', 'name': 'Carving unit'}, {'id': 'b', 'name': 'Shop'}];
    expect(placeName(places, null), 'Not placed yet');
    expect(placeName(places, 'b'), 'Shop');
    expect(placeName(places, 'zzz'), 'Unknown place');
    expect(thingKey({'item_id': 'i1', 'raw_material_id': null}), ('item', 'i1'));
    expect(thingKey({'item_id': null, 'raw_material_id': 'm1'}), ('material', 'm1'));
  });

  test('order figures follow the desktop', () {
    // the final amount once set, else the estimate
    expect(amountOf({'estimated_amount': '1000.00', 'final_amount': null}), 1000);
    expect(amountOf({'estimated_amount': '1000.00', 'final_amount': '1200.00'}), 1200);
    expect(amountOf({'estimated_amount': '1000.00', 'final_amount': '0'}), 1000);
    expect(itemsSummary({'items': []}), '');
    expect(itemsSummary({'items': [{'item_name': 'Door', 'quantity': 1}]}), 'Door');
    expect(
        itemsSummary({
          'items': [
            {'item_name': 'Pillar', 'quantity': 2},
            {'item_name': 'Bracket', 'quantity': 1},
          ]
        }),
        '2 × Pillar  +1 more');
    expect(itemsSummary({'items': [{'item_name': null, 'quantity': 1}]}), 'Catalogue piece');
    // a catalogue piece is priced with GST included
    expect(priceWithGst({'selling_price': '1000', 'gst_percent': '18'}), 1180);
    expect(priceWithGst({'selling_price': '99.99', 'gst_percent': '5'}), 104.99);
    expect(statusWord('in_production'), 'In production');
    expect(statusWord('draft'), 'New');
  });

  test('budget usage follows the desktop: amber from 80%, red when used up', () {
    expect(usageText(0, 500), (0.0, 'no_budget', 'No budget set'));
    expect(usageText(1000, 500), (50.0, 'ok', '50% used · ₹500.00 left'));
    expect(usageText(1000, 800).$2, 'warning');
    expect(usageText(1000, 1000).$2, 'over');
    expect(usageText(1000, 1200), (120.0, 'over', '120% used · ₹200.00 over'));
    expect(periodLabel('month', '2026-03-01'), 'March 2026');
    expect(periodLabel('financial_year', '2026-04-01'), 'Year 2026–27');
    expect(periodLabel('month', null), '');
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
    // The menu list scrolls and only builds what is on screen; with the section headings it
    // is longer than the default 800x600 test window, so use a tall one.
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: brandTheme(),
      home: HomeShell(session: as_('sales'), onSignOut: () => out++),
    ));
    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();
    expect(find.text('Staff desk · u'), findsOneWidget);
    for (final label in ['Home', 'New Bill', 'Stock', 'Buyers', 'Bill History', 'Attendance']) {
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
