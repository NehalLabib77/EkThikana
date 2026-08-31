import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../core/app_config.dart';

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
      if (response.statusCode >= 500 && detail.toLowerCase() == 'internal server error') {
        detail = 'The Gochano backend returned an internal error. Open Render → Logs to see the server traceback.';
      }
      throw ApiException(detail, statusCode: response.statusCode);
    }
    return body;
  }

  static Future<http.Response> _get(String path, {Map<String, String>? query, bool auth = true}) {
    return _guard(() async => http
        .get(_uri(path, query), headers: auth ? await _headers() : {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 100)));
  }

  static Future<http.Response> _post(String path, {Object? body, bool auth = true}) {
    return _guard(() async => http
        .post(
          _uri(path),
          headers: auth ? await _headers() : {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 120)));
  }

  static Future<http.Response> _delete(String path, {bool auth = true}) {
    return _guard(() async => http
        .delete(_uri(path), headers: auth ? await _headers() : {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 100)));
  }

  static Future<Map<String, dynamic>> health() async => _decode(await _get('/api/health', auth: false));

  static Future<Map<String, dynamic>> createGroup(String name, String description) async =>
      _decode(await _post('/api/groups', body: {'name': name, 'description': description}));

  static Future<Map<String, dynamic>> joinGroup(String inviteCode) async =>
      _decode(await _post('/api/groups/join', body: {'invite_code': inviteCode}));

  static Future<void> leaveGroup(String groupId) async {
    _decode(await _post('/api/groups/$groupId/leave'));
  }

  static Future<String> resetGroupInvite(String groupId) async =>
      _decode(await _post('/api/groups/$groupId/invite/reset'))['inviteCode'] as String;

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
    return _guard(() async {
      final request = http.MultipartRequest('POST', _uri('/api/materials/upload'));
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
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 150));
      final response = await http.Response.fromStream(streamed);
      return _decode(response)['id'] as String;
    });
  }

  static Future<String> materialUrl(String id, {bool download = false}) async =>
      _decode(await _get('/api/materials/$id/url', query: {'download': '$download'}))['url'] as String;

  static Future<void> saveMaterial(String id) async {
    _decode(await _post('/api/materials/$id/save'));
  }

  static Future<void> deleteMaterial(String id) async {
    final response = await _guard(() async => _client
        .delete(_uri('/api/materials/$id'), headers: await _headers())
        .timeout(const Duration(seconds: 100)));
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
    return _guard(() async {
      final request = http.MultipartRequest('PUT', _uri('/api/materials/$id/file'));
      request.headers['Authorization'] = 'Bearer ${await _token()}';
      request.headers['Accept'] = 'application/json';
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 150));
      return _decode(await http.Response.fromStream(streamed));
    });
  }

  static const Object _kOmit = Object();

  static Future<http.Response> _patch(String path, {Object? body, bool auth = true}) {
    return _guard(() async => _client
        .patch(
          _uri(path),
          headers: auth ? await _headers() : {'Content-Type': 'application/json', 'Accept': 'application/json'},
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 120)));
  }

  static Future<String> aiNote(String action, String text) async =>
      _decode(await _post('/api/ai/note', body: {'action': action, 'text': text}))['result'] as String;

  static Future<String> askPdf({required String materialId, required String question, int? page}) async =>
      _decode(await _post('/api/ai/pdf-question', body: {
        'material_id': materialId,
        'question': question,
        'page': page,
      }))['answer'] as String;

  static Future<Map<String, dynamic>> prescriptionOcr({
    required Uint8List bytes,
    required String fileName,
  }) async {
    return _guard(() async {
      final request = http.MultipartRequest('POST', _uri('/api/prescriptions/extract'));
      request.headers['Authorization'] = 'Bearer ${await _token()}';
      request.headers['Accept'] = 'application/json';
      request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 150));
      return _decode(await http.Response.fromStream(streamed));
    });
  }

  static Future<List<dynamic>> studyPlan() async =>
      _decode(await _post('/api/study/plan', body: {'max_items': 8}))['items'] as List<dynamic>;

  static Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
  }) async {
    _decode(await _post('/api/reports', body: {
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
      'details': details,
    }));
  }

  static Future<void> deleteAccount() async {
    final response = await _guard(() async => http
        .delete(_uri('/api/account'), headers: await _headers())
        .timeout(const Duration(seconds: 150)));
    _decode(response);
  }

  static Future<Map<String, dynamic>> exportAccount() async =>
      _decode(await _get('/api/account/export'));


  // ---------------- Group chat (member-only, chatEnabled gate) ----------------
  static Future<Map<String, dynamic>> getGroupChat(String groupId, {int limit = 100}) async =>
      _decode(await _get('/api/groups/$groupId/chat', query: {'limit': '$limit'}));

  static Future<Map<String, dynamic>> setGroupChatEnabled(String groupId, bool enabled) async =>
      _decode(await _post('/api/groups/$groupId/chat/toggle', body: {'chatEnabled': enabled}));

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

  // ---------------- Monthly money (reads central ledger) ----------------
  static String _monthKey(DateTime when) {
    final m = when.month.toString().padLeft(2, '0');
    return '${when.year}-$m';
  }

  static Future<Map<String, dynamic>> setMonthlyBudget(DateTime month, double amount) async =>
      _decode(await _post('/api/budget/monthly', body: {
        'month_key': _monthKey(month),
        'available_amount': amount,
      }));

  static Future<Map<String, dynamic>> getMonthlyBudget(DateTime month) async =>
      _decode(await _get('/api/budget/monthly', query: {'month_key': _monthKey(month)}));

  static Future<Map<String, dynamic>> getRemaining(DateTime month) async =>
      _decode(await _get('/api/budget/remaining', query: {'month_key': _monthKey(month)}));

  // ---------------- Focus / study stats ----------------
  static Future<Map<String, dynamic>> startFocus({
    String label = '',
    int plannedMinutes = 25,
    String note = '',
  }) async =>
      _decode(await _post('/api/study/focus/start', body: {
        'label': label,
        'planned_minutes': plannedMinutes,
        'note': note,
      }));

  /// Pause / resume / complete / cancel a focus session.
  ///
  /// The backend route is `PATCH /api/study/focus/{focus_id}`. This used to
  /// send POST, which FastAPI answered with 405 Method Not Allowed — so
  /// pause, resume and finish never reached the server.
  static Future<Map<String, dynamic>> patchFocus(String focusId, String action) async =>
      _decode(await _patch('/api/study/focus/$focusId', body: {'action': action}));

  static Future<List<dynamic>> listFocus({int limit = 100}) async =>
      _decode(await _get('/api/study/focus/list', query: {'limit': '$limit'}))['items'] as List<dynamic>;

  static Future<Map<String, dynamic>> getStudyStats() async =>
      _decode(await _get('/api/study/stats'));

  // ---------------- Offline materials (metadata; device-local file is SoT) ----------------
  static Future<Map<String, dynamic>> registerOffline({
    required String materialId,
    required String title,
    required int size,
    required String localPath,
    required String fileType,
    String originalFilename = '',
  }) async =>
      _decode(await _post('/api/offline/register', body: {
        'material_id': materialId,
        'title': title,
        'size': size,
        'local_path': localPath,
        'file_type': fileType,
        'original_filename': originalFilename,
      }));

  static Future<List<dynamic>> listOffline() async =>
      _decode(await _get('/api/offline/list'))['items'] as List<dynamic>;

  static Future<void> removeOffline(String materialId) async {
    _decode(await _delete('/api/offline/remove/$materialId'));
  }


  static Future<Map<String, dynamic>> commuteSearch(String query) async {
    return _guard(() async {
      final response = await _client.get(
        _uri('/api/commute/search', {'q': query}),
        headers: await _headers(),
      ).timeout(const Duration(seconds: 45));
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
      final response = await _client.post(
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
      ).timeout(const Duration(seconds: 90));
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
  }) async =>
      _decode(await _get(
        '/api/commute/places/search',
        query: {'q': query, 'limit': '$limit'},
      ));

  /// CommuteBD stops within [radiusM] of a coordinate.
  static Future<Map<String, dynamic>> commuteNearbyStops({
    required double lat,
    required double lng,
    int radiusM = 1500,
  }) async =>
      _decode(await _get(
        '/api/commute/nearby-stops',
        query: {'lat': '$lat', 'lng': '$lng', 'radius_m': '$radiusM'},
      ));

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
  }) async {
    return _guard(() async {
      final response = await _client.post(
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
        }),
      ).timeout(const Duration(seconds: 90));
      return _decode(response);
    });
  }

  static Future<Uint8List> downloadBytes(String url) async {
    final response = await _guard(() async => _client.get(Uri.parse(url)).timeout(const Duration(seconds: 150)));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('Download failed (${response.statusCode})', statusCode: response.statusCode);
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
      final response = await http
          .post(
            _uri('/api/ai/image-question'),
            headers: await _headers(),
            body: jsonEncode({
              'material_id': materialId,
              'question': question,
            }),
          )
          .timeout(const Duration(seconds: 90));
      final data = _decode(response);
      return (data['answer'] as String?) ?? '';
    });
  }
}
