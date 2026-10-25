import 'package:flutter/material.dart';

import '../../../../core/design_system/app_design_system.dart';
import 'content_api_service.dart';

class StudyPackScreen extends StatefulWidget {
  const StudyPackScreen({super.key});

  @override
  State<StudyPackScreen> createState() => _StudyPackScreenState();
}

class _StudyPackScreenState extends State<StudyPackScreen> {
  final _topic = TextEditingController();
  final _source = TextEditingController();
  final _materialId = TextEditingController();
  Future<Map<String, dynamic>>? _request;

  @override
  void dispose() {
    _topic.dispose();
    _source.dispose();
    _materialId.dispose();
    super.dispose();
  }

  void _generate() {
    if (_topic.text.trim().isEmpty && _materialId.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a topic or material ID')),
      );
      return;
    }
    setState(() {
      _request = ContentApiService.studyPack(
        topic: _topic.text.trim(),
        sourceText: _source.text.trim(),
        materialId: _materialId.text.trim(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(0.5),
          child: Container(color: colors.border, height: 0.5),
        ),
        title: Text(
          'Complete Study Pack',
          style: type.cardHeading.copyWith(fontSize: 17),
        ),
      ),
      body: AppPageBackground(
        height: 240,
        gradient: isDark
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colors.brand.withValues(alpha: 0.12),
                  colors.background,
                ],
              )
            : AppGradients.toolStudyPacks,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: GochanoRadius.lgAll,
                border: Border.all(color: colors.border),
                boxShadow: [
                  BoxShadow(
                    color: colors.brand.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: colors.brand.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.inventory_2_rounded,
                          size: 18,
                          color: colors.brand,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Generate All-in-One Study Pack', style: type.cardHeading),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Creates comprehensive notes, flashcards, and summary checkpoints from your materials or topic.',
                    style: type.caption,
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _topic,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Topic / Subject Title',
                      hintText: 'e.g. Operating Systems, Microeconomics, Molecular Biology',
                      filled: true,
                      fillColor: colors.surfaceVariant.withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: GochanoRadius.mdAll,
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: GochanoRadius.mdAll,
                        borderSide: BorderSide(color: colors.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _materialId,
                    decoration: InputDecoration(
                      labelText: 'Uploaded Material ID (optional)',
                      hintText: 'Link to a PDF in your Workspace',
                      filled: true,
                      fillColor: colors.surfaceVariant.withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: GochanoRadius.mdAll,
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: GochanoRadius.mdAll,
                        borderSide: BorderSide(color: colors.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _source,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'Lecture notes or textbook extract (optional)',
                      hintText: 'Paste lecture transcripts, slides or notes to synthesize...',
                      filled: true,
                      fillColor: colors.surfaceVariant.withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: GochanoRadius.mdAll,
                        borderSide: BorderSide(color: colors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: GochanoRadius.mdAll,
                        borderSide: BorderSide(color: colors.border),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.brand,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: GochanoRadius.mdAll),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text(
                        'Generate Study Pack',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _generate,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_request != null)
              FutureBuilder<Map<String, dynamic>>(
                future: _request,
                builder: (context, snapshot) {
                  Widget content;
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    content = Padding(
                      key: const ValueKey('loading'),
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 14),
                            Text('Assembling your study pack…', style: type.caption),
                          ],
                        ),
                      ),
                    );
                  } else if (snapshot.hasError) {
                    content = Center(
                      key: const ValueKey('error'),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          snapshot.error.toString(),
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    );
                  } else {
                    final pack = snapshot.data?['generatedContent'] as Map? ?? {};
                    if (pack.isEmpty) {
                      content = Center(
                        key: const ValueKey('empty'),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('No study pack content available.', style: type.bodySecondary),
                        ),
                      );
                    } else {
                      content = Column(
                        key: const ValueKey('content'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Generated Pack Components', style: type.cardHeading),
                          const SizedBox(height: 10),
                          for (final entry in pack.entries)
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: colors.surface,
                                borderRadius: GochanoRadius.lgAll,
                                border: Border.all(color: colors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: colors.brand.withValues(alpha: 0.08),
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                      border: Border(
                                        bottom: BorderSide(
                                          color: colors.brand.withValues(alpha: 0.15),
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      entry.key.toString().toUpperCase(),
                                      style: TextStyle(
                                        color: colors.brand,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Text(
                                      entry.value.toString(),
                                      style: type.body.copyWith(height: 1.55),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    }
                  }
                  return AnimatedSwitcher(
                    duration: AppMotion.duration(context, AppMotion.contentReveal),
                    child: content,
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
