import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    this.noteId,
    this.initialData,
    this.readOnly = false,
    this.initialVisibility = 'private',
    this.initialGroupId,
  });

  final String? noteId;
  final Map<String, dynamic>? initialData;
  final bool readOnly;
  final String initialVisibility;
  final String? initialGroupId;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController title;
  late final TextEditingController content;
  late String visibility;
  String? groupId;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.initialData?['title']?.toString() ?? '');
    content = TextEditingController(text: widget.initialData?['content']?.toString() ?? '');
    visibility = widget.initialData?['visibility']?.toString() ?? widget.initialVisibility;
    groupId = widget.initialData?['groupId']?.toString() ?? widget.initialGroupId;
  }

  @override
  void dispose() {
    title.dispose();
    content.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (title.text.trim().isEmpty) {
      showError(context, Exception('Give the note a title.'));
      return;
    }
    if (visibility == 'group' && (groupId == null || groupId!.isEmpty)) {
      showError(context, Exception('Choose a group.'));
      return;
    }

    setState(() => busy = true);
    try {
      await FirestoreService.saveNote(
        id: widget.noteId,
        title: title.text,
        content: content.text,
        visibility: visibility,
        groupId: groupId,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> aiTool() async {
    if (content.text.trim().isEmpty) {
      showError(context, Exception('Add note content first.'));
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('AI study tool'),
        children: [
          SimpleDialogOption(onPressed: () => Navigator.pop(d, 'cleanup'), child: const Text('Clean up')),
          SimpleDialogOption(onPressed: () => Navigator.pop(d, 'summary'), child: const Text('Summarize')),
          SimpleDialogOption(onPressed: () => Navigator.pop(d, 'explain'), child: const Text('Explain')),
          SimpleDialogOption(onPressed: () => Navigator.pop(d, 'key_topics'), child: const Text('Key topics')),
        ],
      ),
    );
    if (action == null) return;

    setState(() => busy = true);
    try {
      final result = await ApiService.aiNote(action, content.text);
      if (!mounted) return;
      final use = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('AI result'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(child: SelectableText(result)),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Close')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Replace note content')),
          ],
        ),
      );
      if (use == true) content.text = result;
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }



  Future<void> saveSharedNoteCopy() async {
    await FirestoreService.saveNote(
      title: '${title.text} — saved copy',
      content: content.text,
      visibility: 'private',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Private copy saved to My Notes.')),
      );
    }
  }

  Future<void> downloadSharedNote() async {
    final safeName = title.text.trim().isEmpty ? 'Gochano_note' : title.text.trim();
    await FilePicker.saveFile(
      fileName: '$safeName.txt',
      bytes: Uint8List.fromList(utf8.encode(content.text)),
    );
  }

  Future<void> reportNote() async {
    if (widget.noteId == null) return;

    final reason = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('Report note'),
        children: [
          for (final item in const [
            ('spam', 'Spam'),
            ('copyright', 'Copyright concern'),
            ('inappropriate', 'Inappropriate content'),
            ('misleading', 'Misleading information'),
            ('other', 'Other'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(d, item.$1),
              child: Text(item.$2),
            ),
        ],
      ),
    );

    if (reason == null) return;

    try {
      await ApiService.reportContent(
        targetType: 'note',
        targetId: widget.noteId!,
        reason: reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted for review.')),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly) {
      return Scaffold(
        appBar: AppBar(
          title: Text(title.text.isEmpty ? 'Shared note' : title.text),
          actions: [
            if (widget.initialData?['ownerId'] != FirestoreService.uid)
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'save':
                      saveSharedNoteCopy();
                      break;
                    case 'download':
                      downloadSharedNote();
                      break;
                    case 'report':
                      reportNote();
                      break;
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'save',
                    child: Text('Save private copy'),
                  ),
                  PopupMenuItem(
                    value: 'download',
                    child: Text('Download as text'),
                  ),
                  PopupMenuItem(
                    value: 'report',
                    child: Text('Report note'),
                  ),
                ],
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: SelectableText(content.text),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.noteId == null ? 'New note' : 'Edit note'),
        actions: [
          IconButton(
            tooltip: 'AI tools',
            onPressed: busy ? null : aiTool,
            icon: const Icon(Icons.auto_awesome_outlined),
          ),
          TextButton(onPressed: busy ? null : save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: visibility,
            decoration: const InputDecoration(labelText: 'Visibility'),
            items: const [
              DropdownMenuItem(value: 'private', child: Text('Private — only me')),
              DropdownMenuItem(value: 'group', child: Text('Group — selected group')),
              DropdownMenuItem(value: 'public', child: Text('Public — Student Community')),
            ],
            onChanged: (v) => setState(() => visibility = v ?? 'private'),
          ),
          if (visibility == 'group') ...[
            const SizedBox(height: 12),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestoreService.myGroups(),
              builder: (context, snap) {
                final groups = snap.data?.docs ?? [];
                return DropdownButtonFormField<String>(
                  initialValue: groups.any((g) => g.id == groupId) ? groupId : null,
                  decoration: const InputDecoration(labelText: 'Group'),
                  items: [
                    for (final g in groups)
                      DropdownMenuItem(
                        value: g.id,
                        child: Text(g.data()['name']?.toString() ?? 'Group'),
                      ),
                  ],
                  onChanged: (v) => setState(() => groupId = v),
                );
              },
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: content,
            minLines: 16,
            maxLines: null,
            decoration: const InputDecoration(
              labelText: 'Note',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'AI tools explain, summarize, clean and extract key topics. Automatic questions and MCQs are not included.',
          ),
        ],
      ),
    );
  }
}
