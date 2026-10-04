import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../core/app_config.dart';

class CommunityIntelligenceApiService {
  CommunityIntelligenceApiService._();

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final base = AppConfig.apiBaseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
    final uri = Uri.parse('$base$path');
    final response = method == 'POST'
        ? await http.post(uri, headers: headers, body: jsonEncode(body ?? {}))
        : await http.get(uri, headers: headers);
    final decoded = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        decoded is Map
            ? decoded['detail'] ?? 'Request failed'
            : 'Request failed',
      );
    }
    return Map<String, dynamic>.from(decoded as Map);
  }

  static Future<Map<String, dynamic>> feed() =>
      _request('GET', '/api/community/feed');

  static Future<Map<String, dynamic>> askQuestion({
    required String title,
    required String body,
  }) => _request(
    'POST',
    '/api/community/questions',
    body: {'title': title, 'body': body, 'kind': 'question'},
  );

  static Future<Map<String, dynamic>> leaderboard() =>
      _request('GET', '/api/community/leaderboard');
}
