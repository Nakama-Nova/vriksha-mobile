import 'package:flutter/material.dart';

import '../kit.dart';
import '../theme.dart';

/// Greeting, today's numbers (owner/manager) and quick actions, as on the desktop Home.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.session;
    final hour = DateTime.now().hour;
    final greeting = hour < 12 ? 'Good morning' : (hour < 17 ? 'Good afternoon' : 'Good evening');
    final sub = switch (s.role) {
      'achari' => 'Manage manufacturing and stock',
      'worker' => 'Your daily attendance and basic stock',
      _ => "Here's your business at a glance",
    };

    Widget actions() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          heading('Quick actions'),
          Wrap(spacing: 10, runSpacing: 10, children: [
            if (s.canSell)
              FilledButton.icon(
                  onPressed: () => scope.go('bill'),
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('New bill')),
            OutlinedButton.icon(
                onPressed: () => scope.go('stock'),
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('View stock')),
            if (s.canSell)
              OutlinedButton.icon(
                  onPressed: () => scope.go('buyers'),
                  icon: const Icon(Icons.person_add_alt),
                  label: const Text('Add buyer')),
          ]),
        ]);

    return Screen(
      title: greeting,
      subtitle: sub,
      body: s.isStaffLead
          ? Loader<Map>(
              load: (api) async => (await api.getJson('/dashboard/summary')) as Map,
              builder: (c, d, reload) => ListView(padding: const EdgeInsets.all(20), children: [
                metricGrid([
                  Metric("Today's sales", '${numOf(d['today_sales_count']).toInt()}', color: okGreen),
                  Metric("Today's revenue", rupees(d['today_revenue'])),
                  Metric('Low stock', '${numOf(d['low_stock_count']).toInt()}', color: badRed),
                  Metric('Wages due', rupees(d['pending_wages_total']), color: brandGold),
                ]),
                actions(),
              ]),
            )
          : ListView(padding: const EdgeInsets.all(20), children: [actions()]),
    );
  }
}
