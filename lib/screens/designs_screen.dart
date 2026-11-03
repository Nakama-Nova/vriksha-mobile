import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../kit.dart';
import '../theme.dart';

const designStatuses = <(String, Object?)>[('Draft', 'draft'), ('Ready', 'ready'), ('Retired', 'retired')];
const _typeWords = {'furniture': 'Furniture', 'sculpture': 'Sculpture'};
const _projectKinds = {'temple': 'Temple restoration', 'finishing': 'Bought piece: finishing and painting'};
const fileKindWords = {
  'glb': '3D model (.glb)',
  'stl': '3D print/CNC mesh (.stl)',
  'obj': '3D model (.obj)',
  'ply': '3D scan (.ply)',
  'nc': 'CNC G-code (.nc)',
  'render': 'Preview picture',
};

String designStatusWord(Object? s) => designStatuses.where((x) => x.$2 == s).map((x) => x.$1).firstOrNull ?? '$s';

/// "512 KB", "3.4 MB", "1.2 GB".
String fileSize(Object? bytes) {
  final b = numOf(bytes).toDouble();
  if (b >= 1024 * 1024 * 1024) return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
  return '${(b / 1024).toStringAsFixed(0)} KB';
}

/// Designs (DES-0001): reusable patterns, taken from a restoration or made fresh. A design
/// builds sculpture products and shows the 3D files of the restoration it came from. Only
/// the owner and artisans can open this screen.
class DesignsScreen extends StatefulWidget {
  const DesignsScreen({super.key});
  @override
  State<DesignsScreen> createState() => _DesignsScreenState();
}

class _DesignsScreenState extends State<DesignsScreen> {
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
    final made = await saveDesign(context);
    if (made != null && mounted) {
      snack(context, '${made['name']} was saved as ${made['sku']}.');
      setState(() => _gen++);
    }
  }

  @override
  Widget build(BuildContext context) => Screen(
        title: 'Designs',
        fab: addFab('New design', _new),
        body: Loader<List>(
          key: ValueKey('$_gen$_status$_search'),
          load: (api) async =>
              await api.getJson('/designs', {'status': ?_status, if (_search.isNotEmpty) 'search': _search}) as List,
          builder: (c, rows, reload) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
            hint('A design is a pattern to carve, with its own code. Take it from a restoration (it then shows that piece\'s 3D files) '
                'or make it fresh, then build sculpture products from it.'),
            gap(10),
            TextField(
              decoration: const InputDecoration(labelText: 'Search code or name', prefixIcon: Icon(Icons.search)),
              onChanged: (v) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 400), () {
                  if (mounted) setState(() => _search = v.trim());
                });
              },
            ),
            gap(10),
            DropdownButtonFormField<String?>(
              initialValue: _status,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Show'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All designs')),
                for (final (label, value) in designStatuses) DropdownMenuItem(value: value as String, child: Text(label)),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
            gap(12),
            if (rows.isEmpty) hint('No designs here.'),
            for (final d in rows.cast<Map>())
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowCard(
                  title: '${d['sku']} · ${d['name']}',
                  lines: [
                    [if (d['restoration_title'] != null) 'From ${d['restoration_title']}', '${d['product_count']} products']
                        .join(' · '),
                  ],
                  trailing: Text(designStatusWord(d['status']), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textMuted)),
                  onTap: () async {
                    await pushScoped<void>(context, DesignPage(designId: '${d['id']}'));
                    if (mounted) setState(() => _gen++);
                  },
                ),
              ),
          ]),
        ),
      );
}

/// A new design, or the name and notes of an existing one. Returns the saved design.
Future<Map?> saveDesign(BuildContext context, [Map? design]) async {
  final api = AppScope.of(context).session.api;
  List projects = [];
  try {
    projects = await api.getJson('/restorations') as List;
  } on ApiException {
    // taking a design from a restoration is optional
  }
  if (!context.mounted) return null;
  final v = await showForm(context, design == null ? 'New design' : 'Edit design', [
    F('name', 'Name', required: true, initial: design?['name'], hint: 'e.g. Hoysala Madhanika'),
    F('description', 'Notes', kind: K.multiline, initial: design?['description'], hint: 'What it is, size, wood, notes for the carver'),
    F('restoration_id', 'Taken from', kind: K.choice, initial: design?['restoration_id'], choices: [
      ('Not taken from a restoration', null),
      for (final r in projects) ('${r['title']}  (${_projectKinds['${r['kind'] ?? 'temple'}'] ?? ''})', '${r['id']}'),
    ]),
  ]);
  if (v == null || !context.mounted) return null;
  Map? saved;
  final ok = await guard(context, () async {
    saved = (design == null ? await api.postJson('/designs', v) : await api.patchJson('/designs/${design['id']}', v)) as Map;
  });
  return ok ? saved : null;
}

/// One design: its notes, status, the products built from it, and the 3D files of the
/// restoration it was taken from.
class DesignPage extends StatefulWidget {
  const DesignPage({super.key, required this.designId});
  final String designId;
  @override
  State<DesignPage> createState() => _DesignPageState();
}

class _DesignPageState extends State<DesignPage> {
  int _gen = 0;
  ApiClient get _api => AppScope.of(context).session.api;
  void _reload() => setState(() => _gen++);

  Future<void> _edit(Map d) async {
    if (await saveDesign(context, d) != null) _reload();
  }

  Future<void> _setStatus(Map d, Object? status) async {
    if (status == d['status']) return;
    final api = _api;
    if (await guard(context, () async => api.patchJson('/designs/${d['id']}', {'status': status}), done: 'Status changed')) _reload();
  }

  Future<void> _link(Map d) async {
    final linked = {for (final p in (d['products'] as List? ?? const [])) '${p['id']}'};
    final api = _api;
    List<Map<String, dynamic>> items;
    try {
      items = await api.allItems();
    } on ApiException catch (e) {
      if (e.status != 401 && mounted) snack(context, e.message);
      return;
    }
    items = [for (final i in items) if (!linked.contains('${i['id']}')) i]
      ..sort((a, b) {
        final sa = a['item_type'] == 'sculpture' ? 0 : 1, sb = b['item_type'] == 'sculpture' ? 0 : 1; // sculptures first
        return sa != sb ? sa - sb : '${a['sku'] ?? ''}'.compareTo('${b['sku'] ?? ''}');
      });
    if (!mounted) return;
    if (items.isEmpty) {
      return snack(context, 'Every product is already linked, or Stock is empty. Use Create a product to make a new one.');
    }
    final id = await pushScoped<String>(context, _PickProductPage(items: items));
    if (id == null || !mounted) return;
    if (await guard(context, () async => api.postJson('/designs/${d['id']}/products', {'item_id': id}), done: 'Linked')) _reload();
  }

  Future<void> _unlink(Map d, Map p) async {
    final ok = await confirm(context, 'Unlink', 'Take ${p['name']} out of ${d['sku']}? The product stays in Stock.', ok: 'Unlink');
    if (!ok || !mounted) return;
    final api = _api;
    if (await guard(context, () async => api.deleteJson('/designs/${d['id']}/products/${p['id']}'), done: 'Unlinked')) _reload();
  }

  Future<void> _make(Map d) async {
    final v = await showForm(
        context,
        'New product from ${d['sku']}',
        [
          F('name', 'Name', required: true, initial: d['name']),
          F('selling_price', 'Selling price', kind: K.money),
          F('wood_type', 'Wood', hint: 'e.g. Teak (optional)'),
        ],
        ok: 'Create product');
    if (v == null || !mounted) return;
    final api = _api;
    Map? made;
    final ok = await guard(
        context,
        () async => made = await api.postJson('/designs/${d['id']}/create-product', {
              'name': v['name'],
              'selling_price': numOf(v['selling_price']).toDouble(),
              'wood_type': v['wood_type'],
            }) as Map);
    if (ok && mounted) {
      snack(context, '${made!['name']} is in Stock as ${made!['sku']} and linked to ${d['sku']}.');
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) => Screen(
        title: 'Design',
        body: Loader<Map>(
          key: ValueKey(_gen),
          load: (api) async => await api.getJson('/designs/${widget.designId}') as Map,
          builder: (c, d, reload) {
            final source = d['restoration'] as Map?;
            final products = (d['products'] as List?) ?? const [];
            final files = (d['files'] as List?) ?? const [];
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text('${d['sku']} · ${d['name']}', style: serif(24)),
              gap(6),
              Text('${(d['description'] ?? '').toString().isEmpty ? 'No notes yet.' : d['description']}'
                  '${source != null ? '\nTaken from: ${source['title']}' : ''}'),
              gap(12),
              DropdownButtonFormField<Object?>(
                initialValue: d['status'],
                decoration: const InputDecoration(labelText: 'Status'),
                items: [for (final (label, value) in designStatuses) DropdownMenuItem(value: value, child: Text(label))],
                onChanged: (v) => _setStatus(d, v),
              ),
              gap(10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                OutlinedButton(onPressed: () => _edit(d), child: const Text('Edit')),
                OutlinedButton(onPressed: () => _link(d), child: const Text('Link a product…')),
                FilledButton(onPressed: () => _make(d), child: const Text('Create a product')),
              ]),
              gap(16),
              heading('Products built from this design'),
              if (products.isEmpty) hint('None yet.'),
              for (final p in products.cast<Map>())
                RowCard(
                  title: '${p['sku']} · ${p['name']}',
                  lines: ['${_typeWords['${p['item_type']}'] ?? p['item_type']} · ${rupees(p['selling_price'])} · in stock ${p['current_stock']}'],
                  trailing: TextButton(onPressed: () => _unlink(d, p), child: const Text('Unlink')),
                ),
              if (source != null) ...[
                gap(16),
                heading('3D files from the restoration'),
                if (files.isEmpty) hint('No files yet.'),
                for (final f in files.cast<Map>())
                  RowCard(title: fileKindWords['${f['kind']}'] ?? '${f['kind']}', lines: [fileSize(f['size_bytes'])]),
                if (files.isNotEmpty) hint('Save these files from the desktop app.'),
              ],
            ]);
          },
        ),
      );
}

/// Choose one product (by code or name) to link to a design; pops with its id.
class _PickProductPage extends StatefulWidget {
  const _PickProductPage({required this.items});
  final List<Map<String, dynamic>> items;
  @override
  State<_PickProductPage> createState() => _PickProductPageState();
}

class _PickProductPageState extends State<_PickProductPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.toLowerCase();
    final rows = [
      for (final i in widget.items)
        if (q.isEmpty || '${i['name']}'.toLowerCase().contains(q) || '${i['sku'] ?? ''}'.toLowerCase().contains(q)) i
    ];
    return Screen(
      title: 'Link a product',
      body: ListView(padding: const EdgeInsets.all(16), children: [
        searchBox((v) => setState(() => _q = v.trim()), 'Type a code or a name'),
        gap(12),
        if (rows.isEmpty) hint('No product matches.'),
        for (final i in rows.take(100))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RowCard(
              title: '${i['name']}',
              lines: ['${i['sku'] ?? ''} · ${_typeWords['${i['item_type'] ?? 'furniture'}'] ?? ''}'],
              onTap: () => Navigator.of(context).pop('${i['id']}'),
            ),
          ),
        if (rows.length > 100) hint('Showing the first 100. Type to narrow the list.'),
      ]),
    );
  }
}
