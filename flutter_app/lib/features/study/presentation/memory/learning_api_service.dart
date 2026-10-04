import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../../core/app_config.dart';

class LearningApiService {
  LearningApiService._();

  static Future<Map<String, dynamic>> _get(String path) async {
    final base = AppConfig.apiBaseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final response = await http.get(
      Uri.parse('$base$path'),
      headers: {
        'Accept': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
    );
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

  static Future<Map<String, dynamic>> memory() => _get('/api/learning/memory');
  static Future<Map<String, dynamic>> recommendations() =>
      _get('/api/learning/recommendations');
  static Future<Map<String, dynamic>> progress() =>
      _get('/api/learning/progress');
  static Future<Map<String, dynamic>> contentEffectiveness() =>
      _get('/api/learning/content-effectiveness');
}
