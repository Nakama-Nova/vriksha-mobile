import 'package:flutter/material.dart';

import '../kit.dart';

/// Buyers: the customer list, searchable; add, edit, delete.
class BuyersScreen extends StatefulWidget {
  const BuyersScreen({super.key});
  @override
  State<BuyersScreen> createState() => _BuyersScreenState();
}

class _BuyersScreenState extends State<BuyersScreen> {
  String _q = '';
  int _gen = 0;

  List<F> _fields([Map? c]) => [
        F('name', 'Name', initial: c?['name'], required: true, hint: 'e.g. Ramesh Kumar'),
        F('phone', 'Phone', initial: c?['phone']),
        F('address', 'Address', initial: c?['address']),
      ];

  Future<void> _save([Map? c]) async {
    final v = await showForm(context, c == null ? 'Add buyer' : 'Edit buyer', _fields(c));
    if (v == null || !mounted) return;
    final api = AppScope.of(context).session.api;
    if (await guard(
        context,
        () async => c == null
            ? api.postJson('/customers', v)
            : api.putJson('/customers/${c['id']}', v),
        done: 'Saved')) {
      setState(() => _gen++);
    }
  }

  Future<void> _delete(Map c) async {
    if (!await confirm(context, 'Delete buyer', 'Delete ${c['name']}?', ok: 'Delete') || !mounted) return;
    if (await guard(context, () async => AppScope.of(context).session.api.deleteJson('/customers/${c['id']}'),
        done: 'Deleted')) {
      setState(() => _gen++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = AppScope.of(context).session.canSell;
    return Screen(
      title: 'Buyers',
      fab: canEdit ? addFab('Add buyer', _save) : null,
      body: Loader<List>(
        key: ValueKey(_gen),
        load: (api) async => (await api.getJson('/customers')) as List,
        builder: (c, rows, reload) {
          final q = _q.toLowerCase();
          final shown = rows
              .where((r) => '${r['name']}'.toLowerCase().contains(q) || '${r['phone'] ?? ''}'.contains(q))
              .toList();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
            searchBox((v) => setState(() => _q = v), 'Search by name or phone'),
            gap(12),
            if (shown.isEmpty) hint('No buyers found.'),
            for (final r in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowCard(
                  title: '${r['name']}',
                  lines: ['${r['phone'] ?? ''}', '${r['address'] ?? ''}'],
                  onTap: canEdit
                      ? () => actionSheet(context, '${r['name']}', [
                            ('Edit', () => _save(r)),
                            ('Delete', () => _delete(r)),
                          ])
                      : null,
                ),
              ),
          ]);
        },
      ),
    );
  }
}
