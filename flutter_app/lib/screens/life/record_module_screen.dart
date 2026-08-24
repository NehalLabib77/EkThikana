import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/firestore_service.dart';

class RecordModuleScreen extends StatelessWidget {
  const RecordModuleScreen({
    super.key,
    required this.title,
    required this.collection,
    required this.itemLabel,
    required this.detailsLabel,
  });

  final String title;
  final String collection;
  final String itemLabel;
  final String detailsLabel;

  Future<void> _add(BuildContext context) async {
    final item = TextEditingController();
    final details = TextEditingController();

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Add $itemLabel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: item, decoration: InputDecoration(labelText: itemLabel)),
            const SizedBox(height: 10),
            TextField(
              controller: details,
              maxLines: 3,
              decoration: InputDecoration(labelText: detailsLabel),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Save')),
        ],
      ),
    );

    if (save != true || item.text.trim().isEmpty) {
      item.dispose();
      details.dispose();
      return;
    }

    try {
      await FirestoreService.addOwnerRecord(collection, {
        'title': item.text.trim(),
        'details': details.text.trim(),
        'keywords': FirestoreService.keywords('${item.text} ${details.text}'),
      });
    } catch (e) {
      if (context.mounted) showError(context, e);
    } finally {
      item.dispose();
      details.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.ownerStream(collection),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final docs = snap.data!.docs;
          if (docs.isEmpty) return Center(child: Text('No $title records yet.'));

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();
              return Card(
                child: ListTile(
                  title: Text(data['title']?.toString() ?? ''),
                  subtitle: Text(data['details']?.toString() ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await confirmAction(
                        context,
                        title: 'Delete record?',
                        message: 'This record will be removed.',
                        action: 'Delete',
                      );
                      if (ok) await doc.reference.delete();
                    },
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
