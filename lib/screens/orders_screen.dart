import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../kit.dart';
import '../theme.dart';
import 'expenses_screen.dart' show payMethods, methodWord;
import 'letters_screen.dart' show issueLetter;

// The stages, the one forward step from each and who may do what are the desktop's
// (ui/orders_screen.py and services/orders_service.py); the server enforces the rules.
const orderStatuses = <(String, String)>[
  ('New', 'draft'),
  ('Confirmed', 'confirmed'),
  ('In production', 'in_production'),
  ('Ready', 'ready'),
  ('Delivered', 'delivered'),
  ('Cancelled', 'cancelled'),
];
const _open = ['draft', 'confirmed', 'in_production', 'ready'];
// an order can be billed from the moment it is confirmed with the customer
const _billable = ['confirmed', 'in_production', 'ready', 'delivered'];
const _nextStep = <String, (String, String)>{
  'draft': ('confirmed', 'Confirm order'),
  'confirmed': ('in_production', 'Start work'),
  'in_production': ('ready', 'Mark ready'),
  'ready': ('delivered', 'Mark delivered'),
};

String statusWord(Object? s) => orderStatuses.where((x) => x.$2 == s).map((x) => x.$1).firstOrNull ?? '$s';

Color statusColour(Object? s) => switch (s) {
      'draft' => const Color(0xFFD9822B),
      'confirmed' => const Color(0xFF2F6DB5),
      'in_production' => const Color(0xFF6B4FA0),
      'ready' => okGreen,
      'cancelled' => badRed,
      _ => textMuted,
    };

/// What the order is worth: the final amount once set, else the estimate.
double amountOf(Map o) {
  final f = numOf(o['final_amount']);
  return (f > 0 ? f : numOf(o['estimated_amount'])).toDouble();
}

String itemsSummary(Map o) {
  final items = (o['items'] as List?) ?? const [];
  if (items.isEmpty) return '';
  final first = items.first as Map;
  final name = '${first['item_name'] ?? 'Catalogue piece'}';
  final qty = numOf(first['quantity']);
  return '${qty > 1 ? '$qty × ' : ''}$name${items.length > 1 ? '  +${items.length - 1} more' : ''}';
}

/// The price the customer pays for a catalogue piece: selling price plus GST.
double priceWithGst(Map item) {
  final p = numOf(item['selling_price']) * (1 + numOf(item['gst_percent']) / 100);
  return (p * 100).round() / 100;
}

/// Customer orders, from the counter and the website. Everyone who sells can look, create
/// and take money; only the owner and manager move stages, edit or cancel.
class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  String _status = 'open';
  String? _source;
  String _search = '';
  int _gen = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<List> _load(ApiClient api) async {
    final asked = (_status == 'open' || _status == 'all') ? null : _status;
    final rows = await api.getJson('/orders/', {
      'limit': '100',
      'status': ?asked,
      'source': ?_source,
      if (_search.isNotEmpty) 'search': _search,
    }) as List;
    return _status == 'open' ? [for (final o in rows) if (_open.contains(o['status'])) o] : rows;
  }

  Future<void> _new() async {
    final made = await pushScoped<bool>(context, const NewOrderPage());
    if (made == true && mounted) {
      setState(() {
        _status = 'all'; // so the new order is certainly listed
        _gen++;
      });
    }
  }

  Future<void> _details(Map o) async {
    await pushScoped<void>(context, OrderPage(order: Map<String, dynamic>.from(o)));
    if (mounted) setState(() => _gen++);
  }

  @override
  Widget build(BuildContext context) => Screen(
        title: 'Orders',
        fab: addFab('New order', _new),
        body: Loader<List>(
          key: ValueKey('$_gen$_status$_source$_search'),
          load: _load,
          builder: (c, rows, reload) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Search order, name or phone', prefixIcon: Icon(Icons.search)),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () {
                  if (mounted) setState(() => _search = v.trim());
                });
              },
            ),
            gap(10),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _status,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Show'),
                  items: [
                    const DropdownMenuItem(value: 'open', child: Text('Open orders')),
                    const DropdownMenuItem(value: 'all', child: Text('All orders')),
                    for (final (label, value) in orderStatuses) DropdownMenuItem(value: value, child: Text(label)),
                  ],
                  onChanged: (v) => setState(() => _status = v ?? 'open'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _source,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'From'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Shop and website')),
                    DropdownMenuItem(value: 'pos', child: Text('Shop only')),
                    DropdownMenuItem(value: 'web', child: Text('Website only')),
                  ],
                  onChanged: (v) => setState(() => _source = v),
                ),
              ),
            ]),
            gap(12),
            if (rows.isEmpty) hint('No orders here.'),
            for (final o in rows) _card(o as Map),
            if (rows.length >= 100) hint('The newest 100.'),
          ]),
        ),
      );

  Widget _card(Map o) {
    var customer = '${o['customer_name'] ?? 'Walk-in'}';
    if (o['customer_phone'] != null) customer += '  ·  ${o['customer_phone']}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RowCard(
        title: '${o['order_number']}${o['source'] == 'web' ? '  🌐' : ''}',
        lines: [
          customer,
          itemsSummary(o),
          '${rupees(amountOf(o))} · paid ${rupees(o['advance_paid'])} · due ${rupees(o['balance_due'])}'
              '${o['expected_delivery'] != null ? ' · promised ${o['expected_delivery']}' : ''}',
        ],
        trailing: Text(statusWord(o['status']),
            style: TextStyle(color: statusColour(o['status']), fontWeight: FontWeight.w600, fontSize: 12)),
        onTap: () => _details(o),
      ),
    );
  }
}

/// One order: its facts, pieces and payments, and what can be done with it.
class OrderPage extends StatefulWidget {
  const OrderPage({super.key, required this.order});
  final Map<String, dynamic> order;
  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  late Map<String, dynamic> _o = widget.order;

  ApiClient get _api => AppScope.of(context).session.api;
  bool get _manage => AppScope.of(context).session.isStaffLead;
  String get _id => '${_o['id']}';
  double get _due => numOf(_o['balance_due']).toDouble();

  /// Run a call that answers with the changed order and show it.
  Future<void> _change(Future<dynamic> Function() call, String done) async {
    await guard(context, () async {
      final r = await call();
      if (mounted) setState(() => _o = Map<String, dynamic>.from(r as Map));
    }, done: done);
  }

  Future<void> _advance() async {
    final step = _nextStep['${_o['status']}'];
    if (step == null) return;
    if (step.$1 == 'delivered' && _due > 0) {
      final ok = await confirm(context, 'Balance still due',
          '${rupees(_due)} is still due on ${_o['order_number']}. Mark it delivered anyway?');
      if (!ok || !mounted) return;
    }
    await _change(() => _api.patchJson('/orders/$_id/status', {'status': step.$1}), statusWord(step.$1));
  }

  Future<void> _cancel() async {
    final v = await showForm(context, 'Cancel ${_o['order_number']}',
        [F('reason', 'Why is it cancelled?', required: true)], ok: 'Cancel order');
    if (v == null || !mounted) return;
    final reason = '${v['reason']}'.trim();
    if (reason.length < 3) return snack(context, 'Please give a short reason.');
    final notes = '${_o['notes'] ?? ''}\nCancelled: $reason'.trim();
    await _change(() => _api.patchJson('/orders/$_id/status', {'status': 'cancelled', 'notes': notes}), 'Order cancelled');
  }

  Future<void> _pay() async {
    final v = await showForm(context, 'Payment for ${_o['order_number']}', [
      F('amount', 'Amount', kind: K.money, required: true, initial: _due > 0 ? _due : null, hint: 'Due ${rupees(_due)}'),
      F('method', 'How paid', kind: K.choice, choices: payMethods, initial: 'cash'),
      F('reference', 'Reference', hint: 'UPI or cheque number (optional)'),
      F('note', 'Note', hint: 'e.g. advance, second instalment'),
      F('paid_on', 'Date', kind: K.date, initial: isoDate(DateTime.now())),
    ], ok: 'Record payment');
    if (v == null || !mounted) return;
    final amount = (v['amount'] as double);
    if (_due > 0 && amount > _due + 0.001) return snack(context, 'That is more than the ${rupees(_due)} due.');
    await _change(
        () => _api.postJson('/orders/$_id/payments', {
              'amount': double.parse(amount.toStringAsFixed(2)),
              'method': v['method'],
              'reference': v['reference'],
              'note': v['note'],
              'paid_on': v['paid_on'],
            }),
        'Payment recorded');
  }

  Future<void> _edit() async {
    final o = _o;
    final v = await showForm(context, 'Edit ${o['order_number']}', [
      F('estimated_amount', 'Estimate', kind: K.money, initial: o['estimated_amount']),
      F('final_amount', 'Final amount', kind: K.money, initial: o['final_amount'], hint: 'The agreed price once finished; empty = use the estimate'),
      F('expected_delivery', 'Promised delivery date', kind: K.optDate, initial: o['expected_delivery']),
      F('notes', 'Notes', kind: K.multiline, initial: o['notes']),
    ]);
    if (v == null || !mounted) return;
    double r2(Object? x) => double.parse(numOf(x).toStringAsFixed(2));
    final changes = <String, Object?>{};
    if (r2(v['estimated_amount']) != r2(o['estimated_amount'])) changes['estimated_amount'] = r2(v['estimated_amount']);
    if (r2(v['final_amount']) != r2(o['final_amount'])) changes['final_amount'] = r2(v['final_amount']);
    if (v['expected_delivery'] != o['expected_delivery']) changes['expected_delivery'] = v['expected_delivery'];
    final notes = '${v['notes'] ?? ''}'.trim();
    if (notes != '${o['notes'] ?? ''}') changes['notes'] = notes;
    final paid = numOf(o['advance_paid']);
    if (r2(v['final_amount']) > 0 && r2(v['final_amount']) < paid) {
      return snack(context, 'The final amount is less than the ${rupees(paid)} already paid.');
    }
    if (changes.isEmpty) return;
    await _change(() => _api.patchJson('/orders/$_id', changes), 'Saved');
  }

  Future<void> _bill() async {
    final billed = _o['invoice_number'];
    if (billed != null) {
      return snack(context, 'Bill $billed. Find it in Bill History.');
    }
    final ok = await confirm(
        context,
        'Create the bill',
        'Make the bill for ${_o['order_number']}: ${rupees(amountOf(_o))}?\n\n'
            'Stock is taken off for catalogue pieces, and what the customer has already paid (${rupees(_o['advance_paid'])}) '
            'is carried onto the bill. The amount can no longer be changed afterwards.',
        ok: 'Create bill');
    if (!ok || !mounted) return;
    Future<dynamic> make(bool allowNegative) =>
        _api.postJson('/orders/$_id/invoice', {'allow_negative_stock': allowNegative});
    Map? sale;
    try {
      sale = await make(false) as Map;
    } on ApiException catch (e) {
      if (e.status == 401) return;
      if (e.status == 400 && e.message.toLowerCase().contains('stock')) {
        if (!mounted) return;
        final again = await confirm(
            context,
            'Not enough in stock',
            '${e.message}\n\nBill it anyway? Use this when the pieces have already left the workshop; '
                'the stock count will go below zero until it is corrected.',
            ok: 'Bill it');
        if (!again || !mounted) return;
        if (!await guard(context, () async => sale = await make(true) as Map)) return;
      } else {
        if (mounted) snack(context, e.message);
        return;
      }
    }
    if (!mounted || sale == null) return;
    await _change(() => _api.getJson('/orders/$_id'), 'Bill ${sale!['invoice_number']} made');
  }

  Widget _chip(String text, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(border: Border.all(color: c, width: 1.2), borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
      );

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final status = '${o['status']}';
    final isOpen = _open.contains(status);
    final billed = o['invoice_number'];
    final step = _nextStep[status];
    final address = (o['delivery_address'] as Map?) ?? const {};
    final specs = (o['custom_specs'] as Map?) ?? const {};
    final items = (o['items'] as List?) ?? const [];
    final pays = (o['payments'] as List?) ?? const [];
    final who = [
      '${o['customer_name'] ?? 'Walk-in customer'}',
      if (o['customer_phone'] != null) '${o['customer_phone']}',
    ].join('  ·  ');
    return Screen(
      title: '${o['order_number']}',
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          _chip(statusWord(status), statusColour(status)),
          _chip('${o['source'] == 'web' ? 'Website' : 'Shop'} ${o['order_type'] == 'custom' ? 'custom' : 'standard'} order', textMuted),
          if (billed != null) _chip('Bill $billed', okGreen),
        ]),
        gap(12),
        Text(who, style: const TextStyle(fontWeight: FontWeight.w600)),
        if (address.isNotEmpty)
          Text('Deliver to: ${address.values.where((v) => v != null && '$v'.isNotEmpty).join(', ')}',
              style: const TextStyle(color: textMuted)),
        gap(10),
        kv('Amount', rupees(amountOf(o))),
        kv('Paid', rupees(o['advance_paid'])),
        kv('Due', rupees(o['balance_due']), color: _due > 0 ? badRed : okGreen),
        if (o['expected_delivery'] != null) kv('Promised', '${o['expected_delivery']}'),
        if (specs.isNotEmpty) hint('Specs: ${specs.entries.map((e) => '${e.key}: ${e.value}').join(', ')}'),
        if (o['notes'] != null && '${o['notes']}'.isNotEmpty) hint('Notes: ${o['notes']}'),
        gap(12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (step != null && _manage) FilledButton(onPressed: _advance, child: Text(step.$2)),
          if (status != 'cancelled')
            OutlinedButton(
              onPressed: _due <= 0 && amountOf(o) > 0 ? null : _pay, // nothing left to collect
              child: const Text('Record payment'),
            ),
          if (status != 'cancelled')
            OutlinedButton(onPressed: () => issueLetter(context, 'order_confirmation', order: _o), child: const Text('Confirmation letter')),
          if (billed != null || _billable.contains(status))
            OutlinedButton(onPressed: _bill, child: Text(billed != null ? 'Open bill' : 'Create bill')),
          if (isOpen && _manage && billed == null) OutlinedButton(onPressed: _edit, child: const Text('Edit')),
          if (isOpen && _manage && billed == null)
            OutlinedButton(onPressed: _cancel, child: const Text('Cancel order', style: TextStyle(color: badRed))),
        ]),
        gap(16),
        heading('Pieces ordered'),
        if (items.isEmpty) hint('None listed.'),
        for (final l in items.cast<Map>())
          RowCard(
            title: '${l['item_name'] ?? 'Catalogue piece'}',
            lines: ['${l['quantity']} × ${rupees(l['unit_price'])}${l['notes'] != null ? ' · ${l['notes']}' : ''}'],
          ),
        gap(12),
        heading('Payments'),
        if (pays.isEmpty) hint('No payments yet.'),
        for (final p in pays.cast<Map>())
          RowCard(
            title: rupees(p['amount']),
            lines: [
              '${p['paid_on']} · ${methodWord(p['method'])}',
              [p['reference'], p['note']].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
            ],
          ),
      ]),
    );
  }
}

class _PieceLine {
  String? itemId; // null: a custom piece, described in [text]
  final text = TextEditingController();
  final price = TextEditingController();
  int qty = 1;
}

/// A new order: who it is for, what they want (catalogue pieces or a custom piece), the
/// price and the advance. Same checks as the desktop's New order window.
class NewOrderPage extends StatefulWidget {
  const NewOrderPage({super.key});
  @override
  State<NewOrderPage> createState() => _NewOrderPageState();
}

class _NewOrderPageState extends State<NewOrderPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _estimate = TextEditingController();
  final _advance = TextEditingController();
  final _notes = TextEditingController();
  String _kind = 'custom';
  String _method = 'cash';
  DateTime? _date;
  bool _estimateByHand = false;
  bool _busy = false;
  String? _problem;
  List<Map<String, dynamic>>? _catalogue;
  final _lines = [_PieceLine()];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_catalogue == null) _loadCatalogue();
  }

  Future<void> _loadCatalogue() async {
    _catalogue = const [];
    try {
      final items = await AppScope.of(context).session.api.allItems();
      if (mounted) setState(() => _catalogue = items);
    } on ApiException {
      // custom pieces still work without the catalogue
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _phone, _estimate, _advance, _notes]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.text.dispose();
      l.price.dispose();
    }
    super.dispose();
  }

  void _recount() {
    if (_estimateByHand) return;
    final total = _lines.fold<double>(0, (a, l) => a + l.qty * (double.tryParse(l.price.text.trim()) ?? 0));
    _estimate.text = total == 0 ? '' : total.toStringAsFixed(2);
  }

  void _picked(_PieceLine l, String? id) {
    setState(() {
      l.itemId = id;
      if (id != null) {
        l.text.clear();
        final item = _catalogue!.firstWhere((i) => i['id'] == id);
        l.price.text = priceWithGst(item).toStringAsFixed(2); // the customer price: GST included
      }
      _recount();
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context, initialDate: _date ?? now, firstDate: now, lastDate: DateTime(now.year + 5));
    if (d != null) setState(() => _date = d);
  }

  Future<void> _create() async {
    final lines = [
      for (final l in _lines)
        {
          'quantity': l.qty,
          'unit_price': double.tryParse(l.price.text.trim()) ?? 0,
          if (l.itemId == null) 'item_name': l.text.text.trim() else 'item_id': l.itemId,
        }
    ];
    final estimate = double.tryParse(_estimate.text.trim()) ?? 0;
    final advance = double.tryParse(_advance.text.trim()) ?? 0;
    final name = _name.text.trim(), phone = _phone.text.trim();
    String? problem;
    if (lines.any((l) => l['item_id'] == null && (l['item_name'] as String).isEmpty)) {
      problem = 'Describe each custom piece, or pick one from the catalogue.';
    } else if (advance > 0 && estimate > 0 && advance > estimate) {
      problem = 'The advance is more than the estimate.';
    } else if (phone.isNotEmpty && name.isEmpty) {
      problem = "Enter the customer's name too.";
    }
    if (problem != null) return setState(() => _problem = problem);
    setState(() {
      _problem = null;
      _busy = true;
    });
    final api = AppScope.of(context).session.api;
    final ok = await guard(context, () async {
      final order = <String, Object?>{
        'order_type': _kind,
        'items': lines,
        'estimated_amount': double.parse(estimate.toStringAsFixed(2)),
        'advance_paid': 0, // the advance is recorded as a payment, so it has a date and a method
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        if (_date != null) 'expected_delivery': isoDate(_date!),
      };
      if (phone.isNotEmpty) {
        Object? cust;
        try {
          cust = await api.getJson('/customers/search', {'phone': phone});
        } on ApiException catch (e) {
          if (e.status != 404) rethrow;
        }
        cust ??= await api.postJson('/customers', {'name': name, 'phone': phone, 'address': ''});
        order['customer_id'] = (cust as Map)['id'];
      }
      final created = await api.postJson('/orders/', order) as Map;
      if (advance > 0) {
        await api.postJson('/orders/${created['id']}/payments',
            {'amount': double.parse(advance.toStringAsFixed(2)), 'method': _method, 'note': 'Advance'});
      }
    }, done: 'Order created');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) Navigator.of(context).pop(true);
  }

  Widget _lineCard(int i) {
    final l = _lines[i];
    final cat = _catalogue ?? const [];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          DropdownButtonFormField<String?>(
            initialValue: l.itemId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Piece'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Custom piece…')),
              for (final it in cat) DropdownMenuItem(value: '${it['id']}', child: Text('${it['name']}  (${it['sku'] ?? ''})', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => _picked(l, v),
          ),
          if (l.itemId == null) ...[
            gap(8),
            TextField(
              controller: l.text,
              decoration: const InputDecoration(labelText: 'Description', hintText: 'e.g. Door with Ganesha, 6 ft'),
            ),
          ],
          gap(8),
          Row(children: [
            IconButton(
              onPressed: l.qty > 1 ? () => setState(() { l.qty--; _recount(); }) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            Text('${l.qty}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            IconButton(
              onPressed: l.qty < 999 ? () => setState(() { l.qty++; _recount(); }) : null,
              icon: const Icon(Icons.add_circle_outline),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: l.price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Price each (with GST)', prefixText: '₹'),
                onChanged: (_) => setState(_recount),
              ),
            ),
            if (_lines.length > 1)
              IconButton(
                onPressed: () => setState(() { _lines.removeAt(i); _recount(); }),
                icon: const Icon(Icons.delete_outline, color: badRed),
              ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Screen(
        title: 'New order',
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Customer name')),
          gap(10),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone', hintText: 'finds them if they have ordered before'),
          ),
          gap(10),
          DropdownButtonFormField<String>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Order type'),
            items: const [
              DropdownMenuItem(value: 'custom', child: Text('Custom piece (made to order)')),
              DropdownMenuItem(value: 'standard', child: Text('Standard catalogue pieces')),
            ],
            onChanged: (v) => setState(() => _kind = v ?? 'custom'),
          ),
          gap(14),
          heading('What they want'),
          for (var i = 0; i < _lines.length; i++) _lineCard(i),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _lines.add(_PieceLine())),
              icon: const Icon(Icons.add),
              label: const Text('Add a piece'),
            ),
          ),
          gap(10),
          TextField(
            controller: _estimate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Estimate', prefixText: '₹'),
            onChanged: (_) => _estimateByHand = true, // typed by hand: stop overwriting it
          ),
          gap(10),
          TextField(
            controller: _advance,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Advance received', prefixText: '₹'),
          ),
          gap(10),
          DropdownButtonFormField<String>(
            initialValue: _method,
            decoration: const InputDecoration(labelText: 'Advance paid by'),
            items: [for (final (label, value) in payMethods) DropdownMenuItem(value: value as String, child: Text(label))],
            onChanged: (v) => setState(() => _method = v ?? 'cash'),
          ),
          gap(10),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event),
            label: Text(_date == null ? 'Promised delivery date (optional)' : 'Promised ${niceDate(_date!)}'),
          ),
          if (_date != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: () => setState(() => _date = null), child: const Text('Clear the date')),
            ),
          gap(10),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes', hintText: 'wood, size, motif, anything the carver should know'),
          ),
          if (_problem != null) ...[gap(12), Text(_problem!, style: const TextStyle(color: badRed))],
          gap(16),
          FilledButton(
            onPressed: _busy ? null : _create,
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Create order'),
          ),
        ]),
      );
}
