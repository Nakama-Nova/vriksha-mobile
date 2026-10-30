import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// One thing the shop wants this person to know (a website order, money received, stock
/// running low, a finished 3D scan). The server decides who hears what.
class Notice {
  Notice({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.screen,
    this.targetId,
  });

  final String id; // never repeats, so asking twice never shows it twice
  final String kind;
  final String title;
  final String body;
  final String createdAt; // ISO, UTC
  final String screen; // orders | stock | restoration
  final String? targetId;

  factory Notice.fromJson(Map<String, dynamic> j) => Notice(
        id: j['id'] as String,
        kind: j['kind'] as String,
        title: j['title'] as String,
        body: (j['body'] as String?) ?? '',
        createdAt: j['created_at'] as String,
        screen: (j['screen'] as String?) ?? '',
        targetId: j['target_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'title': title,
        'body': body,
        'created_at': createdAt,
        'screen': screen,
        'target_id': targetId,
      };
}

/// The server's answer: where to ask from next time, and what is new.
class NoticeFeed {
  NoticeFeed(this.serverTime, this.items);
  final String serverTime;
  final List<Notice> items;

  factory NoticeFeed.fromJson(Map<String, dynamic> j) => NoticeFeed(
        j['server_time'] as String,
        (j['items'] as List).cast<Map<String, dynamic>>().map(Notice.fromJson).toList(),
      );
}

/// What this phone remembers about a person's notifications.
class NoticeState {
  NoticeState({
    this.since,
    List<String>? seen,
    List<Notice>? recent,
    this.unread = 0,
    this.popups = true,
  })  : seen = seen ?? [],
        recent = recent ?? [];

  static const keepSeen = 300; // ids remembered, so a repeat is never shown
  static const keepRecent = 50; // what the list shows

  String? since;
  List<String> seen;
  List<Notice> recent; // newest first
  int unread;
  bool popups;

  /// Take a server answer in. Returns the notices that are new to this phone, oldest first.
  List<Notice> absorb(NoticeFeed feed) {
    final known = seen.toSet();
    final fresh = feed.items.where((n) => known.add(n.id)).toList();
    since = feed.serverTime;
    seen = [...seen, ...fresh.map((n) => n.id)];
    if (seen.length > keepSeen) seen = seen.sublist(seen.length - keepSeen);
    recent = [...fresh.reversed, ...recent];
    if (recent.length > keepRecent) recent = recent.sublist(0, keepRecent);
    unread = (unread + fresh.length).clamp(0, keepRecent);
    return fresh;
  }

  Map<String, dynamic> toJson() => {
        'since': since,
        'seen': seen,
        'recent': recent.map((n) => n.toJson()).toList(),
        'unread': unread,
        'popups': popups,
      };

  factory NoticeState.fromJson(Map<String, dynamic> j) => NoticeState(
        since: j['since'] as String?,
        seen: (j['seen'] as List?)?.cast<String>(),
        recent: (j['recent'] as List?)
            ?.cast<Map<String, dynamic>>()
            .map(Notice.fromJson)
            .toList(),
        unread: (j['unread'] as num?)?.toInt() ?? 0,
        popups: (j['popups'] as bool?) ?? true,
      );
}

/// One state per signed-in person, so the next person on a shared phone is not shown
/// what the last one was told.
class NoticeStore {
  static String _key(String username) => 'notices:$username';

  static Future<NoticeState> load(String username) async {
    final raw = (await SharedPreferences.getInstance()).getString(_key(username));
    if (raw == null) return NoticeState();
    try {
      return NoticeState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return NoticeState(); // a damaged copy only means starting afresh
    }
  }

  static Future<void> save(String username, NoticeState state) async =>
      (await SharedPreferences.getInstance()).setString(_key(username), jsonEncode(state.toJson()));
}

/// Shows new notices outside the app (a system notification). Faked in tests.
abstract class Alerter {
  Future<void> show(List<Notice> fresh);
}

/// One round of "what is new?": ask the server, remember it, tell the person.
class NoticePoller {
  NoticePoller(this.api, this.username, this.alerter, {Future<NoticeState> Function(String)? load, Future<void> Function(String, NoticeState)? save})
      : _load = load ?? NoticeStore.load,
        _save = save ?? NoticeStore.save;

  final ApiClient api;
  final String username;
  final Alerter? alerter; // null while the app is open: the screen shows them itself
  final Future<NoticeState> Function(String) _load;
  final Future<void> Function(String, NoticeState) _save;

  NoticeState? state; // as it is after the last poll

  Future<List<Notice>> poll() async {
    final state = this.state = await _load(username);
    final fresh = state.absorb(await api.notifications(since: state.since));
    await _save(username, state);
    if (fresh.isNotEmpty && state.popups) await alerter?.show(fresh);
    return fresh;
  }
}
