// Semester list screen — canonical Semester → Subject → Materials flow.
//
// Extracted from workspace_view.dart to serve as the standalone Semester
// screen opened by the Workspace Quick Access shortcut.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/firestore_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'subject_screen.dart';

class SemesterListScreen extends StatelessWidget {
  const SemesterListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Semesters', 'সেমিস্টার'),
        subtitle: GochanoLanguage.text(
          'Organize your subjects by semester',
          'সেমিস্টার অনুযায়ী বিষয় সাজান',
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _addSemester(context),
            icon: const Icon(Icons.add_rounded, size: GochanoSizes.iconSm),
            label: Text(GochanoLanguage.text('Add', 'যোগ')),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.ownerStream('semesters', limit: 60),
        builder: (context, semesterSnapshot) {
          if (semesterSnapshot.connectionState == ConnectionState.waiting) {
            return StaticLoadingState(
              message: GochanoLanguage.text(
                'Loading semesters…',
                'সেমিস্টার লোড হচ্ছে…',
              ),
            );
          }
          if (semesterSnapshot.hasError) {
            return ErrorState(
              message: friendlyErrorMessage(semesterSnapshot.error),
            );
          }

          final semesters = [...?semesterSnapshot.data?.docs]
            ..sort((a, b) => (a.data()['name']?.toString() ?? '')
                .compareTo(b.data()['name']?.toString() ?? ''));

          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirestoreService.ownerStream('subjects', limit: 300),
            builder: (context, subjectSnapshot) {
              final subjects = [...?subjectSnapshot.data?.docs];
              final subjectsBySemester =
                  <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
              for (final subject in subjects) {
                final semesterId =
                    subject.data()['semesterId']?.toString() ?? '';
                subjectsBySemester
                    .putIfAbsent(semesterId, () => [])
                    .add(subject);
              }

              if (semesters.isEmpty) {
                return EmptyState(
                  illustration: GochanoArt.emptySubjects,
                  title: GochanoLanguage.text(
                    'No semesters yet',
                    'এখনো কোনো সেমিস্টার নেই',
                  ),
                  message: GochanoLanguage.text(
                    'Create a semester to organize your subjects and study '
                    'materials.',
                    'আপনার বিষয় ও পড়ার উপকরণ গোছাতে একটি সেমিস্টার তৈরি করুন।',
                  ),
                  actionLabel: GochanoLanguage.text(
                    'Create semester',
                    'সেমিস্টার তৈরি',
                  ),
                  onAction: () => _addSemester(context),
                );
              }

              return ListView.builder(
                padding: GochanoSpacing.scrollBody,
                itemCount: semesters.length,
                itemBuilder: (context, i) {
                  final semester = semesters[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
                    child: _SemesterCard(
                      semester: semester,
                      subjects: subjectsBySemester[semester.id] ?? const [],
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

// ---------------------------------------------------------------------------
// Semester card + subject row (moved from workspace_view.dart)
// ---------------------------------------------------------------------------

class _SemesterCard extends StatelessWidget {
  const _SemesterCard({required this.semester, required this.subjects});

  final QueryDocumentSnapshot<Map<String, dynamic>> semester;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> subjects;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = semester.data()['name']?.toString() ?? '';

    return AppCard(
      accent: colors.study,
      padding: const EdgeInsets.fromLTRB(
        GochanoSpacing.md,
        GochanoSpacing.sm,
        GochanoSpacing.xs,
        GochanoSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, style: context.type.sectionHeading),
                    Text(
                      GochanoLanguage.text(
                        subjects.length == 1
                            ? '1 subject'
                            : '${subjects.length} subjects',
                        '${subjects.length} টি বিষয়',
                      ),
                      style: context.type.caption,
                    ),
                  ],
                ),
              ),
              GochanoOverflowMenu(
                items: [
                  GochanoMenuAction(
                    label: GochanoLanguage.text('Add subject', 'বিষয় যোগ'),
                    icon: Icons.add_rounded,
                    onSelected: () => _addSubject(context, semester.id),
                  ),
                  GochanoMenuAction(
                    label: GochanoLanguage.text(
                      'Rename semester',
                      'নাম পরিবর্তন',
                    ),
                    icon: Icons.edit_outlined,
                    onSelected: () => _renameSemester(context, semester),
                  ),
                  GochanoMenuAction(
                    label: GochanoLanguage.text(
                      'Delete semester',
                      'সেমিস্টার মুছুন',
                    ),
                    icon: Icons.delete_outline_rounded,
                    destructive: true,
                    onSelected: () =>
                        _deleteSemester(context, semester, subjects),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          if (subjects.isEmpty)
            Padding(
              padding: const EdgeInsets.only(
                right: GochanoSpacing.sm,
                bottom: GochanoSpacing.xxs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      GochanoLanguage.text(
                        'No subjects in this semester yet.',
                        'এই সেমিস্টারে এখনো কোনো বিষয় নেই।',
                      ),
                      style: context.type.bodySecondary,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _addSubject(context, semester.id),
                    child: Text(
                      GochanoLanguage.text('Add subject', 'বিষয় যোগ'),
                    ),
                  ),
                ],
              ),
            )
          else
            for (final subject in subjects)
              _SubjectRow(subject: subject, semesterName: name),
        ],
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({required this.subject, required this.semesterName});

  final QueryDocumentSnapshot<Map<String, dynamic>> subject;
  final String semesterName;

  @override
  Widget build(BuildContext context) {
    final name = subject.data()['name']?.toString() ?? '';

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.db
          .collection('materials')
          .where('ownerId', isEqualTo: FirestoreService.uid)
          .where('subject', isEqualTo: name)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return GochanoListRow(
          illustration: GochanoArt.subjectIdFor(name),
          accent: context.colors.study,
          title: name,
          metadata: [
            if (snapshot.hasData)
              GochanoLanguage.text(
                count == 1 ? '1 material' : '$count materials',
                '$count টি উপকরণ',
              ),
          ],
          onTap: () => Navigator.of(context).push(
            GochanoRoute.to(
              builder: (_) => SubjectScreen(
                subjectId: subject.id,
                subjectName: name,
                semesterName: semesterName,
              ),
            ),
          ),
          menuItems: [
            GochanoMenuAction(
              label: GochanoLanguage.text('Rename subject', 'নাম পরিবর্তন'),
              icon: Icons.edit_outlined,
              onSelected: () => _renameSubject(context, subject),
            ),
            GochanoMenuAction(
              label: GochanoLanguage.text('Delete subject', 'বিষয় মুছুন'),
              icon: Icons.delete_outline_rounded,
              destructive: true,
              onSelected: () => _deleteSubject(context, subject),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

Future<void> _addSemester(BuildContext context) async {
  final name = await _promptForName(
    context,
    title: GochanoLanguage.text('New semester', 'নতুন সেমিস্টার'),
    label: GochanoLanguage.text('Semester name', 'সেমিস্টারের নাম'),
    hint: GochanoLanguage.text('Semester 5', '৫ম সেমিস্টার'),
  );
  if (name == null || !context.mounted) return;
  try {
    await FirestoreService.addOwnerRecord('semesters', {'name': name});
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

Future<void> _addSubject(BuildContext context, String semesterId) async {
  final name = await _promptForName(
    context,
    title: GochanoLanguage.text('New subject', 'নতুন বিষয়'),
    label: GochanoLanguage.text('Subject name', 'বিষয়ের নাম'),
    hint: GochanoLanguage.text(
      'Database Management',
      'ডাটাবেজ ম্যানেজমেন্ট',
    ),
  );
  if (name == null || !context.mounted) return;
  try {
    await FirestoreService.addOwnerRecord('subjects', {
      'name': name,
      'semesterId': semesterId,
    });
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

Future<void> _renameSemester(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> semester,
) async {
  final name = await _promptForName(
    context,
    title: GochanoLanguage.text(
      'Rename semester',
      'সেমিস্টারের নাম পরিবর্তন',
    ),
    label: GochanoLanguage.text('Semester name', 'সেমিস্টারের নাম'),
    initial: semester.data()['name']?.toString() ?? '',
  );
  if (name == null) return;
  await semester.reference.update({
    'name': name,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

Future<void> _renameSubject(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> subject,
) async {
  final name = await _promptForName(
    context,
    title: GochanoLanguage.text('Rename subject', 'বিষয়ের নাম পরিবর্তন'),
    label: GochanoLanguage.text('Subject name', 'বিষয়ের নাম'),
    initial: subject.data()['name']?.toString() ?? '',
  );
  if (name == null) return;
  await subject.reference.update({
    'name': name,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}

Future<void> _deleteSemester(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> semester,
  List<QueryDocumentSnapshot<Map<String, dynamic>>> subjects,
) async {
  final confirmed = await showConfirmationSheet(
    context,
    title: GochanoLanguage.text('Delete this semester?', 'সেমিস্টারটি মুছবেন?'),
    message: subjects.isEmpty
        ? GochanoLanguage.text(
            'The semester will be removed.',
            'সেমিস্টারটি মুছে যাবে।',
          )
        : GochanoLanguage.text(
            'Its ${subjects.length} subjects will be removed too. Your uploaded '
            'materials are kept and stay available in your material library.',
            'এর ${subjects.length} টি বিষয়ও মুছে যাবে। আপনার আপলোড করা উপকরণ '
            'থেকে যাবে এবং লাইব্রেরিতে পাওয়া যাবে।',
          ),
    confirmLabel: GochanoLanguage.text('Delete', 'মুছুন'),
  );
  if (!confirmed || !context.mounted) return;

  try {
    final batch = FirestoreService.db.batch();
    for (final subject in subjects) {
      batch.delete(subject.reference);
    }
    batch.delete(semester.reference);
    await batch.commit();
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

Future<void> _deleteSubject(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> subject,
) async {
  final confirmed = await showConfirmationSheet(
    context,
    title: GochanoLanguage.text('Delete this subject?', 'বিষয়টি মুছবেন?'),
    message: GochanoLanguage.text(
      'Your uploaded materials are kept and stay available in your material '
      'library.',
      'আপনার আপলোড করা উপকরণ থেকে যাবে এবং লাইব্রেরিতে পাওয়া যাবে।',
    ),
    confirmLabel: GochanoLanguage.text('Delete', 'মুছুন'),
  );
  if (!confirmed || !context.mounted) return;
  try {
    await subject.reference.delete();
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

Future<String?> _promptForName(
  BuildContext context, {
  required String title,
  required String label,
  String? hint,
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  try {
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onSubmitted: (value) =>
              Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(GochanoLanguage.text('Cancel', 'বাতিল')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(GochanoLanguage.text('Save', 'সংরক্ষণ')),
          ),
        ],
      ),
    );
    return (name == null || name.isEmpty) ? null : name;
  } finally {
    controller.dispose();
  }
}
