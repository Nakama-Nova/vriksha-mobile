import 'package:flutter/material.dart';

import '../kit.dart';
import '../theme.dart';
import '../widgets.dart';

const _typeChoices = <(String, Object?)>[
  ('Bill from the supplier', 'tax_invoice'),
  ('Voucher (no bill)', 'purchase_voucher'),
];
const _payChoices = <(String, Object?)>[('Not paid yet', 'pending'), ('Paid', 'paid')];

/// Purchases: goods bought from suppliers. Confirming a purchase adds the goods to stock.
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  int _gen = 0;

  Future<void> _view(Map p) async {
    final api = AppScope.of(context).session.api;
    Map full = {};
    if (!await guard(context, () async => full = await api.getJson('/purchases/${p['id']}') as Map) || !mounted) return;
    await infoSheet(context, 'Purchase ${full['invoice_number'] ?? ''}'.trim(), [
      for (final i in (full['items'] as List? ?? const []))
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('${numOf(i['quantity'])} × ${rupees(i['unit_price'])}'),
          subtitle: Text('GST ${numOf(i['gst_percent'])}%'),
          trailing: Text(rupees(i['line_total']), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      const Divider(),
      kv('Tax', rupees(full['tax_total'])),
      kv('Total', rupees(full['total_amount'])),
    ]);
  }

  Future<void> _confirm(Map p) async {
    if (!await confirm(context, 'Goods received?',
            'Confirming adds these goods to stock. This cannot be undone. Continue?') ||
        !mounted) {
      return;
    }
    final api = AppScope.of(context).session.api;
    if (await guard(context, () async => api.patchJson('/purchases/${p['id']}/confirm'), done: 'Added to stock')) {
      setState(() => _gen++);
    }
  }

  Future<void> _new() async {
    final created = await pushScoped<bool>(context, const _NewPurchase());
    if (created == true) setState(() => _gen++);
  }

  @override
  Widget build(BuildContext context) => Screen(
        title: 'Purchases',
        fab: addFab('New purchase', _new),
        body: Loader<(List, List)>(
          key: ValueKey(_gen),
          load: (api) async =>
              (await api.getJson('/purchases/', {'limit': '100'}) as List, await api.getJson('/suppliers/') as List),
          builder: (c, d, reload) {
            final (rows, suppliers) = d;
            final names = {for (final s in suppliers) '${s['id']}': '${s['name']}'};
            return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
              hint('Record timber and materials you buy. When the goods arrive, tap the purchase and confirm: that adds them to stock.'),
              gap(12),
              if (rows.isEmpty) hint('No purchases yet.'),
              for (final p in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RowCard(
                    title: '${names['${p['supplier_id']}'] ?? 'Supplier not chosen'} · ${rupees(p['total_amount'])}',
                    lines: [
                      '${'${p['purchase_date'] ?? ''}'.padRight(10).substring(0, 10).trim()} · ${p['invoice_number'] ?? 'no bill number'}',
                      p['payment_status'] == 'paid' ? 'Paid' : 'Not paid yet',
                    ],
                    trailing: p['status'] == 'pending'
                        ? const StatusChip('Waiting for goods', brandGold)
                        : const StatusChip('Received', okGreen),
                    onTap: () => actionSheet(context, 'Purchase', [
                      ('View lines', () => _view(p)),
                      if (p['status'] == 'pending') ('Goods received: confirm', () => _confirm(p)),
                    ]),
                  ),
                ),
            ]);
          },
        ),
      );
}

class _NewPurchase extends StatefulWidget {
  const _NewPurchase();
  @override
  State<_NewPurchase> createState() => _NewPurchaseState();
}

class _NewPurchaseState extends State<_NewPurchase> {
  final _lines = <Map<String, Object?>>[];
  Map<String, Object?> _head = {'purchase_type': 'tax_invoice', 'payment_status': 'pending'};
  List _suppliers = [], _materials = [], _products = [];
  bool _busy = false, _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    final api = AppScope.of(context).session.api;
    guard(context, () async {
      final r = await Future.wait([
        api.getJson('/suppliers/'),
        api.getJson('/raw-materials/', {'limit': '100'}),
        api.allItems(),
      ]);
      if (mounted) {
        setState(() {
          _suppliers = r[0] as List;
          _materials = r[1] as List;
          _products = r[2] as List;
        });
      }
    });
  }

  Future<void> _details() async {
    final v = await showForm(context, 'Purchase details', [
      F('supplier_id', 'Supplier', kind: K.choice, initial: _head['supplier_id'], choices: [
        ('(not chosen)', null),
        for (final s in _suppliers) ('${s['name']}', s['id']),
      ]),
      F('invoice_number', "Supplier's bill number", initial: _head['invoice_number']),
      F('purchase_date', 'Date', kind: K.date, initial: _head['purchase_date']),
      F('purchase_type', 'Document', kind: K.choice, choices: _typeChoices, initial: _head['purchase_type']),
      F('payment_status', 'Payment', kind: K.choice, choices: _payChoices, initial: _head['payment_status']),
      F('notes', 'Note', initial: _head['notes']),
    ], ok: 'Done');
    if (v != null) setState(() => _head = v);
  }

  Future<void> _addLine() async {
    final v = await showForm(context, 'Add line', [
      F('what', 'What did you buy', kind: K.choice, required: true, choices: [
        for (final m in _materials) ('Material: ${m['name']} (${m['unit'] ?? ''})', ('raw_material_id', m['id'])),
        for (final i in _products) ('Product: ${i['name']}', ('item_id', i['id'])),
      ]),
      const F('quantity', 'Quantity', kind: K.number, required: true),
      const F('unit_price', 'Price each', kind: K.money, required: true),
      const F('gst_percent', 'GST % on the bill', kind: K.number, initial: 0),
    ], ok: 'Add');
    if (v == null) return;
    final (key, id) = v['what'] as (String, Object?);
    setState(() => _lines.add({
          key: id,
          'quantity': v['quantity'],
          'unit_price': v['unit_price'],
          'gst_percent': v['gst_percent'] ?? 0,
        }));
  }

  num get _total => _lines.fold<num>(
      0, (a, l) => a + numOf(l['quantity']) * numOf(l['unit_price']) * (1 + numOf(l['gst_percent']) / 100));

  String _label(Map l) {
    final m = _materials.where((m) => m['id'] == l['raw_material_id']);
    final p = _products.where((p) => p['id'] == l['item_id']);
    return m.isNotEmpty ? '${m.first['name']}' : (p.isNotEmpty ? '${p.first['name']}' : 'Line');
  }

  Future<void> _save() async {
    if (_lines.isEmpty) return snack(context, 'Add at least one line.');
    final date = DateTime.tryParse('${_head['purchase_date'] ?? ''}') ?? DateTime.now();
    final api = AppScope.of(context).session.api;
    setState(() => _busy = true);
    final ok = await guard(
        context,
        () async => api.postJson('/purchases/', {
              ..._head,
              'purchase_date': DateTime(date.year, date.month, date.day, 12).toIso8601String(),
              'items': _lines,
            }),
        done: 'Purchase saved');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) => Screen(
        title: 'New purchase',
        body: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(16), children: [
              OutlinedButton(onPressed: _loaded ? _details : null, child: const Text('Supplier, bill number, payment…')),
              gap(),
              FilledButton(onPressed: _addLine, child: const Text('Add a line')),
              gap(12),
              for (var i = 0; i < _lines.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: RowCard(
                    title: _label(_lines[i]),
                    lines: ['${numOf(_lines[i]['quantity'])} × ${rupees(_lines[i]['unit_price'])} · GST ${numOf(_lines[i]['gst_percent'])}%'],
                    trailing: IconButton(
                        onPressed: () => setState(() => _lines.removeAt(i)),
                        icon: const Icon(Icons.close, color: badRed)),
                  ),
                ),
            ]),
          ),
          ActionBar(
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Total ${rupees(_total)}', style: serif(24)),
              FilledButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving…' : 'Save purchase')),
            ]),
          ),
        ]),
      );
}
