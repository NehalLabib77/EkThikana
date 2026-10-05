import 'package:flutter/material.dart';

import '../../../../core/design_system/app_gradients.dart';
import '../../../../core/localization/gochano_language.dart';

/// The 5 deterministic time-of-day periods for Study Mode greeting.
enum GreetingPeriod {
  earlyMorning,
  morning,
  afternoon,
  evening,
  night,
}

/// Centralized presentation model for Study Mode dynamic greetings.
///
/// Encapsulates:
/// - Deterministic time period classification
/// - Localized greeting title and supportive message
/// - Semantic time-of-day gradient token
/// - Semantic icon and contrast-compliant colors
class GreetingPresentation {
  final GreetingPeriod period;
  final String greetingEn;
  final String greetingBn;
  final String messageEn;
  final String messageBn;
  final IconData icon;
  final LinearGradient gradient;
  final Color textColor;
  final Color subtitleColor;
  final Color iconColor;
  final Color iconContainerColor;

  const GreetingPresentation({
    required this.period,
    required this.greetingEn,
    required this.greetingBn,
    required this.messageEn,
    required this.messageBn,
    required this.icon,
    required this.gradient,
    required this.textColor,
    required this.subtitleColor,
    required this.iconColor,
    required this.iconContainerColor,
  });

  /// Deterministic resolver based on local device/app time.
  ///
  /// Periods:
  /// - EARLY MORNING: 5:00 - 8:59
  /// - MORNING: 9:00 - 11:59
  /// - AFTERNOON: 12:00 - 16:59
  /// - EVENING: 17:00 - 19:59
  /// - NIGHT: 20:00 - 4:59
  static GreetingPresentation forTime(DateTime dateTime) {
    final hour = dateTime.hour;

    if (hour >= 5 && hour < 9) {
      // Early Morning
      return const GreetingPresentation(
        period: GreetingPeriod.earlyMorning,
        greetingEn: 'Good Morning',
        greetingBn: 'শুভ সকাল',
        messageEn: 'A fresh start for a productive day.',
        messageBn: 'নতুন দিনের সাথে নতুন সম্ভাবনার সূচনা।',
        icon: Icons.wb_twilight_rounded,
        gradient: AppGradients.greetingEarlyMorning,
        textColor: Color(0xFF0F172A),
        subtitleColor: Color(0xFF475569),
        iconColor: Color(0xFFEA580C),
        iconContainerColor: Color(0x66FFFFFF),
      );
    } else if (hour >= 9 && hour < 12) {
      // Morning
      return const GreetingPresentation(
        period: GreetingPeriod.morning,
        greetingEn: 'Good Morning',
        greetingBn: 'শুভ সকাল',
        messageEn: "Let's make steady progress today.",
        messageBn: 'আজ ধারাবাহিক অগ্রগতির দিন।',
        icon: Icons.wb_sunny_rounded,
        gradient: AppGradients.greetingMorning,
        textColor: Color(0xFF0F172A),
        subtitleColor: Color(0xFF475569),
        iconColor: Color(0xFFD97706),
        iconContainerColor: Color(0x66FFFFFF),
      );
    } else if (hour >= 12 && hour < 17) {
      // Afternoon
      return const GreetingPresentation(
        period: GreetingPeriod.afternoon,
        greetingEn: 'Good Afternoon',
        greetingBn: 'শুভ অপরাহ্ন',
        messageEn: 'Keep the momentum going.',
        messageBn: 'পড়াশোনার গতি ধরে রাখুন।',
        icon: Icons.wb_cloudy_rounded,
        gradient: AppGradients.greetingAfternoon,
        textColor: Color(0xFF0F172A),
        subtitleColor: Color(0xFF475569),
        iconColor: Color(0xFF0284C7),
        iconContainerColor: Color(0x66FFFFFF),
      );
    } else if (hour >= 17 && hour < 20) {
      // Evening
      return const GreetingPresentation(
        period: GreetingPeriod.evening,
        greetingEn: 'Good Evening',
        greetingBn: 'শুভ সন্ধ্যা',
        messageEn: 'A little progress still counts.',
        messageBn: 'প্রতিটি ছোট অগ্রগতিও মূল্যবান।',
        icon: Icons.wb_twilight_rounded,
        gradient: AppGradients.greetingEvening,
        textColor: Color(0xFF0F172A),
        subtitleColor: Color(0xFF475569),
        iconColor: Color(0xFFE11D48),
        iconContainerColor: Color(0x66FFFFFF),
      );
    } else {
      // Night (20:00 - 4:59)
      return const GreetingPresentation(
        period: GreetingPeriod.night,
        greetingEn: 'Good Evening',
        greetingBn: 'শুভ সন্ধ্যা',
        messageEn: 'Wind down, review, and prepare for tomorrow.',
        messageBn: 'আজকের পাঠ পর্যালোচনা করুন এবং আগামীকালের প্রস্তুতি নিন।',
        icon: Icons.nights_stay_rounded,
        gradient: AppGradients.greetingNight,
        textColor: Colors.white,
        subtitleColor: Color(0xFFCBD5E1),
        iconColor: Color(0xFFA78BFA),
        iconContainerColor: Color(0x26FFFFFF),
      );
    }
  }

  /// Localized greeting prefix ('Good Morning' / 'শুভ সকাল').
  String get greetingText => GochanoLanguage.text(greetingEn, greetingBn);

  /// Localized supporting message.
  String get supportingMessage => GochanoLanguage.text(messageEn, messageBn);
}
