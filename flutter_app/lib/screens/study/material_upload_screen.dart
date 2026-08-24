import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';

class MaterialUploadScreen extends StatefulWidget {
  const MaterialUploadScreen({
    super.key,
    this.initialVisibility = 'private',
    this.initialGroupId,
  });

  final String initialVisibility;
  final String? initialGroupId;

  @override
  State<MaterialUploadScreen> createState() => _MaterialUploadScreenState();
}

class _MaterialUploadScreenState extends State<MaterialUploadScreen> {
  final title = TextEditingController();
  final subject = TextEditingController();

  PlatformFile? file;
  Uint8List? bytes;
  late String visibility;
  String? groupId;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    visibility = widget.initialVisibility;
    groupId = widget.initialGroupId;
  }

  @override
  void dispose() {
    title.dispose();
    subject.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    final selected = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
    );
    if (selected == null) return;
    final data = await selected.readAsBytes();
    setState(() {
      file = selected;
      bytes = data;
      if (title.text.trim().isEmpty) title.text = selected.name;
    });
  }

  Future<void> upload() async {
    if (file == null || bytes == null) {
      showError(context, Exception('Choose a file first.'));
      return;
    }
    if (visibility == 'group' && (groupId == null || groupId!.isEmpty)) {
      showError(context, Exception('Choose a group.'));
      return;
    }

    setState(() => busy = true);
    try {
      final profile = await FirestoreService.profile();
      await ApiService.uploadMaterial(
        bytes: bytes!,
        fileName: file!.name,
        title: title.text.trim(),
        visibility: visibility,
        groupId: visibility == 'group' ? groupId! : '',
        university: profile['university']?.toString() ?? '',
        department: profile['department']?.toString() ?? '',
        semester: profile['semester']?.toString() ?? '',
        subject: subject.text.trim(),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload study material')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          OutlinedButton.icon(
            onPressed: busy ? null : pick,
            icon: const Icon(Icons.attach_file),
            label: Text(file == null ? 'Choose PDF or image' : file!.name),
          ),
          const SizedBox(height: 12),
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 12),
          TextField(controller: subject, decoration: const InputDecoration(labelText: 'Subject / topic')),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: visibility,
            decoration: const InputDecoration(labelText: 'Visibility'),
            items: const [
              DropdownMenuItem(value: 'private', child: Text('Private')),
              DropdownMenuItem(value: 'group', child: Text('Group Shared Box')),
              DropdownMenuItem(value: 'public', child: Text('Public Student Community')),
            ],
            onChanged: busy ? null : (v) => setState(() => visibility = v ?? 'private'),
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
                  onChanged: busy ? null : (v) => setState(() => groupId = v),
                );
              },
            ),
          ],
          const SizedBox(height: 18),
          const Text('Free-stack upload limit is configured by the backend (default 15 MB).'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: busy ? null : upload,
            icon: const Icon(Icons.cloud_upload_outlined),
            label: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(busy ? 'Uploading…' : 'Upload'),
            ),
          ),
        ],
      ),
    );
  }
}
