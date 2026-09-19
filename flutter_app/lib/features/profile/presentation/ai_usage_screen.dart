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

      debugPrint('[AiUsage] OK — keys: ${data.keys.toList()}');
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
                      GochanoLanguage.text(
                        'AI Features & Limits',
                        'এআই সুবিধা ও ব্যবহারের সীমা',
                      ),
                      style: type.sectionHeading,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      GochanoLanguage.text(
                        'Track remaining calls for chat, notes, quizzes, and planner.',
                        'চ্যাট, নোট, কুইজ এবং স্টাডি প্ল্যানারের অবশিষ্ট কোটা দেখুন।',
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

        // 1. Chat: 20/day
        _FeatureUsageCard(
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
          used: chatUsed,
          limit: chatLimit,
          isPlan: false,
        ),

        const SizedBox(height: GochanoSpacing.sm),

        // 2. Note AI: 5/month
        _FeatureUsageCard(
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
          used: noteUsed,
          limit: noteLimit,
          isPlan: false,
        ),

        const SizedBox(height: GochanoSpacing.sm),

        // 3. Quiz: 3/month
        _FeatureUsageCard(
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
          used: quizUsed,
          limit: quizLimit,
          isPlan: false,
        ),

        const SizedBox(height: GochanoSpacing.sm),

        // 4. Study Planner: 1 active plan
        _FeatureUsageCard(
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
          used: planUsed,
          limit: planLimit,
          isPlan: true,
        ),

        const SizedBox(height: GochanoSpacing.lg),

        // Footer Note
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
}

class _FeatureUsageCard extends StatelessWidget {
  const _FeatureUsageCard({
    required this.icon,
    required this.title,
    required this.resetBadge,
    required this.remainingText,
    required this.used,
    required this.limit,
    required this.isPlan,
  });

  final IconData icon;
  final String title;
  final String resetBadge;
  final String remainingText;
  final int used;
  final int limit;
  final bool isPlan;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    final ratio = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final isExhausted = !isPlan && (used >= limit);
    final progressColor = isExhausted
        ? colors.error
        : (ratio > 0.7 ? colors.warning : colors.brand);

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
                    Text(
                      resetBadge,
                      style: type.caption.copyWith(color: colors.textSecondary),
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
                  isPlan
                      ? (used >= limit
                            ? GochanoLanguage.text('1 active', '১টি সক্রিয়')
                            : GochanoLanguage.text('0 active', '০টি সক্রিয়'))
                      : GochanoLanguage.text(
                          '${limit - used}/$limit left',
                          'বাকি ${limit - used}/$limit',
                        ),
                  style: type.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isExhausted ? Colors.white : colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
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
          const SizedBox(height: GochanoSpacing.xs),
          Text(
            remainingText,
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
