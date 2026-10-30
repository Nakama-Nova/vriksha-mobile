import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vriksha_capture/api.dart';
import 'package:vriksha_capture/background.dart';
import 'package:vriksha_capture/notices.dart';
import 'package:vriksha_capture/screens/home_shell.dart';
import 'package:vriksha_capture/screens/notices_screen.dart';
import 'package:vriksha_capture/session.dart';
import 'package:vriksha_capture/shop_status.dart';
import 'package:vriksha_capture/theme.dart';
import 'package:vriksha_capture/updates.dart';

Map<String, dynamic> note(String id, {String title = 'Title', String screen = 'orders', String kind = 'order_web'}) => {
      'id': id,
      'kind': kind,
      'title': title,
      'body': 'Body',
      'created_at': '2026-10-28T10:00:00+00:00',
      'screen': screen,
      'target_id': null,
    };

NoticeFeed feed(List<Map<String, dynamic>> items, {String at = '2026-10-28T10:01:00+00:00'}) =>
    NoticeFeed.fromJson({'server_time': at, 'items': items});

class FakeAlerter implements Alerter {
  final shown = <List<Notice>>[];
  @override
  Future<void> show(List<Notice> fresh) async => shown.add(fresh);
}

ApiClient api(http.Response Function(http.Request) handler) =>
    ApiClient('https://shop.test', token: 't', client: MockClient((r) async => handler(r)));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('what is new', () {
    test('only what was not seen is new, and nothing repeats', () {
      final s = NoticeState();
      expect(s.absorb(feed([note('a'), note('b')])).map((n) => n.id), ['a', 'b']);
      expect(s.since, '2026-10-28T10:01:00+00:00');
      expect(s.absorb(feed([note('b'), note('c')], at: '2026-10-28T10:02:00+00:00')).map((n) => n.id), ['c']);
      expect(s.recent.map((n) => n.id), ['c', 'b', 'a']); // newest first
      expect(s.unread, 3);
      expect(s.absorb(feed([])), isEmpty);
    });

    test('the list and the memory are bounded', () {
      final s = NoticeState();
      s.absorb(feed([for (var i = 0; i < 400; i++) note('n$i')]));
      expect(s.recent.length, NoticeState.keepRecent);
      expect(s.seen.length, NoticeState.keepSeen);
      expect(s.unread, NoticeState.keepRecent);
    });

    test('the state survives a restart, per person, and a damaged copy starts afresh', () async {
      final s = NoticeState()..absorb(feed([note('a')]));
      await NoticeStore.save('asha', s);
      expect((await NoticeStore.load('asha')).seen, ['a']);
      expect((await NoticeStore.load('ravi')).seen, isEmpty); // not shown to the next person
      SharedPreferences.setMockInitialValues({'notices:asha': '{not json'});
      expect((await NoticeStore.load('asha')).seen, isEmpty);
    });
  });

  group('asking the server', () {
    test('the first call has no since, later calls send the time from the last answer', () async {
      final seen = <Uri>[];
      final client = api((r) {
        seen.add(r.url);
        return http.Response(jsonEncode({'server_time': '2026-10-28T09:00:00+00:00', 'items': []}), 200);
      });
      await NoticePoller(client, 'asha', null).poll();
      await NoticePoller(client, 'asha', null).poll();
      expect(seen[0].toString(), 'https://shop.test/notifications');
      expect(seen[1].queryParameters, {'since': '2026-10-28T09:00:00+00:00'});
    });

    test('new notices are shown as system notifications once, and not when switched off', () async {
      final client = api((_) => http.Response(
          jsonEncode({'server_time': 'T1', 'items': [note('a', title: 'New website order ORD-1')]}), 200));
      final alerts = FakeAlerter();
      final fresh = await NoticePoller(client, 'asha', alerts).poll();
      expect(fresh.length, 1);
      expect(alerts.shown.single.single.title, 'New website order ORD-1');
      expect(await NoticePoller(client, 'asha', alerts).poll(), isEmpty); // the same one again
      expect(alerts.shown.length, 1);

      final off = NoticeState(popups: false);
      await NoticeStore.save('ravi', off);
      await NoticePoller(client, 'ravi', alerts).poll();
      expect(alerts.shown.length, 1); // counted and listed, but no notification
      expect((await NoticeStore.load('ravi')).unread, 1);
    });

    test('a refused or unreachable server is an ApiException, not a crash', () {
      expect(() => NoticePoller(api((_) => http.Response('{"detail":"Not authenticated"}', 401)), 'a', null).poll(),
          throwsA(isA<ApiException>()));
    });
  });

  group('app updates', () {
    test('versions compare by number, not by text', () {
      expect(isNewer('1.10.0', '1.9.3'), isTrue);
      expect(isNewer('2.0.0', '1.99.99'), isTrue);
      expect(isNewer('1.1.0', '1.1.0'), isFalse);
      expect(isNewer('1.0.9', '1.1.0'), isFalse);
      expect(isNewer('v1.2.0', '1.1.0'), isTrue);
      expect(isNewer('beta', '1.0.0'), isFalse);
    });

    UpdateChecker checker(http.Response Function(http.Request) h, {String installed = '1.0.0'}) =>
        UpdateChecker(api(h), installedVersion: () async => installed);

    http.Response latest(String v) => http.Response(
        jsonEncode({'version': v, 'notes': 'Notifications', 'apk_name': 'VrikshaCapture-$v.apk', 'size': 24 * 1024 * 1024, 'sha256': 'x'}), 200);

    test('a newer published version is offered, an equal one or none is not', () async {
      final u = await checker((_) => latest('1.1.0')).check();
      expect([u?.version, u?.notes, u?.sizeLabel], ['1.1.0', 'Notifications', '24.0 MB']);
      expect(await checker((_) => latest('1.0.0')).check(), isNull);
      expect(await checker((_) => http.Response('{"detail":"No phone app update"}', 404)).check(), isNull);
      expect(await checker((_) => http.Response('oops', 500)).check(), isNull); // never blocks the app
    });

    test('Later is remembered for that version only', () async {
      expect(await UpdateChecker.dismissed('1.1.0'), isFalse);
      await UpdateChecker.dismiss('1.1.0');
      expect(await UpdateChecker.dismissed('1.1.0'), isTrue);
      expect(await UpdateChecker.dismissed('1.2.0'), isFalse);
    });

    test('the download address comes from the server as JSON', () async {
      final seen = <Uri>[];
      final url = await api((r) {
        seen.add(r.url);
        return http.Response(jsonEncode({'url': 'https://objects.example/apk?sig=1'}), 200);
      }).appDownloadUrl('1.1.0');
      expect(url, 'https://objects.example/apk?sig=1');
      expect(seen.single.path, '/app/updates/mobile/download/1.1.0');
    });
  });

  group('the background round', () {
    Session session(ApiClient _) => Session('https://shop.test', 't', 'asha', 'owner');

    test('signed out means nothing happens', () async {
      final alerts = FakeAlerter();
      await checkInBackground(alerter: alerts, loadSession: () async => null);
      expect(alerts.shown, isEmpty);
    });

    test('it shows what is new and announces an update once per version', () async {
      final alerts = FakeAlerter();
      final announced = <String>[];
      final client = api((r) => r.url.path == '/notifications'
          ? http.Response(jsonEncode({'server_time': 'T1', 'items': [note('a')]}), 200)
          : http.Response(
              jsonEncode({'version': '9.9.9', 'notes': '', 'apk_name': 'x.apk', 'size': 1, 'sha256': 'x'}), 200));
      Future<void> round() => checkInBackground(
            alerter: alerts,
            loadSession: () async => session(client),
            apiFor: (_) => client,
            installedVersion: () async => '1.0.0',
            announceUpdate: (v) async => announced.add(v),
          );
      await round();
      expect(alerts.shown.single.single.id, 'a');
      expect(announced, ['9.9.9']);
      await round(); // the same news and the same version: told once
      expect(alerts.shown.length, 1);
      expect(announced, ['9.9.9']);
    });

    test('an unreachable server ends the round quietly', () async {
      expect(
        checkInBackground(
          alerter: FakeAlerter(),
          loadSession: () async => session(api((_) => http.Response('{}', 200))),
          apiFor: (_) => api((_) => throw http.ClientException('down')),
        ),
        throwsA(isA<ApiException>()), // the dispatcher catches this and tries again later
      );
    });
  });

  group('the app', () {
    ShopStatus status({http.Response Function(http.Request)? h, void Function(List<Notice>)? onFresh}) {
      final client = api(h ??
          (r) => r.url.path == '/notifications'
              ? http.Response(jsonEncode({'server_time': 'T1', 'items': [note('a', title: 'New website order ORD-1')]}), 200)
              : http.Response('{"detail":"none"}', 404));
      return ShopStatus(
        Session('https://shop.test', 't', 'asha', 'owner'),
        poller: NoticePoller(client, 'asha', null),
        updates: UpdateChecker(client, installedVersion: () async => '1.0.0'),
        every: const Duration(hours: 1),
        onFresh: onFresh,
        startSystem: false,
      );
    }

    test('refresh fills the list and counts unread, and reading clears the count', () async {
      final fresh = <List<Notice>>[];
      final s = status(onFresh: fresh.add);
      await s.refresh();
      expect(s.unread, 1);
      expect(s.state.recent.single.title, 'New website order ORD-1');
      expect(fresh.single.single.id, 'a');
      await s.markRead();
      expect(s.unread, 0);
      await s.refresh(); // nothing new the second time
      expect(fresh.length, 1);
      s.dispose();
    });

    test('an update shows until put off, then comes back for the next version', () async {
      final s = status(h: (r) => r.url.path.endsWith('/latest')
          ? http.Response(jsonEncode({'version': '1.1.0', 'notes': 'n', 'apk_name': 'a.apk', 'size': 2097152, 'sha256': 'x'}), 200)
          : http.Response(jsonEncode({'server_time': 'T', 'items': []}), 200));
      await s.refresh();
      expect(s.update?.version, '1.1.0');
      await s.putOffUpdate();
      expect(s.update, isNull);
      await s.refresh();
      expect(s.update, isNull); // still put off
      s.dispose();
    });

    test('being offline leaves the list as it was', () async {
      final s = status(h: (_) => throw http.ClientException('down'));
      await s.refresh();
      expect(s.unread, 0);
      s.dispose();
    });

    testWidgets('the Alerts tab shows a count, lists the notices and opens on tap', (tester) async {
      final s = status();
      await s.refresh();
      await tester.pumpWidget(MaterialApp(
        theme: brandTheme(),
        home: HomeShell(session: Session('https://shop.test', 't', 'asha', 'owner'), onSignOut: () {}, status: s),
      ));
      expect(find.text('Alerts'), findsOneWidget);
      expect(find.text('1'), findsOneWidget); // the badge
      await tester.tap(find.text('Alerts'));
      await tester.pump();
      expect(s.unread, 0);
      expect(find.text('New website order ORD-1'), findsOneWidget);
      expect(find.text('Notify me on this phone'), findsOneWidget);
      s.dispose();
    });

    testWidgets('a published update shows a banner with Download and Later', (tester) async {
      final s = status(h: (r) => r.url.path.endsWith('/latest')
          ? http.Response(jsonEncode({'version': '1.1.0', 'notes': '', 'apk_name': 'a.apk', 'size': 1, 'sha256': 'x'}), 200)
          : http.Response(jsonEncode({'server_time': 'T', 'items': []}), 200));
      await s.refresh();
      await tester.pumpWidget(MaterialApp(
        theme: brandTheme(),
        home: HomeShell(session: Session('https://shop.test', 't', 'asha', 'owner'), onSignOut: () {}, status: s),
      ));
      expect(find.text('Version 1.1.0 is available'), findsOneWidget);
      await tester.tap(find.text('Later'));
      await tester.pump();
      expect(find.text('Version 1.1.0 is available'), findsNothing);
      s.dispose();
    });

    test('times are short: the time today, the date and time before', () {
      final now = DateTime(2026, 10, 28, 12);
      String iso(DateTime d) => d.toUtc().toIso8601String();
      expect(NoticesScreen.when(iso(DateTime(2026, 10, 28, 9, 5)), now: now), '09:05');
      expect(NoticesScreen.when(iso(DateTime(2026, 10, 27, 14, 30)), now: now), '27 Oct 14:30');
      expect(NoticesScreen.when('garbage', now: now), '');
    });
  });
}
