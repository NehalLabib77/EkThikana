import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../core/app_config.dart';
import '../features/study/presentation/rescue/exam_rescue_models.dart';
import 'auth_service.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiService {
  ApiService._();

  /// Shared HTTP client. `package:http` is supposed to keep a single
  /// `Client` per process so the TLS handshake to the Render backend is
  /// amortised across calls. Spinning a fresh `http.Client()` per request
  /// (the previous behaviour) meant every API call paid a full TCP+TLS
  /// round trip — clearly visible on cold starts and on the AI endpoints.
  static final http.Client _client = http.Client();

  /// In-flight request deduplication. If two widgets call the same read-only
  /// endpoint concurrently (e.g. `getStudyStats` from Profile and from
  /// `StudyService.stats()`), the second caller receives the same Future
  /// instead of triggering a duplicate HTTP round-trip. Entries are removed
  /// when the request settles (success or failure).
  static final Map<String, Future<Map<String, dynamic>>> _pendingGet = {};

  static Future<Map<String, dynamic>> _deduplicatedGet(
    String path, {
    Map<String, String>? query,
  }) async {
    final key = 'GET:$path:${query ?? {}}';
    final existing = _pendingGet[key];
    if (existing != null) return existing;

    final future = _decode(await _get(path, query: query));
    _pendingGet.remove(key);
    return future;
  }

  static Uri _uri(String path, [Map<String, String>? query]) {
    final configured = AppConfig.apiBaseUrl.trim();
    if (configured.isEmpty) {
      throw ApiException(
        'Backend URL is not configured. Run Flutter with '
        '--dart-define=API_BASE_URL=https://YOUR-RENDER-SERVICE.onrender.com',
      );
    }
    final base = configured.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  static Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on TimeoutException {
      throw ApiException(
        'Gochano server is taking longer than expected. Render may be waking up; wait a moment and try again.',
      );
    } on SocketException catch (e) {
      throw ApiException(_connectionMessage(e.message));
    } on http.ClientException catch (e) {
      throw ApiException(_connectionMessage(e.message));
    }
  }

  static String _connectionMessage(String details) {
    final base = AppConfig.apiBaseUrl;
    final local = base.contains('127.0.0.1') || base.contains('localhost');
    if (local) {
      return 'Cannot reach the backend at $base. On a physical phone, 127.0.0.1 points to the phone itself. '
          'Use your Render HTTPS URL, your PC Wi-Fi IP, or run "adb reverse tcp:8000 tcp:8000". ($details)';
    }
    return 'Cannot reach the Gochano backend at $base. Check internet/Render status and try again. ($details)';
  }

  static Future<String> _token() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw ApiException('You are not signed in.');
    return token;
  }

  static Future<Map<String, String>> _headers() async => {
    'Authorization': 'Bearer ${await _token()}',
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  /// Returns a route string safe for dev-mode logs (no query parameters,
  /// since query strings can carry tokens and ids). We log the *route*
  /// shape, not the full URL, so a 403 line like
  /// `ApiService auth retry: GET /api/materials/{id}/url after 403`
  /// cannot accidentally include a `?download=true&token=...` blob.
  static String _safeRoute(Uri uri) {
    final path = uri.path;
    return path.isEmpty ? '/' : path;
  }

  /// Dev-only log helper. Never logs request bodies, headers, tokens,
  /// passwords, or file bytes — only method + safe route + status, so a
  /// log capture cannot leak a Firebase ID token.
  static void _debugLog(String message) {
    if (kReleaseMode) return;
    debugPrint('[ApiService] $message');
  }

  /// Central authenticated request funnel.
  ///
  /// Every protected JSON call (GET / POST / PATCH / DELETE) flows
  /// through this method so the 403 → token force-refresh → single
  /// retry policy is uniform. The caller passes a [build] closure that
  /// produces a fresh `http.Request` on each invocation; the funnel
  /// invokes it once, and invokes it *exactly one more time* if the
  /// first response is a 403 (the cached JWT was stale).
  ///
  /// Rules:
  ///   * Maximum one retry. No loop.
  ///   * Public / anonymous requests (`auth: false`) never enter the
  ///     retry path — a 403 there is a real verdict.
  ///   * Real auth failures (401 / 403 *after* the retry) are returned
  ///     to the caller so `_decode` can surface them.
  /// `_send` is the single authenticated-JSON funnel. On `403` it calls
  /// `AuthService.forceRefreshIdToken()` exactly once and replays the
  /// request via the supplied [build] closure. Public calls
  /// (`auth: false`) never retry — `!auth ||` is short-circuited
  /// before any side-effect runs.
  static Future<http.Response> _send({
    required String method,
    required Uri uri,
    required bool auth,
    Duration timeout = const Duration(seconds: 100),
    required Future<http.Request> Function() build,
  }) async {
    return _guard(() async {
      final first = await _client.send(await build()).timeout(timeout);
      final response = await http.Response.fromStream(first);
      // Skip the retry path entirely for public / unauthenticated calls:
      // a 403 on those endpoints is a real verdict, not a stale token.
      // `!auth ||` short-circuits before any side-effect runs.
      if (!auth || response.statusCode != 403) {
        return response;
      }
      // First attempt was 403 on an authenticated request: invalidate
      // the cached JWT and try the SAME logical request exactly once.
      _debugLog('auth retry: $method ${_safeRoute(uri)} after 403');
      await AuthService.forceRefreshIdToken();
      final second = await _client.send(await build()).timeout(timeout);
      return http.Response.fromStream(second);
    });
  }

  /// Multipart funnel. Multipart requests are stateful — once the
  /// underlying `MultipartRequest` has been dispatched, it cannot be
  /// sent again, so the retry must rebuild the request from scratch.
  /// The [build] closure returns a fresh `MultipartRequest` on each
  /// invocation.
  ///
  /// Same 403-retry contract as `_send`. The retry path is the only
  /// legitimate reason this funnel exists — everything else is the
  /// shared `_guard` wrapping.
  static Future<http.Response> _sendMultipart({
    required String method,
    required Uri uri,
    required bool auth,
    Duration timeout = const Duration(seconds: 150),
    required Future<http.MultipartRequest> Function() build,
  }) async {
    return _guard(() async {
      final firstRequest = await build();
      final firstStreamed = await _client.send(firstRequest).timeout(timeout);
      final first = await http.Response.fromStream(firstStreamed);
      if (first.statusCode != 403 || !auth) {
        return first;
      }
      _debugLog('auth retry: $method ${_safeRoute(uri)} after 403');
      await AuthService.forceRefreshIdToken();
      final secondRequest = await build();
      final secondStreamed = await _client.send(secondRequest).timeout(timeout);
      return http.Response.fromStream(secondStreamed);
    });
  }

  /// Handles JSON FastAPI responses as well as Render/nginx plain-text or
  /// HTML 5xx responses. This fixes the old FormatException that hid the
  /// real server error behind "Unexpected character".
  static Map<String, dynamic> _decode(http.Response response) {
    final raw = response.body.trim();
    Map<String, dynamic> body = <String, dynamic>{};

    if (raw.isNotEmpty) {
      try {
        final parsed = jsonDecode(raw);
        if (parsed is Map<String, dynamic>) {
          body = parsed;
        } else if (parsed is Map) {
          body = parsed.map((k, v) => MapEntry(k.toString(), v));
        } else {
          body = {'data': parsed};
        }
      } catch (_) {
        body = {'detail': raw};
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      var detail = body['detail']?.toString().trim();
      if (detail == null || detail.isEmpty) {
        detail = 'API error ${response.statusCode}';
      }
      if (response.statusCode >= 500 &&
          detail.toLowerCase() == 'internal server error') {
        detail =
            'The Gochano backend returned an internal error. Open Render → Logs to see the server traceback.';
      }
      throw ApiException(detail, statusCode: response.statusCode);
    }
    return body;
  }

  static Future<http.Response> _get(
    String path, {
    Map<String, String>? query,
    bool auth = true,
  }) {
    final uri = _uri(path, query);
    return _send(
      method: 'GET',
      uri: uri,
      auth: auth,
      build: () async => http.Request('GET', uri)
        ..headers.addAll(
          auth ? await _headers() : {'Accept': 'application/json'},
        ),
    );
  }

  static Future<http.Response> _post(
    String path, {
    Object? body,
    bool auth = true,
  }) {
    final uri = _uri(path);
    final encoded = body == null ? null : jsonEncode(body);
    return _send(
      method: 'POST',
      uri: uri,
      auth: auth,
      timeout: const Duration(seconds: 120),
      build: () async => http.Request('POST', uri)
        ..headers.addAll(
          auth
              ? await _headers()
              : {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
        )
        ..body = encoded ?? '',
    );
  }

  static Future<http.Response> _delete(String path, {bool auth = true}) {
    final uri = _uri(path);
    return _send(
      method: 'DELETE',
      uri: uri,
      auth: auth,
      build: () async => http.Request('DELETE', uri)
        ..headers.addAll(
          auth ? await _headers() : {'Accept': 'application/json'},
        ),
    );
  }

  static Future<Map<String, dynamic>> health() async =>
      _decode(await _get('/api/health', auth: false));

  static Future<Map<String, dynamic>> createGroup(
    String name,
    String description, {
    String category = '',
    String kind = 'study',
  }) async => _decode(
    await _post(
      '/api/groups',
      body: {
        'name': name,
        'description': description,
        if (category.isNotEmpty) 'category': category,
        if (kind.isNotEmpty) 'kind': kind,
      },
    ),
  );

  static Future<Map<String, dynamic>> joinGroup(String inviteCode) async =>
      _decode(
        await _post('/api/groups/join', body: {'invite_code': inviteCode}),
      );

  static Future<void> leaveGroup(String groupId) async {
    _decode(await _post('/api/groups/$groupId/leave'));
  }

  static Future<String> resetGroupInvite(String groupId) async =>
      _decode(await _post('/api/groups/$groupId/invite/reset'))['inviteCode']
          as String;

  static Future<String> uploadMaterial({
    required Uint8List bytes,
    required String fileName,
    required String title,
    required String visibility,
    String groupId = '',
    String university = '',
    String department = '',
    String semester = '',
    String subject = '',
  }) async {
    final uri = _uri('/api/materials/upload');
    final response = await _sendMultipart(
      method: 'POST',
      uri: uri,
      auth: true,
      build: () async {
        final request = http.MultipartRequest('POST', uri);
        request.headers['Authorization'] = 'Bearer ${await _token()}';
        request.headers['Accept'] = 'application/json';
        request.fields.addAll({
          'title': title,
          'visibility': visibility,
          'group_id': groupId,
          'university': university,
          'department': department,
          'semester': semester,
          'subject': subject,
        });
        request.files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: fileName),
        );
        return request;
      },
    );
    return _decode(response)['id'] as String;
  }

  static Future<String> materialUrl(String id, {bool download = false}) async =>
      _decode(
            await _get(
              '/api/materials/$id/url',
              query: {'download': '$download'},
            ),
          )['url']
          as String;

  static Future<void> saveMaterial(String id) async {
    _decode(await _post('/api/materials/$id/save'));
  }

  static Future<void> deleteMaterial(String id) async {
    final response = await _guard(
      () async => _client
          .delete(_uri('/api/materials/$id'), headers: await _headers())
          .timeout(const Duration(seconds: 100)),
    );
    _decode(response);
  }

  /// Owner-only metadata edit. Pass any of [title], [subject], [description].
  /// To clear description, pass `description: null`. Strings over 1000 chars
  /// are rejected server-side.
  static Future<Map<String, dynamic>> updateMaterial(
    String id, {
    String? title,
    String? subject,
    Object? description = _kOmit,
  }) async {
    final body = <String, dynamic>{};
    if (title != null) body['title'] = title;
    if (subject != null) body['subject'] = subject;
    if (!identical(description, _kOmit)) body['description'] = description;
    return _decode(await _patch('/api/materials/$id', body: body));
  }

  /// Owner-only file replacement. Uploads new bytes as multipart to PUT
  /// /api/materials/{id}/file. materialId stays the same; the server
  /// increments the version on success.
  static Future<Map<String, dynamic>> replaceMaterialFile({
    required String id,
    required Uint8List bytes,
    required String fileName,
  }) async {
    final uri = _uri('/api/materials/$id/file');
    final response = await _sendMultipart(
      method: 'PUT',
      uri: uri,
      auth: true,
      build: () async {
        final request = http.MultipartRequest('PUT', uri);
        request.headers['Authorization'] = 'Bearer ${await _token()}';
        request.headers['Accept'] = 'application/json';
        request.files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: fileName),
        );
        return request;
      },
    );
    return _decode(response);
  }

  static const Object _kOmit = Object();

  static Future<http.Response> _patch(
    String path, {
    Object? body,
    bool auth = true,
  }) {
    final uri = _uri(path);
    final encoded = body == null ? null : jsonEncode(body);
    return _send(
      method: 'PATCH',
      uri: uri,
      auth: auth,
      timeout: const Duration(seconds: 120),
      build: () async => http.Request('PATCH', uri)
        ..headers.addAll(
          auth
              ? await _headers()
              : {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
        )
        ..body = encoded ?? '',
    );
  }

  static Future<String> aiNote(String action, String text) async =>
      _decode(
            await _post('/api/ai/note', body: {'action': action, 'text': text}),
          )['result']
          as String;

  /// Daily AI usage counters and remaining limits across features.
  static Future<Map<String, dynamic>> getAiUsage() async =>
      _decode(await _get('/api/ai/usage'));

  /// Smart Journey Guide: returns an AI-generated human-readable explanation
  /// of verified commute facts. On any failure, returns an empty string so
  /// the client can render the local deterministic guide instead.
  static Future<String> commuteGuide(Map<String, dynamic> facts) async {
    try {
      final body = await _post('/api/ai/commute-guide', body: facts);
      final decoded = _decode(body);
      return (decoded['explanation'] as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> askPdf({
    required String materialId,
    required String question,
    int? page,
  }) async =>
      _decode(
            await _post(
              '/api/ai/pdf-question',
              body: {
                'material_id': materialId,
                'question': question,
                'page': page,
              },
            ),
          )['answer']
          as String;

  static Future<Map<String, dynamic>> prescriptionOcr({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final uri = _uri('/api/prescriptions/extract');
    final response = await _sendMultipart(
      method: 'POST',
      uri: uri,
      auth: true,
      build: () async {
        final request = http.MultipartRequest('POST', uri);
        request.headers['Authorization'] = 'Bearer ${await _token()}';
        request.headers['Accept'] = 'application/json';
        request.files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: fileName),
        );
        return request;
      },
    );
    return _decode(response);
  }

  /// Reads a list field from a decoded response body, never throwing.
  ///
  /// The route that returns focus history names its list `sessions`. The
  /// route that returns offline materials and the one that returns a study
  /// plan both name theirs `items`. Both keys are accepted, and an absent,
  /// null, or wrongly-typed value yields an empty list — so an optional
  /// list that is not there means "nothing", and nothing is an empty list,
  /// not a `Null is not a subtype of List` exception.
  static List<dynamic> _listField(Map<String, dynamic>? body, String key) {
    final value = body?[key];
    if (value is List) return value;
    return const [];
  }

  static Future<List<dynamic>> studyPlan() async => _listField(
    _decode(await _post('/api/study/plan', body: {'max_items': 8})),
    'items',
  );

  static Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
  }) async {
    _decode(
      await _post(
        '/api/reports',
        body: {
          'target_type': targetType,
          'target_id': targetId,
          'reason': reason,
          'details': details,
        },
      ),
    );
  }

  static Future<void> deleteAccount() async {
    final response = await _guard(
      () async => http
          .delete(_uri('/api/account'), headers: await _headers())
          .timeout(const Duration(seconds: 150)),
    );
    _decode(response);
  }

  static Future<Map<String, dynamic>> exportAccount() async =>
      _decode(await _get('/api/account/export'));

  // ---------------- Group chat (member-only, chatEnabled gate) ----------------
  static Future<Map<String, dynamic>> getGroupChat(
    String groupId, {
    int limit = 100,
  }) async => _decode(
    await _get('/api/groups/$groupId/chat', query: {'limit': '$limit'}),
  );

  static Future<Map<String, dynamic>> setGroupChatEnabled(
    String groupId,
    bool enabled,
  ) async => _decode(
    await _post(
      '/api/groups/$groupId/chat/toggle',
      body: {'chatEnabled': enabled},
    ),
  );

  static Future<Map<String, dynamic>> postGroupMessage({
    required String groupId,
    required String text,
    Uint8List? attachmentBytes,
    String? attachmentFilename,
    String? attachmentMime,
  }) async {
    String? attachmentUrl;
    int? attachmentSize;
    if (attachmentBytes != null) {
      attachmentFilename = (attachmentFilename ?? 'attachment.bin').trim();
      if (attachmentFilename.isEmpty) attachmentFilename = 'attachment.bin';
      attachmentMime = (attachmentMime ?? 'application/octet-stream').trim();
      attachmentSize = attachmentBytes.length;
      // Re-use existing storage pipeline (correction 5). Upload as a
      // group-scoped material so the storage layer stays consistent, then
      // post the message with the resulting URL.
      attachmentUrl = await uploadMaterial(
        bytes: attachmentBytes,
        fileName: attachmentFilename,
        title: attachmentFilename,
        visibility: 'group',
        groupId: groupId,
      );
      // materialUrl returns the public URL; for chat we need the signed
      // download URL so the recipient can fetch it.
      attachmentUrl = await materialUrl(attachmentUrl, download: false);
    }
    final body = <String, dynamic>{
      'text': text,
      'attachment_url': ?attachmentUrl,
      'attachment_filename': ?attachmentFilename,
      'attachment_mime': ?attachmentMime,
      'attachment_size': ?attachmentSize,
    };
    return _decode(await _post('/api/groups/$groupId/chat', body: body));
  }

  static Future<Map<String, dynamic>> postGroupMessageReaction({
    required String groupId,
    required String messageId,
    required String emoji,
  }) async => _decode(
    await _post(
      '/api/groups/$groupId/chat/$messageId/react',
      body: {'emoji': emoji},
    ),
  );

  // ---------------- Monthly money (reads central ledger) ----------------
  static String _monthKey(DateTime when) {
    final m = when.month.toString().padLeft(2, '0');
    return '${when.year}-$m';
  }

  static Future<Map<String, dynamic>> setMonthlyBudget(
    DateTime month,
    double amount,
  ) async => _decode(
    await _post(
      '/api/budget/monthly',
      body: {'month_key': _monthKey(month), 'available_amount': amount},
    ),
  );

  static Future<Map<String, dynamic>> getMonthlyBudget(DateTime month) async =>
      _deduplicatedGet(
        '/api/budget/monthly',
        query: {'month_key': _monthKey(month)},
      );

  static Future<Map<String, dynamic>> getRemaining(DateTime month) async =>
      _decode(
        await _get(
          '/api/budget/remaining',
          query: {'month_key': _monthKey(month)},
        ),
      );

  // ---------------- Focus / study stats ----------------
  static Future<Map<String, dynamic>> startFocus({
    String label = '',
    int plannedMinutes = 25,
    String note = '',
    String subject = '',
    String topic = '',
  }) async => _decode(
    await _post(
      '/api/study/focus/start',
      body: {
        'label': label,
        'planned_minutes': plannedMinutes,
        'note': note,
        'subject': subject,
        'topic': topic,
      },
    ),
  );

  /// Pause / resume / complete / cancel a focus session.
  ///
  /// The backend route is `PATCH /api/study/focus/{focus_id}`. This used to
  /// send POST, which FastAPI answered with 405 Method Not Allowed — so
  /// pause, resume and finish never reached the server.
  ///
  /// Phase 2 adds `action: 'interruption'` (counts a distraction while the
  /// timer runs) and optional `subject` / `topic` so a finished session can
  /// be re-tagged with what it actually covered.
  static Future<Map<String, dynamic>> patchFocus(
    String focusId,
    String action, {
    int? interruptions,
    String? subject,
    String? topic,
  }) async => _decode(
    await _patch(
      '/api/study/focus/$focusId',
      body: {
        'action': action,
        'interruptions': ?interruptions,
        'subject': ?subject,
        'topic': ?topic,
      },
    ),
  );

  /// Recent focus sessions within the last [days] (backend accepts 1..365).
  ///
  /// This used to send `limit`, which the route does not declare; FastAPI
  /// ignored it and always applied the default 30-day window.
  ///
  /// The route returns its rows under `sessions`, but `items` is also
  /// accepted so a build against an older backend still works.
  static Future<List<dynamic>> listFocus({int days = 30}) async {
    final body = _decode(
      await _get('/api/study/focus/list', query: {'days': '$days'}),
    );
    final sessions = _listField(body, 'sessions');
    if (sessions.isNotEmpty) return sessions;
    return _listField(body, 'items');
  }

  /// Today's deep-work total plus the Focus Score the Home card shows.
  static Future<Map<String, dynamic>> getFocusToday() async =>
      _deduplicatedGet('/api/study/focus/today');

  static Future<Map<String, dynamic>> getStudyStats() async =>
      _deduplicatedGet('/api/study/stats');

  // ---------------- Ziku Focus Engine (Phase 5) ----------------
  //
  // Same `focus_sessions` store as the legacy `/api/study/focus/*` routes
  // above — the engine adds the Focus Score, weekly consistency and the
  // smart nudge, it does not add a second tracking system.

  /// Begin a deep-work block; returns the session id to finish later.
  static Future<Map<String, dynamic>> focusEngineStart({
    String label = '',
    int plannedMinutes = 25,
    String subject = '',
    String topic = '',
  }) async => _decode(
    await _post(
      '/api/focus/start',
      body: {
        'label': label,
        'planned_minutes': plannedMinutes,
        'subject': subject,
        'topic': topic,
      },
    ),
  );

  /// Finish a block. Idempotent server-side; the response carries the fresh
  /// `today` snapshot (minutes, Focus Score, nudge) for the completion card.
  static Future<Map<String, dynamic>> focusEngineComplete(
    String focusId, {
    String? subject,
    String? topic,
  }) async => _decode(
    await _post(
      '/api/focus/complete',
      body: {'focus_id': focusId, 'subject': subject, 'topic': topic},
    ),
  );

  /// Today's minutes vs goal, the rolling Focus Score, weekly consistency,
  /// live session ids and the smart nudge.
  static Future<Map<String, dynamic>> focusEngineToday() async =>
      _deduplicatedGet('/api/focus/today');

  /// Session list + per-day buckets + score for the last [days] days.
  static Future<Map<String, dynamic>> focusEngineHistory({
    int days = 30,
  }) async =>
      _decode(await _get('/api/focus/history', query: {'days': '$days'}));

  // ---------------- Offline materials (metadata; device-local file is SoT) ----------------
  static Future<Map<String, dynamic>> registerOffline({
    required String materialId,
    required String title,
    required int size,
    required String localPath,
    required String fileType,
    String originalFilename = '',
  }) async => _decode(
    await _post(
      '/api/offline/register',
      body: {
        'material_id': materialId,
        'title': title,
        'size': size,
        'local_path': localPath,
        'file_type': fileType,
        'original_filename': originalFilename,
      },
    ),
  );

  static Future<List<dynamic>> listOffline() async =>
      _listField(_decode(await _get('/api/offline/list')), 'items');

  static Future<void> removeOffline(String materialId) async {
    _decode(await _delete('/api/offline/remove/$materialId'));
  }

  static Future<Map<String, dynamic>> commuteSearch(String query) async {
    return _guard(() async {
      final response = await _client
          .get(
            _uri('/api/commute/search', {'q': query}),
            headers: await _headers(),
          )
          .timeout(const Duration(seconds: 45));
      return _decode(response);
    });
  }

  static Future<Map<String, dynamic>> commuteRoute({
    required String originName,
    required double originLat,
    required double originLon,
    required String destinationName,
    required double destinationLat,
    required double destinationLon,
  }) async {
    return _guard(() async {
      final response = await _client
          .post(
            _uri('/api/commute/route'),
            headers: await _headers(),
            body: jsonEncode({
              'origin_name': originName,
              'origin_lat': originLat,
              'origin_lon': originLon,
              'destination_name': destinationName,
              'destination_lat': destinationLat,
              'destination_lon': destinationLon,
            }),
          )
          .timeout(const Duration(seconds: 90));
      return _decode(response);
    });
  }

  /// PostgreSQL/PostGIS-backed route planning.
  ///
  /// This is the richer of the two commute route endpoints. Compared with
  /// [commuteRoute] it also resolves places against the CommuteBD dataset,
  /// returns `recommendations` already categorised as recommended / cheapest /
  /// fastest, and returns `transitCandidates` — real bus services whose stop
  /// sequences connect the two places, looked up from `bus_service_stops`.
  ///
  /// Flutter previously called only `/api/commute/route`, so none of that
  /// reached the user: the dataset-backed transit lookup was dead code from
  /// the app's point of view (spec §64).
  ///
  /// Pass [originPlaceId]/[destinationPlaceId] from a CommuteBD place search
  /// result when you have one — the backend needs the canonical place id to
  /// match BRTA fare segments. Coordinates alone still work and fall back to
  /// map-only routing.
  static Future<Map<String, dynamic>> commuteRoutes({
    String? originPlaceId,
    String? originName,
    double? originLat,
    double? originLon,
    String? destinationPlaceId,
    String? destinationName,
    double? destinationLat,
    double? destinationLon,
  }) async {
    return _decode(
      await _post(
        '/api/commute/routes',
        body: {
          'origin': {
            'place_id': ?originPlaceId,
            'name': ?originName,
            'lat': ?originLat,
            'lon': ?originLon,
          },
          'destination': {
            'place_id': ?destinationPlaceId,
            'name': ?destinationName,
            'lat': ?destinationLat,
            'lon': ?destinationLon,
          },
        },
      ),
    );
  }

  /// CommuteBD dataset place search (PostgreSQL/PostGIS).
  ///
  /// Returns canonical places with the `placeId` that [commuteRoutes] needs
  /// for official BRTA fare lookup. [commuteSearch] is the wider search that
  /// also includes free-text geocoder results.
  static Future<Map<String, dynamic>> commutePlaceSearch(
    String query, {
    int limit = 15,
  }) async => _decode(
    await _get(
      '/api/commute/places/search',
      query: {'q': query, 'limit': '$limit'},
    ),
  );

  /// CommuteBD stops within [radiusM] of a coordinate.
  static Future<Map<String, dynamic>> commuteNearbyStops({
    required double lat,
    required double lng,
    int radiusM = 1500,
  }) async => _decode(
    await _get(
      '/api/commute/nearby-stops',
      query: {'lat': '$lat', 'lng': '$lng', 'radius_m': '$radiusM'},
    ),
  );

  /// All CommuteBD places with mappable coordinates.
  ///
  /// Used by the map picker so each place can be drawn at its real
  /// position. Returns `{ "places": [ { name, lat, lon, place_id, ... } ] }`.
  /// An empty list means the derived coordinate asset is missing on the
  /// server — the picker treats that as a non-error.
  static Future<Map<String, dynamic>> commuteMapPlaces() async =>
      _decode(await _get('/api/commute/places/map'));

  /// Direct bus service match between two CommuteBD places.
  ///
  /// Returns verified direct bus services connecting the stop pair in order,
  /// with board/exit stops, sequence, and any crowd fare aggregate data.
  static Future<Map<String, dynamic>> directBusMatch({
    required String originPlaceId,
    required String destinationPlaceId,
    int limit = 6,
  }) async => _decode(
    await _get(
      '/api/commute/bus-services/direct-match',
      query: {
        'origin_place_id': originPlaceId,
        'destination_place_id': destinationPlaceId,
        'limit': '$limit',
      },
    ),
  );

  /// Resolve a user-selected place to a canonical CommuteBD place ID.
  ///
  /// Accepts Google Places results, geocoded coordinates, or free-text names
  /// and maps them to canonical CommuteBD place IDs for bus matching.
  static Future<Map<String, dynamic>> resolvePlace({
    String? placeId,
    String? name,
    double? lat,
    double? lon,
  }) async {
    final originBody = <String, dynamic>{};
    if (placeId != null) originBody['place_id'] = placeId;
    if (name != null) originBody['name'] = name;
    if (lat != null) originBody['lat'] = lat;
    if (lon != null) originBody['lon'] = lon;
    return _decode(
      await _post(
        '/api/commute/resolve-place',
        body: {
          'origin': originBody,
          'destination': {'name': '__self__'},
        },
      ),
    );
  }

  /// Search bus services by operator name (English or Bengali).
  static Future<Map<String, dynamic>> searchBusServices(
    String query, {
    int limit = 10,
  }) async => _decode(
    await _get(
      '/api/commute/bus-services/search',
      query: {'q': query, 'limit': '$limit'},
    ),
  );

  /// Get details and ordered stops of a single bus service.
  static Future<Map<String, dynamic>> getBusService(String serviceId) async =>
      _decode(await _get('/api/commute/bus-services/$serviceId'));

  /// Fetch fare for a single user-selected transport mode.
  ///
  /// The caller must have already obtained the route via [commuteRoutes] and
  /// passes the route's distanceKm and drivingMinutes so no OSRM rerun occurs.
  /// The endpoint uses origin/destination names for dataset matching (bus
  /// segment lookup, metro station resolution) but does not call any routing
  /// service.
  static Future<Map<String, dynamic>> commuteSingleFare({
    required String originPlaceId,
    required String originName,
    required double originLat,
    required double originLon,
    required String destinationPlaceId,
    required String destinationName,
    required double destinationLat,
    required double destinationLon,
    required String mode,
    required double distanceKm,
    required int drivingMinutes,
    String? busServiceId,
  }) async {
    return _guard(() async {
      final response = await _client
          .post(
            _uri('/api/commute/single-fare'),
            headers: await _headers(),
            body: jsonEncode({
              'origin': {
                'place_id': originPlaceId,
                'name': originName,
                'lat': originLat,
                'lon': originLon,
              },
              'destination': {
                'place_id': destinationPlaceId,
                'name': destinationName,
                'lat': destinationLat,
                'lon': destinationLon,
              },
              'mode': mode,
              'distance_km': distanceKm,
              'driving_minutes': drivingMinutes,
              if (busServiceId != null && busServiceId.isNotEmpty)
                'bus_service_id': busServiceId,
            }),
          )
          .timeout(const Duration(seconds: 60));
      return _decode(response);
    });
  }

  static Future<Map<String, dynamic>> reportCommuteFare({
    required String originText,
    required String destinationText,
    required String mode,
    required double farePaid,
    double? originLat,
    double? originLon,
    double? destinationLat,
    double? destinationLon,
    int? tripMinutes,
    double? routeDistanceKm,
    String trafficLevel = 'unknown',
    String paymentType = 'cash',
    String? routeId,
    bool locationVerified = false,
    String? busServiceId,
    String? busNameUserEntered,
    String? originPlaceId,
    String? destinationPlaceId,
  }) async {
    return _guard(() async {
      final response = await _client
          .post(
            _uri('/api/commute/fare-report'),
            headers: await _headers(),
            body: jsonEncode({
              'origin_text': originText,
              'destination_text': destinationText,
              'origin_lat': originLat,
              'origin_lon': originLon,
              'destination_lat': destinationLat,
              'destination_lon': destinationLon,
              'transport_mode': mode,
              'fare_paid_tk': farePaid,
              'trip_minutes': tripMinutes,
              'route_distance_km': routeDistanceKm,
              'traffic_level': trafficLevel,
              'payment_type': paymentType,
              'route_id_if_known': routeId,
              'device_location_verified': locationVerified,
              if (busServiceId != null && busServiceId.isNotEmpty)
                'bus_service_id': busServiceId,
              if (busNameUserEntered != null && busNameUserEntered.isNotEmpty)
                'bus_name_user_entered': busNameUserEntered,
              if (originPlaceId != null && originPlaceId.isNotEmpty)
                'origin_place_id': originPlaceId,
              if (destinationPlaceId != null && destinationPlaceId.isNotEmpty)
                'destination_place_id': destinationPlaceId,
            }),
          )
          .timeout(const Duration(seconds: 90));
      return _decode(response);
    });
  }

  static Future<Uint8List> downloadBytes(String url) async {
    final response = await _guard(
      () async =>
          _client.get(Uri.parse(url)).timeout(const Duration(seconds: 150)),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        'Download failed (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    return response.bodyBytes;
  }

  // ----- AI image / OCR flow ---------------------------------------------
  // Image upload is handled by uploadMaterial() above (it routes PDFs and
  // images through the same backend endpoint). We just call the new
  // /api/ai/image-question endpoint with the resulting material id.
  static Future<String> askImage({
    required String materialId,
    required String question,
  }) async {
    return _guard(() async {
      final uri = _uri('/api/ai/image-question');
      final body = jsonEncode({
        'material_id': materialId,
        'question': question,
      });
      final response = await _send(
        method: 'POST',
        uri: uri,
        auth: true,
        timeout: const Duration(seconds: 90),
        build: () async {
          final request = http.Request('POST', uri);
          request.headers.addAll(await _headers());
          request.body = body;
          return request;
        },
      );
      final data = _decode(response);
      return (data['answer'] as String?) ?? '';
    });
  }

  // ----- Profile photo ---------------------------------------------------

  /// Determine MIME type from a file path extension.
  ///
  /// `ImagePicker` on Android may return files where the extension is missing
  /// or mismatched (e.g. a HEIC image with a `.jpg` extension after
  /// compression). `MultipartFile.fromPath` relies on `lookupMimeType` which
  /// can fall back to `application/octet-stream`, causing a 415 from the
  /// backend. This method explicitly maps known image extensions.
  static String _imageContentType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        // Let the http package attempt detection; the backend will reject
        // anything not in the allowed set with a clear 415.
        return 'application/octet-stream';
    }
  }

  /// Upload a profile photo. Returns the signed URL for immediate display.
  static Future<String> uploadProfilePhoto(String filePath) async {
    return _guard(() async {
      final uri = _uri('/api/account/profile-photo');
      final contentType = _imageContentType(filePath);
      final file = await http.MultipartFile.fromPath(
        'file',
        filePath,
        contentType: MediaType.parse(contentType),
      );
      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(await _headers())
        ..files.add(file);
      final streamed = await _client.send(request);
      final response = await http.Response.fromStream(streamed);
      final data = _decode(response);
      return (data['photoURL'] as String?) ?? '';
    });
  }

  /// Get a fresh signed URL for the current profile photo.
  static Future<String?> refreshProfilePhotoUrl() async {
    return _guard(() async {
      final uri = _uri('/api/account/profile-photo-url');
      final response = await _send(
        method: 'GET',
        uri: uri,
        auth: true,
        build: () async =>
            http.Request('GET', uri)..headers.addAll(await _headers()),
      );
      final data = _decode(response);
      return data['photoURL'] as String?;
    });
  }

  // ==========================================================================
  // Phase 3B — AI Study Intelligence
  // ==========================================================================

  /// Assignment Assistant: explain what an assignment requires.
  static Future<String> assignmentExplain({
    required String title,
    String description = '',
    String instructions = '',
  }) async {
    return _guard(() async {
      final body = await _post(
        '/api/ai/assignment/explain',
        body: {
          'title': title,
          'description': description,
          'instructions': instructions,
        },
      );
      return (_decode(body)['explanation'] as String?) ?? '';
    });
  }

  /// Assignment Assistant: break down into sections.
  static Future<String> assignmentBreakdown({
    required String title,
    String description = '',
    String instructions = '',
    String? deadline,
  }) async {
    return _guard(() async {
      final body = await _post(
        '/api/ai/assignment/breakdown',
        body: {
          'title': title,
          'description': description,
          'instructions': instructions,
          'deadline': deadline,
        },
      );
      return (_decode(body)['breakdown'] as String?) ?? '';
    });
  }

  /// Assignment Assistant: deadline-aware study plan.
  static Future<String> assignmentPlan({
    required String title,
    String description = '',
    String instructions = '',
    required String deadline,
  }) async {
    return _guard(() async {
      final body = await _post(
        '/api/ai/assignment/plan',
        body: {
          'title': title,
          'description': description,
          'instructions': instructions,
          'deadline': deadline,
        },
      );
      return (_decode(body)['plan'] as String?) ?? '';
    });
  }

  /// Quiz Generator: generate quiz questions from source material.
  static Future<Map<String, dynamic>> quizGenerate({
    String source = '',
    List<String> sourceIds = const [],
    String topic = '',
    int questionCount = 5,
    String difficulty = 'medium',
    String questionType = 'mcq',
  }) async {
    return _guard(() async {
      final body = await _post(
        '/api/ai/quiz/generate',
        body: {
          'source': source,
          'sourceIds': sourceIds,
          'topic': topic,
          'questionCount': questionCount,
          'difficulty': difficulty,
          'questionType': questionType,
        },
      );
      return _decode(body);
    });
  }

  /// Exam Rescue: generate a focused structured exam rescue plan (Phase T2/T3).
  static Future<ExamRescuePlan> generateExamRescuePlan({
    required String examTitle,
    required DateTime examDate,
    int dailyMinutes = 120,
    List<String> materialIds = const [],
    String? extraTopics,
  }) async {
    return _guard(() async {
      final body = await _post(
        '/api/ai/exam-rescue/plan',
        body: {
          'examTitle': examTitle,
          'examDate': examDate.toIso8601String().split('T').first,
          'dailyMinutes': dailyMinutes,
          'materialIds': materialIds,
          if (extraTopics != null && extraTopics.trim().isNotEmpty)
            'extraTopics': extraTopics.trim(),
        },
      );
      final json = _decode(body);
      return ExamRescuePlan.fromJson(json);
    });
  }

  /// Smart Study Planner: get AI daily recommendations.
  static Future<String> smartPlannerRecommend({
    int availableHours = 4,
    List<String> preferredSubjects = const [],
  }) async {
    return _guard(() async {
      final body = await _post(
        '/api/ai/planner/recommend',
        body: {
          'availableHours': availableHours,
          'preferredSubjects': preferredSubjects,
        },
      );
      return (_decode(body)['recommendation'] as String?) ?? '';
    });
  }

  /// AI Context Builder: fetch user's study data for enhanced AI context.
  static Future<Map<String, dynamic>> buildAiContext({
    required String contextType,
    String extraContext = '',
  }) async {
    return _guard(() async {
      final body = await _post(
        '/api/ai/context',
        body: {'contextType': contextType, 'extraContext': extraContext},
      );
      return _decode(body);
    });
  }

  /// Save quiz result to Firestore via backend.
  static Future<Map<String, dynamic>> saveQuizResult({
    required List<Map<String, dynamic>> questions,
    required List<String> userAnswers,
    required List<String> correctAnswers,
    required int score,
    Map<String, int> topicScores = const {},
    String subjectId = '',
    String materialId = '',
    String difficulty = 'medium',
    int timeSpentSeconds = 0,
  }) async {
    return _guard(() async {
      final body = await _post(
        '/api/ai/quiz/save-result',
        body: {
          'questions': questions,
          'userAnswers': userAnswers,
          'correctAnswers': correctAnswers,
          'score': score,
          'topicScores': topicScores,
          'subjectId': subjectId,
          'materialId': materialId,
          'difficulty': difficulty,
          'timeSpentSeconds': timeSpentSeconds,
        },
      );
      return _decode(body);
    });
  }

  /// Get quiz history (newest first).
  static Future<Map<String, dynamic>> getQuizHistory({int limit = 20}) async {
    return _guard(() async {
      final body = await _get(
        '/api/ai/quiz/history',
        query: {'limit': '$limit'},
      );
      return _decode(body);
    });
  }

  /// Get a single quiz result with full question details.
  static Future<Map<String, dynamic>> getQuizResult(String quizId) async {
    return _guard(() async {
      final body = await _get('/api/ai/quiz/history/$quizId');
      return _decode(body);
    });
  }

  /// Get weak topics from quiz history analysis.
  static Future<Map<String, dynamic>> getWeakTopics({
    int threshold = 60,
  }) async {
    return _guard(() async {
      final body = await _get(
        '/api/ai/learning/weak-topics',
        query: {'threshold': '$threshold'},
      );
      return _decode(body);
    });
  }

  /// Get learning summary (overall stats, strong/weak topics).
  static Future<Map<String, dynamic>> getLearningSummary() async {
    return _guard(() async {
      final body = await _get('/api/ai/learning/summary');
      return _decode(body);
    });
  }

  /// Get AI study recommendations.
  static Future<Map<String, dynamic>> getStudyRecommendations() async {
    return _guard(() async {
      final body = await _get('/api/ai/learning/recommendations');
      return _decode(body);
    });
  }

  // -------------------------------------------------------------------------
  // Phase 1 — AI Mistake Memory.
  //
  // Wrong answers saved with a quiz become one record per distinct mistake.
  // These four calls are the whole surface: read them, ask Ziku to explain
  // the not-yet-explained ones, and advance a mistake's review schedule.
  // -------------------------------------------------------------------------

  /// Recorded mistakes, most repeated first. [status] filters the list:
  /// `all`, `due`, `repeated` or `pending`.
  static Future<Map<String, dynamic>> getMistakes({
    String status = 'all',
    int limit = 50,
  }) async {
    return _guard(() async {
      final body = await _get(
        '/api/ai/mistakes',
        query: {'status': status, 'limit': '$limit'},
      );
      return _decode(body);
    });
  }

  /// "My Learning Brain": totals, weak topics, repeats and revision queue.
  static Future<Map<String, dynamic>> getLearningBrain() async {
    return _guard(() async {
      final body = await _get('/api/ai/mistakes/brain');
      return _decode(body);
    });
  }

  /// Ask Ziku to explain every mistake that is still awaiting analysis.
  ///
  /// One request covers a whole batch, so the daily AI allowance is spent on
  /// batches, not on individual questions. Quota/provider failures surface as
  /// an [ApiException] the caller shows rather than silently swallowing.
  static Future<Map<String, dynamic>> analyzeMistakes() async {
    return _guard(() async {
      final body = await _post('/api/ai/mistakes/analyze');
      return _decode(body);
    });
  }

  /// Mark one mistake revised — advances it to the next review date.
  static Future<Map<String, dynamic>> reviewMistake(String mistakeId) async {
    return _guard(() async {
      final body = await _post('/api/ai/mistakes/$mistakeId/review');
      return _decode(body);
    });
  }

  /// Submit feedback on an AI recommendation.
  static Future<Map<String, dynamic>> submitAiFeedback({
    required String feature,
    required String feedback,
    String recommendationId = '',
  }) async {
    return _guard(() async {
      final body = await _post(
        '/api/ai/feedback',
        body: {
          'feature': feature,
          'feedback': feedback,
          'recommendationId': recommendationId,
        },
      );
      return _decode(body);
    });
  }

  /// Multi-turn chat conversation with Ziku AI.
  static Future<Map<String, dynamic>> aiChat({
    required List<Map<String, String>> messages,
    String? currentDestination,
    String? appMode,
    String? contextMaterialId,
  }) async {
    return _guard(() async {
      final body = await _post(
        '/api/ai/chat',
        body: {
          'messages': messages,
          'current_destination': ?currentDestination,
          'app_mode': ?appMode,
          'context_material_id': ?contextMaterialId,
        },
      );
      return _decode(body);
    });
  }

  // ---------------- Phase 2 — Academic Health ----------------

  /// The Academic Health payload: 0-100 score, per-metric breakdown, signals,
  /// weak areas and the rule-based recommendations.
  ///
  /// [examDate] (YYYY-MM-DD) is optional — pass the target exam the student
  /// is currently working towards to score readiness against it.
  static Future<Map<String, dynamic>> getAcademicHealth({
    String? examDate,
  }) async {
    return _guard(() async {
      final body = await _get(
        '/api/ai/academic-health',
        query: examDate == null ? null : {'examDate': examDate},
      );
      return _decode(body);
    });
  }

  /// Daily score snapshots (oldest first) for the trend line.
  static Future<Map<String, dynamic>> getAcademicHealthHistory({
    int days = 30,
  }) async {
    return _guard(() async {
      final body = await _get(
        '/api/ai/academic-health/history',
        query: {'days': '$days'},
      );
      return _decode(body);
    });
  }

  /// Health-rule advice merged with Ziku's AI-authored recommendations.
  static Future<Map<String, dynamic>> getAcademicHealthRecommendations() async {
    return _guard(() async {
      final body = await _get('/api/ai/academic-health/recommendations');
      return _decode(body);
    });
  }

  // ---------------- Phase 3 — Real Exam Simulator ----------------

  /// Build a paper server-side (AI questions, saved quiz questions or a
  /// clone of a previous exam). Returns the exam plus its questions.
  static Future<Map<String, dynamic>> createExam(
    Map<String, dynamic> body,
  ) async {
    return _guard(() async {
      final response = await _post('/api/exams/create', body: body);
      return _decode(response);
    });
  }

  /// Extract questions from an uploaded paper (PDF/image/text). The response
  /// carries the draft questions *with* their answers so the student can
  /// correct them before the exam opens.
  static Future<Map<String, dynamic>> uploadExamPaper({
    required List<int> bytes,
    required String filename,
    String mimeType = '',
    String subject = '',
    int questionCount = 15,
  }) async {
    final uri = _uri('/api/exams/upload');
    final response = await _sendMultipart(
      method: 'POST',
      uri: uri,
      auth: true,
      build: () async {
        final request = http.MultipartRequest('POST', uri);
        request.headers['Authorization'] = 'Bearer ${await _token()}';
        request.headers['Accept'] = 'application/json';
        request.fields.addAll({
          'subject': subject,
          'questionCount': '$questionCount',
        });
        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: filename,
            contentType: mimeType.isEmpty ? null : MediaType.parse(mimeType),
          ),
        );
        return request;
      },
    );
    return _decode(response);
  }

  /// Papers the student already has — the "saved questions" picker.
  static Future<Map<String, dynamic>> listExams({int limit = 20}) async {
    return _guard(() async {
      final body = await _get('/api/exams', query: {'limit': '$limit'});
      return _decode(body);
    });
  }

  static Future<Map<String, dynamic>> getExam(
    String examId, {
    bool includeQuestions = false,
  }) async {
    return _guard(() async {
      final body = await _get(
        '/api/exams/$examId',
        query: {'includeQuestions': '$includeQuestions'},
      );
      return _decode(body);
    });
  }

  /// Open the hall: returns the attempt id, the deadline and the questions
  /// (redacted — no answers).
  static Future<Map<String, dynamic>> startExam(String examId) async {
    return _guard(() async {
      final body = await _post('/api/exams/$examId/start');
      return _decode(body);
    });
  }

  /// Hand the answers to the server for grading, mistake capture and Ziku's
  /// plan. [withAiAnalysis] also generates the Ziku paragraph once.
  static Future<Map<String, dynamic>> submitExam(
    String examId, {
    required String attemptId,
    required List<String> answers,
    int? timeSpentSeconds,
    List<int> markedForReview = const <int>[],
    bool withAiAnalysis = true,
  }) async {
    return _guard(() async {
      final response = await _post(
        '/api/exams/$examId/submit',
        body: <String, dynamic>{
          'attemptId': attemptId,
          'answers': answers,
          'timeSpentSeconds': ?timeSpentSeconds,
          'markedForReview': markedForReview,
          'withAiAnalysis': withAiAnalysis,
        },
      );
      return _decode(response);
    });
  }

  /// The score breakdown: weak topics, mistakes with review dates, the live
  /// Academic Health read and Ziku's rescue plan for this paper.
  static Future<Map<String, dynamic>> getExamAnalysis(
    String examId, {
    String? attemptId,
    bool withAi = false,
  }) async {
    return _guard(() async {
      final body = await _get(
        '/api/exams/$examId/analysis',
        query: {'attemptId': ?attemptId, 'withAi': '$withAi'},
      );
      return _decode(body);
    });
  }

  // ---- Phase 6: Real Exam Simulator Pro ------------------------------------

  /// Reopen the unfinished attempt (spec 6.4). Throws an [ApiException] with
  /// `statusCode` 404 when there is nothing to resume — the caller then
  /// falls back to [startExam].
  static Future<Map<String, dynamic>> resumeExam(
    String examId, {
    String? attemptId,
  }) async {
    return _guard(() async {
      final response = await _post(
        '/api/exams/$examId/resume',
        body: <String, dynamic>{'attemptId': ?attemptId},
      );
      return _decode(response);
    });
  }

  /// Save the selected answers, the review flags and the remaining time
  /// while the paper is still open — the server owns the recovery point.
  static Future<Map<String, dynamic>> saveExamProgress(
    String examId, {
    required String attemptId,
    required List<String> answers,
    List<int> markedForReview = const <int>[],
    int? remainingSeconds,
  }) async {
    return _guard(() async {
      final response = await _post(
        '/api/exams/$examId/save',
        body: <String, dynamic>{
          'attemptId': attemptId,
          'answers': answers,
          'markedForReview': markedForReview,
          'remainingSeconds': ?remainingSeconds,
        },
      );
      return _decode(response);
    });
  }

  /// Freeze the clock — only for papers whose builder allowed a pause.
  static Future<Map<String, dynamic>> pauseExam(
    String examId, {
    required String attemptId,
    int? remainingSeconds,
  }) async {
    return _guard(() async {
      final response = await _post(
        '/api/exams/$examId/pause',
        body: <String, dynamic>{
          'attemptId': attemptId,
          'remainingSeconds': ?remainingSeconds,
        },
      );
      return _decode(response);
    });
  }

  /// "My Exams" (spec 6.9): recent results with the improvement between the
  /// last two papers.
  static Future<Map<String, dynamic>> examHistory({int limit = 20}) async {
    return _guard(() async {
      final body = await _get('/api/exams/history', query: {'limit': '$limit'});
      return _decode(body);
    });
  }

  /// One finished attempt in the submit payload shape — what the history
  /// list opens when a row is tapped.
  static Future<Map<String, dynamic>> getExamResult(
    String examId, {
    String? attemptId,
  }) async {
    return _guard(() async {
      final body = await _get(
        '/api/exams/$examId/result',
        query: {'attemptId': ?attemptId},
      );
      return _decode(body);
    });
  }

  /// Turn a paper's share link on or off (spec 6.10). The link carries the
  /// questions only — marks are never shared.
  static Future<Map<String, dynamic>> shareExam(
    String examId, {
    required bool share,
  }) async {
    return _guard(() async {
      final response = await _post(
        '/api/exams/$examId/share',
        body: <String, dynamic>{'share': share},
      );
      return _decode(response);
    });
  }

  /// Open a paper someone shared by code: redacted questions, no answers.
  static Future<Map<String, dynamic>> getSharedExam(String code) async {
    return _guard(() async {
      final body = await _get('/api/exams/shared/$code');
      return _decode(body);
    });
  }

  // ---- Phase 4: Ziku Personal Study Coach ----------------------------------

  /// Student learning profile (cached today, rule-based, no AI call).
  static Future<Map<String, dynamic>> coachProfile() async {
    return _guard(() async {
      final body = await _get('/api/coach/profile');
      return _decode(body);
    });
  }

  /// Today's coaching brief with mission items (rule-based, cached per day).
  static Future<Map<String, dynamic>> coachDailyBrief() async {
    return _guard(() async {
      final body = await _get('/api/coach/daily');
      return _decode(body);
    });
  }

  /// Weekly academic report (AI narrative, cached per ISO-week).
  static Future<Map<String, dynamic>> coachWeeklyReport() async {
    return _guard(() async {
      final body = await _get('/api/coach/weekly-report');
      return _decode(body);
    });
  }

  /// Force-refresh profile + daily brief (after quiz/exam completion).
  static Future<Map<String, dynamic>> coachRecalculate() async {
    return _guard(() async {
      final body = await _post('/api/coach/recalculate', body: {});
      return _decode(body);
    });
  }

  // ---- Phase 7: Ziku Learning Community ----------------------------------

  /// Question Bank / Learning posts. Filters are optional; `popular` sorts
  /// by answer and useful counts instead of recency.
  static Future<Map<String, dynamic>> listPosts({
    String kind = '',
    String category = '',
    String groupId = '',
    bool popular = false,
    int limit = 30,
  }) async {
    return _guard(() async {
      final body = await _get(
        '/api/community/posts',
        query: {
          if (kind.isNotEmpty) 'kind': kind,
          if (category.isNotEmpty) 'category': category,
          if (groupId.isNotEmpty) 'group_id': groupId,
          if (popular) 'popular': 'true',
          'limit': '$limit',
        },
      );
      return _decode(body);
    });
  }

  /// Create a learning post (question / solution / notes / achievement).
  static Future<Map<String, dynamic>> createPost({
    required String kind,
    required String title,
    String body = '',
    String category = '',
    String groupId = '',
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    return _guard(() async {
      final response = await _post(
        '/api/community/posts',
        body: {
          'kind': kind,
          'title': title,
          'body': body,
          'category': category,
          'group_id': groupId,
          'attachments': attachments,
        },
      );
      return _decode(response);
    });
  }

  /// One post with its answers (group membership enforced server-side).
  static Future<Map<String, dynamic>> getPost(String postId) async {
    return _guard(() async {
      final body = await _get('/api/community/posts/$postId');
      return _decode(body);
    });
  }

  /// Answer a question. Returns the answer plus the post's new answer count.
  static Future<Map<String, dynamic>> addAnswer(
    String postId,
    String text,
  ) async {
    return _guard(() async {
      final body = await _post(
        '/api/community/posts/$postId/answers',
        body: {'body': text},
      );
      return _decode(body);
    });
  }

  /// Asker-only: mark an answer as the accepted one (+5 Learning Points).
  static Future<Map<String, dynamic>> acceptAnswer(
    String postId,
    String answerId,
  ) async {
    return _guard(() async {
      final body = await _post(
        '/api/community/posts/$postId/answers/$answerId/accept',
      );
      return _decode(body);
    });
  }

  /// Mark someone else's answer helpful (+3 Learning Points, once).
  static Future<Map<String, dynamic>> markAnswerHelpful(
    String postId,
    String answerId,
  ) async {
    return _guard(() async {
      final body = await _post(
        '/api/community/posts/$postId/answers/$answerId/helpful',
      );
      return _decode(body);
    });
  }

  /// Mark a peer's notes post useful (+10 Learning Points for its author).
  static Future<Map<String, dynamic>> markPostUseful(String postId) async {
    return _guard(() async {
      final body = await _post('/api/community/posts/$postId/useful');
      return _decode(body);
    });
  }

  /// Learning Points leaderboard — global, or one group's top contributors.
  static Future<Map<String, dynamic>> leaderboard({
    String scope = 'global',
    String groupId = '',
  }) async {
    return _guard(() async {
      final body = await _get(
        '/api/community/leaderboard',
        query: {'scope': scope, if (groupId.isNotEmpty) 'group_id': groupId},
      );
      return _decode(body);
    });
  }

  /// Challenge a classmate with one of your own saved exams.
  static Future<Map<String, dynamic>> createChallenge({
    required String examId,
    String title = '',
    int questionCount = 10,
    int timeLimitMinutes = 15,
    String opponentId = '',
  }) async {
    return _guard(() async {
      final body = await _post(
        '/api/community/challenges',
        body: {
          if (title.isNotEmpty) 'title': title,
          'exam_id': examId,
          'question_count': questionCount,
          'time_limit_minutes': timeLimitMinutes,
          if (opponentId.isNotEmpty) 'opponent_id': opponentId,
        },
      );
      return _decode(body);
    });
  }

  /// Accept a challenge with the invite code the challenger shared.
  static Future<Map<String, dynamic>> joinChallenge(String code) async {
    return _guard(() async {
      final body = await _post(
        '/api/community/challenges/join',
        body: {'code': code},
      );
      return _decode(body);
    });
  }

  /// Challenges I am part of (creator or opponent).
  static Future<Map<String, dynamic>> listChallenges() async {
    return _guard(() async {
      final body = await _get('/api/community/challenges');
      return _decode(body);
    });
  }

  /// One challenge: state plus both participants' results once completed.
  static Future<Map<String, dynamic>> getChallenge(String challengeId) async {
    return _guard(() async {
      final body = await _get('/api/community/challenges/$challengeId');
      return _decode(body);
    });
  }

  /// Refuse a challenge aimed at me.
  static Future<Map<String, dynamic>> declineChallenge(
    String challengeId,
  ) async {
    return _guard(() async {
      final body = await _post(
        '/api/community/challenges/$challengeId/decline',
      );
      return _decode(body);
    });
  }

  /// Start the clock: server serves redacted questions, never the answer key.
  static Future<Map<String, dynamic>> startChallenge(String challengeId) async {
    return _guard(() async {
      final body = await _post('/api/community/challenges/$challengeId/start');
      return _decode(body);
    });
  }

  /// Submit answers for server-side grading (accuracy, topic breakdown).
  static Future<Map<String, dynamic>> submitChallenge(
    String challengeId, {
    required List<dynamic> answers,
    required int durationSeconds,
  }) async {
    return _guard(() async {
      final body = await _post(
        '/api/community/challenges/$challengeId/submit',
        body: {'answers': answers, 'duration_seconds': durationSeconds},
      );
      return _decode(body);
    });
  }

  // ---- Phase 7: Ziku Moderator + group quizzes (on /api/groups) ----------

  /// Ask Ziku a question with the group's study context attached.
  static Future<Map<String, dynamic>> groupZikuAsk(
    String groupId,
    String question,
  ) async {
    return _guard(() async {
      final body = await _post(
        '/api/groups/$groupId/ziku/ask',
        body: {'question': question},
      );
      return _decode(body);
    });
  }

  /// Moderate two competing answers: one verdict + one explanation.
  static Future<Map<String, dynamic>> groupZikuModerate(
    String groupId, {
    required String claimA,
    required String claimB,
    String context = '',
  }) async {
    return _guard(() async {
      final body = await _post(
        '/api/groups/$groupId/ziku/moderate',
        body: {'claim_a': claimA, 'claim_b': claimB, 'context': context},
      );
      return _decode(body);
    });
  }

  /// Suggested discussion topics from group questions (AI, rule fallback).
  static Future<Map<String, dynamic>> groupZikuTopics(String groupId) async {
    return _guard(() async {
      final body = await _post('/api/groups/$groupId/ziku/topics');
      return _decode(body);
    });
  }

  /// Generate a revision quiz for the group (uses the QUIZ quota).
  static Future<Map<String, dynamic>> groupZikuQuiz(
    String groupId, {
    String topic = '',
    int questionCount = 5,
  }) async {
    return _guard(() async {
      final body = await _post(
        '/api/groups/$groupId/ziku/quiz',
        body: {
          if (topic.isNotEmpty) 'topic': topic,
          'question_count': questionCount,
        },
      );
      return _decode(body);
    });
  }

  /// Group insights: hot chapters, weak topics, recent quiz attempts.
  static Future<Map<String, dynamic>> groupInsights(String groupId) async {
    return _guard(() async {
      final body = await _get('/api/groups/$groupId/insights');
      return _decode(body);
    });
  }

  /// Quizzes saved for this group (redacted - no answer key).
  static Future<Map<String, dynamic>> listGroupQuizzes(String groupId) async {
    return _guard(() async {
      final body = await _get('/api/groups/$groupId/quizzes');
      return _decode(body);
    });
  }

  /// One group quiz, still redacted until an attempt is submitted.
  static Future<Map<String, dynamic>> getGroupQuiz(
    String groupId,
    String quizId,
  ) async {
    return _guard(() async {
      final body = await _get('/api/groups/$groupId/quizzes/$quizId');
      return _decode(body);
    });
  }

  /// Submit a group quiz attempt: graded server-side, explanations unlock.
  static Future<Map<String, dynamic>> attemptGroupQuiz(
    String groupId,
    String quizId, {
    required List<dynamic> answers,
    int durationSeconds = 0,
  }) async {
    return _guard(() async {
      final body = await _post(
        '/api/groups/$groupId/quizzes/$quizId/attempt',
        body: {'answers': answers, 'duration_seconds': durationSeconds},
      );
      return _decode(body);
    });
  }

  // ---- Phase 7: Family links (spec 7.7 - architecture only) --------------

  /// Issue a one-time link code a parent redeems (student side).
  static Future<Map<String, dynamic>> familyLinkCode() async {
    return _guard(() async {
      final body = await _post('/api/family/link-code');
      return _decode(body);
    });
  }

  /// Redeem a child's code (parent account).
  static Future<Map<String, dynamic>> familyRedeem(String code) async {
    return _guard(() async {
      final body = await _post('/api/family/link/redeem', body: {'code': code});
      return _decode(body);
    });
  }

  /// Family links I belong to - ids, names and status only (no scores).
  static Future<Map<String, dynamic>> familyLinks() async {
    return _guard(() async {
      final body = await _get('/api/family/links');
      return _decode(body);
    });
  }

  // ---- Phase 8: Ziku Personal Intelligence --------------------------------

  /// "Your Learning Journey": 90 days of exams, quizzes, mistakes, focus
  /// sessions and community activity as one timeline with improvement trends.
  static Future<Map<String, dynamic>> zikuJourney({bool force = false}) async {
    return _guard(() async {
      final body = await _get(
        '/api/ziku/journey',
        query: {if (force) 'force': 'true'},
      );
      return _decode(body);
    });
  }

  /// The upgraded daily brief: morning headings (health, priority, why,
  /// mission) and the evening recap (progress, mistakes, tomorrow).
  static Future<Map<String, dynamic>> zikuBrief({
    String phase = 'auto',
    bool force = false,
  }) async {
    return _guard(() async {
      final body = await _get(
        '/api/ziku/brief',
        query: {
          if (phase != 'auto') 'phase': phase,
          if (force) 'force': 'true',
        },
      );
      return _decode(body);
    });
  }

  /// The Student Learning Profile: preferred study time, learning style and
  /// strong/weak subjects.
  static Future<Map<String, dynamic>> zikuProfile({bool force = false}) async {
    return _guard(() async {
      final body = await _get(
        '/api/ziku/profile',
        query: {if (force) 'force': 'true'},
      );
      return _decode(body);
    });
  }

  /// The Smart Recommendation Engine: five systems ranked into one action,
  /// plus the alternatives that explain why it won.
  static Future<Map<String, dynamic>> zikuNextBestAction({
    bool force = false,
  }) async {
    return _guard(() async {
      final body = await _get(
        '/api/ziku/next-best-action',
        query: {if (force) 'force': 'true'},
      );
      return _decode(body);
    });
  }

  /// The achievement scoreboard (earned stamps are write-once).
  static Future<Map<String, dynamic>> zikuAchievements({
    bool force = false,
  }) async {
    return _guard(() async {
      final body = await _get(
        '/api/ziku/achievements',
        query: {if (force) 'force': 'true'},
      );
      return _decode(body);
    });
  }

  // ---- Phase 10.6: Admin Analytics ----------------------------------------

  /// Platform overview metrics for administrators.
  static Future<Map<String, dynamic>> adminAnalyticsOverview({
    int days = 30,
  }) async {
    return _guard(() async {
      final body = await _get(
        '/api/admin/analytics/overview',
        query: {'days': '$days'},
      );
      return _decode(body);
    });
  }

  /// Subject demand metrics for administrators.
  static Future<Map<String, dynamic>> adminAnalyticsSubjects({
    int days = 30,
  }) async {
    return _guard(() async {
      final body = await _get(
        '/api/admin/analytics/subjects',
        query: {'days': '$days'},
      );
      return _decode(body);
    });
  }

  /// Topic difficulty metrics for administrators.
  static Future<Map<String, dynamic>> adminAnalyticsTopics({
    int days = 30,
  }) async {
    return _guard(() async {
      final body = await _get(
        '/api/admin/analytics/topics',
        query: {'days': '$days'},
      );
      return _decode(body);
    });
  }

  /// Feature usage breakdown for administrators.
  static Future<Map<String, dynamic>> adminAnalyticsFeatures({
    int days = 30,
  }) async {
    return _guard(() async {
      final body = await _get(
        '/api/admin/analytics/features',
        query: {'days': '$days'},
      );
      return _decode(body);
    });
  }

  // ---- Phase 12: Ziku Socratic AI Tutor ------------------------------------

  /// Start a new Socratic tutor session.
  static Future<Map<String, dynamic>> tutorStartSession({
    required String subject,
    required String topic,
    String? concept,
    String mode = 'socratic',
    String? materialId, // Phase 14.5: document-grounded tutor
  }) async {
    return _guard(() async {
      final res = await _post(
        '/api/tutor/session',
        body: {
          'subject': subject,
          'topic': topic,
          if (concept != null && concept.isNotEmpty) 'concept': concept,
          'mode': mode,
          if (materialId != null && materialId.isNotEmpty) 'material_id': materialId,
        },
      );
      return _decode(res);
    });
  }

  /// Submit student response / reasoning to current tutor step.
  static Future<Map<String, dynamic>> tutorRespond({
    required String sessionId,
    required String response,
  }) async {
    return _guard(() async {
      final res = await _post(
        '/api/tutor/$sessionId/respond',
        body: {'response': response},
      );
      return _decode(res);
    });
  }

  /// Request a progressive hint.
  static Future<Map<String, dynamic>> tutorRequestHint({
    required String sessionId,
  }) async {
    return _guard(() async {
      final res = await _post('/api/tutor/$sessionId/hint');
      return _decode(res);
    });
  }

  /// Switch tutor mode (socratic, explain, practice, exam_prep).
  static Future<Map<String, dynamic>> tutorSwitchMode({
    required String sessionId,
    required String mode,
  }) async {
    return _guard(() async {
      final res = await _post(
        '/api/tutor/$sessionId/mode',
        body: {'mode': mode},
      );
      return _decode(res);
    });
  }

  /// Finalize tutor session and receive summary.
  static Future<Map<String, dynamic>> tutorCompleteSession({
    required String sessionId,
  }) async {
    return _guard(() async {
      final res = await _post('/api/tutor/$sessionId/complete');
      return _decode(res);
    });
  }

  /// Get details of an active or past tutor session.
  static Future<Map<String, dynamic>> tutorGetSession(String sessionId) async {
    return _guard(() async {
      final res = await _get('/api/tutor/$sessionId');
      return _decode(res);
    });
  }

  /// Get recent tutor sessions.
  static Future<List<dynamic>> tutorGetRecentSessions({int limit = 10}) async {
    return _guard(() async {
      final res = await _get(
        '/api/tutor/recent',
        query: {'limit': '$limit'},
      );
      final decoded = _decode(res);
      return _listField(decoded, 'data');
    });
  }

  // ---- Phase 12.2.3: Dashboard Bootstrap ---------------------------------

  /// Single aggregate bootstrap call for student home & study dashboard.
  static Future<Map<String, dynamic>> studentDashboardBootstrap() async {
    return _guard(() async {
      final res = await _get('/api/student/dashboard-bootstrap');
      return _decode(res);
    });
  }

  // ---- Phase 14: Document Intelligence -----------------------------------

  /// Trigger document ingestion & chunking.
  /// Idempotent — safe to call again; set [force] to re-process.
  static Future<Map<String, dynamic>> processMaterial(
    String materialId, {
    bool force = false,
  }) async {
    return _guard(() async {
      final res = await _post(
        '/api/materials/$materialId/process',
        body: {'force': force},
      );
      return _decode(res);
    });
  }

  /// Get (or generate) document intelligence — overview, summary, concept map,
  /// important topics.  Returns cached result when available.
  static Future<Map<String, dynamic>> getMaterialIntelligence(
    String materialId, {
    bool force = false,
  }) async {
    return _guard(() async {
      final res = await _get(
        '/api/materials/$materialId/intelligence',
        query: {if (force) 'force': 'true'},
      );
      return _decode(res);
    });
  }

  /// BM25 lexical retrieval of document chunks relevant to [query].
  static Future<Map<String, dynamic>> retrieveDocumentChunks(
    String materialId,
    String query, {
    int topK = 3,
  }) async {
    return _guard(() async {
      final res = await _post(
        '/api/materials/$materialId/retrieve',
        body: {'query': query, 'top_k': topK},
      );
      return _decode(res);
    });
  }

  /// Generate flashcards grounded in document content.
  static Future<Map<String, dynamic>> documentFlashcards(
    String materialId, {
    String topic = '',
    String query = '',
    int count = 10,
  }) async {
    return _guard(() async {
      final res = await _post(
        '/api/materials/$materialId/flashcards',
        body: {'topic': topic, 'query': query, 'count': count},
      );
      return _decode(res);
    });
  }

  /// Generate revision sheet grounded in document content.
  static Future<Map<String, dynamic>> documentRevisionSheet(
    String materialId, {
    String topic = '',
    String query = '',
  }) async {
    return _guard(() async {
      final res = await _post(
        '/api/materials/$materialId/revision-sheet',
        body: {'topic': topic, 'query': query},
      );
      return _decode(res);
    });
  }

  /// Generate complete study pack grounded in document content.
  static Future<Map<String, dynamic>> documentStudyPack(
    String materialId, {
    String topic = '',
    String query = '',
  }) async {
    return _guard(() async {
      final res = await _post(
        '/api/materials/$materialId/study-pack',
        body: {'topic': topic, 'query': query},
      );
      return _decode(res);
    });
  }

  /// Generate quiz questions grounded in document content.
  static Future<Map<String, dynamic>> documentQuiz(
    String materialId, {
    String topic = '',
    String query = '',
    String difficulty = 'medium',
    int count = 5,
  }) async {
    return _guard(() async {
      final res = await _post(
        '/api/materials/$materialId/quiz',
        body: {
          'topic': topic,
          'query': query,
          'difficulty': difficulty,
          'count': count,
        },
      );
      return _decode(res);
    });
  }

  /// Generate a full mock exam grounded in document content.
  static Future<Map<String, dynamic>> documentExam(
    String materialId, {
    String topic = '',
    int timeLimitMinutes = 30,
    int questionCount = 10,
    String difficulty = 'real_exam',
  }) async {
    return _guard(() async {
      final res = await _post(
        '/api/materials/$materialId/exam',
        body: {
          'topic': topic,
          'time_limit_minutes': timeLimitMinutes,
          'question_count': questionCount,
          'difficulty': difficulty,
        },
      );
      return _decode(res);
    });
  }
}


// ---- Phase 4: top-level convenience wrappers (delegate to ApiService) ----

/// Today's Ziku coaching brief.
Future<Map<String, dynamic>> fetchCoachDailyBrief() =>
    ApiService.coachDailyBrief();

/// Weekly academic report.
Future<Map<String, dynamic>> fetchCoachWeeklyReport() =>
    ApiService.coachWeeklyReport();
