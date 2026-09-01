// Upload a study material (spec §32, §45).
//
// File types
// ----------
// The picker allows exactly what the backend accepts. Spec §45 is explicit
// that Flutter must not artificially block a format the API supports, so this
// list mirrors `detect_supported_file_type` on the server rather than being a
// narrower client-side opinion.
//
// Upload goes to `POST /api/materials/upload`, which enforces the per-user
// storage quota and the daily upload limit, writes the object to Backblaze B2
// and creates the Firestore document in one place.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_illustration.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../services/firestore_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

class MaterialUploadScreen extends StatefulWidget {
  const MaterialUploadScreen({
    super.key,
    this.subject = '',
    this.groupId = '',
    this.groupName = '',
  });

  /// Pre-fills the subject when opened from a subject screen.
  final String subject;

  /// When set, the material is uploaded as a group resource.
  final String groupId;
  final String groupName;

  @override
  State<MaterialUploadScreen> createState() => _MaterialUploadScreenState();
}

class _MaterialUploadScreenState extends State<MaterialUploadScreen> {
  /// Exactly what the backend accepts.
  ///
  /// `detect_supported_file_type` in `app/core/utils.py` sniffs magic bytes
  /// and allows PDF, PNG, JPEG, DOC and DOCX — nothing else. Offering more
  /// here would send the student through a file picker to a 415; offering
  /// less would block a format the API supports, which spec §45 forbids.
  /// Keep this list and that function in step.
  static const _allowedExtensions = [
    'pdf',
    'png',
    'jpg',
    'jpeg',
    'doc',
    'docx',
  ];

  late final TextEditingController _title;
  late final TextEditingController _subject;

  Uint8List? _bytes;
  String _fileName = '';
  bool _uploading = false;
  String? _error;

  bool get _isGroupUpload => widget.groupId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController();
    _subject = TextEditingController(text: widget.subject);
  }

  @override
  void dispose() {
    _title.dispose();
    _subject.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: _allowedExtensions,
      );
      if (selected == null) return;
      final bytes = await selected.readAsBytes();
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _fileName = selected.name;
        _error = null;
        if (_title.text.trim().isEmpty) _title.text = selected.name;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    }
  }

  Future<void> _upload() async {
    final bytes = _bytes;
    if (bytes == null) {
      setState(() {
        _error = GochanoLanguage.text(
          'Choose a file first.',
          'প্রথমে একটি ফাইল বাছুন।',
        );
      });
      return;
    }

    setState(() {
      _uploading = true;
      _error = null;
    });

    try {
      final profile = await FirestoreService.profile();
      await ApiService.uploadMaterial(
        bytes: bytes,
        fileName: _fileName,
        title: _title.text.trim().isEmpty ? _fileName : _title.text.trim(),
        visibility: _isGroupUpload ? 'group' : 'private',
        groupId: widget.groupId,
        university: profile['university']?.toString() ?? '',
        department: profile['department']?.toString() ?? '',
        semester: profile['semester']?.toString() ?? '',
        subject: _subject.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      showGochanoMessage(
        context,
        GochanoLanguage.text('Material uploaded.', 'উপকরণ আপলোড হয়েছে।'),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final hasFile = _bytes != null;

    return GochanoScaffold(
      appBar: GochanoAppBar(
        title: _isGroupUpload
            ? GochanoLanguage.text('Share to group', 'গ্রুপে শেয়ার')
            : GochanoLanguage.text('Add material', 'উপকরণ যোগ করুন'),
        subtitle: _isGroupUpload ? widget.groupName : null,
      ),
      bottomBar: PrimaryButton(
        label: _isGroupUpload
            ? GochanoLanguage.text('Share', 'শেয়ার')
            : GochanoLanguage.text('Upload', 'আপলোড'),
        busy: _uploading,
        busyLabel: GochanoLanguage.text('Uploading…', 'আপলোড হচ্ছে…'),
        onPressed: hasFile ? _upload : null,
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          AppCard(
            onTap: _uploading ? null : _pick,
            child: Row(
              children: [
                GochanoIllustration(
                  hasFile
                      ? GochanoArt.fileIdFor(fileName: _fileName)
                      : GochanoArt.emptyMaterials,
                  size: 44,
                  accent: colors.study,
                ),
                const SizedBox(width: GochanoSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hasFile
                            ? _fileName
                            : GochanoLanguage.text('Choose a file', 'একটি ফাইল বাছুন'),
                        style: type.cardHeading,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasFile
                            ? _readableSize(_bytes!.length)
                            : GochanoLanguage.text(
                                'PDF, JPEG or PNG image, or a Word document',
                                'পিডিএফ, জেপিইজি বা পিএনজি ছবি, অথবা ওয়ার্ড ডকুমেন্ট',
                              ),
                        style: type.caption,
                      ),
                    ],
                  ),
                ),
                Icon(
                  hasFile ? Icons.swap_horiz_rounded : Icons.add_rounded,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
          const SizedBox(height: GochanoSpacing.md),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: GochanoLanguage.text('Title', 'শিরোনাম'),
            ),
          ),
          if (!_isGroupUpload) ...[
            const SizedBox(height: GochanoSpacing.sm),
            TextField(
              controller: _subject,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text(
                  'Subject (optional)',
                  'বিষয় (ঐচ্ছিক)',
                ),
                helperText: GochanoLanguage.text(
                  'Files with the same subject are grouped together.',
                  'একই বিষয়ের ফাইল একসাথে দেখানো হয়।',
                ),
              ),
            ),
          ],
          if (_uploading) ...[
            const SizedBox(height: GochanoSpacing.lg),
            StaticLoadingState(
              message: GochanoLanguage.text(
                'Uploading your file…',
                'আপনার ফাইল আপলোড হচ্ছে…',
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
                      style: type.bodySecondary.copyWith(color: colors.error),
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

String _readableSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
