import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// A server answer that was not a success. [message] is safe to show to the user.
class ApiException implements Exception {
  ApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

class LoginResult {
  LoginResult(this.token, this.username, this.role);
  final String token;
  final String username;
  final String role;
}

/// Where and how to send one file (a presigned PUT: the store checks size and type).
class UploadTarget {
  UploadTarget(this.key, this.url, this.method, this.headers);
  final String key;
  final String url;
  final String method;
  final Map<String, String> headers;

  factory UploadTarget.fromJson(Map<String, dynamic> j) => UploadTarget(
        j['key'] as String,
        j['url'] as String,
        (j['method'] as String?) ?? 'PUT',
        Map<String, String>.from((j['headers'] as Map?) ?? const {}),
      );
}

class FileSpec {
  FileSpec(this.filename, this.contentType, this.size);
  final String filename;
  final String contentType;
  final int size;
  Map<String, Object> toJson() =>
      {'filename': filename, 'content_type': contentType, 'size': size};
}

/// A temple restoration a scan can be filed under.
class RestorationRef {
  RestorationRef(this.id, this.title, this.temple);
  final String id;
  final String title;
  final String temple;

  factory RestorationRef.fromJson(Map<String, dynamic> j) =>
      RestorationRef(j['id'] as String, j['title'] as String, j['temple_name'] as String);
}

class ScanJob {
  ScanJob({
    required this.id,
    required this.status,
    required this.sourceKind,
    required this.files,
    required this.sourceBytes,
    required this.progress,
    required this.createdAt,
    this.itemName,
    this.note,
    this.error,
    this.worker,
  });

  final String id;
  final String status;
  final String sourceKind;
  final int files;
  final int sourceBytes;
  final int progress;
  final DateTime createdAt;
  final String? itemName;
  final String? note;
  final String? error;
  final String? worker;

  factory ScanJob.fromJson(Map<String, dynamic> j) => ScanJob(
        id: j['id'] as String,
        status: j['status'] as String,
        sourceKind: j['source_kind'] as String,
        files: (j['files'] as num).toInt(),
        sourceBytes: (j['source_bytes'] as num).toInt(),
        progress: (j['progress'] as num).toInt(),
        createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
        itemName: j['item_name'] as String?,
        note: j['note'] as String?,
        error: j['error'] as String?,
        worker: j['worker'] as String?,
      );

  bool get canCancel => status == 'created' || status == 'uploaded';

  /// Plain words for the shop floor.
  String get statusLabel => switch (status) {
        'created' => 'Not finished uploading',
        'uploaded' => 'Waiting for the workshop PC',
        'processing' => 'Being processed',
        'done' => 'Done',
        'failed' => 'Failed',
        'cancelled' => 'Cancelled',
        _ => status,
      };
}

class CatalogItem {
  CatalogItem(this.id, this.name, this.sku);
  final String id;
  final String name;
  final String sku;
}

class ApiClient {
  ApiClient(String baseUrl, {this.token, http.Client? client})
      : baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), ''),
        _http = client ?? http.Client();

  final String baseUrl;
  final String? token;
  final http.Client _http;

  static const _timeout = Duration(seconds: 30);

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
        if (token != null) 'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  /// Decode a JSON answer, or turn a failure into an [ApiException].
  dynamic _decode(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    }
    throw ApiException(r.statusCode, _detail(r));
  }

  String _detail(http.Response r) {
    try {
      final d = (jsonDecode(utf8.decode(r.bodyBytes)) as Map)['detail'];
      if (d is String) return d;
      if (d is Map && d['message'] is String) return d['message'] as String;
      if (d is List && d.isNotEmpty && d.first is Map) {
        return (d.first as Map)['msg']?.toString() ?? 'Request was not valid';
      }
    } catch (_) {}
    if (r.statusCode == 401) return 'Please sign in again';
    if (r.statusCode == 403) return 'You are not allowed to do this';
    return 'Server error (${r.statusCode})';
  }

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(_timeout);
    } on TimeoutException {
      throw ApiException(0, 'The server did not answer. Check the connection.');
    } on http.ClientException {
      throw ApiException(0, 'Cannot reach the server. Check the connection.');
    }
  }

  Future<LoginResult> login(String username, String password) async {
    final r = await _send(() => _http.post(
          _uri('/auth/login'),
          body: {'username': username, 'password': password},
        ));
    final j = _decode(r) as Map<String, dynamic>;
    return LoginResult(
        j['access_token'] as String, j['username'] as String, j['role'] as String);
  }

  Future<List<ScanJob>> scans() async {
    final r = await _send(() => _http.get(_uri('/scans'), headers: _headers));
    return (_decode(r) as List)
        .map((e) => ScanJob.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Projects that are still open (not restored or cancelled), newest first.
  Future<List<RestorationRef>> restorations() async {
    final r = await _send(() => _http.get(_uri('/restorations'), headers: _headers));
    return (_decode(r) as List)
        .cast<Map<String, dynamic>>()
        .where((j) => j['status'] != 'restored' && j['status'] != 'cancelled')
        .map(RestorationRef.fromJson)
        .toList();
  }

  Future<ScanJob> createScan({
    required String sourceKind,
    String? itemId,
    String? restorationId,
    double? realWidthMm,
    String quality = 'normal',
    bool gcode = false,
  }) async {
    final r = await _send(() => _http.post(
          _uri('/scans'),
          headers: _headers,
          body: jsonEncode({
            'item_id': itemId,
            'restoration_id': restorationId,
            'source_kind': sourceKind,
            'params': {
              'real_width_mm': realWidthMm,
              'quality': quality,
              'gcode': gcode,
            },
          }),
        ));
    return ScanJob.fromJson(_decode(r) as Map<String, dynamic>);
  }

  Future<List<UploadTarget>> presignSources(
      String scanId, List<FileSpec> files) async {
    final r = await _send(() => _http.post(
          _uri('/scans/$scanId/presign'),
          headers: _headers,
          body: jsonEncode({'files': files.map((f) => f.toJson()).toList()}),
        ));
    final j = _decode(r) as Map<String, dynamic>;
    return (j['files'] as List)
        .map((e) => UploadTarget.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Send one file to the store. The body is streamed (never held in memory) and
  /// [onBytes] reports each chunk as it goes out.
  Future<void> put(UploadTarget t, Stream<List<int>> body, int length,
      void Function(int) onBytes) async {
    final req = http.StreamedRequest(t.method, Uri.parse(t.url))
      ..headers.addAll(t.headers)
      ..contentLength = length;
    final counted = body.map((chunk) {
      onBytes(chunk.length);
      return chunk;
    });
    unawaited(req.sink
        .addStream(counted)
        .catchError((Object e) => req.sink.addError(e))
        .whenComplete(req.sink.close));
    try {
      final res = await _http.send(req);
      await res.stream.drain<void>();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ApiException(res.statusCode, 'Upload failed (${res.statusCode})');
      }
    } on http.ClientException {
      throw ApiException(0, 'Upload interrupted. Check the connection.');
    }
  }

  Future<ScanJob> complete(String scanId, List<String> keys) async {
    final r = await _send(() => _http.post(
          _uri('/scans/$scanId/complete'),
          headers: _headers,
          body: jsonEncode({'keys': keys}),
        ));
    return ScanJob.fromJson(_decode(r) as Map<String, dynamic>);
  }

  Future<void> cancel(String scanId) async {
    final r = await _send(
        () => _http.post(_uri('/scans/$scanId/cancel'), headers: _headers));
    _decode(r);
  }

  /// Owner and manager only (the server refuses everyone else).
  Future<List<CatalogItem>> items() async {
    final r = await _send(() =>
        _http.get(_uri('/items/', {'limit': '100'}), headers: _headers));
    return (_decode(r) as List)
        .map((e) => CatalogItem(e['id'] as String, e['name'] as String,
            (e['sku'] as String?) ?? ''))
        .toList();
  }
}
