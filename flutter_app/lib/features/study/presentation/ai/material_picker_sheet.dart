// Material Picker — bottom sheet for selecting source materials for quiz generation.
//
// Shows user's uploaded materials separated into Documents and Images categories.
// Returns list of selected material IDs.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/firestore_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';

/// Shows the material picker and returns selected material IDs.
/// Returns empty list if cancelled.
Future<List<Map<String, String>>> showMaterialPicker(BuildContext context) async {
  final result = await showModalBottomSheet<List<Map<String, String>>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _MaterialPickerSheet(),
  );
  return result ?? [];
}

bool _isImageMaterial(Map<String, dynamic> data) {
  final mime = (data['mimeType'] ?? '').toString().toLowerCase();
  final name = (data['fileName'] ?? '').toString().toLowerCase();
  if (mime.startsWith('image/')) return true;
  if (name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png') || name.endsWith('.webp')) return true;
  return false;
}

bool _isDocumentMaterial(Map<String, dynamic> data) {
  return !_isImageMaterial(data);
}

class _MaterialPickerSheet extends StatefulWidget {
  const _MaterialPickerSheet();

  @override
  State<_MaterialPickerSheet> createState() => _MaterialPickerSheetState();
}

class _MaterialPickerSheetState extends State<_MaterialPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggle(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _confirm() {
    Navigator.of(context).pop(
      _selectedIds.map((id) => {'id': id}).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final height = MediaQuery.of(context).size.height * 0.75;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: GochanoSpacing.sm),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.all(GochanoSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            GochanoLanguage.text(
                              'Select Source Material',
                              'উৎস উপকরণ নির্বাচন করুন',
                            ),
                            style: context.type.sectionHeading,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            GochanoLanguage.text(
                              'Choose materials for your quiz',
                              'আপনার কুইজের জন্য উপকরণ বাছুন',
                            ),
                            style: context.type.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_selectedIds.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.sm,
                          vertical: GochanoSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: colors.ai.withValues(alpha: 0.12),
                          borderRadius: GochanoRadius.mdAll,
                        ),
                        child: Text(
                          '${_selectedIds.length} selected',
                          style: context.type.caption.copyWith(
                            color: colors.ai,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.md),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: GochanoLanguage.text(
                      'Search materials…',
                      'উপকরণ খুঁজুন…',
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                ),
              ),

              const SizedBox(height: GochanoSpacing.sm),

              // Material list with categories
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirestoreService.ownerStream('materials', limit: 100),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return StaticLoadingState(
                        compact: true,
                        message: GochanoLanguage.text(
                          'Loading materials…',
                          'উপকরণ লোড হচ্ছে…',
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      return ErrorState(
                        compact: true,
                        message: friendlyErrorMessage(snapshot.error),
                      );
                    }

                    final docs = [...?snapshot.data?.docs];

                    if (docs.isEmpty) {
                      return EmptyState(
                        compact: true,
                        illustration: GochanoArt.emptyMaterials,
                        title: GochanoLanguage.text(
                          'No materials yet',
                          'এখনো কোনো উপকরণ নেই',
                        ),
                        message: GochanoLanguage.text(
                          'Upload materials first, then select them here for quiz generation.',
                          'প্রথমে উপকরণ আপলোড করুন, তারপর কুইজ তৈরির জন্য এখানে বাছুন।',
                        ),
                      );
                    }

                    // Filter by search query
                    final filtered = docs.where((doc) {
                      if (_searchQuery.isEmpty) return true;
                      final data = doc.data();
                      final title = (data['title'] ?? '').toString().toLowerCase();
                      final fileName = (data['fileName'] ?? '').toString().toLowerCase();
                      final subject = (data['subject'] ?? '').toString().toLowerCase();
                      return title.contains(_searchQuery) ||
                          fileName.contains(_searchQuery) ||
                          subject.contains(_searchQuery);
                    }).toList();

                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          GochanoLanguage.text(
                            'No materials match your search',
                            'আপনার অনুসন্ধান কোনো উপকরণ মেলেনি',
                          ),
                          style: context.type.bodySecondary,
                        ),
                      );
                    }

                    // Separate into categories
                    final documents = filtered.where((doc) => _isDocumentMaterial(doc.data())).toList();
                    final images = filtered.where((doc) => _isImageMaterial(doc.data())).toList();

                    return ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.md),
                      children: [
                        // Documents section
                        if (documents.isNotEmpty) ...[
                          _buildCategoryHeader(
                            context,
                            icon: Icons.description_rounded,
                            label: GochanoLanguage.text('Documents', 'ডকুমেন্ট'),
                            count: documents.length,
                            color: colors.brand,
                          ),
                          ...documents.map((doc) => _buildTile(doc)),
                        ],

                        // Images section
                        if (images.isNotEmpty) ...[
                          _buildCategoryHeader(
                            context,
                            icon: Icons.image_rounded,
                            label: GochanoLanguage.text('Images', 'ছবি'),
                            count: images.length,
                            color: colors.study,
                          ),
                          ...images.map((doc) => _buildTile(doc)),
                        ],
                      ],
                    );
                  },
                ),
              ),

              // Confirm button
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(GochanoSpacing.md),
                  child: Row(
                    children: [
                      Expanded(
                        child: SecondaryButton(
                          label: GochanoLanguage.text('Cancel', 'বাতিল'),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: GochanoSpacing.sm),
                      Expanded(
                        child: PrimaryButton(
                          label: _selectedIds.isEmpty
                              ? GochanoLanguage.text('Select', 'নির্বাচন')
                              : GochanoLanguage.text(
                                  'Select (${_selectedIds.length})',
                                  'নির্বাচন (${_selectedIds.length})',
                                ),
                          onPressed: _selectedIds.isEmpty ? null : _confirm,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryHeader(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: GochanoSpacing.sm, bottom: GochanoSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: GochanoSpacing.xs),
          Text(
            '$label ($count)',
            style: context.type.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final id = doc.id;
    final title = data['title']?.toString().trim().isNotEmpty == true
        ? data['title'].toString()
        : data['fileName']?.toString() ?? '';
    final mimeType = data['mimeType']?.toString() ?? '';
    final fileName = data['fileName']?.toString() ?? '';
    final createdAt = data['createdAt'];
    final selected = _selectedIds.contains(id);

    return _MaterialTile(
      id: id,
      title: title,
      mimeType: mimeType,
      fileName: fileName,
      createdAt: createdAt,
      selected: selected,
      onTap: () => _toggle(id),
    );
  }
}

class _MaterialTile extends StatelessWidget {
  const _MaterialTile({
    required this.id,
    required this.title,
    required this.mimeType,
    required this.fileName,
    required this.createdAt,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String title;
  final String mimeType;
  final String fileName;
  final dynamic createdAt;
  final bool selected;
  final VoidCallback onTap;

  bool get isImage {
    final mime = mimeType.toLowerCase();
    final name = fileName.toLowerCase();
    if (mime.startsWith('image/')) return true;
    if (name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png') || name.endsWith('.webp')) return true;
    return false;
  }

  IconData _fileIcon() {
    final mime = mimeType.toLowerCase();
    final name = fileName.toLowerCase();
    if (mime.contains('pdf') || name.endsWith('.pdf')) {
      return Icons.picture_as_pdf_rounded;
    }
    if (mime.startsWith('image/') ||
        name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp')) {
      return Icons.image_rounded;
    }
    if (name.endsWith('.doc') || name.endsWith('.docx')) {
      return Icons.description_rounded;
    }
    if (name.endsWith('.txt')) {
      return Icons.article_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return '';
    DateTime? date;
    if (ts is Timestamp) {
      date = ts.toDate();
    } else if (ts is DateTime) {
      date = ts;
    }
    if (date == null) return '';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
      child: InkWell(
        onTap: onTap,
        borderRadius: GochanoRadius.mdAll,
        child: Container(
          padding: const EdgeInsets.all(GochanoSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? colors.ai.withValues(alpha: 0.08) : colors.surface,
            borderRadius: GochanoRadius.mdAll,
            border: Border.all(
              color: selected ? colors.ai : colors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              // File type icon
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _fileIconColor(colors).withValues(alpha: 0.12),
                  borderRadius: GochanoRadius.smAll,
                ),
                child: Icon(
                  _fileIcon(),
                  size: 22,
                  color: _fileIconColor(colors),
                ),
              ),
              const SizedBox(width: GochanoSpacing.sm),

              // Title and metadata
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: context.type.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          _fileExtension(),
                          style: context.type.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        if (_formatDate(createdAt).isNotEmpty) ...[
                          Text(
                            ' · ${_formatDate(createdAt)}',
                            style: context.type.caption.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // Selection indicator
              if (selected)
                Icon(
                  Icons.check_circle_rounded,
                  size: 22,
                  color: colors.ai,
                )
              else
                Icon(
                  Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: colors.textTertiary,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _fileExtension() {
    final name = fileName.toLowerCase();
    if (name.endsWith('.pdf')) return 'PDF';
    if (name.endsWith('.doc') || name.endsWith('.docx')) return 'DOC';
    if (name.endsWith('.txt')) return 'TXT';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'JPG';
    if (name.endsWith('.png')) return 'PNG';
    if (name.endsWith('.webp')) return 'WEBP';
    final mime = mimeType.toLowerCase();
    if (mime.contains('pdf')) return 'PDF';
    if (mime.startsWith('image/')) return 'IMG';
    return 'FILE';
  }

  Color _fileIconColor(GochanoColors colors) {
    final ext = _fileExtension();
    switch (ext) {
      case 'PDF':
        return colors.error;
      case 'DOC':
        return colors.brand;
      case 'TXT':
        return colors.textSecondary;
      case 'JPG':
      case 'PNG':
      case 'WEBP':
      case 'IMG':
        return colors.study;
      default:
        return colors.textSecondary;
    }
  }
}
