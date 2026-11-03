import 'package:flutter/material.dart';

import '../api.dart';
import '../kit.dart';
import '../theme.dart';

const notPlaced = 'Not placed yet';
const _placeKinds = <(String, Object?)>[('Plant unit', 'plant'), ('Shop', 'shop')];

/// "2", "2.5", "0.25": no trailing zeros.
String qtyText(Object? v) => numOf(v).toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '');

/// ('item'|'material', id): what a stock row is about.
(String, String) thingKey(Map r) => r['item_id'] != null ? ('item', '${r['item_id']}') : ('material', '${r['raw_material_id']}');

String placeName(List places, Object? id) {
  if (id == null || '$id'.isEmpty) return notPlaced;
  for (final p in places) {
    if ('${p['id']}' == '$id') return '${p['name']}';
  }
  return 'Unknown place';
}

/// Places: where the stock is. Pick a place (or "Not placed yet") to see what it holds, search,
/// and move stock from one place to another. Owner and manager move stock, sales staff can
/// look, and only the owner adds or changes a place (the plant units and the shop).
class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});
  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  int _view = 0; // 0 what is where, 1 recent moves, 2 the places
  String _where = 'all'; // 'all', 'none' or a place id
  String? _kind; // 'item' | 'material'
  String _search = '';
  int _gen = 0;
  List _places = [], _levels = [];

  Future<(List, List, List)> _load(ApiClient api) async {
    final places = await api.getJson('/plant-units/') as List;
    // stock at places, then the stock with no place yet, as one list
    final placed = await api.getJson('/stock/levels', {'limit': '500'}) as List;
    final unplaced = await api.getJson('/stock/unassigned', {'limit': '500'}) as List;
    final moves = await api.getJson('/stock/transfers', {'limit': '50'}) as List;
    return (places, [...placed, ...unplaced], moves);
  }

  Future<void> _move(Map? preset) async {
    if (!_levels.any((r) => numOf(r['quantity']) > 0)) return snack(context, 'There is no stock to move yet.');
    final body = await pushScoped<Map<String, Object?>>(context, MoveStockPage(places: _places, levels: _levels, preset: preset));
    if (body == null || !mounted) return;
    final api = AppScope.of(context).session.api;
    if (await guard(context, () async => api.postJson('/stock/transfers', body), done: 'Stock moved')) {
      setState(() => _gen++);
    }
  }

  Future<void> _savePlace([Map? p]) async {
    final v = await showForm(context, p == null ? 'Add place' : 'Edit place', [
      F('name', 'Name', required: true, initial: p?['name'], hint: 'e.g. Carving unit'),
      F('code', 'Code', required: true, initial: p?['code'], hint: 'Short code, e.g. U1'),
      F('kind', 'Kind', kind: K.choice, choices: _placeKinds, initial: p?['kind'] ?? 'plant'),
      F('has_till', 'Has a till (takes payment at the counter)', kind: K.flag, initial: p?['has_till'] == true),
      F('latitude', 'Latitude', kind: K.number, initial: p?['latitude']),
      F('longitude', 'Longitude', kind: K.number, initial: p?['longitude']),
      F('radius_m', 'Attendance radius (m)', kind: K.number, initial: p?['radius_m'] ?? 100),
      F('is_active', 'In use', kind: K.flag, initial: p?['is_active'] ?? true),
    ]);
    if (v == null || !mounted) return;
    if ('${v['code']}'.length > 10) return snack(context, 'The code can be at most 10 characters.');
    final radius = numOf(v['radius_m']);
    if (radius < 1 || radius > 5000) return snack(context, 'The attendance radius must be between 1 and 5000 m.');
    final lat = numOf(v['latitude']), lng = numOf(v['longitude']);
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return snack(context, 'Check the latitude and longitude.');
    final body = {
      'name': v['name'],
      'code': v['code'],
      'kind': v['kind'],
      'has_till': v['has_till'],
      'latitude': lat,
      'longitude': lng,
      'radius_m': radius,
      'is_active': v['is_active'],
    };
    final api = AppScope.of(context).session.api;
    if (await guard(
        context,
        () async => p == null ? api.postJson('/plant-units/', body) : api.putJson('/plant-units/${p['id']}', body),
        done: 'Saved')) {
      setState(() => _gen++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    final canMove = session.isStaffLead;
    final owner = session.isOwner;
    return Screen(
      title: 'Places',
      fab: owner ? addFab('Add place', _savePlace) : null,
      body: Loader<(List, List, List)>(
        key: ValueKey(_gen),
        load: _load,
        builder: (c, d, reload) {
          final (places, levels, moves) = d;
          _places = places;
          _levels = levels;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
            hint('Each place keeps its own count; the total on a product or material does not change when you move it.'
                '${canMove ? ' Tap a row to move it.' : ''}'),
            gap(10),
            if (canMove)
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: () => _move(null),
                  icon: const Icon(Icons.swap_horiz),
                  label: const Text('Move stock'),
                ),
              ),
            gap(10),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('What is where')),
                ButtonSegment(value: 1, label: Text('Recent moves')),
                ButtonSegment(value: 2, label: Text('Places')),
              ],
              selected: {_view},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
            gap(12),
            if (_view == 0) ..._stock(places, levels, canMove),
            if (_view == 1) ..._moves(places, levels, moves),
            if (_view == 2) ..._placesList(places, owner),
          ]);
        },
      ),
    );
  }

  List<Widget> _stock(List places, List levels, bool canMove) {
    final chips = <(String, String, int)>[
      ('all', 'Everywhere', levels.length),
      for (final p in places) ('${p['id']}', '${p['name']}', levels.where((r) => '${r['location_id']}' == '${p['id']}').length),
      ('none', notPlaced, levels.where((r) => r['location_id'] == null).length),
    ];
    final text = _search.toLowerCase();
    final rows = [
      for (final r in levels)
        if (!(_where == 'none' && r['location_id'] != null) &&
            !(_where != 'all' && _where != 'none' && '${r['location_id']}' != _where) &&
            (_kind == null || thingKey(r).$1 == _kind) &&
            (text.isEmpty || '${r['name']}'.toLowerCase().contains(text)))
          r
    ];
    return [
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (final (id, label, n) in chips)
          ChoiceChip(label: Text('$label ($n)'), selected: _where == id, onSelected: (_) => setState(() => _where = id)),
      ]),
      gap(10),
      searchBox((v) => setState(() => _search = v.trim()), 'Search by name'),
      gap(10),
      DropdownButtonFormField<String?>(
        initialValue: _kind,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Show'),
        items: const [
          DropdownMenuItem(value: null, child: Text('Products and materials')),
          DropdownMenuItem(value: 'item', child: Text('Products')),
          DropdownMenuItem(value: 'material', child: Text('Materials')),
        ],
        onChanged: (v) => setState(() => _kind = v),
      ),
      gap(12),
      if (rows.isEmpty) hint('Nothing here.'),
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: RowCard(
            title: '${r['name']}',
            lines: ['${thingKey(r).$1 == 'item' ? 'Product' : 'Material'} · ${r['location_name'] ?? notPlaced}'],
            trailing: Text(qtyText(r['quantity']), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            onTap: canMove ? () => _move(r) : null,
          ),
        ),
    ];
  }

  List<Widget> _moves(List places, List levels, List moves) {
    final names = {for (final r in levels) thingKey(r): '${r['name']}'};
    if (moves.isEmpty) return [hint('No moves yet.')];
    return [
      for (final m in moves)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: RowCard(
            title: names[m['item_id'] != null ? ('item', '${m['item_id']}') : ('material', '${m['raw_material_id']}')] ??
                (m['item_id'] != null ? 'Product' : 'Material'),
            lines: [
              showTime(m['created_at']),
              '${placeName(places, m['from_location_id'])} → ${placeName(places, m['to_location_id'])}',
              '${m['notes'] ?? ''}',
            ],
            trailing: Text(qtyText(m['quantity']), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
    ];
  }

  List<Widget> _placesList(List places, bool owner) => [
        if (places.isEmpty) hint('No places yet.'),
        for (final p in places)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RowCard(
              title: '${p['code']} · ${p['name']}',
              lines: [
                '${p['kind'] == 'shop' ? 'Shop' : 'Plant unit'}${p['has_till'] == true ? ' · has a till' : ''} · radius ${qtyText(p['radius_m'])} m',
                p['is_active'] == false ? 'Switched off' : 'In use',
              ],
              onTap: owner ? () => _savePlace(p) : null,
            ),
          ),
      ];
}

/// Move stock between places. Choose where from first; the list shows only what is there,
/// the amount is limited to it, and a line shows what each place will hold afterwards.
/// Pops with the body for POST /stock/transfers.
class MoveStockPage extends StatefulWidget {
  const MoveStockPage({super.key, required this.places, required this.levels, this.preset});
  final List places;
  final List levels;
  final Map? preset;
  @override
  State<MoveStockPage> createState() => _MoveStockPageState();
}

class _MoveStockPageState extends State<MoveStockPage> {
  late String _from; // a place id, or '' for "Not placed yet"
  int _thing = 0; // index into _here
  late String _to;
  final _qty = TextEditingController(text: '1');
  final _note = TextEditingController();
  String? _problem;

  String _loc(Object? id) => id == null ? '' : '$id';

  /// Only places that hold something can be moved from.
  List<String> get _origins => [
        for (final id in {for (final r in widget.levels) if (numOf(r['quantity']) > 0) _loc(r['location_id'])}) id
      ];

  List<Map> _here(String from) =>
      [for (final r in widget.levels) if (_loc(r['location_id']) == from && numOf(r['quantity']) > 0) r as Map];

  List<String> _destinations(String from) => [
        for (final id in ['', ...widget.places.where((p) => p['is_active'] != false).map((p) => '${p['id']}')])
          if (id != from) id
      ];

  @override
  void initState() {
    super.initState();
    final p = widget.preset;
    final origins = _origins;
    _from = p != null && origins.contains(_loc(p['location_id'])) ? _loc(p['location_id']) : origins.first;
    final here = _here(_from);
    if (p != null) {
      final i = here.indexWhere((r) => thingKey(r) == thingKey(p));
      if (i >= 0) _thing = i;
    }
    _to = _destinations(_from).first;
    _fit();
  }

  @override
  void dispose() {
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  Map? get _row {
    final here = _here(_from);
    return _thing < here.length ? here[_thing] : null;
  }

  bool get _isMaterial => _row != null && thingKey(_row!).$1 == 'material';

  /// Start from 1 (or what is there, if less), as the desktop does.
  void _fit() {
    final avail = _row == null ? 0 : numOf(_row!['quantity']);
    _qty.text = qtyText(avail < 1 ? avail : 1);
  }

  double _after(String id, double delta) {
    final key = _row == null ? null : thingKey(_row!);
    final now = widget.levels
        .where((r) => _loc(r['location_id']) == id && thingKey(r as Map) == key)
        .fold<double>(0, (a, r) => a + numOf(r['quantity']).toDouble());
    return now + delta;
  }

  void _submit() {
    final row = _row;
    final qty = double.tryParse(_qty.text.trim()) ?? 0;
    final avail = row == null ? 0 : numOf(row['quantity']).toDouble();
    String? problem;
    if (row == null) {
      problem = 'Nothing to move.';
    } else if (qty <= 0) {
      problem = 'Enter how many to move.';
    } else if (qty > avail) {
      problem = 'Only ${qtyText(avail)} here.';
    } else if (!_isMaterial && qty != qty.roundToDouble()) {
      problem = 'Products move in whole numbers.';
    }
    if (problem != null) return setState(() => _problem = problem);
    final (kind, id) = thingKey(row!);
    Navigator.of(context).pop(<String, Object?>{
      'item_id': kind == 'item' ? id : null,
      'raw_material_id': kind == 'material' ? id : null,
      'from_location_id': _from.isEmpty ? null : _from,
      'to_location_id': _to.isEmpty ? null : _to,
      'quantity': qtyText(qty),
      'notes': _note.text.trim().isEmpty ? null : _note.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final here = _here(_from);
    final dests = _destinations(_from);
    final qty = double.tryParse(_qty.text.trim()) ?? 0;
    final row = _row;
    return Screen(
      title: 'Move stock',
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<String>(
          initialValue: _from,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Move from'),
          items: [for (final id in _origins) DropdownMenuItem(value: id, child: Text(placeName(widget.places, id)))],
          onChanged: (v) => setState(() {
            _from = v ?? _from;
            _thing = 0;
            _to = _destinations(_from).first;
            _fit();
          }),
        ),
        gap(10),
        DropdownButtonFormField<int>(
          key: ValueKey(_from), // a new list of things for each place
          initialValue: _thing < here.length ? _thing : 0,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'What'),
          items: [
            for (final (i, r) in here.indexed)
              DropdownMenuItem(value: i, child: Text('${r['name']}  ·  ${qtyText(r['quantity'])} here', overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() {
            _thing = v ?? 0;
            _fit();
          }),
        ),
        gap(10),
        DropdownButtonFormField<String>(
          key: ValueKey('to$_from'),
          initialValue: dests.contains(_to) ? _to : dests.first,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Move to'),
          items: [for (final id in dests) DropdownMenuItem(value: id, child: Text(placeName(widget.places, id)))],
          onChanged: (v) => setState(() => _to = v ?? _to),
        ),
        gap(10),
        TextField(
          controller: _qty,
          keyboardType: TextInputType.numberWithOptions(decimal: _isMaterial),
          decoration: InputDecoration(labelText: 'How many', helperText: row == null ? null : 'Up to ${qtyText(row['quantity'])}'),
          onChanged: (_) => setState(() => _problem = null),
        ),
        gap(10),
        TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note', hintText: 'Optional, e.g. for the weekend sale')),
        gap(12),
        if (row != null && qty > 0)
          Text(
            'After the move:  ${placeName(widget.places, _from)} ${qtyText(_after(_from, 0))} → ${qtyText(_after(_from, -qty))}'
            '   ·   ${placeName(widget.places, _to)} ${qtyText(_after(_to, 0))} → ${qtyText(_after(_to, qty))}',
            style: const TextStyle(color: textMuted),
          ),
        if (_problem != null) ...[gap(10), Text(_problem!, style: const TextStyle(color: badRed))],
        gap(16),
        FilledButton(onPressed: _submit, child: const Text('Move')),
      ]),
    );
  }
}
