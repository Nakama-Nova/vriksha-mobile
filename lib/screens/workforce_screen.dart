import 'package:flutter/material.dart';

import '../kit.dart';
import '../theme.dart';
import '../widgets.dart';

/// Workforce: check people in and out (owner, manager, counter) and the attendance log.
/// Everyone else sees only their own history.
class WorkforceScreen extends StatefulWidget {
  const WorkforceScreen({super.key});
  @override
  State<WorkforceScreen> createState() => _WorkforceScreenState();
}

class _WorkforceScreenState extends State<WorkforceScreen> {
  int _gen = 0;
  String? _user;

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context).session;
    return Screen(
      title: 'Workforce',
      subtitle: s.canSell ? null : 'Your attendance history',
      body: Loader<(List, List)>(
        key: ValueKey(_gen),
        load: (api) async => s.canSell
            ? (await api.getJson('/auth/') as List, await api.getJson('/attendance/all') as List)
            : (const [], await api.getJson('/attendance/my') as List),
        builder: (c, d, reload) {
          final (users, records) = d;
          // The open record (checked in, not out) of each person: the latest one.
          final open = <String, Map>{};
          for (final r in records.where((r) => r['check_out'] == null)) {
            final uid = '${r['user_id']}';
            if (open[uid] == null || '${r['check_in']}'.compareTo('${open[uid]!['check_in']}') >= 0) open[uid] = r;
          }
          final who = _user ?? (users.isEmpty ? null : '${users.first['id']}');
          return ListView(padding: const EdgeInsets.all(16), children: [
            if (s.canSell && users.isNotEmpty) ...[
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
            heading('Recent attendance'),
            if (records.isEmpty) hint('No attendance recorded yet.'),
            for (final r in records.take(60))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowCard(
                  title: '${(r['user'] as Map?)?['full_name'] ?? 'You'} · ${showDate(r['date'])}',
                  lines: [
                    'In ${showTime(r['check_in'])} · Out ${showTime(r['check_out'])} · ${r['total_hours'] ?? 0} h',
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
