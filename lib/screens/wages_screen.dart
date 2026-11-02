import 'package:flutter/material.dart';

import '../kit.dart';
import '../theme.dart';
import 'expenses_screen.dart' show payMethods, methodWord;
import 'staff_screen.dart' show roleWords;

String _name(Map p) => '${p['full_name'] ?? p['username'] ?? '?'}';

const _kinds = <(String, Object?)>[
  ('Piece or job work', 'piece'),
  ('Overtime hours', 'overtime'),
  ('Bonus', 'bonus'),
];
const _kindWords = {'piece': 'Piece work', 'overtime': 'Overtime', 'bonus': 'Bonus'};

/// Wages: what each person is owed and pay-outs (owner and manager); everyone else
/// sees only their own balance and pay-outs.
class WagesScreen extends StatefulWidget {
  const WagesScreen({super.key});
  @override
  State<WagesScreen> createState() => _WagesScreenState();
}

class _WagesScreenState extends State<WagesScreen> {
  int _gen = 0;
  List _people = [];

  Future<void> _post(String path, Map<String, Object?> body, String done) async {
    final api = AppScope.of(context).session.api;
    if (await guard(context, () async => api.postJson(path, body), done: done)) setState(() => _gen++);
  }

  Future<void> _work(Map? p) async {
    final v = await showForm(context, 'Add work or bonus', [
      F('user_id', 'Who', kind: K.choice, required: true, initial: p?['user_id'], choices: [
        for (final x in _people) (_name(x), x['user_id']),
      ]),
      const F('kind', 'What for', kind: K.choice, required: true, initial: 'piece', choices: _kinds),
      const F('work_date', 'Date', kind: K.date),
      const F('description', 'Details', required: true, hint: 'e.g. Carved Ganesha panel'),
      const F('quantity', 'Pieces or hours (not for a bonus)', kind: K.number, initial: 1),
      const F('rate', 'Rate per piece or hour, or the bonus amount', kind: K.money, hint: 'overtime: leave blank for their usual rate'),
    ], ok: 'Add');
    if (v == null || !mounted) return;
    final bonus = v['kind'] == 'bonus';
    if (v['rate'] == null && v['kind'] != 'overtime') return snack(context, 'Enter the rate (or the bonus amount).');
    await _post('/payroll/work-entries', {
      'user_id': v['user_id'],
      'work_date': v['work_date'],
      'kind': v['kind'],
      'description': v['description'],
      'quantity': bonus ? 1 : (v['quantity'] ?? 1),
      'rate': v['rate'],
    }, 'Added');
  }

  Future<void> _advance(Map? p) async {
    final v = await showForm(context, 'Advance', [
      F('user_id', 'Who', kind: K.choice, required: true, initial: p?['user_id'], choices: [
        for (final x in _people) (_name(x), x['user_id']),
      ]),
      const F('kind', 'What', kind: K.choice, initial: 'advance', choices: [
        ('Give an advance', 'advance'),
        ('They paid some back', 'recovery'),
      ]),
      const F('given_on', 'Date', kind: K.date),
      const F('amount', 'Amount', kind: K.money, required: true),
      const F('notes', 'Note', hint: 'optional, e.g. for hospital'),
    ]);
    if (v == null) return;
    await _post('/payroll/advances', v, 'Saved');
  }

  Future<void> _pay(Map p) async {
    final owes = numOf(p['advance_balance']), due = numOf(p['owed_gross']);
    final v = await showForm(
        context,
        'Pay ${_name(p)}',
        [
          F('through', 'Pay everything up to', kind: K.date),
          if (owes > 0) F('deduction', 'Take back from advance (they owe ${rupees(owes)})', kind: K.money),
          const F('method', 'How paid', kind: K.choice, initial: 'cash', choices: payMethods),
          const F('reference', 'Reference', hint: 'UPI or cheque number (optional)'),
        ],
        ok: 'Pay now');
    if (v == null || !mounted) return;
    final cut = numOf(v['deduction']);
    if (cut > owes || cut > due) return snack(context, 'That is more than they owe or are due.');
    final api = AppScope.of(context).session.api;
    Map? paid;
    if (await guard(context, () async => paid = await api.postJson('/payroll/pay', {
          'user_id': p['user_id'],
          'through': v['through'],
          'deduction': cut,
          'method': v['method'],
          'reference': v['reference'],
        }) as Map)) {
      if (mounted) snack(context, '${_name(p)} was paid ${rupees(paid?['net_paid'])}');
      setState(() => _gen++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final manage = AppScope.of(context).session.isStaffLead;
    return Screen(
      title: manage ? 'Wages' : 'My pay',
      body: manage ? _everyone() : _mine(),
    );
  }

  Widget _everyone() => Loader<(List, List)>(
        key: ValueKey(_gen),
        load: (api) async => (await api.getJson('/payroll/summary') as List, await api.getJson('/payroll/payments') as List),
        builder: (c, d, reload) {
          final (owed, pays) = d;
          _people = owed;
          final names = {for (final p in owed) '${p['user_id']}': _name(p)};
          return ListView(padding: const EdgeInsets.all(16), children: [
            hint('Daily wages come from attendance. Add piece work, overtime or a bonus here, then Pay to settle everything up to a date. Paying is what counts wages in your profit.'),
            gap(12),
            metricGrid([
              Metric('Owed to staff now', rupees(owed.fold<num>(0, (a, p) => a + numOf(p['owed_gross']))), color: brandGold),
              Metric('Advances out', rupees(owed.fold<num>(0, (a, p) => a + numOf(p['advance_balance'])))),
            ]),
            gap(12),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _work(null), child: const Text('Work or bonus'))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton(onPressed: () => _advance(null), child: const Text('Advance'))),
            ]),
            gap(12),
            for (final p in owed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowCard(
                  title: _name(p),
                  lines: [
                    '${roleWords['${p['role']}'] ?? p['role'] ?? ''}',
                    'Daily ${rupees(p['pending_daily'])} · Piece/OT/bonus ${rupees(p['pending_extras'])}',
                    'Advance owed ${rupees(p['advance_balance'])}',
                  ],
                  trailing: Text(rupees(p['owed_gross']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  onTap: () => actionSheet(context, _name(p), [
                    if (numOf(p['owed_gross']) > 0) ('Pay', () => _pay(p)),
                    ('Add work or bonus', () => _work(p)),
                    ('Advance', () => _advance(p)),
                  ]),
                ),
              ),
            heading('Recent pay-outs'),
            if (pays.isEmpty) hint('No pay-outs yet.'),
            for (final p in pays.take(20))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowCard(
                  title: names['${p['user_id']}'] ?? '(former staff)',
                  lines: [
                    '${p['paid_on']} · ${methodWord(p['method'])}',
                    'Earned ${rupees(numOf(p['gross_daily']) + numOf(p['gross_extras']))} · Taken back ${rupees(p['deductions'])}',
                  ],
                  trailing: Text(rupees(p['net_paid']), style: const TextStyle(fontWeight: FontWeight.w700, color: okGreen)),
                ),
              ),
          ]);
        },
      );

  Widget _mine() => Loader<Map>(
        load: (api) async => (await api.getJson('/payroll/me')) as Map,
        builder: (c, me, reload) => ListView(padding: const EdgeInsets.all(16), children: [
          hint('What you have earned and not been paid yet, any advance you owe, and your last pay-outs.'),
          gap(12),
          metricGrid([
            Metric('Daily wages due', rupees(me['pending_daily']), color: okGreen),
            Metric('Piece work, overtime, bonus', rupees(me['pending_extras'])),
            Metric('Advance I owe', rupees(me['advance_balance']), color: brandGold),
            Metric('Total waiting for me', rupees(me['owed_gross'])),
          ]),
          heading('Work waiting to be paid'),
          if ((me['pending_entries'] as List).isEmpty) hint('Nothing waiting.'),
          for (final e in me['pending_entries'] as List)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RowCard(
                title: '${e['description']}',
                lines: ['${e['work_date']} · ${_kindWords[e['kind']] ?? e['kind']}'],
                trailing: Text(rupees(e['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          heading('My last pay-outs'),
          for (final p in me['recent_payments'] as List)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RowCard(
                title: '${p['paid_on']}',
                lines: [
                  '${methodWord(p['method'])} · Earned ${rupees(numOf(p['gross_daily']) + numOf(p['gross_extras']))} · Taken back ${rupees(p['deductions'])}',
                ],
                trailing: Text(rupees(p['net_paid']), style: const TextStyle(fontWeight: FontWeight.w700, color: okGreen)),
              ),
            ),
        ]),
      );
}
