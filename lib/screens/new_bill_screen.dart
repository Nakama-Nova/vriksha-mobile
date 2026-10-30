import 'package:flutter/material.dart';

import '../api.dart';
import '../kit.dart';
import '../theme.dart';
import '../widgets.dart';

class _Line {
  _Line(this.id, this.name, this.price, this.gst);
  final String id;
  final String name;
  final num price;
  final num gst;
  int qty = 1;
}

/// New Bill: find or name the buyer, add products, create the bill.
class NewBillScreen extends StatefulWidget {
  const NewBillScreen({super.key});
  @override
  State<NewBillScreen> createState() => _NewBillScreenState();
}

class _NewBillScreenState extends State<NewBillScreen> {
  final _phone = TextEditingController();
  final _name = TextEditingController();
  final _cart = <_Line>[];
  List<Map<String, dynamic>> _items = [];
  TextEditingController? _search;
  String? _loadError;
  bool _busy = false;
  // One id per distinct bill: if the answer is lost and the user taps again, the
  // server returns the bill it already recorded instead of billing twice.
  String? _clientId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_items.isEmpty && _loadError == null) _loadItems();
  }

  @override
  void dispose() {
    _phone.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final scope = AppScope.of(context);
    try {
      final items = await scope.session.api.allItems();
      if (mounted) setState(() => _items = items);
    } on ApiException catch (e) {
      if (e.status == 401) return scope.onSignOut();
      if (mounted) setState(() => _loadError = e.message);
    }
  }

  void _add(Map<String, dynamic> item) {
    final id = '${item['id']}';
    final have = _cart.where((l) => l.id == id);
    setState(() {
      _clientId = null;
      if (have.isNotEmpty) {
        have.first.qty++;
      } else {
        _cart.add(_Line(id, '${item['name']}', numOf(item['selling_price']), numOf(item['gst_percent'])));
      }
    });
    _search?.clear();
  }

  num get _subtotal => _cart.fold<num>(0, (a, l) => a + l.price * l.qty);
  num get _tax => _cart.fold<num>(0, (a, l) => a + l.price * l.qty * l.gst / 100);

  Future<void> _lookup() async {
    final phone = _phone.text.trim();
    if (phone.isEmpty) return snack(context, 'Enter a phone number first.');
    final api = AppScope.of(context).session.api;
    try {
      final c = await api.getJson('/customers/search', {'phone': phone});
      if (!mounted) return;
      if (c is Map) {
        _name.text = '${c['name'] ?? ''}';
        snack(context, 'Buyer found: ${c['name']}');
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      snack(context, e.status == 404 ? "No buyer found. Enter the name and we'll save a new record." : e.message);
    }
  }

  Future<void> _create() async {
    final phone = _phone.text.trim(), name = _name.text.trim();
    if (phone.isEmpty) return snack(context, "Please enter the buyer's phone number.");
    if (name.isEmpty) return snack(context, "Please enter the buyer's name.");
    if (_cart.isEmpty) return snack(context, 'Please add at least one item.');
    final api = AppScope.of(context).session.api;
    setState(() => _busy = true);
    Map? sale;
    final ok = await guard(context, () async {
      Object? cust;
      try {
        cust = await api.getJson('/customers/search', {'phone': phone});
      } on ApiException catch (e) {
        if (e.status != 404) rethrow;
      }
      cust ??= await api.postJson('/customers', {'name': name, 'phone': phone, 'address': ''});
      _clientId ??= newClientId();
      sale = await api.postJson('/sales', {
        'items': [for (final l in _cart) {'item_id': l.id, 'quantity': l.qty}],
        'customer_id': (cust as Map)['id'],
        'client_id': _clientId,
      }) as Map;
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok || sale == null) return;
    await showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Bill created'),
        content: Text('Bill ${sale!['invoice_number']}\nTotal ${rupees(sale!['total_amount'])}'),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: const Text('OK'))],
      ),
    );
    setState(() {
      _cart.clear();
      _clientId = null;
      _phone.clear();
      _name.clear();
    });
    _loadItems(); // stock moved
  }

  @override
  Widget build(BuildContext context) {
    final tax = _tax;
    return Screen(
      title: 'New bill',
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Buyer phone'),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(onPressed: _lookup, child: const Text('Search')),
            ]),
            gap(),
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Buyer name')),
            gap(14),
            if (_loadError != null)
              Text(_loadError!, style: const TextStyle(color: badRed))
            else
              Autocomplete<Map<String, dynamic>>(
                displayStringForOption: (o) => '${o['name']}',
                optionsBuilder: (v) {
                  final q = v.text.trim().toLowerCase();
                  if (q.isEmpty) return const [];
                  return _items.where((i) =>
                      '${i['name']}'.toLowerCase().contains(q) || '${i['sku']}'.toLowerCase().contains(q));
                },
                onSelected: _add,
                fieldViewBuilder: (c, ctl, focus, submit) {
                  _search = ctl;
                  return TextField(
                    controller: ctl,
                    focusNode: focus,
                    decoration: const InputDecoration(
                        labelText: 'Search item', prefixIcon: Icon(Icons.search)),
                  );
                },
              ),
            gap(14),
            if (_cart.isEmpty) hint('No items yet. Search above and tap a product to add it.'),
            for (final l in _cart)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowCard(
                  title: l.name,
                  lines: ['${rupees(l.price)} each · ${rupees(l.price * l.qty * (1 + l.gst / 100))}'],
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        onPressed: l.qty > 1 ? () => setState(() { l.qty--; _clientId = null; }) : null,
                        icon: const Icon(Icons.remove_circle_outline)),
                    Text('${l.qty}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    IconButton(
                        onPressed: () => setState(() { l.qty++; _clientId = null; }),
                        icon: const Icon(Icons.add_circle_outline)),
                    IconButton(
                        onPressed: () => setState(() { _cart.remove(l); _clientId = null; }),
                        icon: const Icon(Icons.close, color: badRed)),
                  ]),
                ),
              ),
          ]),
        ),
        ActionBar(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (tax > 0) ...[
              kv('Subtotal', rupees(_subtotal)),
              kv('CGST', rupees(tax / 2)),
              kv('SGST', rupees(tax / 2)),
            ],
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Total ${rupees(_subtotal + tax)}', style: serif(24, color: okGreen)),
              Row(children: [
                TextButton(
                    onPressed: _cart.isEmpty ? null : () => setState(() { _cart.clear(); _clientId = null; }),
                    child: const Text('Clear')),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: _busy ? null : _create,
                    child: Text(_busy ? 'Creating…' : 'Create bill')),
              ]),
            ]),
          ]),
        ),
      ]),
    );
  }
}
