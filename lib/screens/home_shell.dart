import 'package:flutter/material.dart';

import '../kit.dart';
import '../modules.dart';
import '../session.dart';
import '../theme.dart';
import 'staff_screen.dart' show changeMyPassword;

// The desktop's sidebar colours (ui/theme.py).
const _sideBg = brandBrown;
const _sideHover = Color(0xFF6E3A12);
const _sideActive = Color(0xFF7A4620);
const _sideText = lineColor;

/// The desktop's window as a phone: the same sidebar (brand header, the same screens in
/// the same order, shown or hidden by role, My password, Sign Out) in a slide-out menu,
/// with the chosen screen filling the page.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.session, required this.onSignOut});
  final Session session;
  final VoidCallback onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  String _id = 'home';
  // A screen is built the first time it is opened and then kept, so signing in never
  // waits on every screen's data at once.
  final _opened = <String>{'home'};

  List<Module> get _allowed => [for (final m in modules) if (widget.session.allows(m.id)) m];

  void _go(String id) {
    if (!widget.session.allows(id)) return;
    setState(() {
      _id = id;
      _opened.add(id);
    });
  }

  Widget _navButton(Module m) {
    final active = m.id == _id;
    return InkWell(
      onTap: () {
        Navigator.pop(context); // close the menu
        _go(m.id);
      },
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 17),
        decoration: BoxDecoration(
          color: active ? _sideActive : null,
          border: Border(left: BorderSide(width: 3, color: active ? brandGold : Colors.transparent)),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          '${m.emoji}   ${m.label}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? Colors.white : _sideText,
          ),
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
            Expanded(child: ListView(padding: EdgeInsets.zero, children: [for (final m in _allowed) _navButton(m)])),
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

  @override
  Widget build(BuildContext context) {
    final allowed = _allowed;
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
            body: IndexedStack(
              index: allowed.indexWhere((m) => m.id == _id),
              children: [
                for (final m in allowed) _opened.contains(m.id) ? m.build(context) : const SizedBox.shrink(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
