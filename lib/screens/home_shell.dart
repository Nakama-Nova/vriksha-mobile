import 'dart:async';

import 'package:flutter/material.dart';

import '../alerts.dart';
import '../kit.dart';
import '../modules.dart';
import '../notices.dart';
import '../session.dart';
import '../shop_status.dart';
import '../theme.dart';
import 'notices_screen.dart';
import 'staff_screen.dart' show changeMyPassword;

// The desktop's sidebar colours (ui/theme.py).
const _sideBg = brandBrown;
const _sideHover = Color(0xFF6E3A12);
const _sideActive = Color(0xFF7A4620);
const _sideText = lineColor;

/// Alerts is not one of the desktop's screens: every role has it, after the desktop's.
const _alerts = 'alerts';

/// The desktop's window as a phone: the same sidebar (brand header, the same screens in
/// the same order, shown or hidden by role, Alerts, My password, Sign Out) in a slide-out
/// menu, with the chosen screen filling the page.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.session, required this.onSignOut, this.status});
  final Session session;
  final VoidCallback onSignOut;
  final ShopStatus? status; // tests pass their own

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  String _id = 'home';
  // A screen is built the first time it is opened and then kept, so signing in never
  // waits on every screen's data at once.
  final _opened = <String>{'home'};
  late final ShopStatus _status;
  late final bool _ownsStatus;

  List<Module> get _allowed => [for (final m in modules) if (widget.session.allows(m.id)) m];

  @override
  void initState() {
    super.initState();
    _ownsStatus = widget.status == null;
    _status = widget.status ?? ShopStatus(widget.session, onFresh: _showFresh);
    if (_ownsStatus) unawaited(_start());
  }

  Future<void> _start() async {
    try {
      // a tap on a notification opens the right screen, also when it started the app
      await SystemAlerts.instance.init(onTap: _tapped);
      final launched = await SystemAlerts.instance.launchPayload();
      if (launched != null) _tapped(launched);
    } catch (_) {
      // no notification system here: the open app still shows everything
    }
    await _status.start();
  }

  @override
  void dispose() {
    if (_ownsStatus) _status.dispose();
    super.dispose();
  }

  void _go(String id) {
    if (id != _alerts && !widget.session.allows(id)) return;
    setState(() {
      _id = id;
      _opened.add(id);
    });
    if (id == _alerts) _status.markRead();
  }

  /// The screen a notice is about (null: just the Alerts list).
  String? _screenFor(String? what) => switch (what) {
        'restoration' => 'lab',
        'stock' => 'stock',
        _ => null,
      };

  void _tapped(String? payload) {
    if (!mounted) return;
    final screen = _screenFor(payload);
    _go(screen != null && widget.session.allows(screen) ? screen : _alerts);
  }

  void _openNotice(Notice n) {
    final screen = _screenFor(n.screen);
    if (screen != null) _go(screen);
  }

  /// The app is open, so show new things as a bar instead of a system notification.
  void _showFresh(List<Notice> fresh) {
    if (!mounted) return;
    final text = fresh.length == 1 ? fresh.first.title : '${fresh.length} new notifications';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        action: SnackBarAction(label: 'View', onPressed: () => _go(_alerts)),
      ));
  }

  Widget _navButton(String id, Widget label) {
    final active = id == _id;
    return InkWell(
      onTap: () {
        Navigator.pop(context); // close the menu
        _go(id);
      },
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 17),
        decoration: BoxDecoration(
          color: active ? _sideActive : null,
          border: Border(left: BorderSide(width: 3, color: active ? brandGold : Colors.transparent)),
        ),
        alignment: Alignment.centerLeft,
        child: DefaultTextStyle(
          style: TextStyle(
            fontSize: 15,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? Colors.white : _sideText,
          ),
          child: label,
        ),
      ),
    );
  }

  Widget _footerButton(String text, VoidCallback onTap, {Color color = _sideText}) => InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: _sideHover))),
          child: Text(text, style: TextStyle(fontSize: 14, color: color)),
        ),
      );

  Widget _drawer(BuildContext context) => Drawer(
        backgroundColor: _sideBg,
        shape: const RoundedRectangleBorder(),
        child: SafeArea(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _sideHover))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Vriksha Studio', style: serif(26, color: surfaceWarm)),
                const SizedBox(height: 2),
                Text('Staff desk · ${widget.session.username}',
                    style: const TextStyle(fontSize: 12, color: _sideText)),
              ]),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(padding: EdgeInsets.zero, children: [
                for (final m in _allowed) _navButton(m.id, Text('${m.emoji}   ${m.label}')),
              ]),
            ),
            // pinned under the list, so it is in reach however many screens the role has
            ListenableBuilder(
              listenable: _status,
              builder: (context, _) => _navButton(
                _alerts,
                Row(children: [
                  const Text('🔔   Alerts'),
                  if (_status.unread > 0) ...[
                    const SizedBox(width: 10),
                    Badge(label: Text('${_status.unread}'), backgroundColor: brandGold),
                  ],
                ]),
              ),
            ),
            _footerButton('🔑  My password', () {
              Navigator.pop(context);
              changeMyPassword(context);
            }),
            _footerButton('📄  Licences  ·  v1', () {
              Navigator.pop(context);
              showLicensePage(
                context: context,
                applicationName: 'Vriksha Studio',
                applicationLegalese: 'Copyright (c) 2026 Nakama Nova. All rights reserved. Proprietary software.',
              );
            }),
            _footerButton('🚪  Sign Out', widget.onSignOut, color: _sideText),
          ]),
        ),
      );

  Widget _updateBanner() => ListenableBuilder(
        listenable: _status,
        builder: (context, _) {
          final u = _status.update;
          if (u == null) return const SizedBox.shrink();
          return Material(
            color: const Color(0xFFFBF6EC),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(children: [
                  Expanded(
                    child: Text('Version ${u.version} is available',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ),
                  TextButton(onPressed: _status.openUpdate, child: const Text('Download')),
                  TextButton(onPressed: _status.putOffUpdate, child: const Text('Later')),
                ]),
              ),
            ),
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final ids = [..._allowed.map((m) => m.id), _alerts];
    return AppScope(
      session: widget.session,
      onSignOut: widget.onSignOut,
      go: _go,
      menu: () => _scaffold.currentState?.openDrawer(),
      child: Builder(
        builder: (context) => PopScope(
          // Back from any screen goes Home first, as a phone user expects.
          canPop: _id == 'home',
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _go('home');
          },
          child: Scaffold(
            key: _scaffold,
            drawer: _drawer(context),
            body: Column(children: [
              _updateBanner(),
              Expanded(
                child: IndexedStack(
                  index: ids.indexOf(_id),
                  children: [
                    for (final m in _allowed) _opened.contains(m.id) ? m.build(context) : const SizedBox.shrink(),
                    NoticesScreen(status: _status, onOpen: _openNotice),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
