import 'package:flutter/material.dart';

import '../kit.dart';
import '../theme.dart';

const expenseHeadings = [
  'Shop rent', 'Electricity', 'Transport', 'Tools', 'Repairs', 'Packing', 'Tea and food', 'Advertising', 'Other',
];

/// How money was paid (shared with Wages).
const payMethods = <(String, Object?)>[
  ('Cash', 'cash'), ('UPI', 'upi'), ('Bank', 'bank'), ('Cheque', 'cheque'), ('Other', 'other'),
];

String methodWord(Object? m) {
  final s = '${m ?? ''}';
  return s == 'upi' ? 'UPI' : (s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1));
}

/// Expenses: rent, electricity, transport, tools, repairs. Owner and manager add and
/// fix entries; only the owner can cancel one (it stays on record with the reason).
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String _period = 'month';
  int _gen = 0;
  List _seen = [];

  List<F> _fields([Map? e]) => [
        F('spent_on', 'Date', kind: K.date, initial: e?['spent_on']),
        F('category', 'Heading', kind: K.choice, required: true, initial: e?['category'] ?? expenseHeadings.first, choices: [
          for (final h in {...expenseHeadings, ..._seen}) (h as String, h),
        ]),
        F('amount', 'Amount', kind: K.money, required: true, initial: e?['amount']),
        F('payee', 'Paid to', initial: e?['payee'], hint: 'optional'),
        F('method', 'How paid', kind: K.choice, choices: payMethods, initial: e?['method'] ?? 'cash'),
        F('notes', 'Note', initial: e?['notes'], hint: 'optional'),
      ];

  Future<void> _save([Map? e]) async {
    final v = await showForm(context, e == null ? 'Add expense' : 'Edit expense', _fields(e));
    if (v == null || !mounted) return;
    final api = AppScope.of(context).session.api;
    if (await guard(
        context,
        () async => e == null ? api.postJson('/expenses/', v) : api.patchJson('/expenses/${e['id']}', v),
        done: 'Saved')) {
      setState(() => _gen++);
    }
  }

  Future<void> _void(Map e) async {
    final v = await showForm(
        context,
        'Cancel this entry',
        [F('reason', 'Why is it wrong?', required: true, hint: 'It stays on record, marked cancelled')],
        ok: 'Cancel entry');
    if (v == null || !mounted) return;
    final reason = '${v['reason']}';
    if (reason.length < 3) return snack(context, 'Please give a short reason.');
    final api = AppScope.of(context).session.api;
    if (await guard(context, () async => api.postJson('/expenses/${e['id']}/void', {'reason': reason}),
        done: 'Entry cancelled')) {
      setState(() => _gen++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = AppScope.of(context).session.isOwner;
    final (start, end) = periodRange(_period);
    final q = <String, String>{'start_date': ?start, 'end_date': ?end};
    return Screen(
      title: 'Expenses',
      fab: addFab('Add expense', _save),
      body: Loader<(List, Map)>(
        key: ValueKey('$_gen$_period'),
        load: (api) async => (
          await api.getJson('/expenses/', q) as List,
          await api.getJson('/expenses/summary', q) as Map,
        ),
        builder: (c, d, reload) {
          final (rows, sum) = d;
          _seen = [for (final r in rows) r['category']];
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
            PeriodPicker(value: _period, onChanged: (v) => setState(() => _period = v)),
            gap(12),
            hint('Rent, electricity, transport, tools, repairs. Timber you buy goes under Purchases and staff pay under Wages, so leave those out here.'),
            gap(12),
            Metric('Total spent', rupees(sum['total']), color: badRed),
            gap(),
            Text([for (final x in sum['by_category'] as List) '${x['category']} ${rupees(x['total'])}'].join('  ·  '),
                style: const TextStyle(fontSize: 12, color: textMuted)),
            gap(12),
            if (rows.isEmpty) hint('No expenses in this period.'),
            for (final e in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowCard(
                  title: '${e['category']}',
                  lines: [
                    '${e['spent_on']} · ${methodWord(e['method'])}${e['payee'] != null ? ' · ${e['payee']}' : ''}',
                    '${e['notes'] ?? ''}',
                  ],
                  trailing: Text(rupees(e['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => actionSheet(context, '${e['category']} ${rupees(e['amount'])}', [
                    ('Edit', () => _save(e)),
                    if (owner) ('Cancel entry', () => _void(e)),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
