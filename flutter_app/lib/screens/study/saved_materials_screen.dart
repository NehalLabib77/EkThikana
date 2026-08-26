import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/firestore_service.dart';
import 'material_reader_screen.dart';

class SavedMaterialsScreen extends StatelessWidget {
  const SavedMaterialsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirestoreService.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Saved Library')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('saved_materials')
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final saved = snap.data!.docs;
          if (saved.isEmpty) return const Center(child: Text('You have not saved any materials yet.'));

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: saved.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final s = saved[i];
              final materialId = s.data()['materialId']?.toString() ?? s.id;
              return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: FirebaseFirestore.instance.collection('materials').doc(materialId).get(),
                builder: (context, materialSnap) {
                  final material = materialSnap.data?.data();
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.bookmark),
                      title: Text(
                        material?['title']?.toString() ??
                            s.data()['title']?.toString() ??
                            'Unavailable material',
                      ),
                      subtitle: material == null
                          ? const Text('The material may no longer be shared with you.')
                          : Text(material['subject']?.toString() ?? ''),
                      trailing: IconButton(
                        icon: const Icon(Icons.bookmark_remove_outlined),
                        onPressed: s.reference.delete,
                      ),
                      onTap: material == null
                          ? null
                          : () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => MaterialReaderScreen(
                                    materialId: materialId,
                                    material: material,
                                  ),
                                ),
                              ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
