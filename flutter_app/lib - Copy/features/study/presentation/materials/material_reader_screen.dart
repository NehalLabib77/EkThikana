// Document reader (spec §33).
//
// "Keep most of the screen dedicated to reading." The chrome is one app bar
// with the title, a page indicator, and everything else behind one menu:
// Ask AI, save, share, download, rename, replace, delete.
//
// The signed URL comes from `GET /api/materials/{id}/url`, which the backend
// mints against Backblaze B2 only after checking ownership or group
// membership. It is short-lived by design, so the reader refetches rather
// than caching it.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_illustration.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/api_service.dart';
import '../../../../services/firestore_service.dart';
import '../../../../services/offline_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../ai/ai_assistant_screen.dart';

class MaterialReaderScreen extends StatefulWidget {
  const MaterialReaderScreen({
    super.key,
    required this.materialId,
    required this.title,
    required this.mimeType,
    this.fileName = '',
  });

  final String materialId;
  final String title;
  final String mimeType;
  final String fileName;

  @override
  State<MaterialReaderScreen> createState() => _MaterialReaderScreenState();
}

class _MaterialReaderScreenState extends State<MaterialReaderScreen> {
  final PdfViewerController _pdfController = PdfViewerController();

  String? _signedUrl;
  String _error = '';
  bool _loading = true;
  bool _saving = false;
  int _page = 1;
  int _pageCount = 0;

  bool get _isPdf =>
      widget.mimeType.toLowerCase().contains('pdf') ||
      widget.fileName.toLowerCase().endsWith('.pdf') ||
      widget.title.toLowerCase().endsWith('.pdf');

  bool get _isImage => widget.mimeType.toLowerCase().startsWith('image/');

  @override
  void initState() {
    super.initState();
    _loadUrl();
  }

  Future<void> _loadUrl() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final url = await ApiService.materialUrl(widget.materialId);
      if (!mounted) return;
      setState(() {
        _signedUrl = url;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiService.saveMaterial(widget.materialId);
      if (!mounted) return;
      showGochanoMessage(
        context,
        GochanoLanguage.text('Saved to your library.', 'আপনার লাইব্রেরিতে সংরক্ষিত।'),
      );
    } catch (error) {
      if (!mounted) return;
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Downloads the file and hands it to the platform.
  ///
  /// Goes through the backend's signed download URL (which sets
  /// Content-Disposition: attachment) and then through the existing
  /// `OfflineService.writeTemp` + `OpenFilex` path, so this reuses the app's
  /// one way of putting a file in front of the OS rather than adding a second.
  Future<void> _openExternally({bool download = false}) async {
    setState(() => _saving = true);
    try {
      final url = await ApiService.materialUrl(
        widget.materialId,
        download: download,
      );
      final bytes = await ApiService.downloadBytes(url);
      final file = await OfflineService.writeTemp(
        materialId: widget.materialId,
        bytes: bytes,
        mimeType: widget.mimeType,
        fileName: widget.fileName.isEmpty ? widget.title : widget.fileName,
      );
      final result = await OpenFilex.open(file.path);
      if (!mounted) return;
      if (result.type != ResultType.done) {
        showGochanoMessage(
          context,
          GochanoLanguage.text(
            'No app on this phone can open this file type.',
            'এই ফোনে এই ধরনের ফাইল খোলার কোনো অ্যাপ নেই।',
          ),
          isError: true,
        );
      }
    } catch (error) {
      if (!mounted) return;
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _askAi() {
    Navigator.of(context).push(
      GochanoRoute.to(
        builder: (_) => AiAssistantScreen(
          contextMaterialId: widget.materialId,
          contextMaterialTitle: widget.title,
          contextMimeType: widget.mimeType,
          contextFileName: widget.fileName,
          contextPage: _isPdf ? _page : null,
        ),
      ),
    );
  }

  /// Remembers where the student stopped reading.
  ///
  /// Written to `material_state/{uid}_{materialId}` rather than to the shared
  /// material document, because reading position is per-student and a group
  /// material is read by several people.
  Future<void> _rememberPage(int page) async {
    if (page == _page) return;
    setState(() => _page = page);
    try {
      await FirestoreService.db
          .collection('material_state')
          .doc('${FirestoreService.uid}_${widget.materialId}')
          .set({
        'ownerId': FirestoreService.uid,
        'materialId': widget.materialId,
        'lastPage': page,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Losing a bookmark is not worth interrupting reading for.
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.title,
              style: context.type.cardHeading,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_isPdf && _pageCount > 0)
              Text(
                GochanoLanguage.text(
                  'Page $_page of $_pageCount',
                  'পৃষ্ঠা $_page / $_pageCount',
                ),
                style: context.type.caption,
              ),
          ],
        ),
        actions: [
          IconActionButton(
            icon: Icons.auto_awesome_outlined,
            label: GochanoLanguage.text('Ask AI about this', 'এটি নিয়ে জিজ্ঞাসা'),
            accent: colors.ai,
            onPressed: _askAi,
          ),
          GochanoOverflowMenu(
            items: [
              GochanoMenuAction(
                label: GochanoLanguage.text('Save to library', 'লাইব্রেরিতে সংরক্ষণ'),
                icon: Icons.bookmark_border_rounded,
                enabled: !_saving,
                onSelected: _save,
              ),
              GochanoMenuAction(
                label: GochanoLanguage.text('Download', 'ডাউনলোড'),
                icon: Icons.download_outlined,
                onSelected: () => _openExternally(download: true),
              ),
              GochanoMenuAction(
                label: GochanoLanguage.text('Reload', 'রিলোড'),
                icon: Icons.refresh_rounded,
                onSelected: _loadUrl,
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return StaticLoadingState(
        message: GochanoLanguage.text(
          'Opening this document…',
          'ডকুমেন্টটি খোলা হচ্ছে…',
        ),
      );
    }
    if (_error.isNotEmpty) {
      return ErrorState(
        message: _error,
        title: GochanoLanguage.text(
          'Could not open this document',
          'ডকুমেন্টটি খোলা যায়নি',
        ),
        onRetry: _loadUrl,
      );
    }

    final url = _signedUrl;
    if (url == null) {
      return ErrorState(
        message: GochanoLanguage.text(
          'This material is no longer available.',
          'এই উপকরণটি আর নেই।',
        ),
        onRetry: _loadUrl,
      );
    }

    if (_isPdf) {
      return PdfViewer.uri(
        Uri.parse(url),
        controller: _pdfController,
        initialPageNumber: _page,
        params: PdfViewerParams(
          onViewerReady: (document, _) {
            if (!mounted) return;
            setState(() => _pageCount = document.pages.length);
          },
          onPageChanged: (page) {
            if (page != null) _rememberPage(page);
          },
          textSelectionParams: const PdfTextSelectionParams(enabled: true),
        ),
      );
    }

    if (_isImage) {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: Center(
          child: Image.network(
            url,
            // Bound the decode to the screen so a phone-camera-sized scan
            // does not blow up the image cache (spec §83).
            cacheWidth: MediaQuery.of(context).size.width.round() * 2,
            fit: BoxFit.contain,
            semanticLabel: widget.title,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              final total = progress.expectedTotalBytes;
              return StaticLoadingState(
                message: GochanoLanguage.text('Loading image…', 'ছবি লোড হচ্ছে…'),
                progress: total == null
                    ? null
                    : progress.cumulativeBytesLoaded / total,
              );
            },
            errorBuilder: (context, error, stack) => ErrorState(
              message: GochanoLanguage.text(
                'Could not display this image.',
                'ছবিটি দেখানো যায়নি।',
              ),
              onRetry: _loadUrl,
            ),
          ),
        ),
      );
    }

    // Anything the app cannot render inline — DOC/DOCX, slides — is handed
    // to the platform rather than refused (spec §45).
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GochanoSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GochanoIllustration(
              GochanoArt.fileIdFor(
                fileName: widget.fileName,
                mimeType: widget.mimeType,
              ),
              size: GochanoSizes.illustrationEmpty,
              accent: context.colors.study,
            ),
            const SizedBox(height: GochanoSpacing.md),
            Text(
              GochanoLanguage.text(
                'This file type opens in another app.',
                'এই ধরনের ফাইল অন্য অ্যাপে খুলবে।',
              ),
              style: context.type.bodySecondary,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: GochanoSpacing.lg),
            PrimaryButton(
              label: GochanoLanguage.text('Open file', 'ফাইল খুলুন'),
              icon: Icons.open_in_new_rounded,
              expand: false,
              onPressed: _saving ? null : _openExternally,
            ),
          ],
        ),
      ),
    );
  }
}
