// Material library (spec §32).
//
// A searchable, filterable list of everything the student has uploaded.
// Actions live in each row's overflow menu — Open, Ask AI, Rename, Download,
// Delete — rather than as six permanent buttons per card (spec §32).

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/api_service.dart';
import '../../../../services/firestore_service.dart';
import '../../../../services/offline_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../ai/ai_assistant_screen.dart';
import 'material_reader_screen.dart';
import 'material_upload_screen.dart';

/// How the list is ordered.
enum MaterialSort { newest, oldest, name, size }

class MaterialsScreen extends StatefulWidget {
  const MaterialsScreen({
    super.key,
    this.subjectFilter,
    this.mimeFilter,
    this.documentFilter = false,
    this.materialsStream,
  });

  /// When set, only materials filed under this subject are shown.
  final String? subjectFilter;

  /// When set, only materials whose MIME type starts with this prefix are shown.
  final String? mimeFilter;

  /// When true, shows only document materials (PDF, DOC, DOCX, TXT).
  final bool documentFilter;

  /// Optional stream override for tests or controlled fixtures.
  final Stream<QuerySnapshot<Map<String, dynamic>>>? materialsStream;

  @override
  State<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends State<MaterialsScreen> {
  final _search = TextEditingController();
  String _query = '';
  MaterialSort _sort = MaterialSort.newest;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: widget.documentFilter
            ? GochanoLanguage.text('Documents', 'ডকুমেন্ট')
            : widget.subjectFilter ??
                  (widget.mimeFilter != null
                      ? _mimeFilterTitle(widget.mimeFilter!)
                      : GochanoLanguage.text(
                          'Study Materials',
                          'অধ্যয়ন উপকরণ',
                        )),
        subtitle: widget.documentFilter
            ? GochanoLanguage.text(
                'All document materials',
                'সমস্ত ডকুমেন্ট উপকরণ',
              )
            : widget.subjectFilter != null
                ? GochanoLanguage.text('Subject materials', 'বিষয়ের উপকরণ')
                : widget.mimeFilter != null
                    ? GochanoLanguage.text(
                        'Filtered materials',
                        'ফিল্টার করা উপকরণ',
                      )
                    : GochanoLanguage.text(
                        'PDFs, slides & document library',
                        'পিডিএফ, স্লাইড ও ডকুমেন্ট লাইব্রেরি',
                      ),
        actions: [
          PopupMenuButton<MaterialSort>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: GochanoLanguage.text('Sort', 'সাজান'),
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: MaterialSort.newest,
                child: Text(GochanoLanguage.text('Newest first', 'নতুন আগে')),
              ),
              PopupMenuItem(
                value: MaterialSort.oldest,
                child: Text(GochanoLanguage.text('Oldest first', 'পুরোনো আগে')),
              ),
              PopupMenuItem(
                value: MaterialSort.name,
                child: Text(GochanoLanguage.text('Name', 'নাম')),
              ),
              PopupMenuItem(
                value: MaterialSort.size,
                child: Text(GochanoLanguage.text('Largest first', 'বড় আগে')),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppGradients.skyAccent,
        foregroundColor: Colors.white,
        onPressed: () => Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) =>
                MaterialUploadScreen(subject: widget.subjectFilter ?? ''),
          ),
        ),
        icon: const Icon(Icons.upload_file_rounded),
        label: Text(GochanoLanguage.text('Add material', 'উপকরণ যোগ')),
      ),
      body: AppPageBackground(
        height: 240,
        gradient: context.isDark
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [context.colors.surface, context.colors.background],
              )
            : AppGradients.toolMaterials,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                GochanoSpacing.md,
                GochanoSpacing.xs,
                GochanoSpacing.md,
                GochanoSpacing.sm,
              ),
              child: SearchField(
                controller: _search,
                hint: GochanoLanguage.text(
                  'Search your materials',
                  'আপনার উপকরণ খুঁজুন',
                ),
                onChanged: (value) => setState(() => _query = value.trim()),
                trailing: _query.isEmpty
                    ? null
                    : IconActionButton(
                        icon: Icons.close_rounded,
                        label: GochanoLanguage.text('Clear', 'মুছুন'),
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
            Expanded(child: _buildList(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: widget.materialsStream ??
          FirestoreService.ownerStream('materials', limit: 300),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return StaticLoadingState(
            message: GochanoLanguage.text(
              'Loading materials…',
              'উপকরণ লোড হচ্ছে…',
            ),
          );
        }
        if (snapshot.hasError) {
          return ErrorState(message: friendlyErrorMessage(snapshot.error));
        }

        var docs = [...?snapshot.data?.docs];

        if (widget.subjectFilter != null) {
          docs = docs
              .where(
                (d) => d.data()['subject']?.toString() == widget.subjectFilter,
              )
              .toList();
        }

        if (widget.mimeFilter != null) {
          docs = docs
              .where(
                (d) =>
                    d.data()['mimeType']?.toString().toLowerCase().startsWith(
                      widget.mimeFilter!,
                    ) ==
                    true,
              )
              .toList();
        }

        if (widget.documentFilter) {
          docs = docs.where((d) {
            final data = d.data();
            final mime = (data['mimeType'] ?? '').toString().toLowerCase();
            final name = (data['fileName'] ?? '').toString().toLowerCase();
            // Document: PDF, DOC, DOCX, TXT — any non-image file
            if (mime.startsWith('image/')) {
              return false;
            }
            if (name.endsWith('.jpg') ||
                name.endsWith('.jpeg') ||
                name.endsWith('.png') ||
                name.endsWith('.webp')) {
              return false;
            }
            return true;
          }).toList();
        }

        if (_query.isNotEmpty) {
          final needle = _query.toLowerCase();
          docs = docs.where((d) {
            final data = d.data();
            return [
              data['title']?.toString() ?? '',
              data['fileName']?.toString() ?? '',
              data['subject']?.toString() ?? '',
            ].any((field) => field.toLowerCase().contains(needle));
          }).toList();
        }

        docs.sort((a, b) {
          final ad = a.data();
          final bd = b.data();
          switch (_sort) {
            case MaterialSort.newest:
            case MaterialSort.oldest:
              final at = ad['createdAt'];
              final bt = bd['createdAt'];
              if (at is! Timestamp || bt is! Timestamp) return 0;
              return _sort == MaterialSort.newest
                  ? bt.compareTo(at)
                  : at.compareTo(bt);
            case MaterialSort.name:
              return _title(
                ad,
              ).toLowerCase().compareTo(_title(bd).toLowerCase());
            case MaterialSort.size:
              return ((bd['sizeBytes'] as num?) ?? 0).compareTo(
                (ad['sizeBytes'] as num?) ?? 0,
              );
          }
        });

        if (docs.isEmpty) {
          final bool isFiltered =
              widget.mimeFilter != null ||
              widget.subjectFilter != null ||
              widget.documentFilter;
          final String emptyTitle;
          final String emptyMessage;

          if (_query.isNotEmpty) {
            emptyTitle = GochanoLanguage.text('Nothing matched', 'কিছু মেলেনি');
            emptyMessage = GochanoLanguage.text(
              'Try a different word.',
              'অন্য একটি শব্দ চেষ্টা করুন।',
            );
          } else if (widget.documentFilter) {
            emptyTitle = GochanoLanguage.text(
              'No documents yet',
              'এখনো কোনো ডকুমেন্ট নেই',
            );
            emptyMessage = GochanoLanguage.text(
              'Upload documents (PDF, DOC, TXT) using the + button.',
              '+ বোতাম দিয়ে ডকুমেন্ট (PDF, DOC, TXT) আপলোড করুন।',
            );
          } else if (widget.mimeFilter?.startsWith('image/') == true) {
            emptyTitle = GochanoLanguage.text(
              'No saved images yet',
              'এখনো কোনো সংরক্ষিত ছবি নেই',
            );
            emptyMessage = GochanoLanguage.text(
              'Upload images using the + button.',
              '+ বোতাম দিয়ে ছবি আপলোড করুন।',
            );
          } else if (widget.mimeFilter?.contains('pdf') == true) {
            emptyTitle = GochanoLanguage.text(
              'No PDFs yet',
              'এখনো কোনো পিডিএফ নেই',
            );
            emptyMessage = GochanoLanguage.text(
              'Upload PDFs using the + button.',
              '+ বোতাম দিয়ে পিডিএফ আপলোড করুন।',
            );
          } else if (isFiltered) {
            emptyTitle = GochanoLanguage.text(
              'No materials yet',
              'এখনো কোনো উপকরণ নেই',
            );
            emptyMessage = GochanoLanguage.text(
              'Upload materials using the + button.',
              '+ বোতাম দিয়ে উপকরণ আপলোড করুন।',
            );
          } else {
            emptyTitle = GochanoLanguage.text(
              'No materials yet',
              'এখনো কোনো উপকরণ নেই',
            );
            emptyMessage = GochanoLanguage.text(
              'Upload your first note, PDF or study resource using the + button.',
              '+ বোতাম দিয়ে আপনার প্রথম নোট, পিডিএফ বা পড়ার উপকরণ আপলোড করুন।',
            );
          }

          final emptyWidget = EmptyState(
            key: const ValueKey('materials_empty'),
            illustration: GochanoArt.emptyMaterials,
            title: emptyTitle,
            message: emptyMessage,
          );
          return AnimatedSwitcher(
            duration: AppMotion.duration(
              context,
              AppMotion.contentReveal,
            ),
            switchInCurve: AppMotion.standard,
            switchOutCurve: AppMotion.standard,
            child: emptyWidget,
          );
        }

        // ListView.builder so a student with 300 materials does not build
        // 300 rows at once (spec §83).
        final listWidget = ListView.builder(
          key: ValueKey('materials_list_${_sort.name}_${_query.isEmpty}'),
          padding: GochanoSpacing.scrollBody,
          itemCount: docs.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
            child: AppCard(
              padding: EdgeInsets.zero,
              child: _MaterialRow(doc: docs[i]),
            ),
          ),
        );

        return AnimatedSwitcher(
          duration: AppMotion.duration(
            context,
            AppMotion.contentReveal,
          ),
          switchInCurve: AppMotion.standard,
          switchOutCurve: AppMotion.standard,
          child: listWidget,
        );
      },
    );
  }
}

class _MaterialRow extends StatelessWidget {
  const _MaterialRow({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final title = _title(data);
    final mimeType = data['mimeType']?.toString() ?? '';
    final fileName = data['fileName']?.toString() ?? '';
    final visibility = data['visibility']?.toString() ?? 'private';

    void open() => Navigator.of(context).push(
      GochanoRoute.to(
        builder: (_) => MaterialReaderScreen(
          materialId: doc.id,
          title: title,
          mimeType: mimeType,
          fileName: fileName,
        ),
      ),
    );

    return GochanoListRow(
      illustration: GochanoArt.fileIdFor(
        fileName: fileName,
        mimeType: mimeType,
      ),
      accent: AppGradients.skyAccent,
      title: title,
      subtitle: data['subject']?.toString(),
      metadata: [_fileSize(data['sizeBytes']), _createdAt(data['createdAt'])],
      badge: visibility == 'group'
          ? GochanoBadge(
              label: GochanoLanguage.text('Shared', 'শেয়ার করা'),
              tone: GochanoBadgeTone.info,
              icon: Icons.groups_rounded,
            )
          : null,
      onTap: open,
      menuItems: [
        GochanoMenuAction(
          label: GochanoLanguage.text('Open', 'খুলুন'),
          icon: Icons.open_in_new_rounded,
          onSelected: open,
        ),
        GochanoMenuAction(
          label: GochanoLanguage.text(
            'Ask AI',
            'এআই জিজ্ঞাসা',
          ),
          icon: Icons.auto_awesome_outlined,
          onSelected: () => Navigator.of(context).push(
            GochanoRoute.to(
              builder: (_) => AiAssistantScreen(
                contextMaterialId: doc.id,
                contextMaterialTitle: title,
                contextMimeType: mimeType,
                contextFileName: fileName,
              ),
            ),
          ),
        ),
        GochanoMenuAction(
          label: GochanoLanguage.text('Download', 'ডাউনলোড'),
          icon: Icons.download_outlined,
          onSelected: () =>
              _downloadOffline(context, doc, title, fileName, mimeType),
        ),
        GochanoMenuAction(
          label: GochanoLanguage.text('Rename', 'নাম পরিবর্তন'),
          icon: Icons.edit_outlined,
          onSelected: () => _rename(context, doc, title),
        ),
        GochanoMenuAction(
          label: GochanoLanguage.text('Delete', 'মুছুন'),
          icon: Icons.delete_outline_rounded,
          destructive: true,
          onSelected: () => _delete(context, doc, title),
        ),
      ],
    );
  }
}

Future<void> _downloadOffline(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
  String title,
  String fileName,
  String mimeType,
) async {
  try {
    final existing = await OfflineService.find(doc.id);
    if (existing != null) {
      final f = File(existing.localPath);
      if (await f.exists()) {
        if (context.mounted) {
          showGochanoMessage(
            context,
            GochanoLanguage.text(
              'Already downloaded for offline reading.',
              'ইতিমধ্যেই অফলাইন পড়ার জন্য ডাউনলোড করা আছে।',
            ),
          );
        }
        return;
      }
    }

    if (context.mounted) {
      showGochanoMessage(
        context,
        GochanoLanguage.text('Downloading material…', 'উপকরণ ডাউনলোড হচ্ছে…'),
      );
    }

    final url = await ApiService.materialUrl(doc.id, download: true);
    final bytes = await ApiService.downloadBytes(url);
    await OfflineService.register(
      materialId: doc.id,
      title: title.isEmpty ? fileName : title,
      fileName: fileName.isEmpty ? title : fileName,
      bytes: bytes,
      mimeType: mimeType,
    );

    if (context.mounted) {
      showGochanoMessage(
        context,
        GochanoLanguage.text(
          'Downloaded for offline reading.',
          'অফলাইন পড়ার জন্য ডাউনলোড সম্পন্ন হয়েছে।',
        ),
      );
    }
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialText});
  final String initialText;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: GochanoRadius.lgAll),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isDark
                  ? AppGradients.skyDark.withValues(alpha: 0.3)
                  : const Color(0xFFE0F2FE),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.edit_note_rounded,
              size: 20,
              color: AppGradients.skyAccent,
            ),
          ),
          const SizedBox(width: GochanoSpacing.sm),
          Expanded(
            child: Text(
              GochanoLanguage.text('Rename material', 'উপকরণের নাম পরিবর্তন'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: GochanoLanguage.text('Title', 'শিরোনাম'),
          border: OutlineInputBorder(
            borderRadius: GochanoRadius.mdAll,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: GochanoRadius.mdAll,
            borderSide: const BorderSide(
              color: AppGradients.skyAccent,
              width: 1.5,
            ),
          ),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(GochanoLanguage.text('Cancel', 'বাতিল')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppGradients.skyAccent,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(GochanoLanguage.text('Save', 'সংরক্ষণ')),
        ),
      ],
    );
  }
}

Future<void> _rename(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
  String current,
) async {
  try {
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => _RenameDialog(initialText: current),
    );
    if (title == null || title.isEmpty || !context.mounted) return;
    // Goes through the backend so the owner check and the 1000-char limit
    // are enforced server-side, not just in the UI.
    await ApiService.updateMaterial(doc.id, title: title);
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

Future<void> _delete(
  BuildContext context,
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
  String title,
) async {
  final confirmed = await showConfirmationSheet(
    context,
    title: GochanoLanguage.text('Delete this material?', 'উপকরণটি মুছবেন?'),
    message: GochanoLanguage.text(
      '"$title" and its file will be permanently removed.',
      '"$title" এবং এর ফাইল স্থায়ীভাবে মুছে যাবে।',
    ),
    confirmLabel: GochanoLanguage.text('Delete', 'মুছুন'),
  );
  if (!confirmed || !context.mounted) return;
  try {
    // The backend deletes the B2 object and the Firestore document together.
    await ApiService.deleteMaterial(doc.id);
    if (context.mounted) {
      showGochanoMessage(
        context,
        GochanoLanguage.text('Material deleted.', 'উপকরণ মুছে ফেলা হয়েছে।'),
      );
    }
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

String _title(Map<String, dynamic> data) {
  final title = data['title']?.toString().trim() ?? '';
  if (title.isNotEmpty) return title;
  return data['fileName']?.toString() ?? '';
}

String _fileSize(Object? sizeBytes) {
  final bytes = (sizeBytes as num?)?.toInt() ?? 0;
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _createdAt(Object? value) {
  if (value is! Timestamp) return '';
  final when = value.toDate();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${when.day} ${months[when.month - 1]} ${when.year}';
}

String _mimeFilterTitle(String mimeFilter) {
  if (mimeFilter.startsWith('image/')) {
    return GochanoLanguage.text('Saved Images', 'সংরক্ষিত ছবি');
  }
  if (mimeFilter.contains('pdf')) {
    return GochanoLanguage.text('PDFs', 'পিডিএফ');
  }
  return GochanoLanguage.text('Materials', 'উপকরণ');
}
