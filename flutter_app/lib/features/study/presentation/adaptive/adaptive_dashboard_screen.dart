import 'package:flutter/material.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../shared/widgets/ai_widgets.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'adaptive_api_service.dart';

class AdaptiveDashboardScreen extends StatefulWidget {
  const AdaptiveDashboardScreen({super.key});

  @override
  State<AdaptiveDashboardScreen> createState() =>
      _AdaptiveDashboardScreenState();
}

class _AdaptiveDashboardScreenState extends State<AdaptiveDashboardScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = AdaptiveApiService.curriculum();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text(
          "Today's Adaptive Plan",
          'আজকের অ্যাডাপ্টিভ প্ল্যান',
        ),
      ),
      body: AppPageBackground(
        gradient: AppGradients.planPage,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _future,
          builder: (context, snapshot) {
            final Widget child;
            if (snapshot.connectionState == ConnectionState.waiting) {
              child = const Center(
                key: ValueKey('adaptive_loading'),
                child: CircularProgressIndicator(),
              );
            } else if (snapshot.hasError) {
              child = Center(
                key: const ValueKey('adaptive_error'),
                child: Padding(
                  padding: const EdgeInsets.all(GochanoSpacing.lg),
                  child: AiErrorBanner(message: snapshot.error.toString()),
                ),
              );
            } else {
              final items = (snapshot.data?['items'] as List?) ?? const [];
              if (items.isEmpty) {
                child = Center(
                  key: const ValueKey('adaptive_empty'),
                  child: Padding(
                    padding: const EdgeInsets.all(GochanoSpacing.lg),
                    child: AiEmptyState(
                      icon: Icons.track_changes_rounded,
                      title: GochanoLanguage.text(
                        'No adaptive plan yet',
                        'এখনো কোনো অ্যাডাপ্টিভ প্ল্যান নেই',
                      ),
                      message: GochanoLanguage.text(
                        'Practice quizzes and study materials to unlock personalized daily plans.',
                        'ব্যক্তিগত দৈনিক পরিকল্পনা আনলক করতে কুইজ ও পড়ার উপকরণ অনুশীলন করুন।',
                      ),
                    ),
                  ),
                );
              } else {
                child = RefreshIndicator(
                  key: const ValueKey('adaptive_content'),
                  onRefresh: () async =>
                      setState(() => _future = AdaptiveApiService.curriculum()),
                  child: ListView.builder(
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
                      final reason = item['reason']?.toString() ?? 'Weak area';
                      final minutes = item['totalMinutes'] ?? 0;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
                        child: AppCard(
                          accent: colors.brand,
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: colors.brand.withValues(alpha: 0.12),
                                  borderRadius: GochanoRadius.mdAll,
                                ),
                                child: Icon(
                                  Icons.auto_stories_rounded,
                                  size: 20,
                                  color: colors.brand,
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
                                    const SizedBox(height: 2),
                                    Text(
                                      reason,
                                      style: context.type.caption.copyWith(
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: GochanoSpacing.sm,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.brand.withValues(alpha: 0.1),
                                  borderRadius: GochanoRadius.smAll,
                                ),
                                child: Text(
                                  '$minutes min',
                                  style: context.type.caption.copyWith(
                                    color: colors.brand,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              }
            }
            return AnimatedSwitcher(
              duration: AppMotion.duration(
                context,
                AppMotion.contentReveal,
              ),
              switchInCurve: AppMotion.standard,
              switchOutCurve: AppMotion.standard,
              child: child,
            );
          },
        ),
      ),
    );
  }
}
