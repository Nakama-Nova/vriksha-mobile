import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';

/// A newer version of this app that the server knows about.
class AppUpdate {
  AppUpdate(this.version, this.notes, this.sizeBytes);
  final String version;
  final String notes;
  final int sizeBytes;

  String get sizeLabel => '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// "1.10.0" is newer than "1.9.3"; anything that is not x.y.z counts as not newer.
bool isNewer(String candidate, String installed) {
  List<int>? parse(String v) {
    final m = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)').firstMatch(v.trim());
    return m == null ? null : [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
  }

  final a = parse(candidate), b = parse(installed);
  if (a == null || b == null) return false;
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] > b[i];
  }
  return false;
}

class UpdateChecker {
  UpdateChecker(this.api, {Future<String> Function()? installedVersion})
      : _installed = installedVersion ?? (() async => (await PackageInfo.fromPlatform()).version);

  final ApiClient api;
  final Future<String> Function() _installed;

  /// The newer version, or null (up to date, nothing published yet, or the server could not be asked).
  Future<AppUpdate?> check() async {
    try {
      final latest = await api.latestApp();
      if (latest == null || !isNewer(latest.version, await _installed())) return null;
      return AppUpdate(latest.version, latest.notes, latest.size);
    } on ApiException {
      return null;
    }
  }

  /// Open the download in the browser; Android then offers to install it.
  Future<bool> open(AppUpdate update) async {
    final url = await api.appDownloadUrl(update.version);
    return launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  // "Later" is remembered per version, so the banner comes back for the next release.
  static const _dismissedKey = 'update_dismissed';

  static Future<bool> dismissed(String version) async =>
      (await SharedPreferences.getInstance()).getString(_dismissedKey) == version;

  static Future<void> dismiss(String version) async =>
      (await SharedPreferences.getInstance()).setString(_dismissedKey, version);

  // The system notification for an update is shown once per version.
  static const _announcedKey = 'update_announced';

  static Future<bool> announcedBefore(String version) async =>
      (await SharedPreferences.getInstance()).getString(_announcedKey) == version;

  static Future<void> markAnnounced(String version) async =>
      (await SharedPreferences.getInstance()).setString(_announcedKey, version);
}
