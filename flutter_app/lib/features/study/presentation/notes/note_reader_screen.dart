// Read-only note viewer (spec §21, §32).
//
// Students can view notes in a clean, distraction-free interface without
// the editing controls. This is useful for:
//   - Quick review without accidental edits
//   - Sharing notes as read-only
//   - Viewing notes from other users (if shared)
//
// The screen shows:
//   - Title (large, prominent)
//   - Content (full width, readable typography)
//   - Metadata (created/updated dates, word count)
//   - No editing controls

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

class NoteReaderScreen extends StatelessWidget {
  const NoteReaderScreen({
    super.key,
    required this.noteId,
    required this.initialData,
  });

  final String noteId;
  final Map<String, dynamic> initialData;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = initialData['title']?.toString() ?? '';
    final content = initialData['content']?.toString() ?? '';
    final createdAt = initialData['createdAt'];
    final updatedAt = initialData['updatedAt'];
    final isShared = initialData['visibility']?.toString() == 'group';

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Note', 'নোট'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: GochanoLanguage.text('Copy content', 'কনটেন্ট কপি'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              showGochanoMessage(
                context,
                GochanoLanguage.text('Copied to clipboard', 'ক্লিপবোর্ডে কপি হয়েছে'),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(GochanoSpacing.md),
        children: [
          // Title
          if (title.isNotEmpty)
            Text(
              title,
              style: context.type.pageTitle.copyWith(
                color: colors.textPrimary,
              ),
            ),
          if (title.isNotEmpty)
            const SizedBox(height: GochanoSpacing.sm),

          // Metadata row
          Row(
            children: [
              if (isShared)
                GochanoBadge(
                  label: GochanoLanguage.text('Shared', 'শেয়ার করা'),
                  tone: GochanoBadgeTone.info,
                  icon: Icons.groups_rounded,
                ),
              if (isShared)
                const SizedBox(width: GochanoSpacing.sm),
              Text(
                _formatMetadata(createdAt, updatedAt, content),
                style: context.type.label.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.lg),

          // Content
          if (content.isEmpty)
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.note_alt_outlined,
                    size: 48,
                    color: colors.textTertiary,
                  ),
                  const SizedBox(height: GochanoSpacing.sm),
                  Text(
                    GochanoLanguage.text('Empty note', 'খালি নোট'),
                    style: context.type.cardHeading,
                  ),
                  const SizedBox(height: GochanoSpacing.xs),
                  Text(
                    GochanoLanguage.text(
                      'This note has no content.',
                      'এই নোটে কোনো কনটেন্ট নেই।',
                    ),
                    style: context.type.bodySecondary,
                  ),
                ],
              ),
            )
          else
            SelectableText(
              content,
              style: context.type.body.copyWith(
                color: colors.textPrimary,
                height: 1.7,
              ),
            ),
        ],
      ),
    );
  }

  String _formatMetadata(Object? created, Object? updated, String content) {
    final parts = <String>[];

    // Word count
    final words = content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    parts.add('$words ${words == 1 ? 'word' : 'words'}');

    // Updated date
    if (updated is Timestamp) {
      final date = updated.toDate();
      parts.add('Updated ${_formatDate(date)}');
    } else if (created is Timestamp) {
      final date = created.toDate();
      parts.add('Created ${_formatDate(date)}');
    }

    return parts.join(' · ');
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
