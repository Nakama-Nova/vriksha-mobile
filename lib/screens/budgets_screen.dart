import 'package:flutter/material.dart';

import '../kit.dart';
import '../theme.dart';

const _categoryWords = {'machines': 'Machines', 'raw_materials': 'Raw materials'};
const _stateWords = {'ok': 'On track', 'warning': 'Nearly used', 'over': 'Over budget', 'no_budget': 'No budget'};
const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December',
];

String categoryWord(Object? c) => _categoryWords['$c'] ?? '$c';

Color stateColour(String state) => switch (state) {
      'over' => badRed,
      'warning' => brandGold,
      'ok' => okGreen,
      _ => textMuted,
    };

/// "March 2026", or "Year 2026–27" for a financial year (April to March).
String periodLabel(String period, Object? start) {
  final d = DateTime.tryParse('${start ?? ''}');
  if (d == null) return '';
  if (period == 'financial_year') return 'Year ${d.year}–${((d.year + 1) % 100).toString().padLeft(2, '0')}';
  return '${_months[d.month - 1]} ${d.year}';
}

/// (percent used, state, words) for a budget of [amount] with [spent] used so far; the
/// same rule as the desktop: amber from 80%, red when all of it is used.
(double, String, String) usageText(double amount, double spent) {
  if (amount <= 0) return (0, 'no_budget', 'No budget set');
  final pct = spent / amount * 100;
  final state = spent >= amount ? 'over' : (pct >= 80 ? 'warning' : 'ok');
  final left = amount - spent;
  return (pct, state, '${pct.toStringAsFixed(0)}% used · ${left >= 0 ? '${rupees(left)} left' : '${rupees(-left)} over'}');
}

double _num(Object? v) => double.tryParse('${v ?? ''}') ?? 0;

/// Budgets for machines and raw materials: this month and this financial year. Buying is
/// never blocked. Owner and manager look; only the owner sets or removes a budget.
class BudgetsScreen extends StatefulWidget {
  const BudgetsScreen({super.key});
  @override
  State<BudgetsScreen> createState() => _BudgetsScreenState();
}

class _BudgetsScreenState extends State<BudgetsScreen> {
  int _gen = 0;

  Future<void> _set(Map s) async {
    final v = await showForm(
      context,
      'Budget: ${categoryWord(s['category'])} · ${periodLabel('${s['period']}', s['period_start'])}',
      [
        F('amount', 'Budget', kind: K.money, initial: s['amount'], hint: 'Spent so far ${rupees(s['spent'])}'),
        F('notes', 'Note', initial: s['notes'], hint: 'optional'),
      ],
    );
    if (v == null || !mounted) return;
    final api = AppScope.of(context).session.api;
    if (await guard(
        context,
        () async => api.putJson('/budgets/', {
              'category': s['category'],
              'period': s['period'],
              'starts_on': s['period_start'],
              'amount': '${v['amount'] ?? 0}',
              'notes': v['notes'],
            }),
        done: 'Budget saved')) {
      setState(() => _gen++);
    }
  }

  Future<void> _remove(Map s) async {
    final ok = await confirm(
        context,
        'Remove budget',
        'Remove the ${categoryWord(s['category']).toLowerCase()} budget for ${periodLabel('${s['period']}', s['period_start'])}? What was spent is not touched.',
        ok: 'Remove');
    if (!ok || !mounted) return;
    final api = AppScope.of(context).session.api;
    if (await guard(context, () async => api.deleteJson('/budgets/${s['id']}'), done: 'Budget removed')) {
      setState(() => _gen++);
    }
  }

  Widget _card(Map s, bool owner) {
    final amount = _num(s['amount']);
    final spent = _num(s['spent']);
    final (pct, fallbackState, words) = usageText(amount, spent);
    final state = '${s['state'] ?? fallbackState}';
    final colour = stateColour(state);
    final shown = _num(s['percent_used'] ?? pct);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${categoryWord(s['category'])} · ${periodLabel('${s['period']}', s['period_start'])}',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          gap(6),
          Text('${rupees(spent)}${amount > 0 ? '  of  ${rupees(amount)}' : ''}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          gap(8),
          LinearProgressIndicator(
            value: (shown.clamp(0, 100)) / 100,
            color: colour,
            backgroundColor: lineColor,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          gap(6),
          Text(words, style: TextStyle(color: colour, fontWeight: FontWeight.w600)),
          gap(4),
          Text(
            '${s['category'] == 'machines' ? 'Machines are worth ' : 'Stock is worth '}${rupees(s['current_value'])} today',
            style: const TextStyle(color: textMuted, fontSize: 13),
          ),
          if (owner)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => _set(s), child: Text(amount > 0 ? 'Change budget' : 'Set a budget')),
            ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final owner = AppScope.of(context).session.isOwner;
    return Screen(
      title: 'Budgets',
      body: Loader<(List, List)>(
        key: ValueKey(_gen),
        load: (api) async => (await api.getJson('/budgets/current') as List, await api.getJson('/budgets/', {'limit': '200'}) as List),
        builder: (c, d, reload) {
          final (current, all) = d;
          final hot = [for (final s in current) if (s['state'] == 'warning' || s['state'] == 'over') s];
          return ListView(padding: const EdgeInsets.all(16), children: [
            hint('A budget is a guide: buying is never stopped when one is used up. The bar turns amber at 80% and red when it is all used.'
                '${owner ? " Tap a card's button to set or change its budget." : ''}'),
            if (hot.isNotEmpty) ...[
              gap(12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (hot.any((s) => s['state'] == 'over') ? badRed : brandGold).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '⚠️  ${[
                    for (final s in hot)
                      '${categoryWord(s['category'])} (${periodLabel('${s['period']}', s['period_start']).toLowerCase()}): ${(_stateWords['${s['state']}'] ?? '').toLowerCase()}',
                  ].join('   ·   ')}',
                ),
              ),
            ],
            gap(12),
            for (final s in current) ...[_card(s, owner), gap(10)],
            gap(6),
            heading('Every budget set'),
            if (all.isEmpty) hint('No budgets set yet.'),
            for (final s in all)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowCard(
                  title: '${periodLabel('${s['period']}', s['period_start'])} · ${categoryWord(s['category'])}',
                  lines: [
                    'Budget ${s['amount'] == null ? '—' : rupees(s['amount'])} · spent ${rupees(s['spent'])}'
                        '${s['remaining'] == null ? '' : ' · left ${rupees(s['remaining'])}'}',
                  ],
                  trailing: Text(_stateWords['${s['state']}'] ?? '${s['state']}',
                      style: TextStyle(color: stateColour('${s['state']}'), fontWeight: FontWeight.w600, fontSize: 12)),
                  onTap: owner && s['id'] != null
                      ? () => actionSheet(context, '${categoryWord(s['category'])} budget', [
                            ('Change budget', () => _set(s)),
                            ('Remove budget', () => _remove(s)),
                          ])
                      : null,
                ),
              ),
          ]);
        },
      ),
    );
  }
}
