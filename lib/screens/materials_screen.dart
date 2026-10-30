import 'package:flutter/material.dart';

import '../kit.dart';
import 'stock_screen.dart' show showMovements;

/// Materials: timber and other raw materials with their stock and price.
class MaterialsScreen extends StatefulWidget {
  const MaterialsScreen({super.key});
  @override
  State<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends State<MaterialsScreen> {
  int _gen = 0;

  Future<void> _save([Map? m]) async {
    final v = await showForm(context, m == null ? 'Add material' : 'Edit material', [
      F('name', 'Name', initial: m?['name'], required: true, hint: 'e.g. Teak plank'),
      F('unit', 'Unit', initial: m?['unit'], required: true, hint: 'cft, kg, sheet, pcs'),
      F('current_price', 'Price per unit', kind: K.money, initial: m?['current_price']),
      if (m == null) F('stock', 'Opening stock', kind: K.number, initial: 0),
    ]);
    if (v == null || !mounted) return;
    final body = {...v, 'current_price': v['current_price'] ?? 0, if (m == null) 'stock': v['stock'] ?? 0};
    final api = AppScope.of(context).session.api;
    if (await guard(
        context,
        () async => m == null ? api.postJson('/raw-materials/', body) : api.patchJson('/raw-materials/${m['id']}', body),
        done: 'Saved')) {
      setState(() => _gen++);
    }
  }

  Future<void> _adjust(Map m) async {
    final v = await showForm(
        context,
        'Adjust stock: ${m['name']}',
        [
          F('change', 'Change in ${m['unit'] ?? 'units'} (+ adds, − removes)', kind: K.number, required: true),
          F('notes', 'Reason'),
        ],
        ok: 'Apply');
    if (v == null || !mounted) return;
    final api = AppScope.of(context).session.api;
    if (await guard(
        context,
        () async => api.postJson(
            '/raw-materials/${m['id']}/adjust', {'quantity_change': v['change'], 'notes': v['notes'] ?? ''}),
        done: 'Stock updated')) {
      setState(() => _gen++);
    }
  }

  Future<void> _delete(Map m) async {
    if (!await confirm(context, 'Delete material', 'Delete ${m['name']}?', ok: 'Delete') || !mounted) return;
    if (await guard(context, () async => AppScope.of(context).session.api.deleteJson('/raw-materials/${m['id']}'),
        done: 'Deleted')) {
      setState(() => _gen++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = AppScope.of(context).session.isOwner;
    return Screen(
      title: 'Materials',
      fab: addFab('Add material', _save),
      body: Loader<List>(
        key: ValueKey(_gen),
        load: (api) async => (await api.getJson('/raw-materials/', {'limit': '100'})) as List,
        builder: (c, rows, reload) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
          if (rows.isEmpty) hint('No materials yet.'),
          for (final m in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: RowCard(
                title: '${m['name']}',
                lines: ['${rupees(m['current_price'])} per ${m['unit'] ?? 'unit'}'],
                trailing: Text('${numOf(m['stock'])} ${m['unit'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                onTap: () => actionSheet(context, '${m['name']}', [
                  ('Adjust stock', () => _adjust(m)),
                  ('Stock history', () => showMovements(context, 'History: ${m['name']}', 'raw_material_id', '${m['id']}')),
                  ('Edit', () => _save(m)),
                  if (owner) ('Delete', () => _delete(m)),
                ]),
              ),
            ),
        ]),
      ),
    );
  }
}
