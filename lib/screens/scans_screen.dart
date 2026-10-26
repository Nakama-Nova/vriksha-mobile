import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
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
    final waiting = scans?.where((s) => s.status == 'uploaded').length ?? 0;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: BrandAppBar(
        title: widget.session.isStaffLead ? 'All scans' : 'My scans',
        subtitle: waiting > 0 ? '$waiting waiting for the workshop PC' : null,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            FilledButton.icon(
              onPressed: _newScan,
              icon: const Icon(Icons.add_a_photo_outlined),
              label: const Text('New scan'),
            ),
            const SizedBox(height: 14),
            if (scans == null && _error != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_error!))
            else if (scans == null)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (scans.isEmpty)
              const WarmCard(
                child: Text('No scans yet. Tap "New scan" and walk around the piece taking photos.'),
              )
            else
              for (final s in scans) ...[
                _ScanCard(scan: s, onCancel: _cancel),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}

Color chipColor(String status) => switch (status) {
      'uploaded' => brandGold,
      'processing' => brandBrown,
      'done' => okGreen,
      'failed' => badRed,
      _ => textMuted,
    };

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.scan, required this.onCancel});
  final ScanJob scan;
  final void Function(ScanJob) onCancel;

  @override
  Widget build(BuildContext context) {
    final when = scan.createdAt;
    final date = '${when.day}/${when.month} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    final title = scan.itemName ?? 'Scan $date';
    final kind = scan.sourceKind == 'video' ? 'Video' : 'Photos';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600))),
            const SizedBox(width: 8),
            StatusChip(scan.statusLabel, chipColor(scan.status), fill: scan.status == 'processing'),
          ]),
          const SizedBox(height: 8),
          Text(scan.sourceKind == 'video'
              ? 'Video  ·  ${sizeText(scan.sourceBytes)}'
              : '${scan.files} photos  ·  ${sizeText(scan.sourceBytes)}'),
          const SizedBox(height: 8),
          Text.rich(TextSpan(children: [
            TextSpan(text: kind, style: const TextStyle(color: brandGold, fontWeight: FontWeight.w500)),
            TextSpan(text: '   $date', style: const TextStyle(color: textMuted)),
          ]), style: const TextStyle(fontSize: 11)),
          if (scan.status == 'processing') ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: scan.progress / 100,
              color: brandBrown,
              backgroundColor: lineColor,
              borderRadius: BorderRadius.circular(4),
            ),
            if (scan.note != null)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text(scan.note!, style: const TextStyle(fontSize: 12, color: textMuted))),
          ],
          if (scan.status == 'failed' && scan.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(scan.error!, style: const TextStyle(fontSize: 13, color: badRed)),
            ),
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
