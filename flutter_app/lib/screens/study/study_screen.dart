import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../services/firestore_service.dart';
import '../../widgets/gochano_primitives.dart';
import '../groups/groups_screen.dart';
import 'academic_structure_screen.dart';
// community_screen.dart removed in PART 3 (correction 4: no public runtime).
import 'focus_timer_screen.dart';
import 'material_upload_screen.dart';
import 'materials_screen.dart';
import 'note_editor_screen.dart';
import 'notes_screen.dart';
import 'saved_materials_screen.dart';

class StudyScreen extends StatelessWidget {
  const StudyScreen({super.key});

  void _go(BuildContext context, Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(EkLanguage.text('Study Hub', 'স্টাডি হাব')),
              Text(EkLanguage.text('All your academic essentials', 'আপনার পড়াশোনার সব প্রয়োজনীয় জিনিস'), style: const TextStyle(fontSize: 11, color: EkColors.muted, fontWeight: FontWeight.w500)),
            ],
          ),
          actions: const [Padding(padding: EdgeInsets.only(right: 12), child: LanguageToggle())],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 90),
          children: [
            // Community Library removed in PART 3 (correction 4: no public runtime).
            Row(
              children: [
                Expanded(child: _quick(context, Icons.school_outlined, const Color(0xFF5B3DF5), 'Semesters', 'সেমিস্টার', const AcademicStructureScreen())),
                const SizedBox(width: 8),
                Expanded(child: _quick(context, Icons.groups_outlined, const Color(0xFFFF9500), 'Groups', 'গ্রুপ', const GroupsScreen())),
                const SizedBox(width: 8),
                Expanded(child: _quick(context, Icons.timer_outlined, const Color(0xFFE0388A), 'Focus', 'ফোকাস', const FocusTimerScreen())),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _go(context, const MaterialsScreen()),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFF0EA5E9).withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.library_books_outlined,
                                  color: Color(0xFF0EA5E9), size: 22),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    EkLanguage.text('Materials', 'উপকরণ'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w800),
                                  ),
                                  Text(
                                    EkLanguage.text('Browse PDFs & notes',
                                        'PDF ও নোট দেখুন'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 10, color: EkColors.muted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => _go(context, const MaterialUploadScreen()),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFF16A34A).withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.upload_file_outlined,
                                  color: Color(0xFF16A34A), size: 22),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    EkLanguage.text('Upload', 'আপলোড'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 13, fontWeight: FontWeight.w800),
                                  ),
                                  Text(
                                    EkLanguage.text('PDF, image or doc',
                                        'PDF, ছবি বা ডক'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 10, color: EkColors.muted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            SectionHeader(
              title: Text(EkLanguage.text('My Semesters', 'আমার সেমিস্টার')),
              action: TextButton(onPressed: () => _go(context, const AcademicStructureScreen()), child: Text(EkLanguage.text('View all', 'সব দেখুন'))),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 112,
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirestoreService.ownerStream('semesters'),
                builder: (context, snap) {
                  final docs = snap.data?.docs ?? const [];
                  if (docs.isEmpty) {
                    return Card(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => _go(context, const AcademicStructureScreen()),
                        child: Center(child: Text(EkLanguage.text('Create your first semester', 'প্রথম সেমিস্টার তৈরি করুন'))),
                      ),
                    );
                  }
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: docs.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) {
                      final doc = docs[i];
                      return SizedBox(
                        width: 142,
                        child: Card(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => _go(context, const AcademicStructureScreen()),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.school_rounded, color: EkColors.purple),
                                  const Spacer(),
                                  Text(doc.data()['name']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                                  Text(EkLanguage.text('Open semester', 'সেমিস্টার খুলুন'), style: const TextStyle(color: EkColors.muted, fontSize: 10)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 22),
            SectionHeader(
              title: Text(EkLanguage.text('Recent Notes', 'সাম্প্রতিক নোট')),
              action: TextButton(onPressed: () => _go(context, const NotesScreen()), child: Text(EkLanguage.text('View all', 'সব দেখুন'))),
            ),
            const SizedBox(height: 8),
            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirestoreService.ownerStream('notes', limit: 8),
              builder: (context, snap) {
                final docs = (snap.data?.docs ?? const []).take(5).toList();
                return Card(
                  child: docs.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: EmptyState(
                            module: 'study',
                            title: EkLanguage.text(
                              'No notes yet',
                              'এখনও কোনো নোট নেই',
                            ),
                            message: EkLanguage.text(
                              'Create a note from My Notes.',
                              'My Notes থেকে নোট তৈরি করুন।',
                            ),
                            compact: true,
                          ),
                        )
                      : Column(
                          children: [
                            for (var i = 0; i < docs.length; i++) ...[
                              ListTile(
                                leading: Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(color: const Color(0xFFF0EDFF), borderRadius: BorderRadius.circular(11)),
                                  child: const Icon(Icons.description_outlined, color: EkColors.purple, size: 20),
                                ),
                                title: Text(docs[i].data()['title']?.toString() ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                                subtitle: Text(docs[i].data()['semester']?.toString() ?? '', style: const TextStyle(fontSize: 10)),
                                trailing: const Icon(Icons.chevron_right, size: 18),
                                onTap: () => _go(context, NoteEditorScreen(noteId: docs[i].id, initialData: docs[i].data())),
                              ),
                              if (i != docs.length - 1) const Divider(height: 1, indent: 64),
                            ],
                          ],
                        ),
                );
              },
),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => _go(context, const SavedMaterialsScreen()),
              icon: const Icon(Icons.bookmark_outline),
              label: Text(EkLanguage.text('Open Saved Library', 'সংরক্িত লাইব্রেরি খুলুন')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quick(BuildContext context, IconData icon, Color color, String en, String bn, Widget page) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _go(context, page),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 5),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: color, size: 23),
              ),
              const SizedBox(height: 7),
              Text(EkLanguage.text(en, bn), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}
