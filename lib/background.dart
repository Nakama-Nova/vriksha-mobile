import 'package:workmanager/workmanager.dart';

import 'alerts.dart';
import 'api.dart';
import 'notices.dart';
import 'session.dart';
import 'updates.dart';

const _taskName = 'shop-notices';

/// Runs about every 15 minutes (Android's shortest repeat) even when the app is closed:
/// asks the shop's server what is new and shows it as system notifications, and tells
/// the person once when a newer version of the app is published.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await checkInBackground();
    } catch (_) {
      // offline, signed out, server busy: the next round tries again
    }
    return true; // never ask for a retry storm; the schedule is the retry
  });
}

/// One background round. Public so it can be tested without Workmanager.
Future<void> checkInBackground({
  Alerter? alerter,
  Future<Session?> Function()? loadSession,
  Future<void> Function(String version)? announceUpdate,
  ApiClient Function(Session)? apiFor,
  Future<String> Function()? installedVersion,
}) async {
  final session = await (loadSession ?? SessionStore.load)();
  if (session == null) return; // signed out
  final alerts = alerter ?? SystemAlerts.instance;
  final api = (apiFor ?? (s) => s.api)(session);
  await NoticePoller(api, session.username, alerts).poll();

  final update = await UpdateChecker(api, installedVersion: installedVersion).check();
  if (update != null && !await UpdateChecker.announcedBefore(update.version)) {
    await (announceUpdate ?? SystemAlerts.instance.showUpdate)(update.version);
    await UpdateChecker.markAnnounced(update.version);
  }
}

/// Start (or keep) the repeating background round. Call once the person is signed in.
Future<void> startBackgroundChecks() async {
  await Workmanager().initialize(backgroundDispatcher);
  await Workmanager().registerPeriodicTask(
    _taskName,
    _taskName,
    frequency: const Duration(minutes: 15),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    constraints: Constraints(networkType: NetworkType.connected),
  );
}

/// Stop it when the person signs out, so nothing is fetched for nobody.
Future<void> stopBackgroundChecks() => Workmanager().cancelByUniqueName(_taskName);
