import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../../../core/app_config.dart';

class ContentApiService {
  ContentApiService._();

  static Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final base = AppConfig.apiBaseUrl.trim().replaceFirst(RegExp(r'/$'), '');
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    final response = await http.post(
      Uri.parse('$base$path'),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
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

  static Future<Map<String, dynamic>> explain({
    required String topic,
    String sourceText = '',
    String materialId = '',
    String studentLevel = 'university',
    String learningStyle = 'clear examples',
  }) => _post('/api/content/explain', {
    'topic': topic,
    'source_text': sourceText,
    if (materialId.isNotEmpty) 'material_id': materialId,
    'student_level': studentLevel,
    'learning_style': learningStyle,
  });

  static Future<Map<String, dynamic>> flashcards({
    required String topic,
    String sourceText = '',
    String materialId = '',
    int count = 10,
  }) => _post('/api/content/flashcards', {
    'topic': topic,
    'source_text': sourceText,
    if (materialId.isNotEmpty) 'material_id': materialId,
    'count': count,
  });

  static Future<Map<String, dynamic>> revisionSheet({
    String topic = '',
    String sourceText = '',
    String materialId = '',
  }) => _post('/api/content/revision-sheet', {
    'topic': topic,
    'source_text': sourceText,
    if (materialId.isNotEmpty) 'material_id': materialId,
  });

  static Future<Map<String, dynamic>> studyPack({
    required String topic,
    String sourceText = '',
    String materialId = '',
    int questionCount = 5,
  }) => _post('/api/content/study-pack', {
    'topic': topic,
    'source_text': sourceText,
    if (materialId.isNotEmpty) 'material_id': materialId,
    'question_count': questionCount,
  });
}
