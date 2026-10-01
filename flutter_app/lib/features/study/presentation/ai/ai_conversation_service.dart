import 'package:flutter/foundation.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';

class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.isError = false,
  });

  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime timestamp;
  final bool isError;

  bool get isUser => role == 'user';
}

class AiConversationService extends ChangeNotifier {
  AiConversationService._internal();
  static final AiConversationService instance = AiConversationService._internal();

  final List<ChatMessage> _messages = [];
  final List<String> _suggestions = [
    'Explain key concept simply',
    'Generate quick practice questions',
    'How should I structure my study plan today?',
    'Summarize my weak topics',
  ];

  bool _loading = false;
  String? _contextMaterialId;
  String? _contextMaterialTitle;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<String> get suggestions => List.unmodifiable(_suggestions);
  bool get loading => _loading;
  bool get hasActiveContext => _contextMaterialId != null;
  String? get contextMaterialId => _contextMaterialId;
  String? get contextMaterialTitle => _contextMaterialTitle;

  void setContextMaterial({required String id, required String title}) {
    _contextMaterialId = id;
    _contextMaterialTitle = title;
    notifyListeners();
  }

  void clearContextMaterial() {
    _contextMaterialId = null;
    _contextMaterialTitle = null;
    notifyListeners();
  }

  void clearConversation() {
    _messages.clear();
    _contextMaterialId = null;
    _contextMaterialTitle = null;
    _suggestions
      ..clear()
      ..addAll([
        'Explain key concept simply',
        'Generate quick practice questions',
        'How should I structure my study plan today?',
        'Summarize my weak topics',
      ]);
    _loading = false;
    notifyListeners();
  }

  Future<void> sendMessage(
    String content, {
    String? currentDestination,
    String? appMode,
  }) async {
    final text = content.trim();
    if (text.isEmpty || _loading) return;

    _messages.add(
      ChatMessage(
        role: 'user',
        content: text,
        timestamp: DateTime.now(),
      ),
    );
    _loading = true;
    notifyListeners();

    try {
      final history = _messages
          .where((m) => !m.isError)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();

      final res = await ApiService.aiChat(
        messages: history,
        currentDestination: currentDestination,
        appMode: appMode,
        contextMaterialId: _contextMaterialId,
      );

      final reply = (res['reply'] as String?)?.trim() ?? '';
      final followups = (res['suggested_followups'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      _messages.add(
        ChatMessage(
          role: 'assistant',
          content: reply.isEmpty
              ? GochanoLanguage.text(
                  'I am here to help. Could you ask in another way?',
                  'আমি সাহায্য করতে প্রস্তুত। অন্যভাবে লিখে জিজ্ঞেস করবেন কি?',
                )
              : reply,
          timestamp: DateTime.now(),
        ),
      );

      _suggestions.clear();
      if (followups.isNotEmpty) {
        _suggestions.addAll(followups);
      } else {
        _suggestions.addAll([
          'Give me an example',
          'Explain with real-world application',
          'Test me with a quiz question',
        ]);
      }
    } catch (e) {
      _messages.add(
        ChatMessage(
          role: 'assistant',
          content: GochanoLanguage.text(
            'Unable to contact AI service right now. Please try again.',
            'এই মুহূর্তে এআই সার্ভিসে যোগাযোগ করা যায়নি। অনুগ্রহ করে আবার চেষ্টা করুন।',
          ),
          timestamp: DateTime.now(),
          isError: true,
        ),
      );
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
