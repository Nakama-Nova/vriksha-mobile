import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notices.dart';

/// System notifications on the phone, from [flutter_local_notifications]. No Google or
/// Firebase account is involved: the app (and a background task) asks the shop's own
/// server what is new and shows it here.
class SystemAlerts implements Alerter {
  SystemAlerts._();
  static final SystemAlerts instance = SystemAlerts._();

  static const _channel = AndroidNotificationDetails(
    'shop',
    'Shop updates',
    channelDescription: 'Website orders, money received, low stock, finished 3D scans, app updates',
    importance: Importance.high,
    priority: Priority.high,
  );
  static const _details = NotificationDetails(android: _channel);
  static const atMostSeparate = 3; // more than this at once is one summary

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Set up the plugin. [onTap] gets the payload of a tapped notification (the screen name).
  Future<void> init({void Function(String? payload)? onTap}) async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) => onTap?.call(r.payload),
    );
    _ready = true;
  }

  /// Android 13 and up asks the person once; elsewhere this is already allowed.
  Future<bool> askPermission() async =>
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission() ??
      true;

  /// A tap on a notification that started the app (it was not running).
  Future<String?> launchPayload() async {
    final d = await _plugin.getNotificationAppLaunchDetails();
    return d?.didNotificationLaunchApp == true ? d?.notificationResponse?.payload : null;
  }

  @override
  Future<void> show(List<Notice> fresh) async {
    if (fresh.isEmpty) return;
    await init();
    if (fresh.length > atMostSeparate) {
      await _plugin.show(
        id: 1,
        title: '${fresh.length} new notifications',
        body: '${fresh.take(atMostSeparate).map((n) => n.title).join('\n')}\n'
            'and ${fresh.length - atMostSeparate} more',
        notificationDetails: _details,
        payload: 'list',
      );
      return;
    }
    for (final n in fresh) {
      await _plugin.show(
        id: n.id.hashCode & 0x7fffffff, // the same notice is replaced, not shown twice
        title: n.title,
        body: n.body,
        notificationDetails: _details,
        payload: n.screen,
      );
    }
  }

  Future<void> showUpdate(String version) async {
    await init();
    await _plugin.show(
      id: 2,
      title: 'Update available: Vriksha Capture $version',
      body: 'Open the app to download it.',
      notificationDetails: _details,
      payload: 'update',
    );
  }
}
