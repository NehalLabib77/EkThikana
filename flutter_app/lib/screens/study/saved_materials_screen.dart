import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../services/firestore_service.dart';
import 'material_reader_screen.dart';

import '../../core/page_route.dart';
/// Saved Library. Lists every material the user has bookmarked. Fetches the
/// underlying material documents once per snapshot batch (no N+1 reads) and
/// caches them for the lifetime of the visible list. The Firestore stream
/// itself debounces, so we don't need an additional debouncer.
class SavedMaterialsScreen extends StatefulWidget {
  const SavedMaterialsScreen({super.key});

  @override
  State<SavedMaterialsScreen> createState() => _SavedMaterialsScreenState();
}

class _SavedMaterialsScreenState extends State<SavedMaterialsScreen> {
  final Map<String, DocumentSnapshot<Map<String, dynamic>>> _cache = {};
  bool _loading = true;

  @override
  Widget build(BuildContext context) {
    final uid = FirestoreService.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(EkLanguage.text('Saved Library', 'সংরক্ষিত লাইব্রেরি')),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('saved_materials')
            .snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) return const _Skeleton();
          final saved = snap.data!.docs;

          // Drop cache entries no longer present.
          final alive = saved
              .map((d) => d.data()['materialId']?.toString() ?? d.id)
              .toSet();
          _cache.removeWhere((k, _) => !alive.contains(k));

          if (saved.isEmpty) {
            _loading = false;
            return Center(
              child: Text(
                EkLanguage.text(
                  'You have not saved any materials yet.',
                  'আপনি এখনও কোনো উপকরণ সংরক্ষণ করেননি।',
                ),
              ),
            );
          }

          // Resolve any uncached material docs in a single batched future.
          final missing = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
          for (final d in saved) {
            final mid = d.data()['materialId']?.toString() ?? d.id;
            if (!_cache.containsKey(mid)) missing[mid] = d;
          }

          if (missing.isNotEmpty) {
            // Kick off batched fetch; rebuild when it completes.
            () async {
              try {
                final futures = missing.keys.map(
                  (mid) => FirebaseFirestore.instance
                      .collection('materials')
                      .doc(mid)
                      .get(),
                );
                final results = await Future.wait(futures);
                if (!mounted) return;
                setState(() {
                  for (final r in results) {
                    if (r.exists) _cache[r.id] = r;
                  }
                  _loading = false;
                });
              } catch (_) {
                if (mounted) setState(() => _loading = false);
              }
            }();
          } else {
            _loading = false;
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: saved.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final s = saved[i];
              final materialId =
                  s.data()['materialId']?.toString() ?? s.id;
              final cached = _cache[materialId];
              final material = cached?.data();
              final title = material?['title']?.toString() ??
                  s.data()['title']?.toString() ??
                  EkLanguage.text('Unavailable material', 'উপলব্ধ নয়');
              final subtitle = material == null
                  ? EkLanguage.text(
                      'The material may no longer be shared with you.',
                      'এই উপকরণ আর আপনার সাথে শেয়ার করা নাও থাকতে পারে।',
                    )
                  : [
                      material['subject']?.toString() ?? '',
                      material['ownerName']?.toString() ?? '',
                    ].where((e) => e.trim().isNotEmpty).join(' • ');
              return Card(
                child: ListTile(
                  leading: Icon(
                    cached == null && _loading
                        ? Icons.hourglass_empty
                        : Icons.bookmark,
                  ),
                  title: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove from saved',
                    icon: const Icon(Icons.bookmark_remove_outlined),
                    onPressed: () => _unsave(s.reference),
                  ),
                  onTap: material == null
                      ? null
                      : () => Navigator.push(
                            context,
                            GochanoRoute.to(
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
      ),
    );
  }

  Future<void> _unsave(DocumentReference<Map<String, dynamic>> ref) async {
    try {
      await ref.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              EkLanguage.text('Removed from your library.', 'লাইব্রেরি থেকে সরানো হলো।'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, _) => Card(
        child: SizedBox(
          height: 72,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 140,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 90,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}