import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../core/ui.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';

class MaterialReaderScreen extends StatefulWidget {
  const MaterialReaderScreen({
    super.key,
    required this.materialId,
    required this.material,
  });

  final String materialId;
  final Map<String, dynamic> material;

  @override
  State<MaterialReaderScreen> createState() => _MaterialReaderScreenState();
}

class _MaterialReaderScreenState extends State<MaterialReaderScreen> {
  final PdfViewerController pdfController = PdfViewerController();
  PdfTextSearcher? searcher;

  String? signedUrl;
  String? loadError;
  int currentPage = 1;
  Set<int> bookmarks = {};
  bool busy = true;
  bool downloading = false;

  bool get isPdf {
    final mime = widget.material['mimeType']?.toString().toLowerCase() ?? '';
    final name = widget.material['fileName']?.toString().toLowerCase() ?? '';
    return mime.contains('pdf') || name.endsWith('.pdf');
  }

  DocumentReference<Map<String, dynamic>> get stateRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirestoreService.uid)
          .collection('material_state')
          .doc(widget.materialId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    searcher?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final state = await stateRef.get();
      final stateData = state.data() ?? {};
      final storedBookmarks = (stateData['bookmarks'] as List?)
              ?.map((e) => int.tryParse(e.toString()))
              .whereType<int>()
              .toSet() ??
          <int>{};
      final lastPage = int.tryParse(
            stateData['lastPage']?.toString() ?? '',
          ) ??
          1;

      final url = await ApiService.materialUrl(widget.materialId);

      if (!mounted) return;
      setState(() {
        bookmarks = storedBookmarks;
        currentPage = lastPage < 1 ? 1 : lastPage;
        signedUrl = url;
        busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadError = e.toString();
        busy = false;
      });
    }
  }

  Future<void> _savePage(int page) async {
    currentPage = page;
    try {
      await stateRef.set({
        'lastPage': page,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Reading remains usable if resume state cannot be persisted.
    }
  }

  Future<void> _toggleBookmark() async {
    final next = {...bookmarks};
    if (!next.add(currentPage)) {
      next.remove(currentPage);
    }
    setState(() => bookmarks = next);

    try {
      await stateRef.set({
        'bookmarks': next.toList()..sort(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _saveToLibrary() async {
    try {
      await ApiService.saveMaterial(widget.materialId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to My Library.')),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _downloadOffline() async {
    if (downloading) return;
    setState(() => downloading = true);
    try {
      final url = await ApiService.materialUrl(
        widget.materialId,
        download: true,
      );
      final bytes = await ApiService.downloadBytes(url);
      await FilePicker.saveFile(
        fileName: widget.material['fileName']?.toString() ?? 'material',
        bytes: bytes,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save dialog completed.')),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => downloading = false);
    }
  }

  Future<void> _addPageNote() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Note for page $currentPage'),
        content: TextField(
          controller: c,
          minLines: 3,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'Page-linked note',
            alignLabelWithHint: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok == true && c.text.trim().isNotEmpty) {
      await stateRef.collection('page_notes').add({
        'page': currentPage,
        'text': c.text.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    c.dispose();
  }

  Future<void> _showPageNotes() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * .7,
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stateRef
                  .collection('page_notes')
                  .where('page', isEqualTo: currentPage)
                  .snapshots(),
              builder: (context, snap) {
                final docs = snap.data?.docs ?? [];
                return Column(
                  children: [
                    ListTile(
                      title: Text(
                        'Page $currentPage notes',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      trailing: IconButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _addPageNote();
                        },
                        icon: const Icon(Icons.add),
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: docs.isEmpty
                          ? const Center(
                              child: Text('No page-linked notes yet.'),
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: docs.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) {
                                final doc = docs[i];
                                return Card(
                                  child: ListTile(
                                    title: Text(
                                      doc.data()['text']?.toString() ?? '',
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline,
                                      ),
                                      onPressed: doc.reference.delete,
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _askAi() async {
    final q = TextEditingController();
    bool currentPageOnly = true;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Ask about this PDF'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: q,
                autofocus: true,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Question',
                  alignLabelWithHint: true,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: currentPageOnly,
                title: Text('Use current page ($currentPage) only'),
                onChanged: (v) =>
                    setLocalState(() => currentPageOnly = v ?? true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Ask'),
            ),
          ],
        ),
      ),
    );

    if (submitted != true || q.text.trim().isEmpty) {
      q.dispose();
      return;
    }

    try {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final answer = await ApiService.askPdf(
        materialId: widget.materialId,
        question: q.text.trim(),
        page: currentPageOnly ? currentPage : null,
      );

      if (mounted) Navigator.pop(context);
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Answer'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: SelectableText(answer),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        Navigator.maybePop(context);
        showError(context, e);
      }
    } finally {
      q.dispose();
    }
  }


  Future<void> _reportMaterial() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(
        title: const Text('Report material'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'spam'),
            child: const Text('Spam'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'copyright'),
            child: const Text('Copyright concern'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'inappropriate'),
            child: const Text('Inappropriate content'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'misleading'),
            child: const Text('Misleading material'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, 'other'),
            child: const Text('Other'),
          ),
        ],
      ),
    );

    if (reason == null) return;

    try {
      await ApiService.reportContent(
        targetType: 'material',
        targetId: widget.materialId,
        reason: reason,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Report submitted for review.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _searchPdf() async {
    final c = TextEditingController();

    final term = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Search PDF'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Search text'),
          onSubmitted: (value) => Navigator.pop(d, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(d, c.text.trim()),
            child: const Text('Search'),
          ),
        ],
      ),
    );
    c.dispose();

    if (term == null || term.isEmpty) return;

    searcher ??= PdfTextSearcher(pdfController)
      ..addListener(() {
        if (mounted) setState(() {});
      });

    searcher!.startTextSearch(term);

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: ListenableBuilder(
            listenable: searcher!,
            builder: (context, _) {
              final s = searcher!;
              return Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.hasMatches
                            ? '${s.currentIndex! + 1} / ${s.matches.length} matches'
                            : s.isSearching
                                ? 'Searching…'
                                : 'No matches',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Previous',
                      onPressed: s.hasMatches
                          ? () => s.goToPrevMatch()
                          : null,
                      icon: const Icon(Icons.keyboard_arrow_up),
                    ),
                    IconButton(
                      tooltip: 'Next',
                      onPressed: s.hasMatches
                          ? () => s.goToNextMatch()
                          : null,
                      icon: const Icon(Icons.keyboard_arrow_down),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.material['title']?.toString() ??
        widget.material['fileName']?.toString() ??
        'Material';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (isPdf)
            IconButton(
              tooltip: 'Search',
              onPressed: busy ? null : _searchPdf,
              icon: const Icon(Icons.search),
            ),
          if (isPdf)
            IconButton(
              tooltip: bookmarks.contains(currentPage)
                  ? 'Remove bookmark'
                  : 'Bookmark page',
              onPressed: busy ? null : _toggleBookmark,
              icon: Icon(
                bookmarks.contains(currentPage)
                    ? Icons.bookmark
                    : Icons.bookmark_border,
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'save':
                  _saveToLibrary();
                  break;
                case 'download':
                  _downloadOffline();
                  break;
                case 'page_note':
                  _addPageNote();
                  break;
                case 'show_notes':
                  _showPageNotes();
                  break;
                case 'ai':
                  _askAi();
                  break;
                case 'report':
                  _reportMaterial();
                  break;
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'save',
                child: Text('Save to My Library'),
              ),
              PopupMenuItem(
                value: 'download',
                child: Text(
                  downloading ? 'Downloading…' : 'Download offline',
                ),
              ),
              if (isPdf)
                const PopupMenuItem(
                  value: 'page_note',
                  child: Text('Add note to current page'),
                ),
              if (isPdf)
                const PopupMenuItem(
                  value: 'show_notes',
                  child: Text('View current-page notes'),
                ),
              if (isPdf)
                const PopupMenuItem(
                  value: 'ai',
                  child: Text('Ask AI about PDF'),
                ),
              if (widget.material['ownerId'] != FirestoreService.uid)
                const PopupMenuItem(
                  value: 'report',
                  child: Text('Report material'),
                ),
            ],
          ),
        ],
      ),
      body: busy
          ? const Center(child: CircularProgressIndicator())
          : loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      loadError!,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : signedUrl == null
                  ? const Center(child: Text('File URL unavailable.'))
                  : isPdf
                      ? PdfViewer.uri(
                          Uri.parse(signedUrl!),
                          controller: pdfController,
                          initialPageNumber: currentPage,
                          params: PdfViewerParams(
                            onPageChanged: (page) {
                              if (page != null) _savePage(page);
                            },
                            textSelectionParams:
                                const PdfTextSelectionParams(
                              enabled: true,
                            ),
                          ),
                        )
                      : _ImageMaterial(url: signedUrl!),
    );
  }
}

class _ImageMaterial extends StatelessWidget {
  const _ImageMaterial({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      minScale: .5,
      maxScale: 5,
      child: Center(
        child: Image.network(
          url,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (_, __, ___) => const Center(
            child: Text('Could not display this file as an image.'),
          ),
        ),
      ),
    );
  }
}
