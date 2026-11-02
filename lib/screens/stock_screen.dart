import 'package:flutter/material.dart';

import '../kit.dart';
import '../theme.dart';
import '../widgets.dart';

const movementWords = {
  'adjustment': 'Manual change',
  'raw_in': 'Received',
  'raw_consumed': 'Used in production',
  'finished_in': 'Made',
  'finished_out': 'Sold',
};

/// Stock ledger rows for a product or raw material (shared with Materials).
Future<void> showMovements(BuildContext c, String title, String param, String id) async {
  final api = AppScope.of(c).session.api;
  List rows = [];
  final ok = await guard(c, () async {
    rows = await api.getJson('/inventory/movements', {param: id, 'limit': '100'}) as List;
  });
  if (!ok || !c.mounted) return;
  await infoSheet(c, title, [
    if (rows.isEmpty) hint('Nothing recorded yet.'),
    for (final r in rows)
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(movementWords[r['movement_type']] ?? '${r['movement_type']}'),
        subtitle: Text([
          '${r['created_at']}'.length >= 16 ? '${r['created_at']}'.substring(0, 16).replaceAll('T', ' ') : '',
          if (r['by'] != null) '${r['by']}',
          if (r['notes'] != null) '${r['notes']}',
        ].where((e) => e.isNotEmpty).join(' · ')),
        trailing: Text(
          '${numOf(r['quantity']) > 0 ? '+' : ''}${numOf(r['quantity'])}',
          style: TextStyle(fontWeight: FontWeight.w700, color: numOf(r['quantity']) > 0 ? okGreen : badRed),
        ),
      ),
  ]);
}

/// Stock: every product with its price and quantity; owner/manager can add, edit, adjust.
class StockScreen extends StatefulWidget {
  const StockScreen({super.key});
  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  String _q = '';
  int _gen = 0;

  bool get _canEdit => AppScope.of(context).session.isStaffLead;

  List<F> _fields([Map? i]) => [
        F('name', 'Name', initial: i?['name'], required: true),
        F('sku', 'Code (SKU)', initial: i?['sku'], required: true),
        F('selling_price', 'Selling price', kind: K.money, initial: i?['selling_price']),
        F('purchase_price', 'Buying price', kind: K.money, initial: i?['purchase_price']),
        F('unit', 'Unit', initial: i?['unit'] ?? 'pcs'),
        F('min_stock', 'Warn me below', kind: K.number, initial: i?['min_stock'] ?? 5),
        if (i == null) F('current_stock', 'Starting stock', kind: K.number, initial: 0),
      ];

  Map<String, Object?> _clean(Map<String, Object?> v) => {
        ...v,
        'selling_price': v['selling_price'] ?? 0,
        'purchase_price': v['purchase_price'] ?? 0,
        'unit': v['unit'] ?? 'pcs',
        if (v.containsKey('current_stock')) 'current_stock': v['current_stock'] ?? 0,
      };

  Future<void> _add() async {
    final v = await showForm(context, 'Add product', _fields());
    if (v == null || !mounted) return;
    if (await guard(context, () async => AppScope.of(context).session.api.postJson('/items/', _clean(v)), done: 'Product added')) {
      setState(() => _gen++);
    }
  }

  Future<void> _edit(Map i) async {
    final v = await showForm(context, 'Edit product', _fields(i));
    if (v == null || !mounted) return;
    if (await guard(context, () async => AppScope.of(context).session.api.putJson('/items/${i['id']}', _clean(v)), done: 'Saved')) {
      setState(() => _gen++);
    }
  }

  Future<void> _adjust(Map i) async {
    final v = await showForm(
        context,
        'Adjust stock: ${i['name']}',
        [
          F('quantity', 'Change (+ adds, − removes)', kind: K.number, required: true, hint: 'e.g. 5 or -2'),
          F('notes', 'Reason', hint: 'e.g. counted the shelf'),
        ],
        ok: 'Apply');
    if (v == null || !mounted) return;
    if (await guard(
        context,
        () async => AppScope.of(context).session.api.patchJson(
            '/items/${i['id']}/stock', {'quantity': (v['quantity'] as num).toInt(), 'notes': v['notes'] ?? ''}),
        done: 'Stock updated')) {
      setState(() => _gen++);
    }
  }

  Future<void> _delete(Map i) async {
    if (!await confirm(context, 'Delete product', 'Delete "${i['name']}"? This cannot be undone.', ok: 'Delete') ||
        !mounted) {
      return;
    }
    if (await guard(context, () async => AppScope.of(context).session.api.deleteJson('/items/${i['id']}'), done: 'Deleted')) {
      setState(() => _gen++);
    }
  }

  void _open(Map i) => actionSheet(context, '${i['name']}', [
        ('Stock history', () => showMovements(context, 'History: ${i['name']}', 'item_id', '${i['id']}')),
        if (_canEdit) ('Adjust stock', () => _adjust(i)),
        if (_canEdit) ('Edit product', () => _edit(i)),
        if (_canEdit) ('Delete', () => _delete(i)),
      ]);

  @override
  Widget build(BuildContext context) => Screen(
        title: 'Stock',
        fab: _canEdit ? addFab('Add product', _add) : null,
        body: Loader<List>(
          key: ValueKey(_gen),
          load: (api) => api.allItems(),
          builder: (c, items, reload) {
            final q = _q.toLowerCase();
            final shown = items
                .where((i) => '${i['name']}'.toLowerCase().contains(q) || '${i['sku'] ?? ''}'.toLowerCase().contains(q))
                .toList();
            return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
              searchBox((v) => setState(() => _q = v), 'Search by name or code'),
              gap(12),
              if (shown.isEmpty) hint('No products found.'),
              for (final i in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RowCard(
                    title: '${i['name']}',
                    lines: ['${i['sku'] ?? ''} · ${rupees(i['selling_price'])}'],
                    onTap: () => _open(i),
                    trailing: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${numOf(i['current_stock'])} ${i['unit'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      numOf(i['current_stock']) <= 0
                          ? const StatusChip('Out', badRed)
                          : numOf(i['current_stock']) <= numOf(i['min_stock'])
                              ? const StatusChip('Low', brandGold)
                              : const StatusChip('OK', okGreen),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      );
}
