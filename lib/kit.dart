import 'dart:math';

import 'package:flutter/material.dart';

import 'api.dart';
import 'session.dart';
import 'theme.dart';
import 'widgets.dart';

/// The signed-in session and app-wide actions, for every screen below the shell.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.session,
    required this.onSignOut,
    required this.go,
    required this.menu,
    required super.child,
  });
  final Session session;
  final VoidCallback onSignOut;

  /// Open a module by id (a tab, or a pushed screen), e.g. from Home's quick actions.
  final void Function(String module) go;

  /// Open the sidebar.
  final VoidCallback menu;

  static AppScope of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<AppScope>()!;
  @override
  bool updateShouldNotify(AppScope old) => session != old.session;
}

/// Open a screen on top of the shell. Routes sit above the shell in the widget tree,
/// so the scope is handed on to the new screen.
Future<T?> pushScoped<T>(BuildContext c, Widget screen) {
  final s = AppScope.of(c);
  return Navigator.of(c).push<T>(MaterialPageRoute(
      builder: (_) => AppScope(session: s.session, onSignOut: s.onSignOut, go: s.go, menu: s.menu, child: screen)));
}

// ---- numbers and dates (same look as the desktop: ₹1,234.50, 05 Mar 2026) ----

num numOf(Object? v) => num.tryParse('${v ?? 0}') ?? 0;

String rupees(Object? v, {int dp = 2}) {
  final n = numOf(v);
  final parts = n.abs().toStringAsFixed(dp).split('.');
  final grouped = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${n < 0 ? '-' : ''}₹$grouped${dp > 0 ? '.${parts[1]}' : ''}';
}

String isoDate(DateTime d) => d.toIso8601String().substring(0, 10);

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String niceDate(DateTime d) => '${d.day.toString().padLeft(2, '0')} ${_months[d.month - 1]} ${d.year}';

/// "2026-03-05T10:20:00Z" -> "05 Mar 2026"; anything else is shown as given.
String showDate(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}');
  return d == null ? '${iso ?? ''}' : niceDate(d.toLocal());
}

String showTime(Object? iso) {
  final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
  return d == null
      ? '—'
      : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// The desktop's period picker: (start, end) as ISO dates; (null, null) = everything.
const periods = [
  ('This month', 'month'),
  ('Last month', 'last_month'),
  ('This year', 'year'),
  ('All time', 'all'),
];

(String?, String?) periodRange(String key, [DateTime? now]) {
  final today = now ?? DateTime.now();
  final first = DateTime(today.year, today.month, 1);
  switch (key) {
    case 'month':
      return (isoDate(first), isoDate(today));
    case 'last_month':
      final end = first.subtract(const Duration(days: 1));
      return (isoDate(DateTime(end.year, end.month, 1)), isoDate(end));
    case 'year':
      return (isoDate(DateTime(today.year, 1, 1)), isoDate(today));
  }
  return (null, null);
}

/// An id the server uses to ignore a bill it has already recorded (retry safety).
String newClientId() {
  final r = Random.secure();
  String h(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${h(8)}-${h(4)}-4${h(3)}-${'89ab'[r.nextInt(4)]}${h(3)}-${h(12)}';
}

// ---- feedback -------------------------------------------------------------

void snack(BuildContext c, String message) => ScaffoldMessenger.of(c)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

Future<bool> confirm(BuildContext c, String title, String message, {String ok = 'Yes'}) async =>
    await showDialog<bool>(
      context: c,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
        ],
      ),
    ) ??
    false;

/// Run a server call; show the server's own reason if it fails. A rejected login
/// (401) is left to Session.expire(), which is already signing out with its notice.
/// True when the call went through.
Future<bool> guard(BuildContext c, Future<void> Function() call, {String? done}) async {
  try {
    await call();
    if (done != null && c.mounted) snack(c, done);
    return true;
  } on ApiException catch (e) {
    if (e.status != 401 && c.mounted) snack(c, e.message);
    return false;
  }
}

// ---- screens --------------------------------------------------------------

/// Brown bar + body; shows "← Back" when the screen was opened from another.
class Screen extends StatelessWidget {
  const Screen({super.key, required this.title, this.subtitle, required this.body, this.fab});
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? fab;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: BrandAppBar(
          title: title,
          subtitle: subtitle,
          back: Navigator.canPop(context),
          onMenu: Navigator.canPop(context) ? null : AppScope.of(context).menu,
        ),
        floatingActionButton: fab,
        body: body,
      );
}

Widget addFab(String label, VoidCallback onTap) => FloatingActionButton.extended(
      onPressed: onTap,
      backgroundColor: brandBrown,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add),
      label: Text(label),
    );

/// Loads on open, pull to refresh, and a plain error with Retry. Give it a new
/// `key` to load again (e.g. when a filter changes). [builder] returns a ListView.
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});
  final Future<T> Function(ApiClient api) load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload) builder;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  T? _data;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_data == null && _error == null) _reload();
  }

  Future<void> _reload() async {
    final scope = AppScope.of(context);
    try {
      final d = await widget.load(scope.session.api);
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (e.status == 401) return; // Session.expire() is already signing out, with its notice
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data != null) {
      return RefreshIndicator(
        color: brandBrown,
        onRefresh: _reload,
        child: widget.builder(context, _data as T, _reload),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: badRed)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                setState(() => _error = null);
                _reload();
              },
              child: const Text('Try again'),
            ),
          ]),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}

/// A label + big number tile (Home, Reports, Profit).
class Metric extends StatelessWidget {
  const Metric(this.label, this.value, {super.key, this.color = brandBrown});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: lineColor),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: textMuted)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: serif(26, color: color)),
          ),
        ]),
      );
}

/// Metrics laid out two to a row.
Widget metricGrid(List<Metric> tiles) => GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.7,
      children: tiles,
    );

/// A tappable outlined row card: title, optional lines, optional trailing widget.
class RowCard extends StatelessWidget {
  const RowCard({super.key, required this.title, this.lines = const [], this.trailing, this.onTap});
  final String title;
  final List<String> lines;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  for (final l in lines.where((l) => l.isNotEmpty))
                    Text(l, style: const TextStyle(fontSize: 12, color: textMuted)),
                ]),
              ),
              ?trailing,
            ]),
          ),
        ),
      );
}

Widget gap([double h = 10]) => SizedBox(height: h);

Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: serif(22)),
    );

Widget hint(String text) =>
    Text(text, style: const TextStyle(fontSize: 12, color: textMuted));

Widget searchBox(ValueChanged<String> onChanged, [String label = 'Search']) => TextField(
      onChanged: onChanged,
      decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.search)),
    );

/// Period dropdown shared by Expenses, Profit.
class PeriodPicker extends StatelessWidget {
  const PeriodPicker({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: value,
        decoration: const InputDecoration(labelText: 'Period'),
        items: [for (final p in periods) DropdownMenuItem(value: p.$2, child: Text(p.$1))],
        onChanged: (v) => v == null ? null : onChanged(v),
      );
}

/// Pick one of several actions from a bottom sheet.
Future<void> actionSheet(BuildContext c, String title, List<(String, VoidCallback)> actions) =>
    showModalBottomSheet<void>(
      context: c,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: serif(22)),
          ),
          for (final a in actions)
            ListTile(
              title: Text(a.$1),
              onTap: () {
                Navigator.pop(ctx);
                a.$2();
              },
            ),
        ]),
      ),
    );

// ---- forms ----------------------------------------------------------------

/// [optDate] is a date that may be left empty ("Not set"); [date] starts at today.
enum K { text, multiline, password, money, number, date, optDate, choice, flag }

/// One form field. [choices] are (label, value) pairs for K.choice.
class F {
  const F(this.key, this.label,
      {this.kind = K.text, this.initial, this.choices = const [], this.required = false, this.hint});
  final String key;
  final String label;
  final K kind;
  final Object? initial;
  final List<(String, Object?)> choices;
  final bool required;
  final String? hint;
}

/// A bottom-sheet form. Returns the values by key (blank text = null, money/number
/// parsed, date as ISO), or null if cancelled. Required fields are checked here.
Future<Map<String, Object?>?> showForm(BuildContext c, String title, List<F> fields,
        {String ok = 'Save'}) =>
    showModalBottomSheet<Map<String, Object?>>(
      context: c,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FormSheet(title: title, fields: fields, ok: ok),
    );

class _FormSheet extends StatefulWidget {
  const _FormSheet({required this.title, required this.fields, required this.ok});
  final String title;
  final List<F> fields;
  final String ok;
  @override
  State<_FormSheet> createState() => _FormSheetState();
}

class _FormSheetState extends State<_FormSheet> {
  final _text = <String, TextEditingController>{};
  final _value = <String, Object?>{};
  String? _problem;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      switch (f.kind) {
        case K.date:
        case K.optDate:
        case K.choice:
        case K.flag:
          _value[f.key] = f.initial ?? (f.kind == K.flag ? false : (f.kind == K.date ? isoDate(DateTime.now()) : null));
        default:
          final v = f.initial;
          _text[f.key] = TextEditingController(
              text: v == null || (v is num && v == 0 && f.kind == K.money) ? '' : '$v');
      }
    }
  }

  @override
  void dispose() {
    for (final t in _text.values) {
      t.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final out = <String, Object?>{};
    for (final f in widget.fields) {
      Object? v;
      switch (f.kind) {
        case K.date || K.optDate || K.choice || K.flag:
          v = _value[f.key];
        case K.money:
          v = double.tryParse(_text[f.key]!.text.trim());
        case K.number:
          final raw = _text[f.key]!.text.trim();
          v = int.tryParse(raw) ?? double.tryParse(raw);
        default:
          final s = _text[f.key]!.text.trim();
          v = s.isEmpty ? null : s;
      }
      if (f.required && (v == null || (f.kind == K.money && (v as double) <= 0))) {
        return setState(() => _problem = '${f.label}: please fill this in.');
      }
      out[f.key] = v;
    }
    Navigator.pop(context, out);
  }

  Widget _field(F f) {
    switch (f.kind) {
      case K.date:
        final d = DateTime.tryParse('${_value[f.key]}') ?? DateTime.now();
        return InkWell(
          onTap: () async {
            final p = await showDatePicker(
                context: context,
                initialDate: d,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100));
            if (p != null) setState(() => _value[f.key] = isoDate(p));
          },
          child: InputDecorator(
            decoration: InputDecoration(labelText: f.label, suffixIcon: const Icon(Icons.calendar_today, size: 18)),
            child: Text(niceDate(d)),
          ),
        );
      case K.optDate:
        final set = DateTime.tryParse('${_value[f.key]}');
        return InkWell(
          onTap: () async {
            final p = await showDatePicker(
                context: context,
                initialDate: set ?? DateTime.now(),
                firstDate: DateTime(1990),
                lastDate: DateTime(2100));
            if (p != null) setState(() => _value[f.key] = isoDate(p));
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: f.label,
              suffixIcon: set == null
                  ? const Icon(Icons.calendar_today, size: 18)
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Clear the date',
                      onPressed: () => setState(() => _value[f.key] = null),
                    ),
            ),
            child: Text(set == null ? 'Not set' : niceDate(set), style: TextStyle(color: set == null ? textMuted : null)),
          ),
        );
      case K.choice:
        return DropdownButtonFormField<Object?>(
          initialValue: _value[f.key],
          isExpanded: true,
          decoration: InputDecoration(labelText: f.label + (f.required ? ' *' : '')),
          items: [for (final ch in f.choices) DropdownMenuItem(value: ch.$2, child: Text(ch.$1, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _value[f.key] = v),
        );
      case K.flag:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          value: _value[f.key] == true,
          onChanged: (v) => setState(() => _value[f.key] = v),
        );
      default:
        final numeric = f.kind == K.money || f.kind == K.number;
        return TextField(
          controller: _text[f.key],
          obscureText: f.kind == K.password,
          maxLines: f.kind == K.multiline ? 3 : 1,
          keyboardType: numeric
              ? const TextInputType.numberWithOptions(decimal: true, signed: true)
              : (f.kind == K.multiline ? TextInputType.multiline : TextInputType.text),
          decoration: InputDecoration(
            labelText: f.label + (f.required ? ' *' : ''),
            hintText: f.hint,
            prefixText: f.kind == K.money ? '₹ ' : null,
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.title, style: serif(24)),
            gap(12),
            for (final f in widget.fields) ...[_field(f), gap(12)],
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_problem!, style: const TextStyle(color: badRed, fontSize: 13)),
              ),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(child: FilledButton(onPressed: _submit, child: Text(widget.ok))),
            ]),
          ]),
        ),
      );
}

/// A small "key: value" row for detail sheets.
Widget kv(String k, String v, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(k, style: const TextStyle(color: textMuted))),
        Text(v, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      ]),
    );

/// A read-only sheet of widgets (bill lines, purchase lines, stock history).
Future<void> infoSheet(BuildContext c, String title, List<Widget> children) =>
    showModalBottomSheet<void>(
      context: c,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        builder: (_, ctl) => ListView(
          controller: ctl,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [Text(title, style: serif(24)), gap(8), ...children],
        ),
      ),
    );
