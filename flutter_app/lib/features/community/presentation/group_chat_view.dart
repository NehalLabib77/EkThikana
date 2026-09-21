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

/// Community study sticker definition.
class CommunitySticker {
  const CommunitySticker({
    required this.id,
    required this.titleEn,
    required this.titleBn,
    required this.artId,
  });

  final String id;
  final String titleEn;
  final String titleBn;
  final String artId;

  String get title => GochanoLanguage.text(titleEn, titleBn);
}

/// Curated catalogue of academic stickers with zero gamification dependencies.
const List<CommunitySticker> kCommunityStickers = [
  CommunitySticker(
    id: 'study_time',
    titleEn: 'Study Time',
    titleBn: 'পড়ার সময়',
    artId: GochanoArt.featureStudy,
  ),
  CommunitySticker(
    id: 'exam_prep',
    titleEn: 'Exam Ready',
    titleBn: 'পরীক্ষার প্রস্তুতি',
    artId: GochanoArt.subjectSoftwareEngineering,
  ),
  CommunitySticker(
    id: 'group_work',
    titleEn: 'Group Work',
    titleBn: 'দলগত কাজ',
    artId: GochanoArt.featureGroups,
  ),
  CommunitySticker(
    id: 'notes_ready',
    titleEn: 'Notes Ready',
    titleBn: 'নোট প্রস্তুত',
    artId: GochanoArt.featureCalendar,
  ),
  CommunitySticker(
    id: 'ai_help',
    titleEn: 'Need Help',
    titleBn: 'সাহায্য দরকার',
    artId: GochanoArt.featureAi,
  ),
  CommunitySticker(
    id: 'celebrate',
    titleEn: 'Well Done!',
    titleBn: 'দারুণ কাজ!',
    artId: GochanoArt.featureTasks,
  ),
];

/// Curated standard reaction emojis supported in chat.
const List<String> kCommunityReactions = ['👍', '❤️', '💡', '🔥', '👏', '🤔'];

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
  bool _showStickerDrawer = false;

  @override
  void initState() {
    super.initState();
    if (widget.chatEnabled) _load();
  }

  @override
  void didUpdateWidget(covariant GroupChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.chatEnabled != oldWidget.chatEnabled) {
      if (widget.chatEnabled) {
        _load();
      } else {
        setState(() {
          _messages = const [];
          _loading = false;
          _showStickerDrawer = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _message.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
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
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _messages = _messages.where((m) => m != optimistic).toList();
      });
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
      return;
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _sendSticker(CommunitySticker sticker) async {
    if (_sending) return;

    final optimistic = <String, dynamic>{
      'senderId': FirestoreService.uid,
      'senderName': '',
      'text': '[sticker:${sticker.id}]',
      'createdAt': DateTime.now().toIso8601String(),
    };
    setState(() {
      _sending = true;
      _messages = [..._messages, optimistic];
      _showStickerDrawer = false;
    });
    _scrollToEnd();

    try {
      await ApiService.postGroupMessage(
        groupId: widget.groupId,
        text: '[sticker:${sticker.id}]',
      );
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _messages = _messages.where((m) => m != optimistic).toList();
      });
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
      return;
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _toggleReaction(String messageId, String emoji) async {
    final myUid = FirestoreService.uid;
    if (myUid == null || myUid.isEmpty) {
      showGochanoMessage(
        context,
        GochanoLanguage.text(
          'Sign in to react to messages',
          'প্রতিক্রিয়া জানাতে সাইন ইন করুন',
        ),
        isError: true,
      );
      return;
    }

    final index = _messages.indexWhere((m) => m['id'] == messageId);
    if (index == -1) return;

    final targetMsg = Map<String, dynamic>.from(_messages[index]);
    final rawReactions = (targetMsg['reactions'] as Map?) ?? const {};
    final reactions = <String, List<String>>{};

    for (final entry in rawReactions.entries) {
      final uids = ((entry.value as List?) ?? const [])
          .map((e) => e.toString())
          .toList();
      if (uids.isNotEmpty) {
        reactions[entry.key.toString()] = uids;
      }
    }

    final currentUids = List<String>.from(reactions[emoji] ?? const []);
    if (currentUids.contains(myUid)) {
      currentUids.remove(myUid);
    } else {
      currentUids.add(myUid);
    }

    if (currentUids.isEmpty) {
      reactions.remove(emoji);
    } else {
      reactions[emoji] = currentUids;
    }

    final previousMsg = _messages[index];
    setState(() {
      final updatedList = List<Map<String, dynamic>>.from(_messages);
      targetMsg['reactions'] = reactions;
      updatedList[index] = targetMsg;
      _messages = updatedList;
    });

    try {
      final updatedReactions = await ApiService.postGroupMessageReaction(
        groupId: widget.groupId,
        messageId: messageId,
        emoji: emoji,
      );
      if (!mounted) return;
      setState(() {
        final updatedList = List<Map<String, dynamic>>.from(_messages);
        final currentMsg = Map<String, dynamic>.from(updatedList[index]);
        currentMsg['reactions'] = updatedReactions;
        updatedList[index] = currentMsg;
        _messages = updatedList;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        final updatedList = List<Map<String, dynamic>>.from(_messages);
        updatedList[index] = previousMsg;
        _messages = updatedList;
      });
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }

  void _openReactionSheet(String messageId) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(GochanoRadius.lg),
        ),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: GochanoSpacing.md,
              vertical: GochanoSpacing.md,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  GochanoLanguage.text(
                    'React to message',
                    'বার্তায় প্রতিক্রিয়া দিন',
                  ),
                  style: context.type.cardHeading,
                ),
                const SizedBox(height: GochanoSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: kCommunityReactions.map((emoji) {
                    return InkWell(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _toggleReaction(messageId, emoji);
                      },
                      borderRadius: BorderRadius.circular(24),
                      child: Padding(
                        padding: const EdgeInsets.all(GochanoSpacing.xs),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
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
          if (_showStickerDrawer)
            _StickerDrawer(
              onSelectSticker: _sendSticker,
              onClose: () => setState(() => _showStickerDrawer = false),
            ),
          _Composer(
            controller: _message,
            sending: _sending,
            showStickerDrawer: _showStickerDrawer,
            onToggleStickerDrawer: () {
              setState(() {
                _showStickerDrawer = !_showStickerDrawer;
              });
            },
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

    final myUid = FirestoreService.uid ?? '';

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
        itemBuilder: (context, i) {
          final msg = _messages[i];
          final msgId = msg['id']?.toString() ?? '';
          return _MessageBubble(
            message: msg,
            myUid: myUid,
            onToggleReaction: (emoji) {
              if (msgId.isNotEmpty) {
                _toggleReaction(msgId, emoji);
              }
            },
            onLongPress: () {
              if (msgId.isNotEmpty) {
                _openReactionSheet(msgId);
              }
            },
          );
        },
      ),
    );
  }
}

class _StickerDrawer extends StatelessWidget {
  const _StickerDrawer({required this.onSelectSticker, required this.onClose});

  final void Function(CommunitySticker sticker) onSelectSticker;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.md,
        vertical: GochanoSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                GochanoLanguage.text(
                  'Send a study sticker',
                  'স্টাডি স্টিকার পাঠান',
                ),
                style: context.type.cardHeading,
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onClose,
                tooltip: GochanoLanguage.text('Close', 'বন্ধ করুন'),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Wrap(
            spacing: GochanoSpacing.sm,
            runSpacing: GochanoSpacing.sm,
            children: kCommunityStickers.map((sticker) {
              return InkWell(
                onTap: () => onSelectSticker(sticker),
                borderRadius: GochanoRadius.mdAll,
                child: Container(
                  width: 96,
                  padding: const EdgeInsets.symmetric(
                    vertical: GochanoSpacing.xs,
                    horizontal: GochanoSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: GochanoRadius.mdAll,
                    border: Border.all(color: colors.border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GochanoIllustration(
                        sticker.artId,
                        size: 32,
                        accent: colors.brand,
                      ),
                      const SizedBox(height: GochanoSpacing.xxs),
                      Text(
                        sticker.title,
                        style: context.type.caption,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.myUid,
    required this.onToggleReaction,
    required this.onLongPress,
  });

  final Map<String, dynamic> message;
  final String myUid;
  final void Function(String emoji) onToggleReaction;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final senderId = message['senderId']?.toString() ?? '';
    final isMine = senderId == myUid;
    final senderName = message['senderName']?.toString() ?? '';
    final text = message['text']?.toString() ?? '';
    final attachmentName = message['attachmentFilename']?.toString() ?? '';
    final attachmentMime = message['attachmentMime']?.toString() ?? '';
    final createdAt = DateTime.tryParse(message['createdAt']?.toString() ?? '');
    final rawReactions = (message['reactions'] as Map?) ?? const {};

    final isSticker = text.startsWith('[sticker:') && text.endsWith(']');
    String? stickerId;
    if (isSticker) {
      stickerId = text.substring(9, text.length - 1);
    }

    CommunitySticker? sticker;
    if (stickerId != null) {
      try {
        sticker = kCommunityStickers.firstWhere((s) => s.id == stickerId);
      } catch (_) {
        sticker = null;
      }
    }

    final reactionsMap = <String, List<String>>{};
    for (final entry in rawReactions.entries) {
      final uids = ((entry.value as List?) ?? const [])
          .map((e) => e.toString())
          .toList();
      if (uids.isNotEmpty) {
        reactionsMap[entry.key.toString()] = uids;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      child: Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (!isMine && senderName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(
                left: GochanoSpacing.xs,
                bottom: 2,
              ),
              child: Text(senderName, style: context.type.caption),
            ),
          GestureDetector(
            onLongPress: onLongPress,
            child: Container(
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
                    if (text.isNotEmpty)
                      const SizedBox(height: GochanoSpacing.xxs),
                  ],
                  if (sticker != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: GochanoSpacing.xxs,
                      ),
                      child: Column(
                        children: [
                          GochanoIllustration(
                            sticker.artId,
                            size: 40,
                            accent: colors.brand,
                          ),
                          const SizedBox(height: GochanoSpacing.xxs),
                          Text(
                            sticker.title,
                            style: context.type.caption.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (text.isNotEmpty)
                    Text(text, style: context.type.body),
                  if (createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      _clock(createdAt.toLocal()),
                      style: context.type.caption,
                    ),
                  ],
                  if (reactionsMap.isNotEmpty) ...[
                    const SizedBox(height: GochanoSpacing.xxs),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: reactionsMap.entries.map((entry) {
                        final emoji = entry.key;
                        final count = entry.value.length;
                        final hasReacted =
                            myUid.isNotEmpty && entry.value.contains(myUid);
                        return InkWell(
                          onTap: () => onToggleReaction(emoji),
                          borderRadius: GochanoRadius.smAll,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: hasReacted
                                  ? colors.brand.withValues(alpha: 0.12)
                                  : colors.surfaceVariant,
                              borderRadius: GochanoRadius.smAll,
                              border: Border.all(
                                color: hasReacted
                                    ? colors.brand
                                    : colors.border,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              '$emoji $count',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textPrimary,
                                fontWeight: hasReacted
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
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
    required this.showStickerDrawer,
    required this.onToggleStickerDrawer,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final bool showStickerDrawer;
  final VoidCallback onToggleStickerDrawer;
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
              IconButton(
                icon: Icon(
                  showStickerDrawer
                      ? Icons.keyboard_alt_outlined
                      : Icons.sticky_note_2_outlined,
                  color: showStickerDrawer
                      ? colors.brand
                      : colors.textSecondary,
                ),
                tooltip: GochanoLanguage.text('Stickers', 'স্টিকার'),
                onPressed: onToggleStickerDrawer,
              ),
              const SizedBox(width: GochanoSpacing.xxs),
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
