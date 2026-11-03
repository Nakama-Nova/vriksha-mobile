import 'package:flutter/material.dart';

import '../api.dart';
import '../kit.dart';
import '../theme.dart';
import 'designs_screen.dart' show fileKindWords, fileSize;
import 'letters_screen.dart' show issueLetter;

// The stages and wording are the desktop's (services/restoration_service.py).
const _stages = <(String, String)>[
  ('Planned', 'planned'),
  ('Capturing', 'capturing'),
  ('Building 3D model', 'processing'),
  ('Ready to review', 'review'),
  ('Carving', 'carving'),
  ('Finishing', 'finishing'),
  ('Painting', 'painting'),
  ('Restored', 'restored'),
  ('On hold', 'on_hold'),
  ('Cancelled', 'cancelled'),
];
const _kindStages = {
  'temple': ['planned', 'capturing', 'processing', 'review', 'carving', 'restored', 'on_hold', 'cancelled'],
  'finishing': ['planned', 'finishing', 'painting', 'restored', 'on_hold', 'cancelled'],
};
const projectKinds = <(String, Object?)>[
  ('Temple restoration', 'temple'),
  ('Bought piece: finishing and painting', 'finishing'),
];
const _scanWords = {
  'created': 'Uploading',
  'uploaded': 'Waiting for the workshop PC',
  'processing': 'Building 3D model',
  'done': 'Done',
  'failed': 'Failed',
  'cancelled': 'Cancelled',
};
const _shapeWords = {'relief': 'Flat carving', 'full': '3D object'};

/// The stage in words; the last stage of a bought piece is "Ready to sell".
String stageWord(Object? status, [Object? kind = 'temple']) {
  if (kind == 'finishing' && status == 'restored') return 'Ready to sell';
  if (kind == 'finishing' && status == 'planned') return 'Bought';
  return _stages.where((s) => s.$2 == status).map((s) => s.$1).firstOrNull ?? '$status';
}

List<(String, Object?)> stagesFor(Object? kind) =>
    [for (final s in _kindStages['$kind'] ?? _kindStages['temple']!) (stageWord(s, kind), s)];

/// Temple restorations (and bought pieces to be finished and painted): the owner and
/// artisans keep a record of each project, where the work stands, its scans and 3D files.
/// Adding photos or a video is done from 3D Lab, New scan.
class RestorationScreen extends StatefulWidget {
  const RestorationScreen({super.key});
  @override
  State<RestorationScreen> createState() => _RestorationScreenState();
}

class _RestorationScreenState extends State<RestorationScreen> {
  String? _status;
  int _gen = 0;

  Future<void> _new() async {
    final api = AppScope.of(context).session.api;
    List team = [], sculptures = [], suppliers = [];
    try {
      team = await api.getJson('/restorations/team') as List;
      sculptures = [for (final i in await api.allItems()) if (i['item_type'] == 'sculpture') i];
      suppliers = await api.getJson('/suppliers/') as List;
    } on ApiException catch (e) {
      if (e.status == 401) return;
      // the form still works for a temple restoration without the lists
    }
    if (!mounted) return;
    if (await saveProject(context, team: team, sculptures: sculptures, suppliers: suppliers)) setState(() => _gen++);
  }

  @override
  Widget build(BuildContext context) => Screen(
        title: 'Restoration',
        fab: addFab('New restoration', _new),
        body: Loader<List>(
          key: ValueKey('$_gen$_status'),
          load: (api) async => await api.getJson('/restorations', {'status': ?_status}) as List,
          builder: (c, rows, reload) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
            DropdownButtonFormField<String?>(
              initialValue: _status,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Show'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All projects')),
                for (final (label, value) in _stages) DropdownMenuItem(value: value, child: Text(label)),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
            gap(12),
            if (rows.isEmpty) hint('No projects here.'),
            for (final p in rows.cast<Map>())
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowCard(
                  title: '${p['title']}',
                  lines: [
                    '${p['temple_name'] ?? (p['item_id'] != null ? '${p['item_sku'] ?? ''}  ${p['item_name'] ?? ''}'.trim() : '')}',
                    '${p['piece'] ?? ''}',
                    '${p['lead_artisan_name'] != null ? 'Lead: ${p['lead_artisan_name']} · ' : ''}${p['scan_count']} scans · ${p['file_count']} files',
                  ],
                  trailing: Text(stageWord(p['status'], p['kind'] ?? 'temple'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: brandBrown)),
                  onTap: () async {
                    await pushScoped<void>(context, ProjectPage(projectId: '${p['id']}'));
                    if (mounted) setState(() => _gen++);
                  },
                ),
              ),
          ]),
        ),
      );
}

/// A temple restoration, or a piece bought from another artisan that is to be finished and
/// painted. Returns true when it was saved.
Future<bool> saveProject(BuildContext context,
    {required List team, required List sculptures, required List suppliers, Map? project}) async {
  final editing = project != null;
  final api = AppScope.of(context).session.api;
  final v = await showForm(context, editing ? 'Edit project' : 'New project', [
    if (!editing) F('kind', 'Kind', kind: K.choice, choices: projectKinds, initial: 'temple'), // a project never changes kind
    F('title', 'Title', required: true, initial: project?['title'], hint: 'e.g. Dwarapalaka, left door'),
    if (project == null || project['kind'] != 'finishing') ...[
      F('temple_name', 'Temple (temple restoration)', initial: project?['temple_name'], hint: 'e.g. Veerabhadra Temple'),
      F('location', 'Place', initial: project?['location'], hint: 'town or village'),
    ],
    if (project == null || project['kind'] == 'finishing') ...[
      F('item_id', 'The piece (bought piece)', kind: K.choice, initial: project?['item_id'], choices: [
        ('Choose the piece…', null),
        for (final i in sculptures) ('${i['name']}  (${i['sku'] ?? ''})', '${i['id']}'),
      ]),
      F('supplier_id', 'Bought from (bought piece)', kind: K.choice, initial: project?['supplier_id'], choices: [
        ('Not recorded', null),
        for (final s in suppliers) ('${s['name']}', '${s['id']}'),
      ]),
    ],
    F('piece', 'Piece', initial: project?['piece'], hint: 'what the piece is'),
    F('condition_notes', 'Condition / what needs doing', kind: K.multiline, initial: project?['condition_notes']),
    F('lead_artisan_id', 'Lead artisan', kind: K.choice, initial: project?['lead_artisan_id'], choices: [
      ('Not decided', null),
      for (final t in team) ('${t['name']}', '${t['id']}'),
    ]),
  ]);
  if (v == null || !context.mounted) return false;
  final finishing = (project != null ? project['kind'] : v['kind']) == 'finishing';
  final problem = finishing
      ? ((v['title'] == null || v['item_id'] == null) ? 'Enter a title and choose the piece being finished.' : null)
      : ((v['title'] == null || v['temple_name'] == null) ? "Enter a title and the temple's name." : null);
  if (problem != null) {
    snack(context, problem);
    return false;
  }
  final body = <String, Object?>{
    if (!editing) 'kind': v['kind'],
    'title': v['title'],
    'piece': v['piece'],
    'condition_notes': v['condition_notes'],
    'lead_artisan_id': v['lead_artisan_id'],
    if (finishing) ...{'item_id': v['item_id'], 'supplier_id': v['supplier_id']} else ...{'temple_name': v['temple_name'], 'location': v['location']},
  };
  return guard(context, () async => project != null ? api.patchJson('/restorations/${project['id']}', body) : api.postJson('/restorations', body),
      done: 'Saved');
}

/// One project: notes, stage, designs made from it, its scans and 3D files.
class ProjectPage extends StatefulWidget {
  const ProjectPage({super.key, required this.projectId});
  final String projectId;
  @override
  State<ProjectPage> createState() => _ProjectPageState();
}

class _ProjectPageState extends State<ProjectPage> {
  int _gen = 0;
  ApiClient get _api => AppScope.of(context).session.api;
  void _reload() => setState(() => _gen++);

  Future<void> _setStage(Map d, Object? status) async {
    if (status == d['status']) return;
    final api = _api;
    if (await guard(context, () async => api.patchJson('/restorations/${d['id']}', {'status': status}), done: 'Stage changed')) _reload();
  }

  Future<void> _edit(Map d) async {
    final api = _api;
    List team = [], sculptures = [], suppliers = [];
    try {
      team = await api.getJson('/restorations/team') as List;
      if (d['kind'] == 'finishing') {
        sculptures = [for (final i in await api.allItems()) if (i['item_type'] == 'sculpture') i];
        suppliers = await api.getJson('/suppliers/') as List;
      }
    } on ApiException catch (e) {
      if (e.status == 401) return;
    }
    if (!mounted) return;
    if (await saveProject(context, team: team, sculptures: sculptures, suppliers: suppliers, project: d)) _reload();
  }

  Future<void> _makeDesign(Map d) async {
    final v = await showForm(context, 'Make a design', [F('name', 'Name of the design', required: true, initial: d['title'])], ok: 'Save design');
    if (v == null || !mounted) return;
    final api = _api;
    Map? made;
    final ok = await guard(context,
        () async => made = await api.postJson('/designs', {'name': v['name'], 'restoration_id': d['id'], 'description': d['piece']}) as Map);
    if (ok && mounted) {
      snack(context, '${made!['name']} was saved as ${made!['sku']}. Find it under Designs.');
      _reload();
    }
  }

  Future<void> _cost(Map d) async {
    final api = _api;
    Map c;
    try {
      c = await api.getJson('/restorations/${d['id']}/cost') as Map;
    } on ApiException catch (e) {
      if (e.status != 401 && mounted) snack(context, e.message);
      return;
    }
    if (!mounted) return;
    await infoSheet(context, 'What ${c['item_name'] ?? d['title']} has cost', [
      kv('Bought for', rupees(c['purchase_price'])),
      kv('Labour paid', rupees(c['labour'])),
      kv('Paint and others', rupees(c['expenses'])),
      kv('Total so far', rupees(c['total'])),
      if (c['selling_price'] != null)
        hint('Priced at ${rupees(c['selling_price'])}: ${numOf(c['profit_if_sold']) >= 0 ? 'profit' : 'loss'} ${rupees(numOf(c['profit_if_sold']).abs())} if sold')
      else if (c['item_id'] == null)
        hint('This project is not tied to a piece, so only linked expenses are counted.'),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    return Screen(
      title: 'Project',
      body: Loader<Map>(
        key: ValueKey(_gen),
        load: (api) async => await api.getJson('/restorations/${widget.projectId}') as Map,
        builder: (c, d, reload) {
          final kind = '${d['kind'] ?? 'temple'}';
          final finishing = kind == 'finishing';
          final head = finishing
              ? '${d['title']}  ·  ${d['item_name'] ?? ''} (${d['item_sku'] ?? ''})${d['supplier_name'] != null ? '  ·  bought from ${d['supplier_name']}' : ''}'
              : '${d['title']}  ·  ${d['temple_name'] ?? ''}${d['location'] != null ? ', ${d['location']}' : ''}';
          final designs = (d['designs'] as List?) ?? const [];
          final scans = (d['scans'] as List?) ?? const [];
          final files = (d['files'] as List?) ?? const [];
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(head, style: serif(22)),
            gap(6),
            Text('${d['condition_notes'] ?? (finishing ? 'No notes yet.' : 'No condition notes yet.')}'),
            gap(6),
            Text(designs.isEmpty ? 'No design made from this yet.' : 'Designs: ${designs.map((x) => '${x['sku']} ${x['name']}').join(',  ')}',
                style: const TextStyle(color: textMuted)),
            gap(12),
            DropdownButtonFormField<Object?>(
              initialValue: d['status'],
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Stage'),
              items: [for (final (label, value) in stagesFor(kind)) DropdownMenuItem(value: value, child: Text(label))],
              onChanged: (v) => _setStage(d, v),
            ),
            gap(10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              OutlinedButton(onPressed: () => _edit(d), child: const Text('Edit')),
              OutlinedButton(onPressed: () => _makeDesign(d), child: const Text('Make a design')),
              if (session.isOwner) OutlinedButton(onPressed: () => _cost(d), child: const Text('What it has cost')),
              if (session.isOwner && kind == 'temple' && d['status'] == 'restored')
                OutlinedButton(onPressed: () => issueLetter(context, 'completion_certificate', restoration: d), child: const Text('Certificate of completion')),
            ]),
            gap(6),
            hint('To add photos or a video, use 3D Lab, then New scan, and choose this project.'),
            gap(12),
            heading('Scans'),
            if (scans.isEmpty) hint('No scans yet.'),
            for (final s in scans.cast<Map>())
              RowCard(
                title: '${_shapeWords['${(s['params'] as Map?)?['shape'] ?? 'full'}'] ?? '3D object'}, ${s['source_kind'] == 'video' ? 'video' : 'photos'}',
                lines: [
                  showTime(s['created_at']),
                  '${s['files']} files · ${s['progress']}%',
                  '${s['error'] ?? s['note'] ?? ''}',
                ],
                trailing: Text(_scanWords['${s['status']}'] ?? '${s['status']}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: s['status'] == 'failed' ? badRed : brandBrown)),
              ),
            gap(12),
            heading('3D files and G-code'),
            if (files.isEmpty) hint('No files yet.'),
            for (final f in files.cast<Map>())
              RowCard(
                title: fileKindWords['${f['kind']}'] ?? '${f['kind']}',
                lines: ['${fileSize(f['size_bytes'])} · ${showDate(f['created_at'])}'],
              ),
            if (files.isNotEmpty) hint('Save these files from the desktop app.'),
          ]);
        },
      ),
    );
  }
}
