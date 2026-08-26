import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
      appBar: AppBar(title: Text(groupId == null ? 'My materials' : '$groupName — Shared Box')),
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
        label: const Text('Upload'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const Center(child: Text('No shared materials yet.'));

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();
              final own = data['ownerId'] == FirestoreService.uid;
              return Card(
                child: ListTile(
                  leading: Icon(
                    (data['mimeType']?.toString() ?? '').contains('pdf')
                        ? Icons.picture_as_pdf_outlined
                        : Icons.insert_drive_file_outlined,
                  ),
                  title: Text(data['title']?.toString() ?? data['fileName']?.toString() ?? ''),
                  subtitle: Text(
                    [
                      data['subject']?.toString() ?? '',
                      data['ownerName']?.toString() ?? '',
                    ].where((e) => e.trim().isNotEmpty).join(' • '),
                  ),
                  trailing: own
                      ? PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'delete') {
                              final ok = await confirmAction(
                                context,
                                title: 'Delete material?',
                                message: 'The stored file and its metadata will be removed.',
                                action: 'Delete',
                              );
                              if (!ok) return;
                              try {
                                await ApiService.deleteMaterial(doc.id);
                              } catch (e) {
                                if (context.mounted) showError(context, e);
                              }
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'delete', child: Text('Delete')),
                          ],
                        )
                      : null,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MaterialReaderScreen(materialId: doc.id, material: data),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
