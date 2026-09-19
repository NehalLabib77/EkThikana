// Revision Assistant — AI-powered exam revision planning.
//
// Generates revision checklists, priority rankings, and day-by-day schedules.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

class RevisionAssistantScreen extends StatefulWidget {
  const RevisionAssistantScreen({super.key});

  @override
  State<RevisionAssistantScreen> createState() => _RevisionAssistantScreenState();
}

class _RevisionAssistantScreenState extends State<RevisionAssistantScreen> {
  final _subjectCtrl = TextEditingController();
  final _examDateCtrl = TextEditingController();
  final _topicsCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _busy = false;
  String _result = '';
  String _error = '';

  @override
  void dispose() {
    _subjectCtrl.dispose();
    _examDateCtrl.dispose();
    _topicsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final subject = _subjectCtrl.text.trim();
    final examDate = _examDateCtrl.text.trim();

    if (subject.isEmpty) {
      setState(() => _error = GochanoLanguage.text(
        'Please enter a subject name.',
        'অনুগ্রহ করে একটি বিষয়ের নাম লিখুন।',
      ));
      return;
    }
    if (examDate.isEmpty) {
      setState(() => _error = GochanoLanguage.text(
        'Please enter the exam date.',
        'অনুগ্রহ করে পরীক্ষার তারিখ লিখুন।',
      ));
      return;
    }

    setState(() {
      _busy = true;
      _error = '';
      _result = '';
    });

    try {
      final topics = _topicsCtrl.text
          .split('\n')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final result = await ApiService.revisionPlan(
        subject: subject,
        examDate: examDate,
        topics: topics,
        notesSummary: _notesCtrl.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _busy = false;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Revision Assistant', 'পুনরালোচনা সহকারী'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          GochanoSpacing.md,
          GochanoSpacing.sm,
          GochanoSpacing.md,
          120,
        ),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  GochanoLanguage.text('Exam Details', 'পরীক্ষার বিবরণ'),
                  style: context.type.cardHeading,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                TextField(
                  controller: _subjectCtrl,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('Subject *', 'বিষয় *'),
                    hintText: GochanoLanguage.text(
                      'e.g., Operating Systems',
                      'যেমন, অপারেটিং সিস্টেম',
                    ),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                TextField(
                  controller: _examDateCtrl,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('Exam Date *', 'পরীক্ষার তারিখ *'),
                    hintText: GochanoLanguage.text(
                      'e.g., 2026-10-15',
                      'যেমন, ২০২৬-১০-১৫',
                    ),
                  ),
                ),
                const SizedBox(height: GochanoSpacing.sm),
                TextField(
                  controller: _topicsCtrl,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('Topics (one per line)', 'বিষয় (প্রতিটি এক লাইন)'),
                    hintText: GochanoLanguage.text(
                      'e.g.,\nProcess Management\nMemory Management\nFile Systems',
                      'যেমন,\nপ্রসেস ম্যানেজমেন্ট\nমেমরি ম্যানেজমেন্ট\nফাইল সিস্টেম',
                    ),
                  ),
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                TextField(
                  controller: _notesCtrl,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('Notes Summary (optional)', 'নোট সারাংশ (ঐচ্ছিক)'),
                    hintText: GochanoLanguage.text(
                      'Key points from your notes…',
                      'আপনার নোট থেকে মূল পয়েন্ট…',
                    ),
                  ),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
          ),

          const SizedBox(height: GochanoSpacing.md),

          PrimaryButton(
            label: GochanoLanguage.text('Generate Plan', 'পরিকল্পনা তৈরি করুন'),
            icon: Icons.school_rounded,
            busy: _busy,
            busyLabel: GochanoLanguage.text('Planning…', 'পরিকল্পনা হচ্ছে…'),
            onPressed: _generate,
          ),

          if (_error.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.sm),
            Container(
              padding: const EdgeInsets.all(GochanoSpacing.sm),
              decoration: BoxDecoration(
                color: colors.errorSoft,
                borderRadius: GochanoRadius.mdAll,
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 18, color: colors.error),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: Text(_error, style: context.type.bodySecondary.copyWith(color: colors.error)),
                  ),
                ],
              ),
            ),
          ],

          if (_result.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.md),
            AppCard(
              padding: const EdgeInsets.all(GochanoSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.school_rounded, size: 18, color: colors.ai),
                      const SizedBox(width: GochanoSpacing.xs),
                      Expanded(
                        child: Text(
                          GochanoLanguage.text('Revision Plan', 'পুনরালোচনা পরিকল্পনা'),
                          style: context.type.cardHeading.copyWith(color: colors.ai),
                        ),
                      ),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _result));
                          showGochanoMessage(context, GochanoLanguage.text('Copied', 'কপি হয়েছে'));
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.copy_rounded, size: 14, color: colors.textTertiary),
                            const SizedBox(width: 4),
                            Text(
                              GochanoLanguage.text('Copy', 'কপি'),
                              style: context.type.caption.copyWith(color: colors.textTertiary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.sm),
                  SelectableText(_result, style: context.type.body),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
