import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../core/ui.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import 'material_reader_screen.dart';
import 'material_upload_screen.dart';

class MaterialsScreen extends StatelessWidget {
  const MaterialsScreen({
    super.key,
    this.groupId,
    this.groupName,
  });

  final String? groupId;
  final String? groupName;

  @override
  Widget build(BuildContext context) {
    final stream = groupId == null
        ? FirestoreService.ownerStream('materials')
        : FirestoreService.groupMaterials(groupId!);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          groupId == null
              ? EkLanguage.text('My materials', 'আমার উপকরণ')
              : '$groupName — ${EkLanguage.text('Shared Box', 'শেয়ার্ড বক্স')}',
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MaterialUploadScreen(
              initialVisibility: groupId == null ? 'private' : 'group',
              initialGroupId: groupId,
            ),
          ),
        ),
        icon: const Icon(Icons.upload_file),
        label: Text(EkLanguage.text('Upload', 'আপলোড')),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Text(
                EkLanguage.text(
                  'No shared materials yet.',
                  'এখনও কোনো উপকরণ শেয়ার হয়নি।',
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();
              final own = data['ownerId'] == FirestoreService.uid;
              return _MaterialCard(
                docId: doc.id,
                data: data,
                own: own,
              );
            },
          );
        },
      ),
    );
  }
}

class _MaterialCard extends StatelessWidget {
  const _MaterialCard({
    required this.docId,
    required this.data,
    required this.own,
  });

  final String docId;
  final Map<String, dynamic> data;
  final bool own;

  IconData get _icon {
    final mime = data['mimeType']?.toString() ?? '';
    if (mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
    if (mime.contains('image')) return Icons.image_outlined;
    if (mime.contains('offic') ||
        mime.contains('word') ||
        mime.contains('document')) {
      return Icons.description_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  String _formatDate(dynamic ts) {
    if (ts is Timestamp) {
      final dt = ts.toDate();
      final now = DateTime.now();
      if (dt.year == now.year) {
        return '${dt.day.toString().padLeft(2, '0')} ${_monthShort(dt.month)}';
      }
      return '${dt.day.toString().padLeft(2, '0')} '
          '${_monthShort(dt.month)} ${dt.year}';
    }
    return '';
  }

  String _monthShort(int m) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    if (m < 1 || m > 12) return '';
    return months[m - 1];
  }

  String _subtitle() {
    final parts = <String>[];
    final subject = data['subject']?.toString().trim() ?? '';
    if (subject.isNotEmpty) parts.add(subject);
    final owner = data['ownerName']?.toString().trim() ?? '';
    if (owner.isNotEmpty) parts.add(owner);
    final updated = data['updatedAt'];
    final created = data['createdAt'];
    final date = updated is Timestamp
        ? updated
        : created is Timestamp
            ? created
            : null;
    if (date != null) parts.add(_formatDate(date));
    final version = data['version'];
    if (version is int && version > 1) parts.add('v$version');
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final description = data['description']?.toString().trim() ?? '';
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(_icon),
            title: Text(
              data['title']?.toString() ??
                  data['fileName']?.toString() ??
                  '',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: _subtitle().isEmpty
                ? null
                : Text(
                    _subtitle(),
                    style: const TextStyle(fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
            trailing: own
                ? PopupMenuButton<String>(
                    onSelected: (v) => _handle(context, v),
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit details'),
                          dense: true,
                        ),
                      ),
                      PopupMenuItem(
                        value: 'replace',
                        child: ListTile(
                          leading: Icon(Icons.swap_horiz),
                          title: Text('Replace file'),
                          dense: true,
                        ),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline, color: Colors.red),
                          title: Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                          dense: true,
                        ),
                      ),
                    ],
                  )
                : null,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MaterialReaderScreen(
                  materialId: docId,
                  material: data,
                ),
              ),
            ),
          ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handle(BuildContext context, String action) async {
    switch (action) {
      case 'edit':
        await _editDetails(context);
        break;
      case 'replace':
        await _replaceFile(context);
        break;
      case 'delete':
        await _delete(context);
        break;
    }
  }

  Future<void> _editDetails(BuildContext context) async {
    final titleCtrl =
        TextEditingController(text: data['title']?.toString() ?? '');
    final subjectCtrl =
        TextEditingController(text: data['subject']?.toString() ?? '');
    final descCtrl =
        TextEditingController(text: data['description']?.toString() ?? '');
    bool busy = false;
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (d) {
          return StatefulBuilder(
            builder: (d, setLocal) => AlertDialog(
              title: const Text('Edit details'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: 'Title'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: subjectCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Subject'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      maxLength: 1000,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy ? null : () => Navigator.pop(d, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setLocal(() => busy = true);
                          try {
                            await ApiService.updateMaterial(
                              docId,
                              title: titleCtrl.text.trim(),
                              subject: subjectCtrl.text.trim(),
                              description: descCtrl.text.trim(),
                            );
                            if (d.mounted) Navigator.pop(d, true);
                          } catch (e) {
                            if (d.mounted) {
                              setLocal(() => busy = false);
                              showError(d, e);
                            }
                          }
                        },
                  child: Text(busy ? 'Saving…' : 'Save'),
                ),
              ],
            ),
          );
        },
      );
      if (saved == true && context.mounted) {
        showSuccess(
          context,
          EkLanguage.text('Material updated.', 'উপকরণ আপডেট হয়েছে।'),
        );
      }
    } finally {
      titleCtrl.dispose();
      subjectCtrl.dispose();
      descCtrl.dispose();
    }
  }

  Future<void> _replaceFile(BuildContext context) async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
    );
    if (result.isEmpty) return;
    final file = result.first;
    final bytes = await file.readAsBytes();
    if (!context.mounted) return;
    final ok = await confirmAction(
      context,
      title: 'Replace file?',
      message:
          'The current file will be replaced and the version number will increment. '
          'Saved references and the share link stay the same.',
      action: 'Replace',
    );
    if (!ok) return;
    try {
      await ApiService.replaceMaterialFile(
        id: docId,
        bytes: bytes,
        fileName: file.name,
      );
      if (context.mounted) {
        showSuccess(
          context,
          EkLanguage.text('File replaced.', '�াইল প্রতিস্থাপিত হয়েছে।'),
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final ok = await confirmAction(
      context,
      title: 'Delete material?',
      message: 'The stored file and its metadata will be removed.',
      action: 'Delete',
    );
    if (!ok) return;
    try {
      await ApiService.deleteMaterial(docId);
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}
