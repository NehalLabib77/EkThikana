
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../core/ui.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';

class GroupChatScreen extends StatefulWidget {
  const GroupChatScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _sending = false;

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ApiService.postGroupMessage(
        groupId: widget.groupId,
        text: text,
      );
      _composer.clear();
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAttachment() async {
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'doc', 'docx'],
    );
    if (picked.isEmpty) return;
    final f = picked.single;
    final Uint8List bytes;
    try {
      bytes = await f.readAsBytes();
    } catch (e) {
      if (mounted) {
        showError(context, Exception('Could not read the selected file: $e'));
      }
      return;
    }

    setState(() => _sending = true);
    try {
      await ApiService.postGroupMessage(
        groupId: widget.groupId,
        text: _composer.text.trim(),
        attachmentBytes: bytes,
        attachmentFilename: f.name,
        attachmentMime: _mimeFor(f.name),
      );
      _composer.clear();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _mimeFor(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    return 'application/octet-stream';
  }

  @override
  Widget build(BuildContext context) {
    final me = FirestoreService.uid;
    return Scaffold(
      appBar: AppBar(title: Text('${widget.groupName} • Chat')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestoreService.groupMessages(widget.groupId),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No messages yet.\nStart the conversation below.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    return _MessageBubble(
                      isMine: d['senderId']?.toString() == me,
                      senderName: d['senderName']?.toString() ?? 'Member',
                      text: d['text']?.toString() ?? '',
                      attachment: d['attachment'] is Map
                          ? Map<String, dynamic>.from(d['attachment'] as Map)
                          : null,
                      createdAtIso: d['createdAtIso']?.toString(),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Attach file',
                    onPressed: _sending ? null : _pickAttachment,
                    icon: const Icon(Icons.attach_file),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _composer,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Write a message…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.isMine,
    required this.senderName,
    required this.text,
    required this.attachment,
    required this.createdAtIso,
  });

  final bool isMine;
  final String senderName;
  final String text;
  final Map<String, dynamic>? attachment;
  final String? createdAtIso;

  @override
  Widget build(BuildContext context) {
    final bg = isMine
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final time = createdAtIso == null ? '' : _shortTime(createdAtIso!);

    Widget attachmentPreview;
    if (attachment == null) {
      attachmentPreview = const SizedBox.shrink();
    } else {
      final url = attachment!['url']?.toString() ?? '';
      final filename = attachment!['filename']?.toString() ?? '';
      final mime = attachment!['mime']?.toString() ?? '';
      if (mime.startsWith('image/')) {
        attachmentPreview = Padding(
          padding: const EdgeInsets.only(top: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              height: 160,
              fit: BoxFit.cover,
              // Decode to thumbnail resolution (2x the 160 logical px)
              // instead of full camera resolution — saves ~90% memory
              // for chat attachments that can be 4-12 MB originals.
              cacheWidth: 320,
              semanticLabel: 'Attached image',
              errorBuilder: (_, _, _) => Text('Could not load image.'),
            ),
          ),
        );
      } else {
        attachmentPreview = Padding(
          padding: const EdgeInsets.only(top: 6),
          child: InkWell(
            onTap: url.isEmpty ? null : () => _openUrl(context, url),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.attach_file, size: 16),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    filename.isEmpty ? 'Attachment' : filename,
                    style: const TextStyle(
                      decoration: TextDecoration.underline,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: align,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.78,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              crossAxisAlignment: align,
              children: [
                Text(
                  isMine ? 'You' : senderName,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (text.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(text),
                  ),
                attachmentPreview,
              ],
            ),
          ),
          if (time.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
              child: Text(time, style: const TextStyle(fontSize: 10)),
            ),
        ],
      ),
    );
  }

  String _shortTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      // Use a HEAD ping to confirm reachability; the platform decides
      // whether to launch it via Clipboard if no url_launcher is wired up.
      final ok = await http
          .head(Uri.parse(url))
          .timeout(const Duration(seconds: 5));
      if (!context.mounted) return;
      if (ok.statusCode < 400) {
        await Clipboard.setData(ClipboardData(text: url));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Attachment URL copied to clipboard.')),
          );
        }
      } else {
        if (context.mounted) showError(context, Exception('Attachment unavailable.'));
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}