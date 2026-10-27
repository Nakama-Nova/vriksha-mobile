import 'package:flutter/material.dart';

import '../session.dart';
import '../theme.dart';
import '../widgets.dart';

/// Who is signed in, which server, licences, and Sign out (the design's "More").
class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, required this.session, required this.onSignOut});
  final Session session;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.white,
        appBar: const BrandAppBar(title: 'More'),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          WarmCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text('Signed in', style: TextStyle(fontWeight: FontWeight.w600)),
                StatusChip(session.role.isEmpty ? 'staff' : session.role, okGreen),
              ]),
              const SizedBox(height: 8),
              Text(session.username, style: const TextStyle(fontSize: 15)),
              const SizedBox(height: 2),
              Text(session.baseUrl, style: const TextStyle(fontSize: 12, color: textMuted)),
            ]),
          ),
          const SizedBox(height: 12),
          _Row(
            title: 'Licences',
            subtitle: 'Open-source packages in this app',
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Vriksha Capture',
              applicationLegalese: 'Copyright (c) 2026 Nakama Nova. All rights reserved. Proprietary software.',
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton(onPressed: onSignOut, child: const Text('Sign out')),
          const SizedBox(height: 12),
          const Center(
            child: Text('Vriksha Capture · v1', style: TextStyle(fontSize: 12, color: textMuted)),
          ),
        ]),
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, required this.subtitle, required this.onTap});
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: const TextStyle(fontSize: 12, color: textMuted)),
                ]),
              ),
              const Text('›', style: TextStyle(fontSize: 20, color: brandGold)),
            ]),
          ),
        ),
      );
}
