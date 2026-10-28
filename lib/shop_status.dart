import 'dart:async';

import 'package:flutter/widgets.dart';

import 'alerts.dart';
import 'api.dart';
import 'background.dart';
import 'notices.dart';
import 'session.dart';
import 'updates.dart';

/// What the open app knows about the shop's news: the notifications list, how many are
/// unread, and whether a newer version of the app is published. It asks the server every
/// minute while the app is open and again whenever the app comes back to the front;
/// when the app is closed the background task does the same and uses system notifications.
class ShopStatus extends ChangeNotifier with WidgetsBindingObserver {
  ShopStatus(
    this.session, {
    NoticePoller? poller,
    UpdateChecker? updates,
    this.every = const Duration(minutes: 1),
    this.onFresh,
    this.startSystem = true,
  })  : _poller = poller ?? NoticePoller(session.api, session.username, null),
        _updates = updates ?? UpdateChecker(session.api);

  final Session session;
  final Duration every;
  final bool startSystem; // tests do not touch the phone's notification system
  final void Function(List<Notice> fresh)? onFresh; // the screen shows these itself

  final NoticePoller _poller;
  final UpdateChecker _updates;
  Timer? _timer;
  bool _polling = false;

  NoticeState state = NoticeState();
  AppUpdate? update; // newer than the installed app, and not put off
  bool _disposed = false;

  int get unread => state.unread;

  Future<void> start() async {
    WidgetsBinding.instance.addObserver(this);
    state = await NoticeStore.load(session.username);
    notifyListeners();
    if (startSystem) {
      try {
        await SystemAlerts.instance.init();
        await SystemAlerts.instance.askPermission();
        await startBackgroundChecks();
      } catch (_) {
        // no notification system (an old phone, a test): the open app still works
      }
    }
    _timer = Timer.periodic(every, (_) => refresh());
    await refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  /// Ask the server what is new and whether an update is out.
  Future<void> refresh() async {
    if (_polling || _disposed) return;
    _polling = true;
    try {
      final fresh = await _poller.poll();
      state = _poller.state ?? state;
      if (fresh.isNotEmpty && state.popups) onFresh?.call(fresh);
    } on ApiException {
      // offline or signed out: the list on screen stays as it was
    } finally {
      _polling = false;
    }
    final found = await _updates.check();
    update = found != null && !await UpdateChecker.dismissed(found.version) ? found : null;
    if (!_disposed) notifyListeners();
  }

  Future<void> markRead() async {
    if (state.unread == 0) return;
    state.unread = 0;
    await NoticeStore.save(session.username, state);
    notifyListeners();
  }

  Future<void> setPopups(bool on) async {
    state.popups = on;
    await NoticeStore.save(session.username, state);
    notifyListeners();
  }

  Future<void> putOffUpdate() async {
    final u = update;
    if (u == null) return;
    await UpdateChecker.dismiss(u.version);
    update = null;
    notifyListeners();
  }

  Future<bool> openUpdate() async {
    final u = update;
    return u == null ? false : _updates.open(u);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
