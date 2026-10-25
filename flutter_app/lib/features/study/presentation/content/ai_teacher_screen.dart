import 'package:flutter/material.dart';

import '../../../../core/design_system/app_design_system.dart';
import 'content_api_service.dart';

class AiTeacherScreen extends StatefulWidget {
  const AiTeacherScreen({super.key});

  @override
  State<AiTeacherScreen> createState() => _AiTeacherScreenState();
}

class _AiTeacherScreenState extends State<AiTeacherScreen> {
  final _topic = TextEditingController();
  final _source = TextEditingController();
  Future<Map<String, dynamic>>? _request;

  @override
  void dispose() {
    _topic.dispose();
    _source.dispose();
    super.dispose();
  }

  void _ask() {
    if (_topic.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a topic to explain')),
      );
      return;
    }
    setState(
      () => _request = ContentApiService.explain(
        topic: _topic.text.trim(),
        sourceText: _source.text.trim(),
      ),
    );
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
          'Ask Ziku · AI Teacher',
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
                  colors.ai.withValues(alpha: 0.12),
                  colors.background,
                ],
              )
            : AppGradients.zikuCoach,
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
                    color: colors.ai.withValues(alpha: 0.06),
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
                          color: colors.ai.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.psychology_rounded,
                          size: 18,
                          color: colors.ai,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('Explain Any Concept', style: type.cardHeading),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _topic,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'What would you like explained?',
                      hintText: 'e.g. Quantum tunneling, Bayes theorem, Photosynthesis',
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
                      labelText: 'Paste confusing notes or textbook paragraph (optional)',
                      hintText: 'Add context so Ziku tailors the explanation directly to your course...',
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
                        backgroundColor: colors.ai,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: GochanoRadius.mdAll),
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: const Text(
                        'Teach Me',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: _ask,
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
                            Text('Ziku is preparing an easy-to-understand explanation…', style: type.caption),
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
                    final result = snapshot.data ?? {};
                    final simpleExplanation = result['simpleExplanation']?.toString() ?? '';
                    final analogy = result['analogy']?.toString() ?? '';
                    final formula = result['formula']?.toString() ?? '';
                    final example = result['example']?.toString() ?? '';
                    final practice = result['practiceQuestion']?.toString() ?? '';

                    content = Column(
                      key: const ValueKey('content'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (simpleExplanation.isNotEmpty)
                          _SectionCard(
                            title: 'Explanation',
                            icon: Icons.lightbulb_outline_rounded,
                            accentColor: colors.ai,
                            content: simpleExplanation,
                            type: type,
                            colors: colors,
                          ),
                        if (analogy.isNotEmpty)
                          _SectionCard(
                            title: 'Analogy',
                            icon: Icons.auto_awesome_motion_rounded,
                            accentColor: AppGradients.amberOrange,
                            content: analogy,
                            type: type,
                            colors: colors,
                          ),
                        if (formula.isNotEmpty)
                          _SectionCard(
                            title: 'Key Formula / Rule',
                            icon: Icons.functions_rounded,
                            accentColor: AppGradients.indigoAccent,
                            content: formula,
                            type: type,
                            colors: colors,
                          ),
                        if (example.isNotEmpty)
                          _SectionCard(
                            title: 'Worked Example',
                            icon: Icons.assignment_turned_in_rounded,
                            accentColor: AppGradients.emeraldAccent,
                            content: example,
                            type: type,
                            colors: colors,
                          ),
                        if (practice.isNotEmpty)
                          _SectionCard(
                            title: 'Practice Challenge',
                            icon: Icons.quiz_rounded,
                            accentColor: AppGradients.roseAccent,
                            content: practice,
                            type: type,
                            colors: colors,
                          ),
                      ],
                    );
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.content,
    required this.type,
    required this.colors,
  });

  final String title;
  final IconData icon;
  final Color accentColor;
  final String content;
  final GochanoTypography type;
  final GochanoColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: accentColor),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              content,
              style: type.body.copyWith(height: 1.55),
            ),
          ),
        ],
      ),
    );
  }
}
