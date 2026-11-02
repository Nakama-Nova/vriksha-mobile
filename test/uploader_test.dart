import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  int failFirstPutsOf = 0; // how many PUT attempts to the failing file fail
  String failSuffix = '/0.jpg'; // which file those PUTs belong to
  int _failed = 0;
  int status = 200;
  int firstLinksLive = 1 << 30; // PUTs the first presigned batch accepts before it "expires"
  int _firstLinksUsed = 0;
  int presigns = 0;
  final presignSizes = <int>[]; // files asked for in each presign call

  MockClient get client => MockClient.streaming((req, body) async {
        final path = req.url.path;
        if (req.method == 'PUT') {
          final bytes = await body.expand((c) => c).toList();
          if (path.endsWith(failSuffix) && _failed < failFirstPutsOf) {
            _failed++;
            return http.StreamedResponse(Stream.value(utf8.encode('x')), 500);
          }
          if (req.url.query == 'sig=1' && ++_firstLinksUsed > firstLinksLive) {
            return http.StreamedResponse(Stream.value(utf8.encode('expired')), 403);
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
          presigns++;
          presignSizes.add(files.length);
          r = json({
            'files': [
              for (var i = 0; i < files.length; i++)
                {
                  'key': 'scans/scan-1/src/${files[i]['filename']}',
                  'url': 'https://store.invalid/scans/scan-1/src/${files[i]['filename']}?sig=$presigns',
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
        openRead: fakeRead, exists: (_) async => true, retryDelay: Duration.zero);
    final scan = await up.upload(kind: 'photos', files: files, onProgress: progress.add);

    expect(scan.status, 'uploaded');
    expect(backend.puts.length, 3);
    expect(backend.puts.values.every((b) => b.length == 3), isTrue);
    expect(backend.putHeaders.values.first['Content-Type'], 'image/jpeg');
    expect(backend.calls, containsAllInOrder(['POST /scans', 'POST /scans/scan-1/presign']));
    expect(backend.calls.last, 'keys scans/scan-1/src/0.jpg,scans/scan-1/src/1.jpg,scans/scan-1/src/2.png');
    expect(progress.last, 1.0);
    expect(progress, everyElement(inInclusiveRange(0.0, 1.0)));
  });

  test('a failed upload is retried, and the progress never counts the failed attempt twice', () async {
    final backend = FakeBackend()..failFirstPutsOf = 2;
    final progress = <double>[];
    final up = ScanUploader(ApiClient('https://shop.test', token: 't', client: backend.client),
        openRead: fakeRead, exists: (_) async => true, retryDelay: Duration.zero);
    await up.upload(kind: 'photos', files: files, onProgress: progress.add);
    expect(backend.puts.length, 3); // all arrived in the end
    expect(progress.last, 1.0);
    expect(progress, everyElement(lessThanOrEqualTo(1.0)));
  });

  test('gives up after the retries, keeps the scan id so it can resume, and does not complete', () async {
    final backend = FakeBackend()..failFirstPutsOf = 99;
    final up = ScanUploader(ApiClient('https://shop.test', token: 't', client: backend.client),
        openRead: fakeRead, exists: (_) async => true, retries: 3, retryDelay: Duration.zero);
    await expectLater(
      up.upload(kind: 'photos', files: files),
      throwsA(isA<UploadFailed>().having((e) => e.scanId, 'scanId', 'scan-1')),
    );
    expect(backend.calls.where((c) => c.endsWith('/complete')), isEmpty);
  });

  group('an upload that does not finish in one go', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    ScanUploader uploaderFor(FakeBackend b, PendingStore store, {bool onPhone = true}) =>
        ScanUploader(ApiClient('https://shop.test', token: 't', client: b.client),
            store: store,
            parallel: 1, // one at a time, so which file goes first is certain
            openRead: fakeRead,
            exists: (_) async => onPhone,
            retries: 2,
            retryDelay: Duration.zero);

    test('after a restart only the files not yet sent go out, then it completes', () async {
      final store = PendingStore('https://shop.test', 'asha');
      final backend = FakeBackend()
        ..failSuffix = '/2.png'
        ..failFirstPutsOf = 99;
      await expectLater(uploaderFor(backend, store).upload(kind: 'photos', files: files), throwsA(isA<UploadFailed>()));

      final left = (await PendingStore('https://shop.test', 'asha').load())!; // what a fresh app start reads
      expect(left.scanId, 'scan-1');
      expect(left.sent, 2); // files 0 and 1 are already in the store

      backend.failFirstPutsOf = 0; // the network is back
      final scan = await uploaderFor(backend, store).resume(left.scanId, left.files);

      expect(scan.status, 'uploaded');
      expect(backend.presignSizes.last, 1); // asked for one link, not three
      expect(backend.puts.length, 3); // each file is stored once; nothing was sent twice
      expect(backend.calls.last, 'keys scans/scan-1/src/0.jpg,scans/scan-1/src/1.jpg,scans/scan-1/src/2.png');
      expect(await store.load(), isNull); // finished: nothing left to resume
    });

    test('a link that runs out part-way is replaced with one request for what is left', () async {
      final backend = FakeBackend()..firstLinksLive = 1;
      final progress = <double>[];
      final scan = await uploaderFor(backend, PendingStore('https://shop.test', 'asha'))
          .upload(kind: 'photos', files: files, onProgress: progress.add);
      expect(scan.status, 'uploaded');
      expect(backend.presignSizes, [3, 2]); // one request per round, not one per file
      expect(backend.puts.length, 3);
      expect(progress, everyElement(lessThanOrEqualTo(1.0)));
      expect(progress.last, 1.0);
    });

    test('a file that vanished from the phone is named, and nothing is sent', () async {
      final backend = FakeBackend();
      await expectLater(
        uploaderFor(backend, PendingStore('https://shop.test', 'asha'), onPhone: false).resume('scan-1', files),
        throwsA(isA<UploadFailed>()
            .having((e) => e.reason, 'reason', allOf(contains('0.jpg'), contains('no longer on this phone')))),
      );
      expect(backend.calls, isEmpty);
    });

    test('each person on each server has their own unfinished upload', () async {
      await PendingStore('https://a.test', 'asha').save(PendingUpload('s1', files));
      expect(await PendingStore('https://a.test', 'ravi').load(), isNull);
      expect(await PendingStore('https://b.test', 'asha').load(), isNull);
      expect((await PendingStore('https://a.test', 'asha').load())!.files.map((f) => f.path),
          ['/p/0.jpg', '/p/1.jpg', '/p/2.png']);
    });
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
