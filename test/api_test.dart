import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vriksha_capture/api.dart';

ApiClient clientFor(http.Response Function(http.Request) handler, {String? token}) =>
    ApiClient('https://shop.test/', token: token, client: MockClient((r) async => handler(r)));

void main() {
  test('login posts a form and returns the token and role', () async {
    late http.Request seen;
    final api = clientFor((r) {
      seen = r;
      return http.Response(
          jsonEncode({'access_token': 'abc', 'token_type': 'bearer', 'username': 'asha', 'role': 'achari'}), 200);
    });
    final login = await api.login('asha', 'pw');
    expect(seen.url.toString(), 'https://shop.test/auth/login'); // trailing slash trimmed
    expect(seen.bodyFields, {'username': 'asha', 'password': 'pw'});
    expect([login.token, login.username, login.role], ['abc', 'asha', 'achari']);
  });

  test('server errors become readable messages', () async {
    expect(
      () => clientFor((_) => http.Response(jsonEncode({'detail': 'Invalid credentials'}), 401)).login('a', 'b'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Invalid credentials')),
    );
    expect(
      () => clientFor((_) => http.Response(
              jsonEncode({'detail': {'message': 'Some files did not upload', 'missing': ['k']}}), 409))
          .complete('s', ['k']),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Some files did not upload')),
    );
    expect(
      () => clientFor((_) => http.Response('<html>', 502)).scans(),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Server error (502)')),
    );
  });

  test('requests carry the bearer token', () async {
    String? auth;
    final api = clientFor((r) {
      auth = r.headers['Authorization'];
      return http.Response('[]', 200);
    }, token: 'tok');
    expect(await api.scans(), isEmpty);
    expect(auth, 'Bearer tok');
  });

  test('a scan parses and has plain-language status', () {
    final s = ScanJob.fromJson({
      'id': 'x', 'status': 'uploaded', 'source_kind': 'video', 'files': 1, 'source_bytes': 5,
      'progress': 0, 'created_at': '2026-10-26T10:00:00Z', 'item_name': 'Chair', 'note': null,
      'error': null, 'worker': null,
    });
    expect(s.statusLabel, 'Waiting for the workshop PC');
    expect(s.canCancel, isTrue);
    expect(s.itemName, 'Chair');
    expect(ScanJob.fromJson({...{
      'id': 'x', 'status': 'done', 'source_kind': 'video', 'files': 1, 'source_bytes': 5,
      'progress': 100, 'created_at': '2026-10-26T10:00:00Z'}}).canCancel, isFalse);
  });

  test('a network failure says so instead of crashing', () async {
    final api = ApiClient('https://shop.test',
        client: MockClient((_) async => throw http.ClientException('no route')));
    expect(() => api.scans(), throwsA(isA<ApiException>().having((e) => e.status, 'status', 0)));
  });
  test('a scan can be filed under a restoration and ask for G-code', () async {
    late Map<String, dynamic> body;
    final api = clientFor((r) {
      body = jsonDecode(r.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({
            'id': 's1', 'status': 'created', 'source_kind': 'photos', 'files': 0,
            'source_bytes': 0, 'progress': 0, 'created_at': '2026-10-27T10:00:00Z',
          }),
          201);
    }, token: 't');
    await api.createScan(sourceKind: 'photos', restorationId: 'r1', realWidthMm: 600, gcode: true);
    expect(body['restoration_id'], 'r1');
    expect(body['item_id'], isNull);
    expect(body['params'], {'real_width_mm': 600, 'quality': 'normal', 'gcode': true});
  });

  test('only open restorations are offered', () async {
    final api = clientFor((r) {
      expect(r.url.path, '/restorations');
      return http.Response(
          jsonEncode([
            {'id': 'a', 'title': 'Nandi', 'temple_name': 'Veerabhadra', 'status': 'planned'},
            {'id': 'b', 'title': 'Old door', 'temple_name': 'Kasi', 'status': 'restored'},
            {'id': 'c', 'title': 'Pillar', 'temple_name': 'Kasi', 'status': 'cancelled'},
            {'id': 'd', 'title': 'Guardian', 'temple_name': 'Lepakshi', 'status': 'review'},
          ]),
          200);
    }, token: 't');
    final open = await api.restorations();
    expect(open.map((e) => e.id), ['a', 'd']);
    expect(open.first.temple, 'Veerabhadra');
  });
}
