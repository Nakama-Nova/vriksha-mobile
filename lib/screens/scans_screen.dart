import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../kit.dart' show AppScope;
import '../session.dart';
import '../theme.dart';
import '../widgets.dart';
import '../uploader.dart';
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
  late final _store = PendingStore(widget.session.baseUrl, widget.session.username);
  PendingUpload? _pending; // an upload the app was closed or interrupted in the middle of
  double? _resuming;
  String? _resumeError;

  @override
  void initState() {
    super.initState();
    _store.load().then((p) {
      if (mounted) setState(() => _pending = p);
    });
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
      // The server moved on (finished, cancelled, or the "complete" reply was lost): nothing to resume.
      final p = _pending;
      if (p != null && _resuming == null && scans.any((s) => s.id == p.scanId && s.status != 'created')) {
        await _store.clear();
        _pending = null;
      }
      if (!mounted) return;
      setState(() {
        _scans = scans;
        _error = null;
      });
    } on ApiException catch (e) {
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
    final p = await _store.load(); // a failed upload leaves one behind
    if (mounted) setState(() => _pending = p);
    if (done == true) _load();
  }

  Future<void> _resume() async {
    final p = _pending;
    if (p == null) return;
    setState(() {
      _resuming = 0;
      _resumeError = null;
    });
    String? problem;
    try {
      await ScanUploader(widget.session.api, store: _store).resume(p.scanId, p.files, onProgress: (f) {
        if (mounted) setState(() => _resuming = f);
      });
    } on UploadFailed catch (e) {
      problem = e.reason;
    } on ApiException catch (e) {
      problem = e.message;
    }
    final left = await _store.load(); // nothing left when it finished
    if (!mounted) return;
    setState(() {
      _pending = left;
      _resuming = null;
      _resumeError = problem;
    });
    _load();
  }

  Future<void> _discard() async {
    final p = _pending;
    if (p == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Discard this upload?'),
        content: const Text('What was already sent is removed from the server.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Discard')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.session.api.cancel(p.scanId);
    } on ApiException catch (e) {
      // 404/409: it is already gone or finished on the server, so only the phone's note is left
      if (e.status != 404 && e.status != 409) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        return;
      }
    }
    await _store.clear();
    if (mounted) setState(() => _pending = null);
    _load();
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
        onMenu: AppScope.of(context).menu,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_pending != null) ...[
              _PendingCard(
                pending: _pending!,
                progress: _resuming,
                error: _resumeError,
                onResume: _resume,
                onDiscard: _discard,
              ),
              const SizedBox(height: 14),
            ] else ...[
              FilledButton.icon(
                onPressed: _newScan,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('New scan'),
              ),
              const SizedBox(height: 14),
            ],
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

/// An upload that stopped half-way: send the rest, or throw it away.
class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.pending,
    required this.progress,
    required this.error,
    required this.onResume,
    required this.onDiscard,
  });
  final PendingUpload pending;
  final double? progress; // null when not sending right now
  final String? error;
  final VoidCallback onResume;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final busy = progress != null;
    return WarmCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Unfinished upload', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('${pending.sent} of ${pending.files.length} files sent. Send the rest to finish this scan.'),
        if (busy) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: progress,
            color: brandBrown,
            backgroundColor: lineColor,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 4),
          const Text('Keep the app open.', style: TextStyle(fontSize: 12, color: textMuted)),
        ],
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, style: const TextStyle(color: badRed, fontSize: 13)),
        ],
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: busy ? null : onDiscard, child: const Text('Discard')),
          const SizedBox(width: 8),
          FilledButton(onPressed: busy ? null : onResume, child: const Text('Resume')),
        ]),
      ]),
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
    final kind = '${scan.shape == 'relief' ? 'Flat carving' : '3D object'}, ${scan.sourceKind == 'video' ? 'video' : 'photos'}';
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
