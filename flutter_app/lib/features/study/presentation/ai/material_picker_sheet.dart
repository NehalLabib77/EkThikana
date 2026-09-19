// Material Picker — bottom sheet for selecting source materials.
//
// Quiz mode (allowImages=false): documents only (PDF, DOC, DOCX, TXT)
// General mode (allowImages=true): all materials + upload + delete

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../services/firestore_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';

Future<List<Map<String, String>>> showMaterialPicker(BuildContext context) async {
  final result = await showModalBottomSheet<List<Map<String, String>>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _MaterialPickerSheet(allowImages: false),
  );
  return result ?? [];
}

Future<List<Map<String, String>>> showGeneralMaterialPicker(BuildContext context) async {
  final result = await showModalBottomSheet<List<Map<String, String>>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _MaterialPickerSheet(allowImages: true),
  );
  return result ?? [];
}

bool _isImageFile(Map<String, dynamic> data) {
  final mime = (data['mimeType'] ?? '').toString().toLowerCase();
  final name = (data['fileName'] ?? '').toString().toLowerCase();
  if (mime.startsWith('image/')) return true;
  if (name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png') || name.endsWith('.webp')) return true;
  return false;
}

bool _isDocumentFile(Map<String, dynamic> data) => !_isImageFile(data);

class _MaterialPickerSheet extends StatefulWidget {
  const _MaterialPickerSheet({required this.allowImages});
  final bool allowImages;

  @override
  State<_MaterialPickerSheet> createState() => _MaterialPickerSheetState();
}

class _MaterialPickerSheetState extends State<_MaterialPickerSheet> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  final Set<String> _selectedIds = {};
  bool _refreshKey = false;

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

  Future<void> _uploadMaterial() async {
    try {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt', 'jpg', 'jpeg', 'png'],
      );
      if (selected == null) return;
      final bytes = await selected.readAsBytes();
      if (!mounted) return;

      final titleCtrl = TextEditingController(text: selected.name);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(GochanoLanguage.text('Upload Material', '\u0989\u09aa\u0995\u09b0\u09a3 \u0986\u09aa\u09b2\u09cb\u09a1 \u0995\u09b0\u09c1\u09a8')),
          content: TextField(
            controller: titleCtrl,
            decoration: InputDecoration(labelText: GochanoLanguage.text('Title', '\u09b6\u09bf\u09b0\u09cb\u09a8\u09be\u09ae')),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(GochanoLanguage.text('Cancel', '\u09ac\u09be\u09a4\u09bf\u09b2'))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(GochanoLanguage.text('Upload', '\u0986\u09aa\u09b2\u09cb\u09a1'))),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      await ApiService.uploadMaterial(
        bytes: bytes,
        fileName: selected.name,
        title: titleCtrl.text.trim().isNotEmpty ? titleCtrl.text.trim() : selected.name,
        visibility: 'private',
      );

      if (mounted) {
        setState(() => _refreshKey = !_refreshKey);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(GochanoLanguage.text('Material uploaded', '\u0989\u09aa\u0995\u09b0\u09a3 \u0986\u09aa\u09b2\u09cb\u09a1 \u09b9\u09af\u09bc\u09c7\u099b\u09c7'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(GochanoLanguage.text('Upload failed', '\u0986\u09aa\u09b2\u09cb\u09a1 \u09ac\u09cd\u09af\u09b0\u09cd\u09a5'))),
        );
      }
    }
  }

  Future<void> _deleteMaterial(String id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(GochanoLanguage.text('Delete Material', '\u0989\u09aa\u0995\u09b0\u09a3 \u09ae\u09c1\u099b\u09c1\u09a8')),
        content: Text(GochanoLanguage.text('Delete ""?', '"" \u09ae\u09c1\u099b\u09c7 \u09ab\u09c7\u09b2\u09ac\u09c7\u09a8?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(GochanoLanguage.text('Cancel', '\u09ac\u09be\u09a4\u09bf\u09b2'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(GochanoLanguage.text('Delete', '\u09ae\u09c1\u099b\u09c1\u09a8')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ApiService.deleteMaterial(id);
      if (mounted) {
        setState(() {
          _refreshKey = !_refreshKey;
          _selectedIds.remove(id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(GochanoLanguage.text('Material deleted', '\u0989\u09aa\u0995\u09b0\u09a3 \u09ae\u09c1\u099b\u09c7 \u09ab\u09c7\u09b2\u09be \u09b9\u09af\u09bc\u09c7\u099b\u09c7'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(GochanoLanguage.text('Delete failed', '\u09ae\u09c1\u099b\u09c7 \u09ab\u09c7\u09b2\u09be \u09ac\u09cd\u09af\u09b0\u09cd\u09a5'))),
        );
      }
    }
  }

  String _titleFromData(Map<String, dynamic> data) {
    final t = data['title']?.toString().trim();
    if (t != null && t.isNotEmpty) return t;
    return data['fileName']?.toString() ?? '';
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
              Container(
                margin: const EdgeInsets.only(top: GochanoSpacing.sm),
                width: 40, height: 4,
                decoration: BoxDecoration(color: colors.border, borderRadius: BorderRadius.circular(2)),
              ),
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
                              widget.allowImages ? 'Materials' : 'Select Source Material',
                              widget.allowImages ? '\u0989\u09aa\u0995\u09b0\u09a3' : '\u0989\u09a4\u09cd\u09b8 \u0989\u09aa\u0995\u09b0\u09a3 \u09a8\u09bf\u09b0\u09cd\u09ac\u09be\u099a\u09a8 \u0995\u09b0\u09c1\u09a8',
                            ),
                            style: context.type.sectionHeading,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            GochanoLanguage.text(
                              widget.allowImages ? 'Manage your materials' : 'Choose documents for your quiz',
                              widget.allowImages ? '\u0986\u09aa\u09a8\u09be\u09b0 \u0989\u09aa\u0995\u09b0\u09a3 \u09aa\u09b0\u09bf\u099a\u09be\u09b2\u09a8\u09be \u0995\u09b0\u09c1\u09a8' : '\u0986\u09aa\u09a8\u09be\u09b0 \u0995\u09c1\u0987\u099c\u09c7\u09b0 \u099c\u09a8\u09cd\u09af \u09a1\u0995\u09c1\u09ae\u09c7\u09a8\u09cd\u099f \u09ac\u09be\u099b\u09c1\u09a8',
                            ),
                            style: context.type.caption.copyWith(color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (_selectedIds.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.sm, vertical: GochanoSpacing.xs),
                        decoration: BoxDecoration(color: colors.ai.withValues(alpha: 0.12), borderRadius: GochanoRadius.mdAll),
                        child: Text(
                          ' selected',
                          style: context.type.caption.copyWith(color: colors.ai, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.md),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: GochanoLanguage.text('Search materials\u2026', '\u0989\u09aa\u0995\u09b0\u09a3 \u0996\u09c1\u099c\u09c1\u09a8\u2026'),
                          prefixIcon: const Icon(Icons.search_rounded, size: 20),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                      ),
                    ),
                    if (widget.allowImages) ...[
                      const SizedBox(width: GochanoSpacing.sm),
                      IconButton(
                        onPressed: _uploadMaterial,
                        icon: const Icon(Icons.upload_file_rounded),
                        tooltip: GochanoLanguage.text('Upload Material', '\u0989\u09aa\u0995\u09b0\u09a3 \u0986\u09aa\u09b2\u09cb\u09a1'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: GochanoSpacing.sm),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirestoreService.ownerStream('materials', limit: 100),
                  key: ValueKey(_refreshKey),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return StaticLoadingState(compact: true, message: GochanoLanguage.text('Loading materials\u2026', '\u0989\u09aa\u0995\u09b0\u09a3 \u09b2\u09cb\u09a1 \u09b9\u099a\u09cd\u099b\u09c7\u2026'));
                    }
                    if (snapshot.hasError) {
                      return ErrorState(compact: true, message: friendlyErrorMessage(snapshot.error));
                    }
                    final docs = [...?snapshot.data?.docs];
                    if (docs.isEmpty) {
                      return EmptyState(
                        compact: true,
                        illustration: GochanoArt.emptyMaterials,
                        title: GochanoLanguage.text('No materials yet', '\u098f\u0996\u09a8\u09cb \u0995\u09cb\u09a8\u09cb \u0989\u09aa\u0995\u09b0\u09a3 \u09a8\u09c7\u0987'),
                        message: GochanoLanguage.text('Upload materials first, then select them here for quiz generation.', '\u09aa\u09cd\u09b0\u09a5\u09ae\u09c7 \u0989\u09aa\u0995\u09b0\u09a3 \u0986\u09aa\u09b2\u09cb\u09a1 \u0995\u09b0\u09c1\u09a8, \u09a4\u09be\u09b0\u09aa\u09b0 \u0995\u09c1\u0987\u099c \u09a4\u09c8\u09b0\u09bf\u09b0\u09c7\u09b0 \u099c\u09a8\u09cd\u09af \u098f\u0996\u09be\u09a8\u09c7 \u09ac\u09be\u099b\u09c1\u09a8\u0964'),
                      );
                    }
                    final filtered = docs.where((doc) {
                      final data = doc.data();
                      if (!widget.allowImages && _isImageFile(data)) return false;
                      if (_searchQuery.isEmpty) return true;
                      final t = (data['title'] ?? '').toString().toLowerCase();
                      final f = (data['fileName'] ?? '').toString().toLowerCase();
                      final s = (data['subject'] ?? '').toString().toLowerCase();
                      return t.contains(_searchQuery) || f.contains(_searchQuery) || s.contains(_searchQuery);
                    }).toList();
                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          GochanoLanguage.text('No materials match your search', '\u0986\u09aa\u09a8\u09be\u09b0 \u0985\u09a8\u09c1\u09b8\u09a8\u09cd\u09a7\u09be\u09a8 \u0995\u09cb\u09a8\u09cb \u0989\u09aa\u0995\u09b0\u09a3 \u09ae\u09c7\u09b2\u09c7\u09a8\u09bf'),
                          style: context.type.bodySecondary,
                        ),
                      );
                    }
                    if (widget.allowImages) {
                      final documents = filtered.where((doc) => _isDocumentFile(doc.data())).toList();
                      final images = filtered.where((doc) => _isImageFile(doc.data())).toList();
                      return ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.md),
                        children: [
                          if (documents.isNotEmpty) ...[
                            _buildCategoryHeader(context, icon: Icons.description_rounded, label: GochanoLanguage.text('Documents', '\u09a1\u0995\u09c1\u09ae\u09c7\u09a8\u09cd\u099f'), count: documents.length, color: colors.brand),
                            ...documents.map((doc) => _buildTile(doc)),
                          ],
                          if (images.isNotEmpty) ...[
                            _buildCategoryHeader(context, icon: Icons.image_rounded, label: GochanoLanguage.text('Images', '\u099b\u09ac\u09bf'), count: images.length, color: colors.study),
                            ...images.map((doc) => _buildTile(doc)),
                          ],
                        ],
                      );
                    }
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.md),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final doc = filtered[index];
                        final data = doc.data();
                        return _MaterialTile(
                          id: doc.id,
                          title: _titleFromData(data),
                          mimeType: data['mimeType']?.toString() ?? '',
                          fileName: data['fileName']?.toString() ?? '',
                          createdAt: data['createdAt'],
                          selected: _selectedIds.contains(doc.id),
                          onTap: () => _toggle(doc.id),
                        );
                      },
                    );
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(GochanoSpacing.md),
                  child: Row(
                    children: [
                      Expanded(child: SecondaryButton(label: GochanoLanguage.text('Cancel', '\u09ac\u09be\u09a4\u09bf\u09b2'), onPressed: () => Navigator.of(context).pop())),
                      const SizedBox(width: GochanoSpacing.sm),
                      Expanded(
                        child: PrimaryButton(
                          label: _selectedIds.isEmpty
                              ? GochanoLanguage.text('Select', '\u09a8\u09bf\u09b0\u09cd\u09ac\u09be\u099a\u09a8')
                              : GochanoLanguage.text('Select ()', '\u09a8\u09bf\u09b0\u09cd\u09ac\u09be\u099a\u09a8 ()'),
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

  Widget _buildCategoryHeader(BuildContext context, {required IconData icon, required String label, required int count, required Color color}) {
    return Padding(
      padding: const EdgeInsets.only(top: GochanoSpacing.sm, bottom: GochanoSpacing.xs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: GochanoSpacing.xs),
          Text(' ()', style: context.type.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final id = doc.id;
    final title = _titleFromData(data);
    final mimeType = data['mimeType']?.toString() ?? '';
    final fileName = data['fileName']?.toString() ?? '';
    final createdAt = data['createdAt'];
    final selected = _selectedIds.contains(id);
    return _MaterialTile(
      id: id, title: title, mimeType: mimeType, fileName: fileName,
      createdAt: createdAt, selected: selected,
      onTap: () => _toggle(id),
      onDelete: widget.allowImages ? () => _deleteMaterial(id, title) : null,
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
    this.onDelete,
  });

  final String id;
  final String title;
  final String mimeType;
  final String fileName;
  final dynamic createdAt;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  IconData _fileIcon() {
    final mime = mimeType.toLowerCase();
    final name = fileName.toLowerCase();
    if (mime.contains('pdf') || name.endsWith('.pdf')) return Icons.picture_as_pdf_rounded;
    if (name.endsWith('.doc') || name.endsWith('.docx')) return Icons.description_rounded;
    if (name.endsWith('.txt')) return Icons.article_rounded;
    if (mime.startsWith('image/') || name.endsWith('.jpg') || name.endsWith('.jpeg') || name.endsWith('.png')) return Icons.image_rounded;
    return Icons.insert_drive_file_rounded;
  }

  String _fileExtension() {
    final name = fileName.toLowerCase();
    if (name.endsWith('.pdf')) return 'PDF';
    if (name.endsWith('.doc') || name.endsWith('.docx')) return 'DOC';
    if (name.endsWith('.txt')) return 'TXT';
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'JPG';
    if (name.endsWith('.png')) return 'PNG';
    final mime = mimeType.toLowerCase();
    if (mime.contains('pdf')) return 'PDF';
    if (mime.startsWith('image/')) return 'IMG';
    return 'FILE';
  }

  Color _fileIconColor(GochanoColors colors) {
    switch (_fileExtension()) {
      case 'PDF': return colors.error;
      case 'DOC': return colors.brand;
      case 'TXT': return colors.textSecondary;
      case 'JPG': case 'PNG': case 'IMG': return colors.study;
      default: return colors.textSecondary;
    }
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
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: _fileIconColor(colors).withValues(alpha: 0.12),
                  borderRadius: GochanoRadius.smAll,
                ),
                child: Icon(_fileIcon(), size: 22, color: _fileIconColor(colors)),
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.type.body.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(_fileExtension(), style: context.type.caption.copyWith(color: colors.textSecondary)),
                        if (_formatDate(createdAt).isNotEmpty)
                          Text(' \u00b7 ', style: context.type.caption.copyWith(color: colors.textSecondary)),
                      ],
                    ),
                  ],
                ),
              ),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: colors.error),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              if (selected)
                Icon(Icons.check_circle_rounded, size: 22, color: colors.ai)
              else
                Icon(Icons.radio_button_unchecked_rounded, size: 22, color: colors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
