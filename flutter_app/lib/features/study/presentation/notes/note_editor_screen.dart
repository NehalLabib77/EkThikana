// Text note editor (spec §21, §32, §34).
//
// A note is study content the student writes rather than uploads. It lives in
// the `notes` Firestore collection, can be private or shared to a group, and
// is the one material type the AI can work on directly through
// `POST /api/ai/note` — cleanup, summary, explanation and key topics, which
// are exactly the four instructions the backend implements.
//
// The AI never overwrites the note silently: a result is shown first, and
// replacing the content is a separate, explicit tap.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/feedback_messages.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../services/firestore_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    this.noteId,
    this.initialData,
    this.initialVisibility = 'private',
    this.initialGroupId,
    this.initialGroupName,
  });

  final String? noteId;
  final Map<String, dynamic>? initialData;

  /// 'private' or 'group'.
  final String initialVisibility;
  final String? initialGroupId;
  final String? initialGroupName;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late final TextEditingController _title;
  late final TextEditingController _content;
  late String _visibility;
  String? _groupId;
  late bool _showMoreOptions;

  bool _saving = false;
  bool _thinking = false;
  String? _error;

  bool get _isEdit => widget.noteId != null;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData ?? const <String, dynamic>{};
    _title = TextEditingController(text: data['title']?.toString() ?? '');
    _content = TextEditingController(text: data['content']?.toString() ?? '');
    _visibility = data['visibility']?.toString() ?? widget.initialVisibility;
    _groupId = data['groupId']?.toString() ?? widget.initialGroupId;
    _showMoreOptions = _visibility == 'group';
  }

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() {
        _error = GochanoLanguage.text(
          'Give the note a title.',
          'নোটটির একটি শিরোনাম দিন।',
        );
      });
      return;
    }
    if (_visibility == 'group' && (_groupId == null || _groupId!.isEmpty)) {
      setState(() {
        _error = GochanoLanguage.text(
          'Choose which group to share with.',
          'কোন গ্রুপে শেয়ার করবেন তা বাছুন।',
        );
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await FirestoreService.saveNote(
        id: widget.noteId,
        title: _title.text,
        content: _content.text,
        visibility: _visibility,
        groupId: _groupId,
      );
      if (mounted) Navigator.of(context).pop(true);
      if (mounted) {
        showGochanoMessage(
          context,
          FeedbackMessages.noteSaved(isEdit: widget.noteId != null),
        );
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  /// Runs one of the backend's four note instructions and offers the result.
  Future<void> _runAi(String action, String label) async {
    if (_content.text.trim().isEmpty) {
      setState(() {
        _error = GochanoLanguage.text(
          'Write something in the note first.',
          'আগে নোটে কিছু লিখুন।',
        );
      });
      return;
    }

    setState(() {
      _thinking = true;
      _error = null;
    });

    try {
      final result = await ApiService.aiNote(action, _content.text);
      if (!mounted) return;
      setState(() => _thinking = false);

      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(label),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(result, style: context.type.body),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(
                GochanoLanguage.text('Keep my note', 'আমার নোট রাখুন'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(
                GochanoLanguage.text('Use this instead', 'এটি ব্যবহার করুন'),
              ),
            ),
          ],
        ),
      );
      if (replace == true && mounted) {
        setState(() => _content.text = result);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _thinking = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: _isEdit
            ? GochanoLanguage.text('Edit note', 'নোট সম্পাদনা')
            : GochanoLanguage.text('New note', 'নতুন নোট'),
        subtitle: _visibility == 'group' ? widget.initialGroupName : null,
        actions: [
          GochanoOverflowMenu(
            tooltip: GochanoLanguage.text('AI tools', 'এআই টুল'),
            items: [
              GochanoMenuAction(
                label: GochanoLanguage.text(
                  'Clean up my note',
                  'নোট গুছিয়ে দাও',
                ),
                icon: Icons.auto_fix_high_outlined,
                enabled: !_thinking,
                onSelected: () => _runAi(
                  'cleanup',
                  GochanoLanguage.text('Cleaned up', 'গোছানো হয়েছে'),
                ),
              ),
              GochanoMenuAction(
                label: GochanoLanguage.text('Summarise', 'সারাংশ'),
                icon: Icons.short_text_rounded,
                enabled: !_thinking,
                onSelected: () => _runAi(
                  'summary',
                  GochanoLanguage.text('Summary', 'সারাংশ'),
                ),
              ),
              GochanoMenuAction(
                label: GochanoLanguage.text('Explain this', 'ব্যাখ্যা করো'),
                icon: Icons.school_outlined,
                enabled: !_thinking,
                onSelected: () => _runAi(
                  'explain',
                  GochanoLanguage.text('Explanation', 'ব্যাখ্যা'),
                ),
              ),
              GochanoMenuAction(
                label: GochanoLanguage.text(
                  'Extract key points',
                  'মূল পয়েন্ট',
                ),
                icon: Icons.format_list_bulleted_rounded,
                enabled: !_thinking,
                onSelected: () => _runAi(
                  'key_topics',
                  GochanoLanguage.text('Key points', 'মূল পয়েন্ট'),
                ),
              ),
            ],
          ),
        ],
      ),
      bottomBar: PrimaryButton(
        label: GochanoLanguage.text('Save note', 'নোট সংরক্ষণ'),
        busy: _saving,
        busyLabel: GochanoLanguage.text('Saving…', 'সংরক্ষণ হচ্ছে…'),
        onPressed: _save,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          TextField(
            controller: _title,
            autofocus: !_isEdit,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('Title', 'শিরোনাম'),
              hintText: GochanoLanguage.text(
                'Normalization — 1NF to BCNF',
                'নরমালাইজেশন — ১এনএফ থেকে বিসিএনএফ',
              ),
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),
          TextField(
            controller: _content,
            minLines: 8,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            style: context.type.body,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('Note', 'নোট'),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: GochanoSpacing.sm),

          // More options toggle (progressive disclosure)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('note_more_options_toggle'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                minimumSize: const Size(0, GochanoSizes.minTouchTarget),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () =>
                  setState(() => _showMoreOptions = !_showMoreOptions),
              icon: Icon(
                _showMoreOptions
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 20,
              ),
              label: Text(
                GochanoLanguage.text('More options', 'আরও অপশন'),
                style: context.type.bodySecondary.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.brand,
                ),
              ),
            ),
          ),

          if (_showMoreOptions) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Text(
              GochanoLanguage.text('Visibility', 'দৃশ্যমানতা'),
              style: context.type.label,
            ),
            const SizedBox(height: GochanoSpacing.xs),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: 'private',
                  label: Text(GochanoLanguage.text('Private', 'ব্যক্তিগত')),
                  icon: const Icon(Icons.lock_outline_rounded, size: 16),
                ),
                ButtonSegment(
                  value: 'group',
                  label: Text(
                    GochanoLanguage.text('Share to group', 'গ্রুপে শেয়ার'),
                  ),
                  icon: const Icon(Icons.group_outlined, size: 16),
                ),
              ],
              selected: {_visibility},
              onSelectionChanged: (val) {
                setState(() => _visibility = val.first);
              },
            ),
            if (_visibility == 'group') ...[
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                widget.initialGroupName != null
                    ? GochanoLanguage.text(
                        'Sharing with: ${widget.initialGroupName}',
                        'শেয়ার হচ্ছে: ${widget.initialGroupName}',
                      )
                    : GochanoLanguage.text(
                        'Shared with your study group',
                        'আপনার স্টাডি গ্রুপে শেয়ার করা হবে',
                      ),
                style: context.type.caption.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ],

          if (_thinking) ...[
            const SizedBox(height: GochanoSpacing.md),
            StaticLoadingState(
              compact: true,
              message: GochanoLanguage.text(
                'Reading your note…',
                'আপনার নোট পড়া হচ্ছে…',
              ),
            ),
          ],

          if (_error != null) ...[
            const SizedBox(height: GochanoSpacing.md),
            Container(
              padding: const EdgeInsets.all(GochanoSpacing.sm),
              decoration: BoxDecoration(
                color: colors.errorSoft,
                borderRadius: GochanoRadius.mdAll,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: GochanoSizes.iconSm,
                    color: colors.error,
                  ),
                  const SizedBox(width: GochanoSpacing.xs),
                  Expanded(
                    child: Text(
                      _error!,
                      style: context.type.bodySecondary.copyWith(
                        color: colors.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Deletes a note after confirmation.
Future<bool> deleteNote(
  BuildContext context,
  DocumentSnapshot<Map<String, dynamic>> doc,
) async {
  final title = doc.data()?['title']?.toString() ?? '';
  final confirmed = await showConfirmationSheet(
    context,
    title: GochanoLanguage.text('Delete this note?', 'নোটটি মুছবেন?'),
    message: title,
    confirmLabel: GochanoLanguage.text('Delete', 'মুছুন'),
  );
  if (!confirmed || !context.mounted) return false;
  try {
    await FirestoreService.deleteOwnerDocument('notes', doc.id);
    return true;
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
    return false;
  }
}
