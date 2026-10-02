import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../../core/app_config.dart';

class AdaptiveApiService {
  AdaptiveApiService._();

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

  static Future<Map<String, dynamic>> curriculum() =>
      _get('/api/adaptive/curriculum');
  static Future<Map<String, dynamic>> revisionQueue() =>
      _get('/api/adaptive/revision-queue');
  static Future<Map<String, dynamic>> textbook() =>
      _get('/api/adaptive/textbook');
}
