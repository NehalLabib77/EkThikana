import 'package:flutter/material.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../shared/widgets/ai_widgets.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import '../ai/quiz_generator_screen.dart';
import 'adaptive_api_service.dart';

class RevisionQueueScreen extends StatelessWidget {
  const RevisionQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text(
          "Today's Revision Queue",
          'আজকের রিভিশন কিউ',
        ),
      ),
      body: AppPageBackground(
        gradient: AppGradients.toolPastPapers,
        child: FutureBuilder<Map<String, dynamic>>(
          future: AdaptiveApiService.revisionQueue(),
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
            final items = (snapshot.data?['items'] as List?) ?? const [];
            if (items.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(GochanoSpacing.lg),
                  child: AiEmptyState(
                    icon: Icons.checklist_rounded,
                    title: GochanoLanguage.text(
                      'All caught up!',
                      'সব সম্পন্ন হয়েছে!',
                    ),
                    message: GochanoLanguage.text(
                      'Nothing is due for revision today. Great job keeping up with your studies!',
                      'আজকের জন্য কোনো রিভিশন বাকি নেই। পড়াশোনা চালিয়ে যাওয়ার জন্য অভিনন্দন!',
                    ),
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                GochanoSpacing.md,
                GochanoSpacing.md,
                GochanoSpacing.md,
                120,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = Map<String, dynamic>.from(items[index] as Map);
                final topic = item['topic']?.toString() ?? 'Topic';
                final priority = item['priority'] ?? (index + 1);
                final reasons =
                    (item['reason'] as List?)?.map((r) => r.toString()) ?? [];

                return Padding(
                  padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
                  child: AppCard(
                    accent: colors.warning,
                    child: InkWell(
                      borderRadius: GochanoRadius.mdAll,
                      onTap: () {
                        Navigator.of(context).push(
                          GochanoRoute.to(
                            builder: (_) => QuizGeneratorScreen(
                              initialTopic: topic,
                            ),
                          ),
                        );
                      },
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: colors.warning.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$priority',
                              style: context.type.caption.copyWith(
                                color: colors.warning,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: GochanoSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  topic,
                                  style: context.type.cardHeading.copyWith(
                                    fontSize: 15,
                                  ),
                                ),
                                if (reasons.isNotEmpty) ...[
                                  const SizedBox(height: GochanoSpacing.xs),
                                  Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: reasons.map((r) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: colors.warning.withValues(
                                            alpha: 0.08,
                                          ),
                                          borderRadius: GochanoRadius.smAll,
                                        ),
                                        child: Text(
                                          r,
                                          style: context.type.caption.copyWith(
                                            color: colors.textSecondary,
                                            fontSize: 11,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: colors.warning,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
