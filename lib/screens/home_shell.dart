import 'package:flutter/material.dart';

import '../session.dart';
import 'more_screen.dart';
import 'scans_screen.dart';

/// Two tabs, like the design's bottom bar: Scans and More.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.session, required this.onSignOut});
  final Session session;
  final VoidCallback onSignOut;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: IndexedStack(index: _tab, children: [
          ScansScreen(session: widget.session, onSignOut: widget.onSignOut),
          MoreScreen(session: widget.session, onSignOut: widget.onSignOut),
        ]),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE8DCC8)))),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.view_in_ar_outlined),
                selectedIcon: Icon(Icons.view_in_ar),
                label: 'Scans',
              ),
              NavigationDestination(
                icon: Icon(Icons.more_horiz),
                selectedIcon: Icon(Icons.more_horiz),
                label: 'More',
              ),
            ],
          ),
        ),
      );
}
