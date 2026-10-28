import 'dart:async';

import 'package:flutter/material.dart';

import '../alerts.dart';
import '../notices.dart';
import '../session.dart';
import '../shop_status.dart';
import '../theme.dart';
import 'more_screen.dart';
import 'notices_screen.dart';
import 'scans_screen.dart';

/// Three tabs, like the design's bottom bar: Scans, Alerts and More.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.session, required this.onSignOut, this.status});
  final Session session;
  final VoidCallback onSignOut;
  final ShopStatus? status; // tests pass their own

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  late final ShopStatus _status;
  late final bool _ownsStatus;

  @override
  void initState() {
    super.initState();
    _ownsStatus = widget.status == null;
    _status = widget.status ?? ShopStatus(widget.session, onFresh: _showFresh);
    if (_ownsStatus) unawaited(_start());
  }

  Future<void> _start() async {
    try {
      // a tap on a notification opens the right tab, also when it started the app
      await SystemAlerts.instance.init(onTap: _tapped);
      final launched = await SystemAlerts.instance.launchPayload();
      if (launched != null) _tapped(launched);
    } catch (_) {
      // no notification system here: the open app still shows everything
    }
    await _status.start();
  }

  void _tapped(String? payload) {
    if (!mounted) return;
    setState(() => _tab = (payload == 'restoration' || payload == 'stock') ? 0 : 1);
  }

  /// The app is open, so show new things as a bar instead of a system notification.
  void _showFresh(List<Notice> fresh) {
    if (!mounted) return;
    final text = fresh.length == 1 ? fresh.first.title : '${fresh.length} new notifications';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        action: SnackBarAction(label: 'View', onPressed: () => setState(() => _tab = 1)),
      ));
  }

  void _openNotice(Notice n) {
    if (n.screen == 'restoration' || n.screen == 'stock') setState(() => _tab = 0);
  }

  @override
  void dispose() {
    if (_ownsStatus) _status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          ListenableBuilder(
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
          ),
          Expanded(
            child: IndexedStack(index: _tab, children: [
              ScansScreen(session: widget.session, onSignOut: widget.onSignOut),
              NoticesScreen(status: _status, onOpen: _openNotice),
              MoreScreen(session: widget.session, onSignOut: widget.onSignOut),
            ]),
          ),
        ]),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE8DCC8)))),
          child: ListenableBuilder(
            listenable: _status,
            builder: (context, _) => NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) {
                setState(() => _tab = i);
                if (i == 1) _status.markRead();
              },
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.view_in_ar_outlined),
                  selectedIcon: Icon(Icons.view_in_ar),
                  label: 'Scans',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: _status.unread > 0,
                    label: Text('${_status.unread}'),
                    backgroundColor: brandGold,
                    child: const Icon(Icons.notifications_none),
                  ),
                  selectedIcon: const Icon(Icons.notifications),
                  label: 'Alerts',
                ),
                const NavigationDestination(
                  icon: Icon(Icons.more_horiz),
                  selectedIcon: Icon(Icons.more_horiz),
                  label: 'More',
                ),
              ],
            ),
          ),
        ),
      );
}
