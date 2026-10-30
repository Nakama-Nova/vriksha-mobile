import 'package:flutter/material.dart';

import '../kit.dart';
import '../theme.dart';

/// Profit: sales billed minus timber bought, wages paid and expenses (owner and manager).
class ProfitScreen extends StatefulWidget {
  const ProfitScreen({super.key});
  @override
  State<ProfitScreen> createState() => _ProfitScreenState();
}

class _ProfitScreenState extends State<ProfitScreen> {
  String _period = 'month';

  @override
  Widget build(BuildContext context) {
    final (start, end) = periodRange(_period);
    return Screen(
      title: 'Profit',
      body: Loader<Map>(
        key: ValueKey(_period),
        load: (api) async => (await api.getJson('/reports/profit', {
          'start_date': ?start,
          'end_date': ?end,
        })) as Map,
        builder: (c, r, reload) {
          final loss = numOf(r['profit']) < 0;
          final tint = loss ? badRed : okGreen;
          return ListView(padding: const EdgeInsets.all(16), children: [
            PeriodPicker(value: _period, onChanged: (v) => setState(() => _period = v)),
            gap(12),
            metricGrid([
              Metric('Sales billed', rupees(r['sales']), color: okGreen),
              Metric('Timber & materials bought', rupees(r['purchases'])),
              Metric('Wages paid', rupees(r['wages'])),
              Metric('Other expenses', rupees(r['expenses'])),
              Metric('Profit', rupees(r['profit']), color: tint),
              Metric('Margin', '${numOf(r['margin_pct']).toStringAsFixed(1)}%', color: tint),
            ]),
            gap(12),
            kv('Owed to staff now', rupees(r['unpaid_wages'])),
            kv('Advances staff owe you', rupees(r['advances_outstanding'])),
            kv('Timber and materials in stock', rupees(r['raw_material_stock_value'])),
            if ((r['expenses_by_category'] as List).isNotEmpty) ...[
              gap(),
              Text(
                'Expenses: ${[for (final x in r['expenses_by_category'] as List) '${x['category']} ${rupees(x['total'])}'].join('  ·  ')}',
                style: const TextStyle(fontSize: 12, color: textMuted),
              ),
            ],
            heading('Month by month'),
            for (final m in r['months'] as List)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('${m['month']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(rupees(m['profit']),
                            style: TextStyle(fontWeight: FontWeight.w700, color: numOf(m['profit']) < 0 ? badRed : okGreen)),
                      ]),
                      kv('Sales', rupees(m['sales'])),
                      kv('Materials', rupees(m['purchases'])),
                      kv('Wages', rupees(m['wages'])),
                      kv('Expenses', rupees(m['expenses'])),
                    ]),
                  ),
                ),
              ),
            gap(),
            hint('Profit here is what came in minus what went out in the same dates. Timber counts when you buy it, so a big purchase lowers that month; the stock still on the shelf is shown above and is not lost.'),
          ]);
        },
      ),
    );
  }
}
