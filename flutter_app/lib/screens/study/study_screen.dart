// Study Hub — bento rebuild.
//
// Visual contract (per bento brief):
//   * No heavy borders, soft shadows, rounded corners, large whitespace.
//   * BentoLargeCard hero at the top, two rows of BentoSmallCards for the
//     primary actions, then a BentoLargeCard for materials + notes.
//   * All navigation targets are unchanged (AcademicStructureScreen,
//     AiAssistantScreen, FocusTimerScreen, MaterialsScreen,
//     MaterialUploadScreen, NotesScreen, NoteEditorScreen,
//     SavedMaterialsScreen).
//
// P2-UX note:
//   * `GroupsScreen` no longer lives here — it is the top-level
//     Community tab in `HomeShell`. The slot previously occupied by
//     the Groups card now hosts `AiAssistantScreen`, which previously
//     had its own top-level tab.
//   * No architecture, provider, model, or service changes.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/language.dart';
import '../../services/firestore_service.dart';
import '../../widgets/bento/bento_bar.dart';
import '../../widgets/gochano_primitives.dart' show EmptyState;
import 'ai_assistant_screen.dart';
import 'academic_structure_screen.dart';
// community_screen.dart removed in PART 3 (correction 4: no public runtime).
import 'focus_timer_screen.dart';
import 'material_upload_screen.dart';
import 'materials_screen.dart';
import 'note_editor_screen.dart';
import 'notes_screen.dart';
import 'saved_materials_screen.dart';

import '../../core/page_route.dart';
class StudyScreen extends StatelessWidget {
  const StudyScreen({super.key});

  void _go(BuildContext context, Widget page) =>
      Navigator.push(context, GochanoRoute.to(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: EkLanguage.bangla,
      builder: (context, _, _) => Scaffold(
        appBar: AppBar(
          backgroundColor: BentoColors.scaffold(context),
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            EkLanguage.text('Study Hub', 'স্টাডি হাব'),
            style: TextStyle(
              color: BentoColors.onTint(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          actions: const [Padding(padding: EdgeInsets.only(right: 12), child: LanguageToggle())],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            BentoLargeCard(
              moduleId: 'study',
              icon: Icons.menu_book_rounded,
              title: EkLanguage.text('Study Hub', 'স্টাডি হাব'),
              subtitle: EkLanguage.text(
                'All your academic essentials in one place.',
                'আপনার পড়াশোনার সব প্রয়োজনীয় জিনিস এক জায়গায়।',
              ),
              trailing: const BentoIllustration(module: 'study', size: 64),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: BentoSmallCard(
                    moduleId: 'study',
                    icon: Icons.school_rounded,
                    title: EkLanguage.text('Semesters', 'সেমিস্টার'),
                    subtitle: EkLanguage.text(
                      'Browse your semesters',
                      'আপনার সেমিস্টার দেখুন',
                    ),
                    onTap: () => _go(context, const AcademicStructureScreen()),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: BentoSmallCard(
                    moduleId: 'ai',
                    icon: Icons.auto_awesome_rounded,
                    title: EkLanguage.text('AI Assistant', 'এআই সহকারী'),
                    subtitle: EkLanguage.text(
                      'Ask about PDFs or photos',
                      'PDF বা ছবি সম্পর্কে জিজ্ঞাসা করুন',
                    ),
                    onTap: () => _go(context, const AiAssistantScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: BentoSmallCard(
                    moduleId: 'ai',
                    icon: Icons.timer_rounded,
                    title: EkLanguage.text('Focus', 'ফোকাস'),
                    subtitle: EkLanguage.text(
                      'Start a study session',
                      'স্টাডি সেশন শুরু করুন',
                    ),
                    onTap: () => _go(context, const FocusTimerScreen()),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: BentoSmallCard(
                    moduleId: 'tasks',
                    icon: Icons.task_alt_rounded,
                    title: EkLanguage.text('Tasks', 'কাজ'),
                    subtitle: EkLanguage.text(
                      'Plan your day',
                      'দিনের পরিকল্পনা',
                    ),
                    onTap: () => _go(context, const SavedMaterialsScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: BentoSmallCard(
                    moduleId: 'study',
                    icon: Icons.library_books_rounded,
                    title: EkLanguage.text('Materials', 'উপকরণ'),
                    subtitle: EkLanguage.text(
                      'Browse PDFs & notes',
                      'PDF ও নোট দেখুন',
                    ),
                    onTap: () => _go(context, const MaterialsScreen()),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: BentoSmallCard(
                    moduleId: 'medicine',
                    icon: Icons.upload_file_rounded,
                    title: EkLanguage.text('Upload', 'আপলোড'),
                    subtitle: EkLanguage.text(
                      'PDF, image or doc',
                      'PDF, ছবি বা ডক',
                    ),
                    onTap: () => _go(context, const MaterialUploadScreen()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _SectionLabel(
              title: EkLanguage.text('My Semesters', 'আমার সেমিস্টার'),
              action: EkLanguage.text('See all', 'সব দেখুন'),
              onAction: () => _go(context, const AcademicStructureScreen()),
            ),
            const SizedBox(height: 10),
            _SemesterStrip(onTap: () => _go(context, const AcademicStructureScreen())),
            const SizedBox(height: 22),
            _SectionLabel(
              title: EkLanguage.text('Recent Notes', 'সাম্প্রতিক নোট'),
              action: EkLanguage.text('See all', 'সব দেখুন'),
              onAction: () => _go(context, const NotesScreen()),
            ),
            const SizedBox(height: 10),
            _RecentNotesCard(
              onTap: () => _go(context, const NotesScreen()),
            ),
            const SizedBox(height: 14),
            BentoLargeCard(
              moduleId: 'study',
              icon: Icons.bookmark_outline,
              title: EkLanguage.text('Saved Library', 'সংরক্ষিত লাইব্রেরি'),
              subtitle: EkLanguage.text(
                'Pick up where you left off.',
                'যেখানে রেখেছিলেন, সেখান থেকে শুরু করুন।',
              ),
              trailing: const Icon(Icons.arrow_forward_rounded),
              onTap: () => _go(context, const SavedMaterialsScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.title,
    required this.action,
    required this.onAction,
  });

  final String title;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: BentoColors.onTint(context),
              letterSpacing: -0.1,
            ),
          ),
        ),
        GestureDetector(
          onTap: onAction,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              action,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: BentoColors.module(context, 'study').accent,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SemesterStrip extends StatelessWidget {
  const _SemesterStrip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 124,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.ownerStream('semesters'),
        builder: (context, snap) {
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return BentoCard(
              padding: const EdgeInsets.all(18),
              background: BentoColors.module(context, 'study').tint,
              onTap: onTap,
              child: Center(
                child: Text(
                  EkLanguage.text(
                    'Create your first semester',
                    'প্রথম সেমিস্টার তৈরি করুন',
                  ),
                  style: TextStyle(
                    color: BentoColors.onTintMuted(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final name = doc.data()['name']?.toString() ?? '';
              return SizedBox(
                width: 152,
                child: BentoCard(
                  padding: const EdgeInsets.all(16),
                  background: BentoColors.module(context, 'study').tint,
                  onTap: onTap,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const BentoIllustration(module: 'study', size: 40),
                      const Spacer(),
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: BentoColors.onTint(context),
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        EkLanguage.text('Open semester', 'সেমিস্টার খুলুন'),
                        style: TextStyle(
                          color: BentoColors.onTintMuted(context),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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

class _RecentNotesCard extends StatelessWidget {
  const _RecentNotesCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BentoCard(
      padding: const EdgeInsets.all(18),
      background: BentoColors.module(context, 'study').tint,
      onTap: onTap,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.ownerStream('notes', limit: 8),
        builder: (context, snap) {
          final docs = (snap.data?.docs ?? const []).take(5).toList();
          if (docs.isEmpty) {
            return SizedBox(
              height: 140,
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
            );
          }
          return Column(
            children: [
              for (var i = 0; i < docs.length; i++) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.push(
                    context,
                    GochanoRoute.to(
                      builder: (_) => NoteEditorScreen(
                        noteId: docs[i].id,
                        initialData: docs[i].data(),
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        const BentoIllustration(module: 'study', size: 38),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                docs[i].data()['title']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: BentoColors.onTint(context),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                docs[i].data()['semester']?.toString() ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: BentoColors.onTintMuted(context),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: BentoColors.onTintMuted(context),
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
                if (i != docs.length - 1)
                  Divider(
                    height: 1,
                    indent: 50,
                    color: BentoColors.onTintMuted(context).withValues(alpha: 0.2),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
