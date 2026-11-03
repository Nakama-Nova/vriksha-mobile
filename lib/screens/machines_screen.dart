import 'package:flutter/material.dart';

import '../api.dart';
import '../kit.dart';
import '../theme.dart';

const _dueSoonDays = 14;
const _statusWords = {
  'active': 'Working',
  'down': 'Stopped',
  'retired': 'Retired',
  'available': 'Available',
  'issued': 'Handed out',
  'broken': 'Broken',
  'lost': 'Lost',
};
const _conditions = <(String, Object?)>[('New', 'new'), ('Good', 'good'), ('Worn', 'worn'), ('Damaged', 'damaged')];

Color machineStatusColour(Object? s) => switch (s) {
      'active' || 'available' => okGreen,
      'down' || 'broken' || 'lost' => badRed,
      'issued' => const Color(0xFFD9822B),
      _ => textMuted,
    };

DateTime? _day(Object? v) {
  final s = '${v ?? ''}';
  if (s.length < 10) return null;
  final d = DateTime.tryParse(s.substring(0, 10));
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

/// 'overdue', 'soon' (within two weeks) or '' for a machine that is not retired.
String dueState(Map m, [DateTime? today]) {
  if (m['status'] == 'retired') return '';
  if (m['service_overdue'] == true) return 'overdue';
  final due = _day(m['service_due_on']);
  final now = today ?? DateTime.now();
  if (due != null && due.difference(DateTime(now.year, now.month, now.day)).inDays <= _dueSoonDays) return 'soon';
  return '';
}

/// Machines and tools. Machines: what each is worth now, when it is next due for service,
/// record a service or repair, mark it stopped and working again. Tools: who has which tool,
/// hand one out, take it back (fine, damaged or lost). Owner and manager manage both; the
/// achari can see tools.
class MachinesScreen extends StatefulWidget {
  const MachinesScreen({super.key});
  @override
  State<MachinesScreen> createState() => _MachinesScreenState();
}

class _MachinesScreenState extends State<MachinesScreen> {
  int _view = 0; // 0 machines, 1 tools
  String _machineChip = 'all';
  String _toolChip = 'all';
  String _search = '';
  int _gen = 0;
  List _places = [];
  Map<String, String> _staff = {};

  Future<(List, List, List, Map<String, String>)> _load(ApiClient api, bool manage) async {
    final places = await api.getJson('/plant-units/') as List;
    final machines = manage ? await api.getJson('/machines/', {'limit': '200'}) as List : [];
    final tools = await api.getJson('/tools/', {'limit': '200'}) as List;
    final staff = <String, String>{};
    if (manage) {
      for (final u in await api.getJson('/auth/') as List) {
        staff['${u['id']}'] = '${u['full_name'] ?? u['username']}';
      }
    }
    return (places, machines, tools, staff);
  }

  ApiClient get _api => AppScope.of(context).session.api;
  void _refresh() => setState(() => _gen++);

  List<(String, Object?)> get _placeChoices => [
        ('Not set', null),
        for (final p in _places) ('${p['name']}', '${p['id']}'),
      ];

  double? _positive(Object? v) => numOf(v) > 0 ? numOf(v).toDouble() : null;

  // ---- machines -----------------------------------------------------------
  Future<void> _saveMachine([Map? m]) async {
    final editing = m != null;
    final canSetStatus = m != null && m['status'] != 'down'; // Stopped is set with its own button
    final v = await showForm(context, editing ? 'Edit machine' : 'Add machine', [
      F('tag', 'Tag', required: true, initial: m?['tag'], hint: 'Number painted on the machine, e.g. M-01'),
      F('name', 'Name', required: true, initial: m?['name'], hint: 'e.g. Table saw'),
      F('make_model', 'Make / model', initial: m?['make_model']),
      F('serial_number', 'Serial number', initial: m?['serial_number']),
      F('location_id', 'Kept at', kind: K.choice, choices: _placeChoices, initial: m?['location_id']),
      F('purchase_date', 'Bought on', kind: K.optDate, initial: m?['purchase_date']),
      F('purchase_cost', 'Bought for', kind: K.money, initial: m?['purchase_cost']),
      F('useful_life_years', 'Lasts about (years)', kind: K.number, initial: m?['useful_life_years']),
      F('salvage_value', 'Worth at the end', kind: K.money, initial: m?['salvage_value']),
      F('maintenance_every_days', 'Service every (days)', kind: K.number, initial: m?['maintenance_every_days'], hint: 'empty = no schedule'),
      F('notes', 'Notes', initial: m?['notes']),
      if (canSetStatus)
        F('status', 'Status', kind: K.choice, initial: m!['status'] == 'retired' ? 'retired' : 'active', choices: const [
          ('Working', 'active'),
          ('Retired (no longer used)', 'retired'),
        ]),
    ]);
    if (v == null || !mounted) return;
    final life = _positive(v['useful_life_years']);
    final every = _positive(v['maintenance_every_days']);
    final body = {
      'tag': v['tag'],
      'name': v['name'],
      'make_model': v['make_model'],
      'serial_number': v['serial_number'],
      'location_id': v['location_id'],
      'purchase_date': v['purchase_date'],
      'purchase_cost': _positive(v['purchase_cost'])?.toStringAsFixed(2),
      'useful_life_years': life?.round(),
      'salvage_value': numOf(v['salvage_value']).toDouble().toStringAsFixed(2),
      'maintenance_every_days': every?.round(),
      'notes': v['notes'],
      if (canSetStatus) 'status': v['status'],
    };
    final api = _api;
    if (await guard(context, () async => editing ? api.putJson('/machines/${m!['id']}', body) : api.postJson('/machines/', body),
        done: 'Saved')) {
      _refresh();
    }
  }

  Future<void> _service(Map m) async {
    final v = await showForm(context, 'Service: ${m['name']}', [
      F('kind', 'What', kind: K.choice, initial: 'scheduled', choices: const [('Scheduled service', 'scheduled'), ('Repair', 'repair')]),
      F('performed_on', 'Date', kind: K.date),
      F('cost', 'Cost', kind: K.money),
      F('done_by', 'Done by', hint: 'optional'),
      F('description', 'What was done', hint: 'optional'),
    ], ok: 'Record');
    if (v == null || !mounted) return;
    final api = _api;
    if (await guard(
        context,
        () async => api.postJson('/machines/${m['id']}/maintenance', {
              'kind': v['kind'],
              'performed_on': v['performed_on'],
              'cost': numOf(v['cost']).toDouble().toStringAsFixed(2),
              'done_by': v['done_by'],
              'description': v['description'],
            }),
        done: 'Recorded')) {
      _refresh();
    }
  }

  Future<void> _stopped(Map m) async {
    final v = await showForm(context, 'Machine stopped', [F('reason', 'What happened to ${m['name']}?', hint: 'optional')],
        ok: 'Mark stopped');
    if (v == null || !mounted) return;
    final api = _api;
    if (await guard(context, () async => api.postJson('/machines/${m['id']}/downtime', {'reason': v['reason']}),
        done: '${m['name']} marked stopped')) {
      _refresh();
    }
  }

  Future<void> _working(Map m) async {
    final api = _api;
    if (await guard(context, () async => api.postJson('/machines/${m['id']}/downtime/end'), done: '${m['name']} is working again')) {
      _refresh();
    }
  }

  Future<void> _machineHistory(Map m) async {
    final api = _api;
    List maint, down;
    try {
      maint = await api.getJson('/machines/${m['id']}/maintenance') as List;
      down = await api.getJson('/machines/${m['id']}/downtime') as List;
    } on ApiException catch (e) {
      if (e.status != 401 && mounted) snack(context, e.message);
      return;
    }
    if (!mounted) return;
    await infoSheet(context, '${m['tag']} · ${m['name']}', [
      kv('Status', _statusWords['${m['status']}'] ?? '${m['status']}', color: machineStatusColour(m['status'])),
      if (m['make_model'] != null) kv('Make / model', '${m['make_model']}'),
      if (m['serial_number'] != null) kv('Serial number', '${m['serial_number']}'),
      if (m['location_id'] != null) kv('Kept at', placeNameOf(_places, m['location_id'])),
      if (m['purchase_date'] != null) kv('Bought on', showDate(m['purchase_date'])),
      if (m['purchase_cost'] != null) kv('Bought for', rupees(m['purchase_cost'])),
      kv('Worth now', m['book_value'] == null ? '—' : rupees(m['book_value'])),
      kv('Next service', '${m['service_due_on'] ?? '—'}'),
      kv('Spent on service', rupees(m['maintenance_spent'])),
      if (m['notes'] != null) hint('${m['notes']}'),
      gap(10),
      heading('Services and repairs (${maint.length})'),
      if (maint.isEmpty) hint('None yet.'),
      for (final r in maint.cast<Map>())
        RowCard(
          title: '${r['kind'] == 'repair' ? 'Repair' : 'Service'} · ${r['performed_on']}',
          lines: [rupees(r['cost']), '${r['done_by'] ?? ''}', '${r['description'] ?? ''}'],
        ),
      gap(10),
      heading('Stoppages (${down.length})'),
      if (down.isEmpty) hint('None.'),
      for (final r in down.cast<Map>())
        RowCard(
          title: 'Stopped ${showTime(r['started_at'])}',
          lines: [r['ended_at'] == null ? 'Still stopped' : 'Working again ${showTime(r['ended_at'])}', '${r['reason'] ?? ''}'],
        ),
    ]);
  }

  // ---- tools --------------------------------------------------------------
  Future<void> _saveTool([Map? t]) async {
    final editing = t != null;
    final canSetStatus = t != null && (t['status'] == 'available' || t['status'] == 'retired');
    final v = await showForm(context, editing ? 'Edit tool' : 'Add tool', [
      F('tag', 'Tag', required: true, initial: t?['tag'], hint: 'Number marked on the tool, e.g. T-01'),
      F('name', 'Name', required: true, initial: t?['name'], hint: 'e.g. Chisel set'),
      F('category', 'Category', initial: t?['category']),
      F('condition', 'Condition', kind: K.choice, choices: _conditions, initial: t?['condition'] ?? 'good'),
      F('location_id', 'Kept at', kind: K.choice, choices: _placeChoices, initial: t?['location_id']),
      F('purchase_date', 'Bought on', kind: K.optDate, initial: t?['purchase_date']),
      F('purchase_cost', 'Bought for', kind: K.money, initial: t?['purchase_cost']),
      F('notes', 'Notes', initial: t?['notes']),
      if (canSetStatus)
        F('status', 'Status', kind: K.choice, initial: t!['status'], choices: const [
          ('Available', 'available'),
          ('Retired (no longer used)', 'retired'),
        ]),
    ]);
    if (v == null || !mounted) return;
    final body = {
      'tag': v['tag'],
      'name': v['name'],
      'category': v['category'],
      'condition': v['condition'],
      'location_id': v['location_id'],
      'purchase_date': v['purchase_date'],
      'purchase_cost': _positive(v['purchase_cost'])?.toStringAsFixed(2),
      'notes': v['notes'],
      if (canSetStatus) 'status': v['status'],
    };
    final api = _api;
    if (await guard(context, () async => editing ? api.putJson('/tools/${t!['id']}', body) : api.postJson('/tools/', body),
        done: 'Saved')) {
      _refresh();
    }
  }

  Future<void> _handOut(Map t) async {
    if (_staff.isEmpty) return snack(context, 'There are no staff accounts to hand a tool to.');
    final v = await showForm(
        context,
        'Hand out',
        [F('user', 'Who is taking ${t['name']}?', kind: K.choice, required: true, choices: [for (final e in _staff.entries) (e.value, e.key)])],
        ok: 'Hand out');
    if (v == null || !mounted) return;
    final api = _api;
    if (await guard(context, () async => api.postJson('/tools/${t['id']}/issue', {'user_id': v['user'], 'notes': null}),
        done: 'Handed out')) {
      _refresh();
    }
  }

  Future<void> _takeBack(Map t) async {
    final v = await showForm(
        context,
        'Take back',
        [
          F('outcome', '${t['name']} is:', kind: K.choice, initial: 'ok', choices: const [
            ('Returned in good order', 'ok'),
            ('Returned damaged', 'damaged'),
            ('Lost', 'lost'),
          ])
        ],
        ok: 'Take back');
    if (v == null || !mounted) return;
    final api = _api;
    if (await guard(context, () async => api.postJson('/tools/${t['id']}/return', {'outcome': v['outcome'], 'notes': null}),
        done: 'Recorded')) {
      _refresh();
    }
  }

  Future<void> _toolHistory(Map t) async {
    final api = _api;
    List rows;
    try {
      rows = await api.getJson('/tools/${t['id']}/history') as List;
    } on ApiException catch (e) {
      if (e.status != 401 && mounted) snack(context, e.message);
      return;
    }
    if (!mounted) return;
    const outcome = {'ok': 'Fine', 'damaged': 'Damaged', 'lost': 'Lost'};
    await infoSheet(context, '${t['tag']} · ${t['name']}', [
      if (rows.isEmpty) hint('Nobody has had it yet.'),
      for (final r in rows.cast<Map>())
        RowCard(
          title: '${r['user_name'] ?? ''}',
          lines: [
            'Handed out ${showTime(r['issued_at'])}',
            r['returned_at'] == null ? 'Still out' : 'Back ${showTime(r['returned_at'])}',
            outcome['${r['outcome']}'] ?? '',
          ],
        ),
    ]);
  }

  // ---- screen -------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final manage = AppScope.of(context).session.isStaffLead;
    final onMachines = manage && _view == 0;
    return Screen(
      title: 'Machines and tools',
      fab: manage ? addFab(onMachines ? 'Add machine' : 'Add tool', onMachines ? _saveMachine : _saveTool) : null,
      body: Loader<(List, List, List, Map<String, String>)>(
        key: ValueKey(_gen),
        load: (api) => _load(api, manage),
        builder: (c, d, reload) {
          final (places, machines, tools, staff) = d;
          _places = places;
          _staff = staff;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
            if (manage) ...[
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Machines')),
                  ButtonSegment(value: 1, label: Text('Tools')),
                ],
                selected: {_view},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _view = s.first),
              ),
              gap(12),
            ],
            if (onMachines) ..._machines(machines) else ..._tools(tools, manage),
          ]);
        },
      ),
    );
  }

  Widget _chips(List<(String, String, int)> chips, String current, ValueChanged<String> pick) => Wrap(spacing: 8, runSpacing: 4, children: [
        for (final (id, label, n) in chips)
          ChoiceChip(label: Text('$label ($n)'), selected: current == id, onSelected: (_) => pick(id)),
      ]);

  List<Widget> _machines(List machines) {
    final late = machines.where((m) => dueState(m) == 'overdue').toList();
    final down = machines.where((m) => m['status'] == 'down').toList();
    String names(List l) => '${l.take(4).map((m) => m['name']).join(', ')}${l.length > 4 ? '…' : ''}';
    final parts = [
      if (late.isNotEmpty) '${late.length} overdue for service: ${names(late)}',
      if (down.isNotEmpty) '${down.length} stopped: ${names(down)}',
    ];
    final text = _search.toLowerCase();
    final rows = [
      for (final m in machines)
        if (!(_machineChip == 'due' && dueState(m).isEmpty) &&
            !(const {'down', 'active', 'retired'}.contains(_machineChip) && m['status'] != _machineChip) &&
            (text.isEmpty || ['tag', 'name', 'make_model'].map((k) => '${m[k] ?? ''}').join(' ').toLowerCase().contains(text)))
          m
    ];
    int count(bool Function(Map) f) => machines.where((m) => f(m as Map)).length;
    return [
      if (parts.isNotEmpty) ...[
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: badRed.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
          child: Text('⚠️  ${parts.join('   ·   ')}'),
        ),
        gap(12),
      ],
      _chips([
        ('all', 'All', machines.length),
        ('due', 'Due for service', count((m) => dueState(m).isNotEmpty)),
        ('down', 'Stopped', count((m) => m['status'] == 'down')),
        ('active', 'Working', count((m) => m['status'] == 'active')),
        ('retired', 'Retired', count((m) => m['status'] == 'retired')),
      ], _machineChip, (id) => setState(() => _machineChip = id)),
      gap(10),
      searchBox((v) => setState(() => _search = v.trim()), 'Search by tag, name or make'),
      gap(12),
      if (rows.isEmpty) hint('No machines here.'),
      for (final m in rows) _machineCard(m as Map),
    ];
  }

  Widget _machineCard(Map m) {
    final state = dueState(m);
    final due = m['service_due_on'];
    final dueLine = switch (state) {
      'overdue' => 'Overdue${due != null ? ' · $due' : ''}',
      'soon' => 'Service soon · $due',
      _ => due != null ? 'Next service $due' : '',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RowCard(
        title: '${m['tag']} · ${m['name']}',
        lines: ['Worth ${m['book_value'] == null ? '—' : rupees(m['book_value'])} · spent ${rupees(m['maintenance_spent'])}', dueLine],
        trailing: Text(_statusWords['${m['status']}'] ?? '${m['status']}',
            style: TextStyle(color: machineStatusColour(m['status']), fontWeight: FontWeight.w600, fontSize: 12)),
        onTap: () => actionSheet(context, '${m['name']}', [
          ('Record a service or repair', () => _service(m)),
          if (m['status'] == 'down') ('Working again', () => _working(m)),
          if (m['status'] == 'active') ('Stopped', () => _stopped(m)),
          ('History', () => _machineHistory(m)),
          ('Edit', () => _saveMachine(m)),
        ]),
      ),
    );
  }

  List<Widget> _tools(List tools, bool manage) {
    final text = _search.toLowerCase();
    final rows = [
      for (final t in tools)
        if ((_toolChip == 'all' || t['status'] == _toolChip) &&
            (text.isEmpty || ['tag', 'name', 'category'].map((k) => '${t[k] ?? ''}').join(' ').toLowerCase().contains(text)))
          t
    ];
    int count(String s) => tools.where((t) => t['status'] == s).length;
    return [
      _chips([
        ('all', 'All', tools.length),
        ('available', 'Available', count('available')),
        ('issued', 'Handed out', count('issued')),
        ('broken', 'Broken', count('broken')),
        ('lost', 'Lost', count('lost')),
        ('retired', 'Retired', count('retired')),
      ], _toolChip, (id) => setState(() => _toolChip = id)),
      gap(10),
      searchBox((v) => setState(() => _search = v.trim()), 'Search by tag, name or category'),
      gap(12),
      if (rows.isEmpty) hint('No tools here.'),
      for (final t in rows.cast<Map>())
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: RowCard(
            title: '${t['tag']} · ${t['name']}',
            lines: [
              [t['category'], _conditions.where((c) => c.$2 == t['condition']).map((c) => c.$1).firstOrNull]
                  .where((x) => x != null && '$x'.isNotEmpty)
                  .join(' · '),
              if (t['held_by'] != null) 'With ${_staff['${t['held_by']}'] ?? 'someone'}',
            ],
            trailing: Text(_statusWords['${t['status']}'] ?? '${t['status']}',
                style: TextStyle(color: machineStatusColour(t['status']), fontWeight: FontWeight.w600, fontSize: 12)),
            onTap: manage
                ? () => actionSheet(context, '${t['name']}', [
                      if (t['status'] == 'issued') ('Take back', () => _takeBack(t)),
                      if (t['status'] == 'available') ('Hand out', () => _handOut(t)),
                      ('History', () => _toolHistory(t)),
                      ('Edit', () => _saveTool(t)),
                    ])
                : null,
          ),
        ),
    ];
  }
}

String placeNameOf(List places, Object? id) {
  for (final p in places) {
    if ('${p['id']}' == '$id') return '${p['name']}';
  }
  return 'Unknown place';
}
