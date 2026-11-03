import 'dart:async';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../api.dart';
import '../kit.dart';
import '../session.dart';
import '../theme.dart';
import 'expenses_screen.dart' show payMethods;
import 'orders_screen.dart' show amountOf;

// Kinds, who may issue them and the letterhead fields are the desktop's
// (services/letters_service.py); the server numbers each letter once and enforces the roles.
const letterKinds = <(String, String)>[
  ('Quotation', 'quotation'),
  ('Order confirmation and advance receipt', 'order_confirmation'),
  ('Purchase receipt (bought piece)', 'purchase_receipt'),
  ('Certificate of completion', 'completion_certificate'),
];
const _kindShort = {
  'quotation': 'Quotation',
  'order_confirmation': 'Order confirmation',
  'purchase_receipt': 'Purchase receipt',
  'completion_certificate': 'Certificate',
};
const _letterhead = <(String, String)>[
  ('name', 'Name'),
  ('tagline', 'Tagline'),
  ('address', 'Address'),
  ('phone', 'Phone'),
  ('email', 'Email'),
  ('gstin', 'GSTIN (leave empty until registered)'),
  ('signatory_name', 'Signed by'),
  ('signatory_title', 'Title'),
  ('footer_note', 'Footer line'),
];

bool mayIssue(Session s, String kind) => switch (kind) {
      'quotation' || 'order_confirmation' => s.isStaffLead || s.role == 'sales',
      'purchase_receipt' => s.isStaffLead,
      _ => s.isOwner, // the certificate of completion
    };

String _slug(String kind) => kind.replaceAll('_', '-');

/// Fetch a letter's PDF and hand it to the phone: share it, save it, or print it.
Future<void> openLetterPdf(BuildContext context, Map letter) async {
  final api = AppScope.of(context).session.api;
  try {
    final bytes = await api.getBytes('/letters/${letter['id']}/pdf');
    await Printing.sharePdf(bytes: bytes, filename: '${letter['number']}.pdf');
  } on ApiException catch (e) {
    if (e.status != 401 && context.mounted) snack(context, e.message);
  } catch (_) {
    if (context.mounted) snack(context, 'The letter could not be opened. Try again.');
  }
}

/// Ask for the details and issue a letter, then open its PDF. [order] / [restoration] fix the
/// letter to that one order or project (the buttons on those screens). Null if cancelled.
Future<Map?> issueLetter(BuildContext context, String kind, {Map? order, Map? restoration}) async {
  final api = AppScope.of(context).session.api;
  Map<String, Object?>? body;
  try {
    switch (kind) {
      case 'quotation':
        body = await pushScoped<Map<String, Object?>>(context, const _QuotationPage());
      case 'order_confirmation':
        List orders = order != null ? [order] : [];
        if (order == null) {
          orders = [for (final o in await api.getJson('/orders/', {'limit': '100'}) as List) if (o['status'] != 'cancelled') o];
          if (orders.isEmpty && context.mounted) {
            snack(context, 'There are no orders to confirm yet.');
            return null;
          }
        }
        if (!context.mounted) return null;
        final vo = await showForm(context, 'Order confirmation', [
          F('order_id', 'Order', kind: K.choice, required: true, initial: order?['id'], choices: [
            for (final o in orders) ('${o['order_number']} · ${o['customer_name'] ?? 'Walk-in'} · ${rupees(amountOf(o))}', '${o['id']}'),
          ]),
          F('notes', 'Notes', kind: K.multiline, hint: 'optional'),
        ], ok: 'Issue letter');
        if (vo != null) body = {'order_id': vo['order_id'], 'notes': vo['notes']};
      case 'purchase_receipt':
        final suppliers = await api.getJson('/suppliers/') as List;
        if (!context.mounted) return null;
        final vp = await showForm(context, 'Purchase receipt', [
          F('supplier_id', 'Seller (a supplier)', kind: K.choice, choices: [
            ('Not in the list: type the name below', null),
            for (final s in suppliers) ('${s['name']}', '${s['id']}'),
          ]),
          F('seller_name', 'Seller name', hint: 'if not a supplier'),
          F('seller_phone', 'Seller phone', hint: 'optional'),
          F('description', 'What was bought', required: true),
          F('quantity', 'How many', kind: K.number, initial: 1),
          F('amount', 'Amount paid', kind: K.money, required: true),
          F('paid_on', 'Paid on', kind: K.date),
          F('method', 'How paid', kind: K.choice, choices: payMethods, initial: 'cash'),
          F('reference', 'Reference', hint: 'UPI or cheque number (optional)'),
          F('notes', 'Notes', hint: 'optional'),
        ], ok: 'Issue letter');
        if (vp != null) {
          if (vp['supplier_id'] == null && vp['seller_name'] == null) {
            if (context.mounted) snack(context, 'Choose the seller, or type the seller name.');
            return null;
          }
          body = {
            'supplier_id': vp['supplier_id'],
            'seller_name': vp['seller_name'],
            'seller_phone': vp['seller_phone'],
            'description': vp['description'],
            'quantity': (vp['quantity'] is num ? (vp['quantity'] as num).round() : 1).clamp(1, 10000),
            'amount': numOf(vp['amount']).toDouble().toStringAsFixed(2),
            'paid_on': vp['paid_on'],
            'method': vp['method'],
            'reference': vp['reference'],
            'notes': vp['notes'],
          };
        }
      default: // completion_certificate
        List projects = restoration != null ? [restoration] : [];
        if (restoration == null) {
          projects = [
            for (final p in await api.getJson('/restorations', {'status': 'restored'}) as List) if ((p['kind'] ?? 'temple') == 'temple') p
          ];
          if (projects.isEmpty && context.mounted) {
            snack(context, 'No temple restoration is marked Restored yet.');
            return null;
          }
        }
        if (!context.mounted) return null;
        final vc = await showForm(context, 'Certificate of completion', [
          F('restoration_id', 'Project', kind: K.choice, required: true, initial: restoration?['id'], choices: [
            for (final p in projects) ('${p['title']}', '${p['id']}'),
          ]),
          F('work_done', 'Work done', kind: K.multiline, required: true, hint: 'what was restored'),
          F('completed_on', 'Completed on', kind: K.date),
          F('notes', 'Notes', hint: 'optional'),
        ], ok: 'Issue letter');
        if (vc != null) body = vc;
    }
  } on ApiException catch (e) {
    if (e.status != 401 && context.mounted) snack(context, e.message);
    return null;
  }
  if (body == null || !context.mounted) return null;
  final payload = body;
  Map? letter;
  final ok = await guard(context, () async => letter = await api.postJson('/letters/${_slug(kind)}', payload) as Map);
  if (!ok || letter == null || !context.mounted) return null;
  snack(context, '${letter!['number']} issued');
  await openLetterPdf(context, letter!);
  return letter;
}

/// Official letters on the shop letterhead: quotation, order confirmation with advance
/// receipt, purchase receipt, completion certificate. Each gets its number once and opens
/// as a PDF; a wrong one is voided, never deleted. The owner edits the letterhead.
class LettersScreen extends StatefulWidget {
  const LettersScreen({super.key});
  @override
  State<LettersScreen> createState() => _LettersScreenState();
}

class _LettersScreenState extends State<LettersScreen> {
  String? _kind;
  String? _status;
  String _search = '';
  int _gen = 0;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _new() async {
    final s = AppScope.of(context).session;
    final kinds = [for (final (label, value) in letterKinds) if (mayIssue(s, value)) (label, value)];
    await actionSheet(context, 'Issue a letter', [
      for (final (label, value) in kinds)
        (label, () async {
          if (await issueLetter(context, value) != null && mounted) setState(() => _gen++);
        }),
    ]);
  }

  Future<void> _void(Map l) async {
    final v = await showForm(context, 'Void ${l['number']}', [F('reason', 'Why is it wrong?', required: true, hint: 'It stays on record, marked void')],
        ok: 'Void letter');
    if (v == null || !mounted) return;
    final reason = '${v['reason']}'.trim();
    if (reason.length < 3) return snack(context, 'Please give a short reason.');
    final api = AppScope.of(context).session.api;
    if (await guard(context, () async => api.postJson('/letters/${l['id']}/void', {'reason': reason}), done: 'Letter voided')) {
      setState(() => _gen++);
    }
  }

  Future<void> _editLetterhead() async {
    final api = AppScope.of(context).session.api;
    Map profile;
    try {
      profile = await api.getJson('/letters/profile') as Map;
    } on ApiException catch (e) {
      if (e.status != 401 && mounted) snack(context, e.message);
      return;
    }
    if (!mounted) return;
    final v = await showForm(context, 'Letterhead', [
      for (final (key, label) in _letterhead) F(key, label, initial: profile[key], required: key == 'name'),
    ]);
    if (v == null || !mounted) return;
    if (await guard(context, () async => api.putJson('/letters/profile', v), done: 'Letterhead saved')) setState(() => _gen++);
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    final canIssue = letterKinds.any((k) => mayIssue(session, k.$2));
    return Screen(
      title: 'Letters',
      fab: canIssue ? addFab('New letter', _new) : null,
      body: Loader<List>(
        key: ValueKey('$_gen$_kind$_status$_search'),
        load: (api) async => await api.getJson('/letters', {
          'limit': '200',
          'kind': ?_kind,
          'status': ?_status,
          if (_search.isNotEmpty) 'search': _search,
        }) as List,
        builder: (c, rows, reload) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
          hint('Each letter gets its number once. A wrong one is voided, never deleted.'),
          gap(10),
          TextField(
            decoration: const InputDecoration(labelText: 'Search number, name or subject', prefixIcon: Icon(Icons.search)),
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
              child: DropdownButtonFormField<String?>(
                initialValue: _kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kind'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All kinds')),
                  for (final e in _kindShort.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _kind = v),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String?>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('All')),
                  DropdownMenuItem(value: 'issued', child: Text('Issued')),
                  DropdownMenuItem(value: 'void', child: Text('Void')),
                ],
                onChanged: (v) => setState(() => _status = v),
              ),
            ),
          ]),
          if (session.isOwner)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(onPressed: _editLetterhead, child: const Text('Edit the letterhead')),
            ),
          gap(8),
          if (rows.isEmpty) hint('No letters here.'),
          for (final l in rows.cast<Map>())
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RowCard(
                title: '${l['number']}',
                lines: [
                  '${_kindShort['${l['kind']}'] ?? l['kind_label']} · ${showDate(l['issued_on'])}',
                  '${l['party_name']}',
                  '${l['subject']}',
                ],
                trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  if (l['amount'] != null) Text(rupees(l['amount']), style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(l['status'] == 'void' ? 'Void' : 'Issued',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: l['status'] == 'void' ? badRed : okGreen)),
                ]),
                onTap: () => actionSheet(context, '${l['number']}', [
                  ('Open the PDF', () => openLetterPdf(context, l)),
                  if (session.isOwner && l['status'] != 'void') ('Void this letter', () => _void(l)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}

class _QLine {
  final text = TextEditingController();
  final price = TextEditingController();
  int qty = 1;
}

/// A quotation: who it is for, what is quoted, how long it stays valid. Pops with the body
/// for POST /letters/quotation.
class _QuotationPage extends StatefulWidget {
  const _QuotationPage();
  @override
  State<_QuotationPage> createState() => _QuotationPageState();
}

class _QuotationPageState extends State<_QuotationPage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _subject = TextEditingController();
  final _days = TextEditingController(text: '15');
  final _notes = TextEditingController();
  final _lines = [_QLine()];
  String? _problem;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _subject, _days, _notes]) {
      c.dispose();
    }
    for (final l in _lines) {
      l.text.dispose();
      l.price.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final lines = [
      for (final l in _lines)
        if (l.text.text.trim().isNotEmpty)
          {'description': l.text.text.trim(), 'quantity': l.qty, 'unit_price': (double.tryParse(l.price.text.trim()) ?? 0).toStringAsFixed(2)},
    ];
    final days = int.tryParse(_days.text.trim()) ?? 15;
    if (_name.text.trim().isEmpty) return setState(() => _problem = 'Enter who the quotation is for.');
    if (lines.isEmpty) return setState(() => _problem = 'Describe at least one piece.');
    if (days < 1 || days > 365) return setState(() => _problem = 'Valid for 1 to 365 days.');
    String? nz(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    Navigator.of(context).pop(<String, Object?>{
      'party_name': _name.text.trim(),
      'party_phone': nz(_phone),
      'party_address': nz(_address),
      'subject': nz(_subject),
      'lines': lines,
      'valid_days': days,
      'notes': nz(_notes),
    });
  }

  @override
  Widget build(BuildContext context) => Screen(
        title: 'Quotation',
        body: ListView(padding: const EdgeInsets.all(16), children: [
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'For (name)')),
          gap(10),
          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone')),
          gap(10),
          TextField(controller: _address, decoration: const InputDecoration(labelText: 'Address')),
          gap(10),
          TextField(controller: _subject, decoration: const InputDecoration(labelText: 'Subject', hintText: 'e.g. Teak door with Ganesha')),
          gap(14),
          heading('What is quoted'),
          for (var i = 0; i < _lines.length; i++)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  TextField(controller: _lines[i].text, decoration: const InputDecoration(labelText: 'Description')),
                  gap(8),
                  Row(children: [
                    IconButton(
                      onPressed: _lines[i].qty > 1 ? () => setState(() => _lines[i].qty--) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('${_lines[i].qty}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    IconButton(onPressed: () => setState(() => _lines[i].qty++), icon: const Icon(Icons.add_circle_outline)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _lines[i].price,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Price each', prefixText: '₹'),
                      ),
                    ),
                    if (_lines.length > 1)
                      IconButton(onPressed: () => setState(() => _lines.removeAt(i)), icon: const Icon(Icons.delete_outline, color: badRed)),
                  ]),
                ]),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _lines.add(_QLine())),
              icon: const Icon(Icons.add),
              label: const Text('Add a line'),
            ),
          ),
          gap(10),
          TextField(
            controller: _days,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Valid for (days)'),
          ),
          gap(10),
          TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
          if (_problem != null) ...[gap(12), Text(_problem!, style: const TextStyle(color: badRed))],
          gap(16),
          FilledButton(onPressed: _submit, child: const Text('Issue letter')),
        ]),
      );
}
