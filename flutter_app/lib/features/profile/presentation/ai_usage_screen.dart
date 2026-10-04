import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/app_config.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../services/api_service.dart';
import '../../../shared/widgets/gochano_surfaces.dart';

/// Dedicated screen to view remaining AI usage quotas across features (Phase 3A).
class AiUsageScreen extends StatefulWidget {
  const AiUsageScreen({super.key});

  @override
  State<AiUsageScreen> createState() => _AiUsageScreenState();
}

class _AiUsageScreenState extends State<AiUsageScreen> {
  Map<String, dynamic>? _usage;
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchUsage();
  }

  Future<void> _fetchUsage() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final endpoint = '${AppConfig.apiBaseUrl}/api/ai/usage';
      debugPrint('[AiUsage] GET $endpoint');

      final data = await ApiService.getAiUsage();

      debugPrint('[AiUsage] OK: received data');
      if (!mounted) return;
      setState(() {
        _usage = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      // Safe logging: log error category and status only — never tokens,
      // keys, or user data.
      final errorType = e.runtimeType.toString();
      final statusCode = (e is ApiException) ? e.statusCode : null;
      final safeMessage = _sanitizeErrorMessage(e);
      debugPrint(
        '[AiUsage] FAIL status=$statusCode [$errorType] $safeMessage',
      );

      setState(() {
        _loading = false;
        _errorMessage = _categorizeError(e);
      });
    }
  }

  /// Extracts a safe, loggable message from the exception without exposing
  /// API keys, tokens, or user-specific data.
  static String _sanitizeErrorMessage(Object error) {
    if (error is ApiException) {
      // ApiException.message is already a user-facing detail from the
      // backend — never contains raw tokens or keys.
      return 'status=${error.statusCode ?? "?"} detail=${error.message}';
    }
    if (error is SocketException) return 'network unreachable';
    if (error is HttpException) return 'HTTP error';
    if (error.toString().contains('TimeoutException')) return 'request timeout';
    // Generic fallback — type name only, no `.toString()` which could
    // embed a URL with query-string credentials.
    return error.runtimeType.toString();
  }

  /// Maps the exception to a user-visible, localized error string so the
  /// screen shows actionable guidance instead of always blaming the network.
  static String _categorizeError(Object error) {
    if (error is ApiException) {
      final code = error.statusCode ?? 0;
      if (code == 401) {
        return GochanoLanguage.text(
          'You are not signed in. Please sign in and try again.',
          'আপনি সাইন ইন করেননি। সাইন ইন করে আবার চেষ্টা করুন।',
        );
      }
      if (code == 403) {
        return GochanoLanguage.text(
          'AI usage is available for student accounts only.',
          'এআই ব্যবহার শুধুমাত্র ছাত্র অ্যাকাউন্টের জন্য।',
        );
      }
      if (code >= 500) {
        return GochanoLanguage.text(
          'Server is temporarily unavailable. Please try again in a moment.',
          'সার্ভার সাময়িকভাবে অনুপলব্ধ। কিছুক্ষণ অপেক্ষা করে আবার চেষ্টা করুন।',
        );
      }
      if (error.message.contains('Backend URL is not configured')) {
        return GochanoLanguage.text(
          'App configuration error. Please reinstall or contact support.',
          'অ্যাপ কনফিগারেশন ত্রুটি। পুনরায় ইনস্টল করুন বা সাপোর্টে যোগাযোগ করুন।',
        );
      }
    }
    if (error is SocketException ||
        error.toString().contains('TimeoutException')) {
      return GochanoLanguage.text(
        'Failed to load AI usage. Please check your connection and try again.',
        'এআই ব্যবহারের তথ্য লোড করা যায়নি। ইন্টারনেট সংযোগ চেক করে আবার চেষ্টা করুন।',
      );
    }
    return GochanoLanguage.text(
      'Failed to load AI usage. Please try again.',
      'এআই ব্যবহারের তথ্য লোড করা যায়নি। আবার চেষ্টা করুন।',
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return ValueListenableBuilder<GochanoLocale>(
      valueListenable: GochanoLanguage.current,
      builder: (context, locale, _) {
        return GochanoScaffold(
          padBody: false,
          appBar: GochanoAppBar(
            title: GochanoLanguage.text('AI Usage', 'এআই ব্যবহার'),
            automaticallyImplyLeading: true,
          ),
          body: RefreshIndicator(
            onRefresh: _fetchUsage,
            color: colors.brand,
            child: _buildBody(colors, type),
          ),
        );
      },
    );
  }

  Widget _buildBody(GochanoColors colors, GochanoTypography type) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(colors.brand),
        ),
      );
    }

    if (_errorMessage != null || _usage == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(GochanoSpacing.lg),
        children: [
          const SizedBox(height: GochanoSpacing.xl),
          Icon(Icons.error_outline_rounded, size: 54, color: colors.error),
          const SizedBox(height: GochanoSpacing.md),
          Text(
            _errorMessage ??
                GochanoLanguage.text('Usage unavailable', 'ব্যবহার অনুপলব্ধ'),
            style: type.bodySecondary,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: GochanoSpacing.lg),
          Center(
            child: ElevatedButton.icon(
              onPressed: _fetchUsage,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(GochanoLanguage.text('Retry', 'আবার চেষ্টা করুন')),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final usage = _usage!;

    // Quota enforcement is a server-side switch (AI_QUOTA_ENFORCEMENT).
    // When it is OFF, "remaining/negative" quota values are meaningless —
    // show actual usage counts instead (presentation only, counters untouched).
    final unlimited = usage['quota_enforcement_enabled'] == false;

    // Phase 3A Features
    final chatData = usage['chat'] as Map<String, dynamic>? ?? {};
    final chatUsed = chatData['used'] as int? ?? 0;
    final chatLimit = chatData['limit'] as int? ?? 20;
    final chatRemaining =
        chatData['remaining'] as int? ??
        (chatLimit - chatUsed).clamp(0, chatLimit);

    final noteData = usage['note_ai'] as Map<String, dynamic>? ?? {};
    final noteUsed = noteData['used'] as int? ?? 0;
    final noteLimit = noteData['limit'] as int? ?? 5;
    final noteRemaining =
        noteData['remaining'] as int? ??
        (noteLimit - noteUsed).clamp(0, noteLimit);

    final quizData = usage['quiz'] as Map<String, dynamic>? ?? {};
    final quizUsed = quizData['used'] as int? ?? 0;
    final quizLimit = quizData['limit'] as int? ?? 3;
    final quizRemaining =
        quizData['remaining'] as int? ??
        (quizLimit - quizUsed).clamp(0, quizLimit);

    final planData = usage['study_plan'] as Map<String, dynamic>? ?? {};
    final planUsed = planData['used'] as int? ?? 0;
    final planLimit = planData['limit'] as int? ?? 1;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.md,
        vertical: GochanoSpacing.sm,
      ),
      children: [
        if (unlimited) ...[
          Container(
            padding: const EdgeInsets.all(GochanoSpacing.md),
            margin: const EdgeInsets.only(bottom: GochanoSpacing.md),
            decoration: BoxDecoration(
              color: colors.warningSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colors.warning),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.bolt_rounded,
                  color: colors.warning,
                  size: 28,
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            GochanoLanguage.text(
                              'Unlimited AI Mode Active',
                              'আনলিমিটেড এআই মোড সক্রিয়',
                            ),
                            style: type.body.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colors.warning,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colors.warning,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'FREE',
                              style: type.caption.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        GochanoLanguage.text(
                          'Quota enforcement is temporarily disabled. Enjoy unrestricted AI assistance!',
                          'কোটা সীমাবদ্ধতা সাময়িকভাবে শিথিল করা হয়েছে। সীমাহীন এআই সুবিধা উপভোগ করুন!',
                        ),
                        style: type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // Summary Header Card
        Container(
          padding: const EdgeInsets.all(GochanoSpacing.md),
          decoration: BoxDecoration(
            color: colors.brand.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.brand.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.brand.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: colors.brand,
                  size: 24,
                ),
              ),
              const SizedBox(width: GochanoSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      unlimited
                          ? GochanoLanguage.text(
                              'AI Features & Usage',
                              'এআই সুবিধা ও ব্যবহার',
                            )
                          : GochanoLanguage.text(
                              'AI Features & Limits',
                              'এআই সুবিধা ও ব্যবহারের সীমা',
                            ),
                      style: type.sectionHeading,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      unlimited
                          ? GochanoLanguage.text(
                              'Track your AI usage across chat, notes, quizzes, planner, and study AI.',
                              'চ্যাট, নোট, কুইজ, প্ল্যানার এবং স্টাডি এআই-এর ব্যবহার দেখুন।',
                            )
                          : GochanoLanguage.text(
                              'Track remaining calls for chat, notes, quizzes, planner, and study AI.',
                              'চ্যাট, নোট, কুইজ, প্ল্যানার এবং স্টাডি এআই-এর অবশিষ্ট কোটা দেখুন।',
                            ),
                      style: type.caption.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: GochanoSpacing.md),

        // 1. Chat: 20/day (unlimited mode: actual uses, never "remaining")
        AiFeatureUsageCard(
          icon: Icons.chat_bubble_outline_rounded,
          title: GochanoLanguage.text('Chat', 'চ্যাট'),
          resetBadge: GochanoLanguage.text(
            'Daily (resets at 00:00 UTC)',
            'দৈনিক (০০:০০ ইউটিসিতে রিসেট)',
          ),
          remainingText: GochanoLanguage.text(
            '$chatRemaining of $chatLimit remaining today',
            'আজ $chatLimitটির মধ্যে $chatRemainingটি বাকি',
          ),
          usageLabel: GochanoLanguage.text(
            '$chatUsed uses',
            '$chatUsed বার ব্যবহার',
          ),
          unlimited: unlimited,
          used: chatUsed,
          limit: chatLimit,
          isPlan: false,
        ),

        const SizedBox(height: GochanoSpacing.sm),

        // 2. Note AI: 5/month
        AiFeatureUsageCard(
          icon: Icons.edit_note_rounded,
          title: GochanoLanguage.text('Note AI', 'নোট এআই'),
          resetBadge: GochanoLanguage.text(
            'Monthly (resets 1st of month)',
            'মাসিক (মাসের ১ তারিখে রিসেট)',
          ),
          remainingText: GochanoLanguage.text(
            '$noteRemaining of $noteLimit remaining this month',
            'এই মাসে $noteLimitটির মধ্যে $noteRemainingটি বাকি',
          ),
          usageLabel: GochanoLanguage.text(
            '$noteUsed uses',
            '$noteUsed বার ব্যবহার',
          ),
          unlimited: unlimited,
          used: noteUsed,
          limit: noteLimit,
          isPlan: false,
        ),

        const SizedBox(height: GochanoSpacing.sm),

        // 3. Quiz: 3/month
        AiFeatureUsageCard(
          icon: Icons.quiz_outlined,
          title: GochanoLanguage.text('Quiz Generator', 'কুইজ জেনারেটর'),
          resetBadge: GochanoLanguage.text(
            'Monthly (resets 1st of month)',
            'মাসিক (মাসের ১ তারিখে রিসেট)',
          ),
          remainingText: GochanoLanguage.text(
            '$quizRemaining of $quizLimit remaining this month',
            'এই মাসে $quizLimitটির মধ্যে $quizRemainingটি বাকি',
          ),
          usageLabel: GochanoLanguage.text(
            '$quizUsed generations',
            '$quizUsed জেনারেশন',
          ),
          unlimited: unlimited,
          used: quizUsed,
          limit: quizLimit,
          isPlan: false,
        ),

        const SizedBox(height: GochanoSpacing.sm),

        // 4. Study Planner: 1 active plan
        AiFeatureUsageCard(
          icon: Icons.calendar_month_outlined,
          title: GochanoLanguage.text('Study Planner', 'স্টাডি প্ল্যানার'),
          resetBadge: GochanoLanguage.text(
            'Max 1 active plan allowed',
            'সর্বোচ্চ ১টি সক্রিয় প্ল্যান',
          ),
          remainingText: planUsed >= planLimit
              ? GochanoLanguage.text('1 active plan', '১টি সক্রিয় প্ল্যান')
              : GochanoLanguage.text(
                  '0 active plan (1 available)',
                  '০টি সক্রিয় (১টি খালি আছে)',
                ),
          usageLabel: GochanoLanguage.text(
            '$planUsed active',
            '$planUsed সক্রিয়',
          ),
          unlimited: unlimited,
          used: planUsed,
          limit: planLimit,
          isPlan: true,
        ),

        const SizedBox(height: GochanoSpacing.sm),

        // 5. Assignment Assistant (future quota ready)
        AiFeatureUsageCard(
          icon: Icons.assignment_rounded,
          title: GochanoLanguage.text('Assignment Assistant', 'এসাইনমেন্ট সহকারী'),
          resetBadge: GochanoLanguage.text(
            'Coming soon — usage tracking ready',
            'শীঘ্রই আসছে — ব্যবহার ট্র্যাকিং প্রস্তুত',
          ),
          remainingText: GochanoLanguage.text(
            'Available for all students',
            'সকল শিক্ষার্থীর জন্য উপলব্ধ',
          ),
          used: 0,
          limit: 1,
          isPlan: true,
        ),

        if (unlimited) ...[
          const SizedBox(height: GochanoSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.sm),
            child: Text(
              GochanoLanguage.text(
                'Usage is still tracked, but limits are temporarily not enforced.',
                'ব্যবহার এখনো ট্র্যাক করা হচ্ছে, তবে সীমাগুলো সাময়িকভাবে প্রযোজ্য নয়।',
              ),
              style: type.caption.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
        ],

        const SizedBox(height: GochanoSpacing.lg),
        Text(
          GochanoLanguage.text(
            'AI Activity Dashboard',
            'এআই অ্যাক্টিভিটি ড্যাশবোর্ড',
          ),
          style: type.cardHeading.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: GochanoSpacing.sm),
        _buildActivityDashboard(colors, type, usage),

        const SizedBox(height: GochanoSpacing.lg),

        // Footer Note (quota mode only — a "limits" note would contradict
        // unlimited mode, which carries its own caption above.)
        if (!unlimited)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: GochanoSpacing.sm),
            child: Text(
              GochanoLanguage.text(
                'Limits ensure equal access and fair server resources for all students across campus.',
                'ক্যাম্পাসের সকল শিক্ষার্থীর জন্য সমান ও টেকসই সেবা নিশ্চিত করতে এই সীমা নির্ধারিত।',
              ),
              style: type.caption.copyWith(color: colors.textTertiary),
              textAlign: TextAlign.center,
            ),
          ),

        const SizedBox(height: GochanoSpacing.xl),
      ],
    );
  }

  Widget _buildActivityDashboard(
    GochanoColors colors,
    GochanoTypography type,
    Map<String, dynamic> usage,
  ) {
    final summary = usage['summary'] as Map<String, dynamic>? ?? {};

    int count(String key) => (summary[key] as num?)?.toInt() ?? 0;

    // Every counter the backend records in ai_usage_summary/{uid}.
    final entries = <({IconData icon, String en, String bn, Color accent, int value})>[
      (
        icon: Icons.chat_bubble_outline_rounded,
        en: 'Chat messages',
        bn: 'চ্যাট বার্তা',
        accent: colors.brand,
        value: count('ai_chat_messages'),
      ),
      (
        icon: Icons.auto_stories_outlined,
        en: 'Note AI',
        bn: 'নোট এআই',
        accent: colors.study,
        value: count('ai_notes'),
      ),
      (
        icon: Icons.picture_as_pdf_outlined,
        en: 'PDF questions',
        bn: 'পিডিএফ প্রশ্ন',
        accent: colors.ai,
        value: count('pdf_questions'),
      ),
      (
        icon: Icons.image_outlined,
        en: 'Image questions',
        bn: 'ছবি প্রশ্ন',
        accent: colors.medicine,
        value: count('image_questions'),
      ),
      (
        icon: Icons.auto_awesome_outlined,
        en: 'Quiz generations',
        bn: 'কুইজ তৈরি',
        accent: colors.usageMedium,
        value: count('quiz_generations'),
      ),
      (
        icon: Icons.quiz_outlined,
        en: 'Quiz questions',
        bn: 'কুইজ প্রশ্ন',
        accent: colors.info,
        value: count('quiz_questions'),
      ),
      (
        icon: Icons.assignment_turned_in_outlined,
        en: 'Assignment AI',
        bn: 'এসাইনমেন্ট এআই',
        accent: colors.expense,
        value: count('assignment_uses'),
      ),
      (
        icon: Icons.calendar_month_outlined,
        en: 'Study plans',
        bn: 'স্টাডি প্ল্যান',
        accent: colors.success,
        value: count('planner_plans'),
      ),
      (
        icon: Icons.crisis_alert_outlined,
        en: 'Exam Rescue plans',
        bn: 'এক্সাম রেসকিউ প্ল্যান',
        accent: colors.error,
        value: count('exam_rescue_plans'),
      ),
      (
        icon: Icons.tips_and_updates_outlined,
        en: 'Study recommendations',
        bn: 'স্টাডি সুপারিশ',
        accent: colors.community,
        value: count('study_recommendations'),
      ),
      (
        icon: Icons.directions_bus_outlined,
        en: 'Commute guides',
        bn: 'যাত্রা গাইড',
        accent: colors.commute,
        value: count('commute_guides'),
      ),
      (
        // One request analyses a whole batch of recorded mistakes, so this
        // counts batches explained — not questions examined.
        icon: Icons.psychology_outlined,
        en: 'Mistake analyses',
        bn: 'ভুল বিশ্লেষণ',
        accent: colors.ai,
        value: count('mistake_analyses'),
      ),
    ];

    final rows = <Widget>[];
    for (var i = 0; i < entries.length; i += 2) {
      final pair = entries.sublist(
        i,
        i + 2 < entries.length ? i + 2 : entries.length,
      );
      rows.add(
        Row(
          children: [
            Expanded(
              child: _AiSummaryStatCard(
                icon: pair[0].icon,
                label: GochanoLanguage.text(pair[0].en, pair[0].bn),
                value: '${pair[0].value}',
                accent: pair[0].accent,
              ),
            ),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: pair.length > 1
                  ? _AiSummaryStatCard(
                      icon: pair[1].icon,
                      label: GochanoLanguage.text(pair[1].en, pair[1].bn),
                      value: '${pair[1].value}',
                      accent: pair[1].accent,
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
      if (i + 2 < entries.length) {
        rows.add(const SizedBox(height: GochanoSpacing.sm));
      }
    }

    rows.add(const SizedBox(height: GochanoSpacing.xs));
    rows.add(
      Text(
        GochanoLanguage.text(
          'Counters are lifetime totals per account. Quiz Generations counts '
          'successful generations; Quiz Questions counts the usable questions '
          'produced.',
          'গণনা অ্যাকাউন্ট প্রতি আজীবন মোট। কুইজ তৈরি সফল জেনারেশন গুনে, কুইজ '
          'প্রশ্ন তৈরি হওয়া ব্যবহারযোগ্য প্রশ্ন গুনে।',
        ),
        style: type.caption.copyWith(color: colors.textTertiary),
      ),
    );

    return Column(children: rows);
  }
}

/// One feature's usage card.
///
/// Quota mode (`unlimited == false`) keeps the original used/limit/remaining
/// presentation. Unlimited mode shows actual usage only: a "N uses" badge and
/// caption, no progress bar, no "x/y left", no negative values, no exhaustion
/// styling — the server is not enforcing limits, so the UI must not imply it.
class AiFeatureUsageCard extends StatelessWidget {
  const AiFeatureUsageCard({
    super.key,
    required this.icon,
    required this.title,
    required this.resetBadge,
    required this.remainingText,
    required this.used,
    required this.limit,
    required this.isPlan,
    this.unlimited = false,
    this.usageLabel,
  });

  final IconData icon;
  final String title;
  final String resetBadge;
  final String remainingText;

  /// Actual-usage text shown in unlimited mode (e.g. "16 uses").
  final String? usageLabel;
  final int used;
  final int limit;
  final bool isPlan;
  final bool unlimited;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    final showQuota = !unlimited;
    final ratio = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final isExhausted = showQuota && !isPlan && (used >= limit);
    final progressColor = isExhausted
        ? colors.error
        : (ratio > 0.7 ? colors.warning : colors.brand);

    final String badgeText;
    if (!showQuota) {
      badgeText = usageLabel ??
          (isPlan
              ? GochanoLanguage.text('$used active', '$used সক্রিয়')
              : GochanoLanguage.text('$used uses', '$used বার ব্যবহার'));
    } else if (isPlan) {
      badgeText = used >= limit
          ? GochanoLanguage.text('1 active', '১টি সক্রিয়')
          : GochanoLanguage.text('0 active', '০টি সক্রিয়');
    } else {
      badgeText = GochanoLanguage.text(
        '${limit - used}/$limit left',
        'বাকি ${limit - used}/$limit',
      );
    }

    return Container(
      padding: const EdgeInsets.all(GochanoSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (isExhausted ? colors.error : colors.brand).withValues(
                    alpha: 0.12,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: isExhausted ? colors.error : colors.brand,
                  size: 20,
                ),
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: type.body),
                    // Reset dates only mean something when quotas are enforced.
                    if (showQuota)
                      Text(
                        resetBadge,
                        style: type.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (isExhausted ? colors.error : colors.surfaceVariant),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badgeText,
                  style: type.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isExhausted ? Colors.white : colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          if (showQuota) ...[
            const SizedBox(height: GochanoSpacing.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 7,
                backgroundColor: colors.surfaceVariant,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
          ],
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            showQuota ? remainingText : badgeText,
            style: type.caption.copyWith(
              color: isExhausted ? colors.error : colors.textSecondary,
              fontWeight: isExhausted ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiSummaryStatCard extends StatelessWidget {
  const _AiSummaryStatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Container(
      padding: const EdgeInsets.all(GochanoSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: accent),
              const Spacer(),
              Text(
                value,
                style: type.body.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: type.caption.copyWith(
              color: colors.textSecondary,
              fontSize: 11,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
