import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../core/app_config.dart';

class ApiService {
  ApiService._();

  static Uri _uri(String path, [Map<String, String>? query]) {
    final base = AppConfig.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  static Future<String> _token() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (token == null) throw Exception('You are not signed in.');
    return token;
  }

  static Future<Map<String, String>> _headers() async => {
        'Authorization': 'Bearer ${await _token()}',
        'Content-Type': 'application/json',
      };

  static Map<String, dynamic> _decode(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['detail']?.toString() ?? 'API error ${response.statusCode}');
    }
    return body;
  }

  static Future<Map<String, dynamic>> health() async {
    final response = await http
        .get(_uri('/api/health'))
        .timeout(const Duration(seconds: 90));
    return _decode(response);
  }

  static Future<Map<String, dynamic>> createGroup(
    String name,
    String description,
  ) async {
    final response = await http
        .post(
          _uri('/api/groups'),
          headers: await _headers(),
          body: jsonEncode({'name': name, 'description': description}),
        )
        .timeout(const Duration(seconds: 90));
    return _decode(response);
  }

  static Future<Map<String, dynamic>> joinGroup(String inviteCode) async {
    final response = await http
        .post(
          _uri('/api/groups/join'),
          headers: await _headers(),
          body: jsonEncode({'invite_code': inviteCode}),
        )
        .timeout(const Duration(seconds: 90));
    return _decode(response);
  }


  static Future<void> leaveGroup(String groupId) async {
    final response = await http
        .post(
          _uri('/api/groups/$groupId/leave'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 90));
    _decode(response);
  }

  static Future<String> resetGroupInvite(String groupId) async {
    final response = await http
        .post(
          _uri('/api/groups/$groupId/invite/reset'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 90));
    return _decode(response)['inviteCode'] as String;
  }

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
    final request = http.MultipartRequest(
      'POST',
      _uri('/api/materials/upload'),
    );
    request.headers['Authorization'] = 'Bearer ${await _token()}';
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
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      ),
    );
    final streamed = await request.send().timeout(const Duration(seconds: 120));
    final response = await http.Response.fromStream(streamed);
    return _decode(response)['id'] as String;
  }

  static Future<String> materialUrl(
    String id, {
    bool download = false,
  }) async {
    final response = await http
        .get(
          _uri('/api/materials/$id/url', {'download': '$download'}),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 90));
    return _decode(response)['url'] as String;
  }

  static Future<void> saveMaterial(String id) async {
    final response = await http
        .post(
          _uri('/api/materials/$id/save'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 90));
    _decode(response);
  }

  static Future<void> deleteMaterial(String id) async {
    final response = await http
        .delete(
          _uri('/api/materials/$id'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 90));
    _decode(response);
  }

  static Future<String> aiNote(String action, String text) async {
    final response = await http
        .post(
          _uri('/api/ai/note'),
          headers: await _headers(),
          body: jsonEncode({'action': action, 'text': text}),
        )
        .timeout(const Duration(seconds: 120));
    return _decode(response)['result'] as String;
  }

  static Future<String> askPdf({
    required String materialId,
    required String question,
    int? page,
  }) async {
    final response = await http
        .post(
          _uri('/api/ai/pdf-question'),
          headers: await _headers(),
          body: jsonEncode({
            'material_id': materialId,
            'question': question,
            'page': page,
          }),
        )
        .timeout(const Duration(seconds: 120));
    return _decode(response)['answer'] as String;
  }

  static Future<Map<String, dynamic>> prescriptionOcr({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('/api/prescriptions/extract'),
    );
    request.headers['Authorization'] = 'Bearer ${await _token()}';
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: fileName),
    );
    final streamed = await request.send().timeout(const Duration(seconds: 120));
    final response = await http.Response.fromStream(streamed);
    return _decode(response);
  }

  static Future<List<dynamic>> studyPlan() async {
    final response = await http
        .post(
          _uri('/api/study/plan'),
          headers: await _headers(),
          body: jsonEncode({'max_items': 8}),
        )
        .timeout(const Duration(seconds: 90));
    return _decode(response)['items'] as List<dynamic>;
  }


  static Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String details = '',
  }) async {
    final response = await http
        .post(
          _uri('/api/reports'),
          headers: await _headers(),
          body: jsonEncode({
            'target_type': targetType,
            'target_id': targetId,
            'reason': reason,
            'details': details,
          }),
        )
        .timeout(const Duration(seconds: 90));
    _decode(response);
  }

  static Future<void> deleteAccount() async {
    final response = await http
        .delete(
          _uri('/api/account'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 120));
    _decode(response);
  }

  /// §29 Data export. Returns the user's accessible personal records as
  /// plain JSON. Never contains secrets or binary file contents — the
  /// backend filters those out before responding.
  static Future<Map<String, dynamic>> exportAccount() async {
    final response = await http
        .get(
          _uri('/api/account/export'),
          headers: await _headers(),
        )
        .timeout(const Duration(seconds: 90));
    return _decode(response);
  }

  static Future<Uint8List> downloadBytes(String url) async {
    final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 120));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Download failed (${response.statusCode})');
    }
    return response.bodyBytes;
  }
}
