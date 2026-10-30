import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vriksha_capture/api.dart';
import 'package:vriksha_capture/uploader.dart';

Map<String, dynamic> scanJson(String status) => {
      'id': 'scan-1',
      'item_id': null,
      'item_name': null,
      'status': status,
      'source_kind': 'photos',
      'files': 3,
      'source_bytes': 3000,
      'params': {},
      'progress': 0,
      'note': null,
      'error': null,
      'attempts': 0,
      'worker': null,
      'lease_until': null,
      'created_at': '2026-10-26T10:00:00Z',
      'finished_at': null,
      'result_asset_ids': [],
    };

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// A fake server and store in one: records what the phone sent.
class FakeBackend {
  final calls = <String>[];
  final puts = <String, List<int>>{}; // url -> bytes received
  final putHeaders = <String, Map<String, String>>{};
  int failFirstPutsOf = 0; // how many PUT attempts to the first file fail
  int _failed = 0;
  int status = 200;

  MockClient get client => MockClient.streaming((req, body) async {
        final path = req.url.path;
        if (req.method == 'PUT') {
          final bytes = await body.expand((c) => c).toList();
          if (path.endsWith('/0.jpg') && _failed < failFirstPutsOf) {
            _failed++;
            return http.StreamedResponse(Stream.value(utf8.encode('x')), 500);
          }
          puts[req.url.toString()] = bytes;
          putHeaders[req.url.toString()] = req.headers;
          return http.StreamedResponse(Stream.value(const []), 200);
        }
        final text = utf8.decode(await body.expand((c) => c).toList());
        calls.add('${req.method} $path');
        http.Response r;
        if (path == '/scans' && req.method == 'POST') {
          r = json(scanJson('created'), 201);
        } else if (path.endsWith('/presign')) {
          final files = (jsonDecode(text)['files'] as List);
          r = json({
            'files': [
              for (var i = 0; i < files.length; i++)
                {
                  'key': 'scans/scan-1/src/$i.jpg',
                  'url': 'https://store.invalid/scans/scan-1/src/$i.jpg?sig=1',
                  'method': 'PUT',
                  'headers': {'Content-Type': files[i]['content_type']},
                }
            ],
            'expires_in': 600,
          });
        } else if (path.endsWith('/complete')) {
          calls.add('keys ${(jsonDecode(text)['keys'] as List).join(',')}');
          r = json(scanJson('uploaded'));
        } else {
          r = json({'detail': 'unexpected $path'}, 404);
        }
        return http.StreamedResponse(Stream.value(r.bodyBytes), r.statusCode,
            headers: {'content-type': 'application/json'});
      });
}

void main() {
  captureTests();
  final files = [
    CaptureFile('/p/0.jpg', 3),
    CaptureFile('/p/1.jpg', 3),
    CaptureFile('/p/2.png', 3),
  ];
  Stream<List<int>> fakeRead(String path) => Stream.fromIterable([
        [1, 2],
        [3]
      ]);

  test('uploads every file with its signed headers, then completes the scan', () async {
    final backend = FakeBackend();
    final progress = <double>[];
    final up = ScanUploader(ApiClient('https://shop.test/', token: 't', client: backend.client),
        openRead: fakeRead, retryDelay: Duration.zero);
    final scan = await up.upload(kind: 'photos', files: files, onProgress: progress.add);

    expect(scan.status, 'uploaded');
    expect(backend.puts.length, 3);
    expect(backend.puts.values.every((b) => b.length == 3), isTrue);
    expect(backend.putHeaders.values.first['Content-Type'], 'image/jpeg');
    expect(backend.calls, containsAllInOrder(['POST /scans', 'POST /scans/scan-1/presign']));
    expect(backend.calls.last, 'keys scans/scan-1/src/0.jpg,scans/scan-1/src/1.jpg,scans/scan-1/src/2.jpg');
    expect(progress.last, 1.0);
    expect(progress, everyElement(inInclusiveRange(0.0, 1.0)));
  });

  test('a failed upload is retried, and the progress never counts the failed attempt twice', () async {
    final backend = FakeBackend()..failFirstPutsOf = 2;
    final progress = <double>[];
    final up = ScanUploader(ApiClient('https://shop.test', token: 't', client: backend.client),
        openRead: fakeRead, retryDelay: Duration.zero);
    await up.upload(kind: 'photos', files: files, onProgress: progress.add);
    expect(backend.puts.length, 3); // all arrived in the end
    expect(progress.last, 1.0);
    expect(progress, everyElement(lessThanOrEqualTo(1.0)));
  });

  test('gives up after the retries, keeps the scan id so it can resume, and does not complete', () async {
    final backend = FakeBackend()..failFirstPutsOf = 99;
    final up = ScanUploader(ApiClient('https://shop.test', token: 't', client: backend.client),
        openRead: fakeRead, retries: 3, retryDelay: Duration.zero);
    await expectLater(
      up.upload(kind: 'photos', files: files),
      throwsA(isA<UploadFailed>().having((e) => e.scanId, 'scanId', 'scan-1')),
    );
    expect(backend.calls.where((c) => c.endsWith('/complete')), isEmpty);
  });

  test('content types follow the file extension', () {
    expect(CaptureFile('/a/b.PNG', 1).contentType, 'image/png');
    expect(CaptureFile(r'C:\a\b.mp4', 1).contentType, 'video/mp4');
    expect(CaptureFile('/a/b.mov', 1).contentType, 'video/quicktime');
    expect(CaptureFile('/a/b.jpeg', 1).contentType, 'image/jpeg');
    expect(CaptureFile(r'C:\a\b.mp4', 1).name, 'b.mp4');
  });
}

void captureTests() {
  CaptureFile photo(String n, [int size = 1000]) => CaptureFile('/p/$n', size);

  test('capture rules match the desktop app and the server', () {
    final eight = [for (var i = 0; i < 8; i++) photo('$i.jpg')];
    expect(captureProblem('photos', 'full', eight), isNull);
    expect(captureProblem('photos', 'full', []), 'Take or choose a photo first.');
    expect(captureProblem('photos', 'full', [photo('a.jpg')]), contains('at least 8 photos'));
    expect(captureProblem('photos', 'relief', [photo('a.jpg')]), isNull); // a flat carving needs one
    expect(captureProblem('photos', 'relief', [for (var i = 0; i < 301; i++) photo('$i.jpg')]),
        'At most 300 photos in one scan.');
    expect(captureProblem('photos', 'relief', [photo('a.heic')]), contains('.jpg, .jpeg, .png'));
    expect(captureProblem('photos', 'relief', [photo('a.jpg', 101 * 1024 * 1024)]), contains('too big'));
    expect(captureProblem('video', 'full', [photo('a.mp4'), photo('b.mp4')]), 'Choose one video.');
    expect(captureProblem('video', 'full', [photo('a.mp4')]), isNull);
    expect(captureProblem('video', 'full', [photo('a.avi')]), contains('.mp4, .mov'));
  });
}
