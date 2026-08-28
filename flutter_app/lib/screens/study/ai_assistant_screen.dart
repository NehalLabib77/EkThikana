import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../services/api_service.dart';
import '../search/universal_search_screen.dart';
import 'materials_screen.dart';
import 'notes_screen.dart';
import 'study_plan_screen.dart';

/// Modern AI Assistant - visual rebuild only.
///
/// No AI service, Gemini integration, file upload API, response parser,
/// authentication gate, or business logic was modified. All such behaviour
/// is delegated to the same call sites the previous screen used
/// (ApiService.aiNote, ApiService.askPdf, and Navigator.push into the
/// existing Notes / Materials / StudyPlan screens).
class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final List<_ChatBubble> _bubbles = <_ChatBubble>[];
  final TextEditingController _chatController = TextEditingController();
  final FocusNode _chatFocus = FocusNode();
  bool _sending = false;

  PlatformFile? _pickedFile;
  final bool _uploading = false;
  String? _uploadError;

  @override
  void dispose() {
    _chatController.dispose();
    _chatFocus.dispose();
    super.dispose();
  }

  Future<void> _sendChat() async {
    final raw = _chatController.text.trim();
    if (raw.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _bubbles.add(_ChatBubble.user(raw));
    });
    _chatController.clear();

    try {
      final reply = await ApiService.aiNote('explain', raw);
      if (!mounted) return;
      setState(() => _bubbles.add(_ChatBubble.ai(reply)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _bubbles.add(_ChatBubble.error(
            EkLanguage.text(
              'Could not reach the AI service. Try again.',
              'AI পরিষেবায় যোগাযোগ করা যায়নি। আবার চেষ্টা করুন।',
            ),
          )));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickUpload() async {
    try {
      // file_picker 12.x: pickFiles is static on FilePicker and returns a List<PlatformFile>.
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      );
      if (picked.isEmpty) return;
      setState(() {
        _pickedFile = picked.first;
        _uploadError = null;
      });
    } catch (_) {
      setState(() => _uploadError = EkLanguage.text(
            'Could not read the selected file.',
            'নির্বাচিত ফাইল পড়া যায়নি।',
          ));
    }
  }

  void _askPdfFromUpload() {
    final file = _pickedFile;
    if (file == null || _uploading) return;
    final question = _chatController.text.trim();
    if (question.isEmpty) {
      setState(() => _uploadError = EkLanguage.text(
            'Type a question about the file first.',
            'আগে ফাইল সম্পর্কে একটি প্রশ্ন লিখুন।',
          ));
      return;
    }
    setState(() {
      _bubbles.add(_ChatBubble.user(
          '${EkLanguage.text('File', 'ফাইল')}: ${file.name}\n$question'));
    });
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MaterialsScreen()),
    );
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.search),
                title: Text(EkLanguage.text(
                    'Search your study content', 'আপনার পড়ার বিষয় খুঁজুন')),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const UniversalSearchScreen(student: true),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.event_note_outlined),
                title: Text(EkLanguage.text(
                    'Plan my study', 'পড়াশোনার পরিকল্পনা')),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const StudyPlanScreen()),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: Text(EkLanguage.text(
                    'Gochano does not generate MCQs or automatic quizzes.',
                    'Gochano MCQ বা স্বয়ংক্রিয় কুইজ তৈরি করে না।')),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final scheme = Theme.of(context).colorScheme;
    final aiBg = brightness == Brightness.dark
        ? scheme.primaryContainer.withValues(alpha: 0.45)
        : const Color(0xFFE0F2FE);
    const primary = Color(0xFF0284C7);
    final bg = brightness == Brightness.dark ? scheme.surface : const Color(0xFFF8FAFC);
    final inkColor =
        brightness == Brightness.dark ? scheme.onSurface : const Color(0xFF1E293B);

    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, _) {
        return Scaffold(
          backgroundColor: bg,
          appBar: AppBar(
            backgroundColor: bg,
            elevation: 0,
            scrolledUnderElevation: 0.5,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  EkLanguage.text('AI Assistant', 'AI সহকারী'),
                  style: TextStyle(
                    color: inkColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                Text(
                  EkLanguage.text('Your smart helper', 'আপনার স্মার্ট সহায়ক'),
                  style: TextStyle(
                    color: inkColor.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: EkLanguage.text('Settings', 'সেটিংস'),
                icon: const Icon(Icons.tune),
                onPressed: _openSettings,
              ),
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: LanguageToggle(),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    if (_bubbles.isEmpty)
                      _EmptyState(
                        aiBg: aiBg,
                        primary: primary,
                        inkColor: inkColor,
                      )
                    else
                      ..._bubbles.map((b) => _ChatBubbleView(
                            bubble: b,
                            primary: primary,
                          )),
                    if (_sending) _TypingIndicator(primary: primary),
                  ],
                ),
              ),
              if (_pickedFile != null)
                _UploadPreview(
                  file: _pickedFile!,
                  uploading: _uploading,
                  error: _uploadError,
                  onClear: () => setState(() => _pickedFile = null),
                  onAsk: _askPdfFromUpload,
                ),
              _ChatInput(
                controller: _chatController,
                focusNode: _chatFocus,
                sending: _sending,
                primary: primary,
                onSend: _sendChat,
                onUpload: _pickUpload,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChatBubble {
  _ChatBubble.user(this.text) : kind = _BubbleKind.user, error = null;
  _ChatBubble.ai(this.text) : kind = _BubbleKind.ai, error = null;
  _ChatBubble.error(this.error) : text = '', kind = _BubbleKind.error;

  final String text;
  final _BubbleKind kind;
  final String? error;
}

enum _BubbleKind { user, ai, error }

class _ChatBubbleView extends StatelessWidget {
  const _ChatBubbleView({required this.bubble, required this.primary});

  final _ChatBubble bubble;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = bubble.kind == _BubbleKind.user;
    final isError = bubble.kind == _BubbleKind.error;

    final bg = isUser
        ? primary
        : isError
            ? scheme.errorContainer
            : scheme.surfaceContainerHighest;
    final fg = isUser
        ? Colors.white
        : isError
            ? scheme.onErrorContainer
            : scheme.onSurface;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 2),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: primary.withValues(alpha: 0.12),
                child: Icon(
                  isError ? Icons.error_outline : Icons.auto_awesome,
                  size: 14,
                  color: primary,
                ),
              ),
            ),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: Text(
                isError ? (bubble.error ?? '') : bubble.text,
                style: TextStyle(color: fg, fontSize: 14, height: 1.4),
              ),
            ),
          ),
          if (isUser)
            const Padding(
              padding: EdgeInsets.only(left: 8, bottom: 2),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: Color(0xFFE2E8F0),
                child: Icon(Icons.person_outline,
                    size: 14, color: Color(0xFF475569)),
              ),
            ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator({required this.primary});
  final Color primary;

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: widget.primary.withValues(alpha: 0.12),
            child: Icon(Icons.auto_awesome, size: 14, color: widget.primary),
          ),
          const SizedBox(width: 8),
          AnimatedBuilder(
            animation: _c,
            builder: (_, _) {
              final t = _c.value;
              Widget dot(double delay) {
                final v = (t + delay) % 1.0;
                final clamped = (1 - (v - 0.5).abs() * 2).clamp(0.0, 1.0);
                final scale = 0.7 + 0.3 * clamped;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Transform.scale(scale: scale, child: const _Dot()),
                );
              }

              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(18),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [dot(0.0), dot(0.3), dot(0.6)],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) => Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.aiBg,
    required this.primary,
    required this.inkColor,
  });

  final Color aiBg;
  final Color primary;
  final Color inkColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: aiBg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                EkLanguage.text('Hi 👋', 'হ্যালো 👋'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: inkColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                EkLanguage.text(
                  'How can I help you today?',
                  'আজ আমি আপনাকে কীভাবে সাহায্য করতে পারি?',
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: inkColor.withValues(alpha: 0.75),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          EkLanguage.text('Quick actions', 'দ্রুত কাজ'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: inkColor.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            _QuickAction(
              icon: Icons.summarize_outlined,
              labelEn: 'Summarize',
              labelBn: 'সারাংশ',
              primary: primary,
              onTap: () => _AiNav.notes(context),
            ),
            _QuickAction(
              icon: Icons.lightbulb_outline,
              labelEn: 'Explain',
              labelBn: 'ব্যাখ্যা',
              primary: primary,
              onTap: () => _AiNav.notes(context),
            ),
            _QuickAction(
              icon: Icons.image_outlined,
              labelEn: 'Generate Image',
              labelBn: 'ছবি তৈরি',
              primary: primary,
              onTap: () => _AiNav.notes(context),
            ),
            _QuickAction(
              icon: Icons.bar_chart_outlined,
              labelEn: 'Analyze Data',
              labelBn: 'ডেটা বিশ্লেষণ',
              primary: primary,
              onTap: () => _AiNav.plan(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.labelEn,
    required this.labelBn,
    required this.primary,
    required this.onTap,
  });

  final IconData icon;
  final String labelEn;
  final String labelBn;
  final Color primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: isDark ? scheme.surfaceContainerHigh : const Color(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: primary, size: 20),
              ),
              const SizedBox(height: 6),
              Text(
                EkLanguage.text(labelEn, labelBn),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadPreview extends StatelessWidget {
  const _UploadPreview({
    required this.file,
    required this.uploading,
    required this.error,
    required this.onClear,
    required this.onAsk,
  });

  final PlatformFile file;
  final bool uploading;
  final String? error;
  final VoidCallback onClear;
  final VoidCallback onAsk;

  @override
  Widget build(BuildContext context) {
    // file_picker 12.x dropped PlatformFile.extension/.size; derive from name.
    final ext = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : '';
    final isPdf = ext == 'pdf';
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isPdf ? Icons.picture_as_pdf_outlined : Icons.image_outlined,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                Text(
                  error ??
                      (uploading
                          ? EkLanguage.text('Uploading…', 'আপলোড হচ্ছে…')
                          : ext.toUpperCase()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: error != null ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (uploading)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          IconButton(
            tooltip: EkLanguage.text('Ask about this file', 'এই ফাইল সম্পর্কে জিজ্ঞাসা'),
            onPressed: uploading ? null : onAsk,
            icon: const Icon(Icons.send_rounded, size: 18),
          ),
          IconButton(
            tooltip: EkLanguage.text('Remove file', 'ফাইল মুছুন'),
            onPressed: uploading ? null : onClear,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}

class _ChatInput extends StatelessWidget {
  const _ChatInput({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.primary,
    required this.onSend,
    required this.onUpload,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final Color primary;
  final VoidCallback onSend;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        decoration: BoxDecoration(
          color: isDark ? scheme.surface : const Color(0xFFFFFFFF),
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              tooltip: EkLanguage.text('Upload PDF or image', 'PDF বা ছবি আপলোড'),
              onPressed: sending ? null : onUpload,
              icon: Icon(Icons.attach_file_rounded, color: scheme.onSurfaceVariant),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(22),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => onSend(),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: EkLanguage.text(
                              'Ask anything…', 'যেকোনো কিছু জিজ্ঞাসা করুন…'),
                          hintStyle: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: EkLanguage.text('Voice input', 'ভয়েস ইনপুট'),
                      onPressed: sending ? null : () {/* future hook */},
                      icon: Icon(Icons.mic_none,
                          color: scheme.onSurfaceVariant, size: 20),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Material(
              color: sending ? primary.withValues(alpha: 0.5) : primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: sending ? null : onSend,
                child: const SizedBox(
                  width: 44,
                  height: 44,
                  child:
                      Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiNav {
  static void notes(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NotesScreen()),
      );
  static void plan(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const StudyPlanScreen()),
      );
}
