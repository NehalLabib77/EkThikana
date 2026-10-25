import 'package:flutter/material.dart';

import '../../../../core/design_system/app_design_system.dart';
import 'content_api_service.dart';

class RevisionSheetScreen extends StatefulWidget {
  const RevisionSheetScreen({super.key});

  @override
  State<RevisionSheetScreen> createState() => _RevisionSheetScreenState();
}

class _RevisionSheetScreenState extends State<RevisionSheetScreen> {
  final _topic = TextEditingController();
  Future<Map<String, dynamic>>? _request;

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  void _generate() {
    if (_topic.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an exam topic')),
      );
      return;
    }
    setState(() {
      _request = ContentApiService.revisionSheet(
        topic: _topic.text.trim(),
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
          'Before-Exam Revision Sheet',
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
                  AppGradients.amberOrange.withValues(alpha: 0.12),
                  colors.background,
                ],
              )
            : AppGradients.toolPastPapers,
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
                    color: AppGradients.amberOrange.withValues(alpha: 0.05),
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
                          color: AppGradients.amberOrange.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.menu_book_rounded,
                          size: 18,
                          color: AppGradients.amberAccent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Generate Quick Cheat Sheet', style: type.cardHeading),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _topic,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Exam Topic or Chapter',
                      hintText: 'e.g. Organic Chemistry reactions, Thermodynamics, DBMS normalization',
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
                        backgroundColor: AppGradients.amberAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: GochanoRadius.mdAll),
                      ),
                      icon: const Icon(Icons.bolt_rounded, size: 18),
                      label: const Text(
                        'Generate Revision Sheet',
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
                            Text('Compiling high-yield revision summaries…', style: type.caption),
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
                    final sheet = snapshot.data?['generatedContent'] as Map? ?? {};
                    if (sheet.isEmpty) {
                      content = Center(
                        key: const ValueKey('empty'),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('No revision sheet available.', style: type.bodySecondary),
                        ),
                      );
                    } else {
                      content = Column(
                        key: const ValueKey('content'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('High-Yield Revision Points', style: type.cardHeading),
                          const SizedBox(height: 10),
                          for (final entry in sheet.entries)
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
                                      color: AppGradients.amberSoft,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                                      border: Border(
                                        bottom: BorderSide(
                                          color: AppGradients.amberOrange.withValues(alpha: 0.2),
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      entry.key.toString().toUpperCase(),
                                      style: const TextStyle(
                                        color: AppGradients.amberDark,
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
