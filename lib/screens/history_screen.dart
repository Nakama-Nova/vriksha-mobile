import 'package:flutter/material.dart';

import '../kit.dart';

/// Bill History: past bills, optionally for one day; tap a bill to see its items.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  DateTime? _day;

  Future<void> _pick() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _day ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now());
    if (d != null) setState(() => _day = d);
  }

  Future<void> _items(Map sale) async {
    final api = AppScope.of(context).session.api;
    List rows = [];
    if (!await guard(context, () async => rows = await api.getJson('/sales/${sale['id']}/items') as List) ||
        !mounted) {
      return;
    }
    await infoSheet(context, 'Bill ${sale['invoice_number']}', [
      if (rows.isEmpty) hint('No items found for this bill.'),
      for (final r in rows)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${r['item_name'] ?? 'Item'}'),
          subtitle: Text('${numOf(r['quantity'])} × ${rupees(r['price_at_sale'])}'),
          trailing: Text(rupees(r['total_price']), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      const Divider(),
      kv('Total', rupees(sale['total_amount'])),
    ]);
  }

  @override
  Widget build(BuildContext context) => Screen(
        title: 'Bill history',
        body: Loader<List>(
          key: ValueKey(_day),
          load: (api) async =>
              (await api.getJson('/sales', _day == null ? null : {'date': isoDate(_day!)})) as List,
          builder: (c, rows, reload) => ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pick,
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(_day == null ? 'Filter by date' : niceDate(_day!)),
                ),
              ),
              if (_day != null) TextButton(onPressed: () => setState(() => _day = null), child: const Text('Clear')),
            ]),
            gap(12),
            if (rows.isEmpty) hint('No bills found.'),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowCard(
                  title: '${r['invoice_number'] ?? 'N/A'}',
                  lines: [showDate(r['created_at'])],
                  onTap: () => _items(r),
                  trailing: Text(rupees(r['total_amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
          ]),
        ),
      );
}
