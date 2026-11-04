import 'package:flutter_test/flutter_test.dart';
import 'package:vriksha_capture/location.dart';
import 'package:vriksha_capture/screens/workforce_screen.dart';

void main() {
  test('a position goes to the server as latitude, longitude and accuracy in metres', () {
    expect(const GeoFix(12.9716, 77.5946, 8.5).toJson(), {'latitude': 12.9716, 'longitude': 77.5946, 'accuracy_m': 8.5});
  });

  test('where my day stands: not in, in, out, or marked by a manager', () {
    expect(dayState(null), 'not_in');
    expect(dayState({'check_in': null, 'check_out': null}), 'marked');
    expect(dayState({'check_in': '2026-11-04T04:00:00Z', 'check_out': null}), 'in');
    expect(dayState({'check_in': '2026-11-04T04:00:00Z', 'check_out': '2026-11-04T12:00:00Z'}), 'out');
  });

  test('the place line names the unit, says away, or says nothing', () {
    final places = [
      {'id': 'u1', 'name': 'Carving unit'},
      {'id': 'u2', 'name': 'Shop'},
    ];
    expect(siteLine('on_site', 'u1', places), 'At Carving unit');
    expect(siteLine('on_site', 'u2', places), 'At Shop');
    expect(siteLine('on_site', 'gone', places), 'At the workshop');
    expect(siteLine('off_site', null, places), 'Away from the workshop');
    expect(siteLine(null, null, places), '');
  });

  test('team states read like the server names them', () {
    expect(teamStateWord('not_in'), 'Not in');
    expect(teamStateWord('in'), 'In');
    expect(teamStateWord('out'), 'Out');
    expect(teamStateWord('marked'), 'Marked present');
  });

  test('a location problem says what to do and what would help', () {
    const p = LocationProblem('Location is blocked.', fix: LocationFix.appSettings);
    expect(p.toString(), 'Location is blocked.');
    expect(p.fix, LocationFix.appSettings);
    expect(const LocationProblem('x').fix, LocationFix.none);
  });
}
