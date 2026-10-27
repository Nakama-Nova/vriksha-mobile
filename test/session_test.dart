import 'package:flutter_test/flutter_test.dart';
import 'package:vriksha_capture/session.dart';

void main() {
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
