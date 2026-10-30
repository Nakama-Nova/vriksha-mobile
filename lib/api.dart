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

/// Plain http:// is only acceptable on this phone's own network (the shop's PC or
/// server). Anything reachable over the internet must be https://.
bool isInsecureRemote(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || u.scheme != 'http') return false;
  final h = u.host.toLowerCase();
  if (h == 'localhost' || h.endsWith('.local')) return false;
  final p = h.split('.');
  if (p.length == 4 && p.every((x) => int.tryParse(x) != null)) {
    final a = int.parse(p[0]), b = int.parse(p[1]);
    if (a == 10 || a == 127 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31)) {
      return false;
    }
  }
  return true;
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
    } on Exception catch (e) {
      // e.g. a failed secure (TLS) handshake, which is not a ClientException
      throw ApiException(0,
          'Could not connect (${e.runtimeType}). Check the date, time and connection of the phone.');
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

  Future<ScanJob> createScan({
    required String sourceKind,
    String? itemId,
    double? realWidthMm,
    String quality = 'normal',
  }) async {
    final r = await _send(() => _http.post(
          _uri('/scans'),
          headers: _headers,
          body: jsonEncode({
            'item_id': itemId,
            'source_kind': sourceKind,
            'params': {
              'real_width_mm': realWidthMm,
              'quality': quality,
              'gcode': false,
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
      void Function(int) onBytes,
      {Duration stall = const Duration(seconds: 60)}) async {
    // A big video is allowed to take as long as it needs, but not to sit still: if no
    // data moves for [stall] the upload is aborted (the uploader then retries it).
    final stalled = Completer<void>();
    Timer? idle;
    void bump() {
      idle?.cancel();
      idle = Timer(stall, () {
        if (!stalled.isCompleted) stalled.complete();
      });
    }

    final req = http.AbortableStreamedRequest(t.method, Uri.parse(t.url),
        abortTrigger: stalled.future)
      ..headers.addAll(t.headers)
      ..contentLength = length;
    final counted = body.map((chunk) {
      bump();
      onBytes(chunk.length);
      return chunk;
    });
    unawaited(req.sink
        .addStream(counted)
        .catchError((Object e) => req.sink.addError(e))
        .whenComplete(req.sink.close));
    bump();
    try {
      final res = await _http.send(req);
      bump();
      await res.stream.drain<void>();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw ApiException(res.statusCode, 'Upload failed (${res.statusCode})');
      }
    } on http.RequestAbortedException {
      throw ApiException(0, 'The upload stalled. Check the connection.');
    } on http.ClientException {
      throw ApiException(0, 'Upload interrupted. Check the connection.');
    } finally {
      idle?.cancel();
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

  // The desktop's screens all speak plain JSON to the same server; one generic
  // call per verb keeps each screen to its own logic. Paths match the desktop's.
  Future<dynamic> getJson(String path, [Map<String, String>? query]) async =>
      _decode(await _send(() => _http.get(_uri(path, query), headers: _headers)));

  Future<dynamic> _body(String verb, String path, Object? body,
          Map<String, String>? query) async =>
      _decode(await _send(() {
        final u = _uri(path, query);
        final b = body == null ? null : jsonEncode(body);
        return switch (verb) {
          'POST' => _http.post(u, headers: _headers, body: b),
          'PUT' => _http.put(u, headers: _headers, body: b),
          'PATCH' => _http.patch(u, headers: _headers, body: b),
          _ => _http.delete(u, headers: _headers),
        };
      }));

  Future<dynamic> postJson(String path, [Object? body, Map<String, String>? query]) =>
      _body('POST', path, body, query);
  Future<dynamic> putJson(String path, Object body) => _body('PUT', path, body, null);
  Future<dynamic> patchJson(String path, [Object? body]) => _body('PATCH', path, body, null);
  Future<dynamic> deleteJson(String path) => _body('DELETE', path, null, null);

  /// Every product: the server returns at most 100 per call, so read page by page.
  Future<List<Map<String, dynamic>>> allItems() async {
    final out = <Map<String, dynamic>>[];
    while (true) {
      final page = (await getJson('/items/', {'limit': '100', 'offset': '${out.length}'}))
          as List;
      out.addAll(page.cast<Map<String, dynamic>>());
      if (page.length < 100) return out;
    }
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
