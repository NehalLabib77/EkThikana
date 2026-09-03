// Group chat (spec §44).
//
// Reads and writes through `GET/POST /api/groups/{id}/chat`, both of which
// are member-only server-side; the POST additionally rejects when the group's
// `chatEnabled` is false. The UI mirrors those rules but does not rely on
// them — an unauthorised request fails at the server, which is where a
// permission check has to live (spec §82).
//
// Messages come back newest-first from the API and are reversed here so the
// thread reads top-to-bottom like a conversation.
//
// Attachments reuse the material pipeline: `ApiService.postGroupMessage`
// uploads the file as a group-visibility material and attaches its signed URL,
// so a chat attachment gets the same quota accounting and the same private
// storage as everything else.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_illustration.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../services/api_service.dart';
import '../../../services/firestore_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';

class GroupChatView extends StatefulWidget {
  const GroupChatView({
    super.key,
    required this.groupId,
    required this.chatEnabled,
    required this.isAdmin,
  });

  final String groupId;
  final bool chatEnabled;
  final bool isAdmin;

  @override
  State<GroupChatView> createState() => _GroupChatViewState();
}

class _GroupChatViewState extends State<GroupChatView> {
  final _message = TextEditingController();
  final _scroll = ScrollController();

  List<Map<String, dynamic>> _messages = const [];
  bool _loading = true;
  bool _sending = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    if (widget.chatEnabled) _load();
  }

  @override
  void didUpdateWidget(covariant GroupChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // An admin turning chat on should not require leaving and re-entering.
    if (!oldWidget.chatEnabled && widget.chatEnabled) _load();
  }

  @override
  void dispose() {
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // Only show the full-screen loading spinner on the very first load.
    // Subsequent refreshes (pull-to-refresh, after send) keep the existing
    // message list visible so the chat never feels like it is reloading.
    if (_messages.isEmpty) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }
    try {
      final body = await ApiService.getGroupChat(widget.groupId);
      if (!mounted) return;
      final messages = ((body['messages'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
          .toList()
          // The API returns newest first; a conversation reads oldest first.
          .reversed
          .toList();
      setState(() {
        _loading = false;
        _messages = messages;
      });
      _scrollToEnd();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) return;

    // Optimistic UI: add the message to the list immediately so the user
    // sees their message appear without waiting for the server round-trip.
    final optimistic = <String, dynamic>{
      'senderId': FirestoreService.uid,
      'senderName': '',
      'text': text,
      'createdAt': DateTime.now().toIso8601String(),
    };
    setState(() {
      _sending = true;
      _messages = [..._messages, optimistic];
    });
    _message.clear();
    _scrollToEnd();

    try {
      await ApiService.postGroupMessage(groupId: widget.groupId, text: text);
      // Background refresh to get the server-assigned fields (senderName,
      // server timestamp, etc.) without showing a loading state.
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (!mounted) return;
      // Remove the optimistic message on failure and show the error.
      setState(() {
        _sending = false;
        _messages = _messages.where((m) => m != optimistic).toList();
      });
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
      return;
    }
    if (mounted) setState(() => _sending = false);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.chatEnabled) {
      return EmptyState(
        illustration: GochanoArt.emptyMessages,
        title: GochanoLanguage.text('Chat is off', 'চ্যাট বন্ধ'),
        message: widget.isAdmin
            ? GochanoLanguage.text(
                'Turn chat on from the menu to let members message each other.',
                'সদস্যরা যাতে বার্তা পাঠাতে পারে সেজন্য মেনু থেকে চ্যাট চালু করুন।',
              )
            : GochanoLanguage.text(
                'A group admin has turned chat off for this group.',
                'গ্রুপ অ্যাডমিন এই গ্রুপের চ্যাট বন্ধ রেখেছেন।',
              ),
      );
    }

    return Scaffold(
      backgroundColor: context.colors.background,
      body: Column(
        children: [
          Expanded(child: _buildThread(context)),
          _Composer(
            controller: _message,
            sending: _sending,
            onSend: _send,
          ),
        ],
      ),
    );
  }

  Widget _buildThread(BuildContext context) {
    if (_loading) {
      return StaticLoadingState(
        message: GochanoLanguage.text('Loading messages…', 'বার্তা লোড হচ্ছে…'),
      );
    }
    if (_error.isNotEmpty) {
      return ErrorState(message: _error, onRetry: _load);
    }
    if (_messages.isEmpty) {
      return EmptyState(
        illustration: GochanoArt.emptyMessages,
        title: GochanoLanguage.text('No messages yet', 'এখনো কোনো বার্তা নেই'),
        message: GochanoLanguage.text(
          'Say hello to your group.',
          'আপনার গ্রুপকে শুভেচ্ছা জানান।',
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(
          GochanoSpacing.md,
          GochanoSpacing.sm,
          GochanoSpacing.md,
          GochanoSpacing.sm,
        ),
        itemCount: _messages.length,
        itemBuilder: (context, i) => _MessageBubble(message: _messages[i]),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final Map<String, dynamic> message;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final senderId = message['senderId']?.toString() ?? '';
    final isMine = senderId == FirestoreService.uid;
    final senderName = message['senderName']?.toString() ?? '';
    final text = message['text']?.toString() ?? '';
    final attachmentName = message['attachmentFilename']?.toString() ?? '';
    final attachmentMime = message['attachmentMime']?.toString() ?? '';
    final createdAt = DateTime.tryParse(message['createdAt']?.toString() ?? '');

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isMine && senderName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: GochanoSpacing.xs,
                bottom: 2,
              ),
              child: Text(senderName, style: context.type.caption),
            ),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: GochanoSpacing.sm,
              vertical: GochanoSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: isMine ? colors.brandSoft : colors.surface,
              borderRadius: GochanoRadius.mdAll,
              border: Border.all(color: colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (attachmentName.isNotEmpty) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GochanoIllustration(
                        GochanoArt.fileIdFor(
                          fileName: attachmentName,
                          mimeType: attachmentMime,
                        ),
                        size: 20,
                        accent: colors.community,
                      ),
                      const SizedBox(width: GochanoSpacing.xxs),
                      Flexible(
                        child: Text(
                          attachmentName,
                          style: context.type.bodySecondary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (text.isNotEmpty) const SizedBox(height: GochanoSpacing.xxs),
                ],
                if (text.isNotEmpty)
                  Text(text, style: context.type.body),
                if (createdAt != null) ...[
                  const SizedBox(height: 2),
                  Text(_clock(createdAt.toLocal()), style: context.type.caption),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(GochanoSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: !sending,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: GochanoLanguage.text(
                      'Message the group…',
                      'গ্রুপে বার্তা…',
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (_) => onSend(),
                ),
              ),
              const SizedBox(width: GochanoSpacing.xs),
              FilledButton(
                // Disabled while sending, which is what stops a double tap
                // posting the same message twice (spec §77).
                onPressed: sending ? null : onSend,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(
                    GochanoSizes.buttonHeight,
                    GochanoSizes.buttonHeight,
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: Icon(
                  Icons.send_rounded,
                  size: GochanoSizes.iconMd,
                  semanticLabel: GochanoLanguage.text('Send', 'পাঠান'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _clock(DateTime when) {
  final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final minute = when.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${when.hour < 12 ? 'am' : 'pm'}';
}
