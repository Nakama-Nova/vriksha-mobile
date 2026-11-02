import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vriksha_capture/api.dart';
import 'package:vriksha_capture/session.dart';

void main() {
  group('a refused token', () {
    ApiClient client(int status, {String? token = 't', void Function()? onUnauthorized}) => ApiClient(
        'https://shop.test',
        token: token,
        onUnauthorized: onUnauthorized,
        client: MockClient((_) async => http.Response('{"detail":"nope"}', status)));

    test('any authenticated call reports a 401, and only a 401', () async {
      var hits = 0;
      await expectLater(client(401, onUnauthorized: () => hits++).scans(), throwsA(isA<ApiException>()));
      await expectLater(client(403, onUnauthorized: () => hits++).scans(), throwsA(isA<ApiException>()));
      await expectLater(client(500, onUnauthorized: () => hits++).scans(), throwsA(isA<ApiException>()));
      expect(hits, 1);
    });

    test('a wrong password at login is not an expired session', () async {
      var hits = 0;
      await expectLater(
          client(401, token: null, onUnauthorized: () => hits++).login('a', 'b'), throwsA(isA<ApiException>()));
      expect(hits, 0);
    });

    test('the session signs out once, however many calls fail together', () async {
      var out = 0;
      final s = Session('https://shop.test', 't', 'asha', 'owner')..onExpired = () => out++;
      s.expire();
      s.expire();
      s.expire();
      expect(out, 1);
    });
  });

  test('only the owner and artisans can file a scan under a restoration', () {
    Session as(String role) => Session('https://shop.test', 't', 'u', role);
    expect(as('owner').canRestore, isTrue);
    expect(as('artisan').canRestore, isTrue);
    for (final r in ['manager', 'sales', 'achari', 'worker', '']) {
      expect(as(r).canRestore, isFalse, reason: r);
    }
    expect(as('artisan').isStaffLead, isFalse); // an artisan does not pick products
  });
}
