import 'package:flutter/material.dart';

import '../kit.dart';
import '../theme.dart';
import '../widgets.dart';

const _roles = <(String, Object?)>[
  ('Owner', 'owner'),
  ('Manager', 'manager'),
  ('Sales', 'sales'),
  ('Achari (carpenter)', 'achari'),
  ('Worker', 'worker'),
];
final roleWords = {for (final r in _roles) r.$2 as String: r.$1};
const _minPassword = 8;

/// Change your own password (reachable from More, for every role).
Future<void> changeMyPassword(BuildContext context) async {
  final v = await showForm(context, 'My password', [
    const F('current', 'Current password', kind: K.password, required: true),
    const F('new', 'New password (8 or more characters)', kind: K.password, required: true),
    const F('repeat', 'Repeat new password', kind: K.password, required: true),
  ]);
  if (v == null || !context.mounted) return;
  if ('${v['new']}'.length < _minPassword) return snack(context, 'Use at least $_minPassword characters.');
  if (v['new'] != v['repeat']) return snack(context, 'The two new passwords are not the same.');
  final api = AppScope.of(context).session.api;
  await guard(context, () async => api.postJson('/auth/me/password', {'current_password': v['current'], 'new_password': v['new']}),
      done: 'Password changed');
}

/// Staff accounts (owner only): add, edit, switch on/off, reset a password.
class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});
  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  int _gen = 0;
  String? _me;

  Future<void> _save([Map? u]) async {
    final adding = u == null;
    final v = await showForm(context, adding ? 'Add staff' : 'Edit ${u['username']}', [
      if (adding) const F('username', 'Username', required: true),
      F('full_name', 'Name', initial: u?['full_name']),
      F('email', 'Email', initial: u?['email'], required: true),
      F('phone', 'Phone', initial: u?['phone']),
      if (u == null || u['id'] != _me) F('role', 'Role', kind: K.choice, choices: _roles, initial: u?['role'] ?? 'worker'),
      F('base_daily_wage', 'Daily wage', kind: K.money, initial: u?['base_daily_wage']),
      F('overtime_rate_per_hour', 'Overtime rate per hour', kind: K.money, initial: u?['overtime_rate_per_hour']),
      if (adding) const F('password', 'Password (8 or more characters)', kind: K.password, required: true),
    ]);
    if (v == null || !mounted) return;
    if (!'${v['email']}'.contains('@')) return snack(context, 'Enter a valid email.');
    if (adding && '${v['password']}'.length < _minPassword) return snack(context, 'Use at least $_minPassword characters.');
    final body = {...v, 'base_daily_wage': v['base_daily_wage'] ?? 0};
    final api = AppScope.of(context).session.api;
    if (await guard(context, () async => adding ? api.postJson('/auth/register', body) : api.patchJson('/auth/users/${u['id']}', body),
        done: 'Saved')) {
      setState(() => _gen++);
    }
  }

  Future<void> _reset(Map u) async {
    final v = await showForm(context, 'New password for ${u['username']}',
        [const F('password', 'New password (8 or more characters)', kind: K.password, required: true)],
        ok: 'Reset');
    if (v == null || !mounted) return;
    if ('${v['password']}'.length < _minPassword) return snack(context, 'Use at least $_minPassword characters.');
    final api = AppScope.of(context).session.api;
    await guard(context, () async => api.postJson('/auth/users/${u['id']}/reset-password', {'new_password': v['password']}),
        done: 'Password reset');
  }

  Future<void> _toggle(Map u) async {
    final off = u['is_active'] == true;
    if (!await confirm(context, off ? 'Switch off' : 'Switch on',
            off ? '${u['username']} will no longer be able to sign in.' : '${u['username']} can sign in again.') ||
        !mounted) {
      return;
    }
    final api = AppScope.of(context).session.api;
    if (await guard(context, () async => api.patchJson('/auth/users/${u['id']}', {'is_active': !off}))) {
      setState(() => _gen++);
    }
  }

  @override
  Widget build(BuildContext context) => Screen(
        title: 'Staff',
        fab: addFab('Add staff', _save),
        body: Loader<List>(
          key: ValueKey(_gen),
          load: (api) async {
            _me = '${(await api.getJson('/auth/me') as Map)['id']}';
            final rows = [...(await api.getJson('/auth/') as List)];
            rows.sort((a, b) => a['is_active'] == b['is_active']
                ? '${a['username']}'.compareTo('${b['username']}')
                : (a['is_active'] == true ? -1 : 1));
            return rows;
          },
          builder: (c, rows, reload) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 90), children: [
            for (final u in rows)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: RowCard(
                  title: '${u['full_name'] ?? u['username']}${u['id'] == _me ? '  (you)' : ''}',
                  lines: [
                    '${u['username']} · ${roleWords['${u['role']}'] ?? u['role']}',
                    '${u['phone'] ?? ''}',
                    'Daily wage ${rupees(u['base_daily_wage'], dp: 0)}',
                  ],
                  trailing: u['is_active'] == true ? const StatusChip('Active', okGreen) : const StatusChip('Switched off', textMuted),
                  onTap: () => actionSheet(context, '${u['username']}', [
                    ('Edit', () => _save(u)),
                    ('Reset password', () => _reset(u)),
                    if (u['id'] != _me) (u['is_active'] == true ? 'Switch off' : 'Switch on', () => _toggle(u)),
                  ]),
                ),
              ),
          ]),
        ),
      );
}
