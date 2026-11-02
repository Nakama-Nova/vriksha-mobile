import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// A photo or video chosen on the phone.
class CaptureFile {
  CaptureFile(this.path, this.size);
  final String path;
  final int size;

  String get name => path.split(RegExp(r'[\\/]')).last;

  String get contentType {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.mp4')) return 'video/mp4';
    if (n.endsWith('.mov')) return 'video/quicktime';
    return 'image/jpeg';
  }
}

const _mb = 1024 * 1024;
const maxPhotos = 300; // server limits, same as the desktop app
const _minPhotos = 8;

/// A plain-words problem with the chosen files, or null. Mirrors the server (and the
/// desktop app) so nothing is created on the server for files it would refuse.
String? captureProblem(String kind, String shape, List<CaptureFile> files) {
  if (files.isEmpty) {
    return kind == 'photos' ? 'Take or choose a photo first.' : 'Record or choose a video first.';
  }
  final photos = kind == 'photos';
  if (!photos && files.length != 1) return 'Choose one video.';
  if (photos && shape != 'relief' && files.length < _minPhotos) {
    return 'A full 3D object needs at least $_minPhotos photos, walking around it. For a flat carving, choose Flat carving.';
  }
  if (files.length > maxPhotos) return 'At most $maxPhotos photos in one scan.';
  final exts = photos ? const ['.jpg', '.jpeg', '.png'] : const ['.mp4', '.mov'];
  final biggest = photos ? 100 * _mb : 1024 * _mb;
  for (final f in files) {
    final n = f.name.toLowerCase();
    if (!exts.any(n.endsWith)) {
      return '${f.name}: use ${exts.join(', ')} files for ${photos ? 'photos' : 'a video'}.';
    }
    if (f.size > biggest) {
      return '${f.name} is too big (limit ${photos ? '100 MB a photo' : '1 GB for a video'}).';
    }
  }
  return null;
}

/// The file could not be sent after all retries. The scan exists on the server in
/// the "not finished" state, so [resume] can try again, or the user can cancel it.
class UploadFailed implements Exception {
  UploadFailed(this.scanId, this.reason);
  final String scanId;
  final String reason;
  @override
  String toString() => reason;
}

Stream<List<int>> _openFile(String path) => File(path).openRead();
Future<bool> _exists(String path) => File(path).exists();

/// An upload that has not finished, kept so it survives the app being closed or killed.
/// [done] maps each file already in the store to the key it was stored under.
class PendingUpload {
  PendingUpload(this.scanId, this.files, [Map<String, String>? done]) : done = done ?? {};
  final String scanId;
  final List<CaptureFile> files;
  final Map<String, String> done;

  int get sent => files.where((f) => done.containsKey(f.path)).length;

  Map<String, dynamic> toJson() => {
        'scan_id': scanId,
        'files': [for (final f in files) {'path': f.path, 'size': f.size}],
        'done': done,
      };

  factory PendingUpload.fromJson(Map<String, dynamic> j) => PendingUpload(
        j['scan_id'] as String,
        [for (final f in (j['files'] as List)) CaptureFile(f['path'] as String, (f['size'] as num).toInt())],
        Map<String, String>.from(j['done'] as Map),
      );
}

/// One unfinished upload per person per server.
class PendingStore {
  PendingStore(String baseUrl, String username) : _key = 'pending:$baseUrl:$username';
  final String _key;

  Future<PendingUpload?> load() async {
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw == null) return null;
    try {
      return PendingUpload.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null; // a damaged copy only means starting afresh
    }
  }

  Future<void> save(PendingUpload p) async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode(p.toJson()));

  Future<void> clear() async => (await SharedPreferences.getInstance()).remove(_key);
}

/// Phone side of a scan: create it, send every file straight to the store, then
/// tell the server it is complete so the workshop PC can pick it up.
///
/// With a [store], progress is remembered file by file, so after the app is closed
/// [resume] sends only what is missing.
class ScanUploader {
  ScanUploader(
    this.api, {
    this.store,
    this.openRead = _openFile,
    this.exists = _exists,
    this.retries = 3,
    this.parallel = 3,
    this.retryDelay = const Duration(seconds: 2),
  });

  final ApiClient api;
  final PendingStore? store;
  final Stream<List<int>> Function(String path) openRead;
  final Future<bool> Function(String path) exists;
  final int retries;
  final int parallel;
  final Duration retryDelay;

  // Signed links last 10 minutes. When one runs out part-way, ask for fresh links for what
  // is left. The server allows only 20 presign calls a minute for the whole shop, so this
  // is one call per round, never one per file.
  static const _maxRounds = 5;

  Future<ScanJob> upload({
    required String kind,
    required List<CaptureFile> files,
    String? itemId,
    String? restorationId,
    double? realWidthMm,
    String quality = 'normal',
    bool gcode = false,
    String shape = 'full',
    void Function(double fraction)? onProgress,
  }) async {
    final scan = await api.createScan(
      sourceKind: kind,
      itemId: itemId,
      restorationId: restorationId,
      realWidthMm: realWidthMm,
      quality: quality,
      gcode: gcode,
      shape: shape,
    );
    await store?.save(PendingUpload(scan.id, files));
    return resume(scan.id, files, onProgress: onProgress);
  }

  /// Send what is still missing for an existing, unfinished scan, then complete it.
  Future<ScanJob> resume(String scanId, List<CaptureFile> files,
      {void Function(double fraction)? onProgress}) async {
    for (final f in files) {
      if (!await exists(f.path)) {
        throw UploadFailed(scanId,
            '${f.name} is no longer on this phone. Discard this upload and take the photos again.');
      }
    }
    final saved = await store?.load();
    final job = saved != null && saved.scanId == scanId ? saved : PendingUpload(scanId, files);
    final total = files.fold<int>(0, (a, f) => a + f.size);
    final sent = [for (final f in files) job.done.containsKey(f.path) ? f.size : 0];
    void report() => onProgress?.call(
        total == 0 ? 1 : sent.fold<int>(0, (a, b) => a + b) / total);
    report();

    for (var round = 1;; round++) {
      final todo = [
        for (var i = 0; i < files.length; i++)
          if (!job.done.containsKey(files[i].path)) i
      ];
      if (todo.isEmpty) break;
      final targets = await api.presignSources(
        scanId,
        [for (final i in todo) FileSpec(files[i].name, files[i].contentType, files[i].size)],
      );

      var next = 0;
      Object? failure;
      Future<void> worker() async {
        while (failure == null && next < todo.length) {
          final n = next++;
          final i = todo[n];
          try {
            await _sendOne(files[i], targets[n], (b) {
              sent[i] += b;
              report();
            }, () {
              sent[i] = 0;
              report();
            });
            job.done[files[i].path] = targets[n].key;
            await store?.save(job);
          } catch (e) {
            sent[i] = 0; // it will be sent again from the start
            failure ??= e;
          }
        }
      }

      await Future.wait(List.generate(parallel, (_) => worker()));
      final f = failure;
      if (f != null && !(_linkExpired(f) && round < _maxRounds)) {
        throw UploadFailed(scanId, f.toString());
      }
    }
    final scan = await api.complete(scanId, [for (final f in files) job.done[f.path]!]);
    await store?.clear();
    return scan;
  }

  bool _linkExpired(Object e) => e is ApiException && e.status == 403;

  Future<void> _sendOne(CaptureFile f, UploadTarget t, void Function(int) onBytes,
      void Function() onRetry) async {
    for (var attempt = 1;; attempt++) {
      try {
        await api.put(t, openRead(f.path), f.size, onBytes);
        return;
      } catch (e) {
        if (attempt >= retries || _linkExpired(e)) rethrow; // an expired link needs a new one
        onRetry();
        await Future<void>.delayed(retryDelay);
      }
    }
  }
}
