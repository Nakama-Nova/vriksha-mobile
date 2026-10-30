import 'package:flutter/material.dart';

import '../kit.dart';
import '../theme.dart';
import '../widgets.dart';

/// Reports: totals and the low-stock list (owner and manager).
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) => Screen(
        title: 'Reports',
        body: Loader<List>(
          load: (api) => Future.wait([
            api.getJson('/dashboard/summary'),
            api.getJson('/reports/sales'),
            api.getJson('/reports/inventory'),
          ]),
          builder: (c, d, reload) {
            final dash = (d[0] ?? {}) as Map, sales = (d[1] ?? {}) as Map;
            final low = (d[2] as List).where((i) => i['is_low_stock'] == true).toList();
            return ListView(padding: const EdgeInsets.all(20), children: [
              metricGrid([
                Metric("Today's bills", '${numOf(dash['today_sales_count']).toInt()}', color: okGreen),
                Metric("Today's revenue", rupees(dash['today_revenue'])),
                Metric('Total bills', '${numOf(sales['total_orders']).toInt()}'),
                Metric('Total revenue', rupees(sales['total_revenue']), color: brandGold),
                // No tax tile until the shop is GST-registered and bills carry tax.
                if (numOf(sales['total_tax']) > 0) Metric('Total tax', rupees(sales['total_tax'])),
                Metric('Low stock items', '${low.length}', color: badRed),
              ]),
              heading('Low stock alerts'),
              if (low.isEmpty) hint('Nothing is running low.'),
              for (final i in low)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RowCard(
                    title: '${i['name']}',
                    lines: ['${i['sku'] ?? ''} · reorder at ${numOf(i['min_stock'])}'],
                    trailing: StatusChip('${numOf(i['current_stock'])} left', badRed),
                  ),
                ),
            ]);
          },
        ),
      );
}
