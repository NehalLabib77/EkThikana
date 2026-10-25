import 'package:flutter/material.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../shared/widgets/ai_widgets.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'adaptive_api_service.dart';

class AiTextbookScreen extends StatelessWidget {
  const AiTextbookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('My AI Textbook', 'আমার এআই পাঠ্যবই'),
      ),
      body: AppPageBackground(
        gradient: AppGradients.toolMaterials,
        child: FutureBuilder<Map<String, dynamic>>(
          future: AdaptiveApiService.textbook(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(GochanoSpacing.lg),
                  child: AiErrorBanner(message: snapshot.error.toString()),
                ),
              );
            }
            final chapters = (snapshot.data?['chapters'] as List?) ?? const [];
            if (chapters.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(GochanoSpacing.lg),
                  child: AiEmptyState(
                    icon: Icons.menu_book_rounded,
                    title: GochanoLanguage.text(
                      'Textbook is growing',
                      'পাঠ্যবই তৈরি হচ্ছে',
                    ),
                    message: GochanoLanguage.text(
                      'Your textbook will grow as you practice and review topics.',
                      'অনুশীলন ও বিষয় পর্যালোচনার সাথে সাথে আপনার পাঠ্যবই প্রসারিত হবে।',
                    ),
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(
                GochanoSpacing.md,
                GochanoSpacing.md,
                GochanoSpacing.md,
                120,
              ),
              children: [
                for (final raw in chapters) ...[
                  Builder(
                    builder: (ctx) {
                      final item = raw as Map;
                      final chapterTitle =
                          item['chapter']?.toString() ?? 'Chapter';
                      final correction = (item['correction'] ?? '').toString();
                      final mistakes =
                          ((item['yourMistakes'] as List?) ?? const []);

                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: GochanoSpacing.sm,
                        ),
                        child: AppCard(
                          accent: colors.ai,
                          child: Theme(
                            data: Theme.of(ctx).copyWith(
                              dividerColor: Colors.transparent,
                            ),
                            child: ExpansionTile(
                              tilePadding: EdgeInsets.zero,
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: colors.ai.withValues(alpha: 0.12),
                                  borderRadius: GochanoRadius.smAll,
                                ),
                                child: Icon(
                                  Icons.bookmark_rounded,
                                  size: 18,
                                  color: colors.ai,
                                ),
                              ),
                              title: Text(
                                chapterTitle,
                                style: context.type.cardHeading.copyWith(
                                  fontSize: 15,
                                ),
                              ),
                              children: [
                                if (correction.isNotEmpty) ...[
                                  Container(
                                    width: double.infinity,
                                    margin: const EdgeInsets.symmetric(
                                      vertical: GochanoSpacing.xs,
                                    ),
                                    padding: const EdgeInsets.all(
                                      GochanoSpacing.sm,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colors.success.withValues(
                                        alpha: 0.08,
                                      ),
                                      borderRadius: GochanoRadius.smAll,
                                      border: Border.all(
                                        color: colors.success.withValues(
                                          alpha: 0.2,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.check_circle_outline_rounded,
                                          size: 16,
                                          color: colors.success,
                                        ),
                                        const SizedBox(
                                          width: GochanoSpacing.xs,
                                        ),
                                        Expanded(
                                          child: Text(
                                            '${GochanoLanguage.text('Key takeaway', 'মূল ধারণা')}: $correction',
                                            style: context.type.caption
                                                .copyWith(
                                                  color: colors.textPrimary,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                for (final error in mistakes)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: GochanoSpacing.sm,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: colors.error.withValues(
                                          alpha: 0.06,
                                        ),
                                        borderRadius: GochanoRadius.smAll,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Icon(
                                            Icons.error_outline_rounded,
                                            size: 14,
                                            color: colors.error,
                                          ),
                                          const SizedBox(
                                            width: GochanoSpacing.xs,
                                          ),
                                          Expanded(
                                            child: Text(
                                              error.toString(),
                                              style: context.type.caption
                                                  .copyWith(
                                                    color: colors.textPrimary,
                                                  ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
