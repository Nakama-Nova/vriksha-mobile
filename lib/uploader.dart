import 'dart:io';

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

/// Phone side of a scan: create it, send every file straight to the store, then
/// tell the server it is complete so the workshop PC can pick it up.
class ScanUploader {
  ScanUploader(
    this.api, {
    this.openRead = _openFile,
    this.retries = 3,
    this.parallel = 3,
    this.retryDelay = const Duration(seconds: 2),
  });

  final ApiClient api;
  final Stream<List<int>> Function(String path) openRead;
  final int retries;
  final int parallel;
  final Duration retryDelay;

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
    return resume(scan.id, files, onProgress: onProgress);
  }

  /// Send everything again for an existing, unfinished scan.
  Future<ScanJob> resume(String scanId, List<CaptureFile> files,
      {void Function(double fraction)? onProgress}) async {
    final targets = await api.presignSources(
      scanId,
      [for (final f in files) FileSpec(f.name, f.contentType, f.size)],
    );
    final total = files.fold<int>(0, (a, f) => a + f.size);
    final sent = List<int>.filled(files.length, 0);
    void report() => onProgress?.call(
        total == 0 ? 1 : sent.fold<int>(0, (a, b) => a + b) / total);

    var next = 0;
    Object? failure;
    Future<void> worker() async {
      while (failure == null && next < files.length) {
        final i = next++;
        try {
          await _sendOne(files[i], targets[i], (n) {
            sent[i] += n;
            report();
          }, () {
            sent[i] = 0;
            report();
          });
        } catch (e) {
          failure ??= e;
        }
      }
    }

    await Future.wait(List.generate(parallel, (_) => worker()));
    if (failure != null) {
      throw UploadFailed(scanId, failure.toString());
    }
    return api.complete(scanId, [for (final t in targets) t.key]);
  }

  Future<void> _sendOne(CaptureFile f, UploadTarget t, void Function(int) onBytes,
      void Function() onRetry) async {
    for (var attempt = 1;; attempt++) {
      try {
        await api.put(t, openRead(f.path), f.size, onBytes);
        return;
      } catch (e) {
        if (attempt >= retries) rethrow;
        onRetry();
        await Future<void>.delayed(retryDelay);
      }
    }
  }
}
