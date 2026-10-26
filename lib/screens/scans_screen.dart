import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../session.dart';
import 'new_scan_screen.dart';

String sizeText(int bytes) => bytes >= 1024 * 1024 * 1024
    ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
    : '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';

class ScansScreen extends StatefulWidget {
  const ScansScreen({super.key, required this.session, required this.onSignOut});
  final Session session;
  final VoidCallback onSignOut;

  @override
  State<ScansScreen> createState() => _ScansScreenState();
}

class _ScansScreenState extends State<ScansScreen> {
  List<ScanJob>? _scans;
  String? _error;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // keep the progress of a scan being processed fresh while this screen is open
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final scans = await widget.session.api.scans();
      if (!mounted) return;
      setState(() {
        _scans = scans;
        _error = null;
      });
    } on ApiException catch (e) {
      if (e.status == 401) {
        widget.onSignOut();
        return;
      }
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _cancel(ScanJob s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Cancel this scan?'),
        content: const Text('Its photos are removed from the server.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cancel scan')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.session.api.cancel(s.id);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    _load();
  }

  Future<void> _newScan() async {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NewScanScreen(session: widget.session)),
    );
    if (done == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final scans = _scans;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.session.isStaffLead ? 'All scans' : 'My scans'),
        actions: [
          IconButton(
            tooltip: 'Licences',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showLicensePage(
                context: context,
                applicationName: 'Vriksha Capture',
                applicationLegalese: 'MIT License. Copyright (c) 2026 Nakama Nova'),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: widget.onSignOut,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newScan,
        icon: const Icon(Icons.add_a_photo),
        label: const Text('New scan'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: scans == null
            ? ListView(children: [
                if (_error != null)
                  Padding(padding: const EdgeInsets.all(24), child: Text(_error!))
                else
                  const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(child: CircularProgressIndicator())),
              ])
            : scans.isEmpty
                ? ListView(children: const [
                    Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('No scans yet. Tap "New scan" and walk around the piece taking photos.'))
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: scans.length,
                    itemBuilder: (_, i) => _ScanCard(scan: scans[i], onCancel: _cancel),
                  ),
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.scan, required this.onCancel});
  final ScanJob scan;
  final void Function(ScanJob) onCancel;

  @override
  Widget build(BuildContext context) {
    final when = scan.createdAt;
    final title = scan.itemName ??
        'Scan ${when.day}/${when.month} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            '${scan.sourceKind == 'video' ? 'Video' : '${scan.files} photos'} · ${sizeText(scan.sourceBytes)}',
            style: const TextStyle(color: Color(0xFF7A5A3C)),
          ),
          const SizedBox(height: 8),
          Text(scan.statusLabel,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: scan.status == 'failed' ? scheme.error : scheme.primary)),
          if (scan.status == 'processing') ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: scan.progress / 100),
            if (scan.note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(scan.note!)),
          ],
          if (scan.status == 'failed' && scan.error != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text(scan.error!)),
          if (scan.canCancel)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: () => onCancel(scan), child: const Text('Cancel')),
            ),
        ]),
      ),
    );
  }
}
