import 'package:flutter/material.dart';

import '../api.dart';
import '../kit.dart';
import '../location.dart';
import '../theme.dart';
import '../widgets.dart';

const _stateWords = {'not_in': 'Not in', 'in': 'In', 'out': 'Out', 'marked': 'Marked present'};

String teamStateWord(Object? s) => _stateWords['$s'] ?? '$s';

Color teamStateColour(Object? s) => switch (s) {
      'in' => okGreen,
      'out' => textMuted,
      'marked' => brandBrown,
      _ => const Color(0xFFD9822B), // not in yet
    };

/// Where my day stands: 'not_in', 'in', 'out', or 'marked' (a manager marked me present).
String dayState(Map? today) {
  if (today == null) return 'not_in';
  if (today['check_in'] == null) return 'marked';
  return today['check_out'] == null ? 'in' : 'out';
}

/// "At Carving unit", "Away from the workshop", or '' when no position was sent.
String siteLine(Object? status, Object? unitId, List places) {
  if (status == 'on_site') {
    final name = places.where((p) => '${p['id']}' == '$unitId').map((p) => '${p['name']}').firstOrNull;
    return name == null ? 'At the workshop' : 'At $name';
  }
  if (status == 'off_site') return 'Away from the workshop';
  return '';
}

/// Attendance. Everyone checks themselves in and out from their own phone (with the phone's
/// position; the server picks the plant unit). Owner, manager and the counter also check
/// other people in and out and see the attendance log; a person with people under them sees
/// where each one stands today. Everyone else sees only their own history.
class WorkforceScreen extends StatefulWidget {
  const WorkforceScreen({super.key, this.position});

  /// Where the position comes from; the phone's GPS unless a test says otherwise.
  final PositionSource? position;

  @override
  State<WorkforceScreen> createState() => _WorkforceScreenState();
}

typedef _Data = (List users, List records, Map? today, List places, Map? team, List teamToday);

class _WorkforceScreenState extends State<WorkforceScreen> {
  int _gen = 0;
  String? _user;
  bool _busy = false;

  /// The extras (my day, my team) must never take the whole screen down.
  Future<T> _soft<T>(Future<T> Function() call, T fallback) async {
    try {
      return await call();
    } on ApiException {
      return fallback;
    }
  }

  Future<_Data> _load(ApiClient api, bool canSell) async {
    final users = canSell ? await api.getJson('/auth/') as List : const [];
    final records = await api.getJson(canSell ? '/attendance/all' : '/attendance/my') as List;
    final today = await _soft<Map?>(() async => await api.getJson('/attendance/me/today') as Map?, null);
    final places = await _soft<List>(() async => await api.getJson('/plant-units/') as List, const []);
    final team = await _soft<Map?>(() async => await api.getJson('/team/me') as Map?, null);
    final teamToday = await _soft<List>(() async => await api.getJson('/team/attendance') as List, const []);
    return (users, records, today, places, team, teamToday);
  }

  void _problem(LocationProblem e) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(e.message),
        duration: const Duration(seconds: 8),
        action: e.fix == LocationFix.none ? null : SnackBarAction(label: 'Open settings', onPressed: () => openFix(e.fix)),
      ));
  }

  Future<void> _checkInOut(bool checkIn, List places) async {
    final api = AppScope.of(context).session.api;
    setState(() => _busy = true);
    try {
      final fix = await (widget.position ?? currentFix)();
      if (!mounted) return;
      Map? r;
      final ok = await guard(
          context, () async => r = await api.postJson('/attendance/me/${checkIn ? 'check-in' : 'check-out'}', fix.toJson()) as Map);
      if (ok && mounted && r != null) {
        final site = checkIn
            ? siteLine(r!['location_status'], r!['plant_unit_id'], places)
            : siteLine(r!['check_out_location_status'], r!['check_out_plant_unit_id'], places);
        final word = checkIn ? 'Checked in' : 'Checked out';
        snack(context, site == 'Away from the workshop' ? '$word. You are away from the workshop, so your manager will see it.' : (site.isEmpty ? word : '$word · $site'));
        setState(() => _gen++);
      }
    } on LocationProblem catch (e) {
      if (mounted) _problem(e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _myDay(Map? today, List places) {
    final state = dayState(today);
    final site = today == null
        ? ''
        : state == 'out'
            ? siteLine(today['check_out_location_status'], today['check_out_plant_unit_id'], places)
            : siteLine(today['location_status'], today['plant_unit_id'], places);
    return WarmCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('My day', style: TextStyle(fontWeight: FontWeight.w600)),
        gap(6),
        Text(switch (state) {
          'in' => 'Checked in at ${showTime(today!['check_in'])}${site.isEmpty ? '' : ' · $site'}',
          'out' => 'Day finished · in ${showTime(today!['check_in'])}, out ${showTime(today['check_out'])} · ${today['total_hours'] ?? 0} h',
          'marked' => 'Your manager marked you present today.',
          _ => 'You have not checked in today.',
        }),
        if (state == 'not_in' || state == 'in') ...[
          gap(10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _checkInOut(state == 'not_in', places),
              icon: _busy
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Icon(state == 'not_in' ? Icons.login : Icons.logout),
              label: Text(state == 'not_in' ? 'Check in' : 'Check out'),
            ),
          ),
          gap(4),
          const Text('Your phone\'s position is sent with it.', style: TextStyle(fontSize: 12, color: textMuted)),
        ],
      ]),
    );
  }

  List<Widget> _myTeam(Map? team, List teamToday) {
    final boss = team?['manager'] as Map?;
    if (boss == null && teamToday.isEmpty) return const [];
    return [
      gap(12),
      heading('My team'),
      if (boss != null) hint('You report to ${boss['full_name'] ?? boss['username']}.'),
      for (final r in teamToday.cast<Map>())
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: RowCard(
            title: '${r['full_name'] ?? r['role']}',
            lines: [
              '${r['role']}',
              switch ('${r['state']}') {
                'in' => 'In since ${showTime((r['attendance'] as Map?)?['check_in'])}',
                'out' => 'In ${showTime((r['attendance'] as Map?)?['check_in'])} · Out ${showTime((r['attendance'] as Map?)?['check_out'])} · ${(r['attendance'] as Map?)?['total_hours'] ?? 0} h',
                _ => '',
              },
              if (r['off_site'] == true) '⚠ Away from the workshop',
            ],
            trailing: Text(teamStateWord(r['state']),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: teamStateColour(r['state']))),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).session;
    return Screen(
      title: 'Attendance',
      subtitle: s.canSell ? null : 'Your attendance history',
      body: Loader<_Data>(
        key: ValueKey(_gen),
        load: (api) => _load(api, s.canSell),
        builder: (c, d, reload) {
          final (users, records, today, places, team, teamToday) = d;
          // The open record (checked in, not out) of each person: the latest one.
          final open = <String, Map>{};
          for (final r in records.where((r) => r['check_out'] == null)) {
            final uid = '${r['user_id']}';
            if (open[uid] == null || '${r['check_in']}'.compareTo('${open[uid]!['check_in']}') >= 0) open[uid] = r;
          }
          final who = _user ?? (users.isEmpty ? null : '${users.first['id']}');
          return ListView(padding: const EdgeInsets.all(16), children: [
            _myDay(today, places),
            ..._myTeam(team, teamToday),
            if (s.canSell && users.isNotEmpty) ...[
              gap(12),
              WarmCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  DropdownButtonFormField<String>(
                    initialValue: who,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Select worker'),
                    items: [
                      for (final u in users)
                        DropdownMenuItem(
                            value: '${u['id']}', child: Text('${u['full_name'] ?? u['username']}')),
                    ],
                    onChanged: (v) => setState(() => _user = v),
                  ),
                  gap(),
                  Row(children: [
                    Expanded(
                      child: FilledButton(
                        onPressed: who == null || open.containsKey(who)
                            ? null
                            : () async {
                                final api = AppScope.of(context).session.api;
                                if (await guard(context,
                                    () async => api.postJson('/attendance/check-in', null, {'user_id': who}),
                                    done: 'Checked in')) {
                                  setState(() => _gen++);
                                }
                              },
                        child: const Text('Check in'),
                      ),
                    ),
                    if (s.isStaffLead) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: who == null || !open.containsKey(who)
                              ? null
                              : () async {
                                  final api = AppScope.of(context).session.api;
                                  if (await guard(
                                      context,
                                      () async => api.postJson('/attendance/check-out', null,
                                          {'attendance_id': '${open[who]!['id']}'}),
                                      done: 'Checked out')) {
                                    setState(() => _gen++);
                                  }
                                },
                          child: const Text('Check out'),
                        ),
                      ),
                    ],
                  ]),
                ]),
              ),
            ],
            gap(12),
            heading('Recent attendance'),
            if (records.isEmpty) hint('No attendance recorded yet.'),
            for (final r in records.take(60))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowCard(
                  title: '${(r['user'] as Map?)?['full_name'] ?? 'You'} · ${showDate(r['date'])}',
                  lines: [
                    'In ${showTime(r['check_in'])} · Out ${showTime(r['check_out'])} · ${r['total_hours'] ?? 0} h',
                    if (r['location_status'] == 'off_site' || r['check_out_location_status'] == 'off_site') '⚠ Away from the workshop',
                  ],
                  trailing: r['check_out'] == null
                      ? const StatusChip('In', okGreen)
                      : Text(rupees(((r['wage_entry'] as Map?) ?? const {})['amount']),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
          ]);
        },
      ),
    );
  }
}
