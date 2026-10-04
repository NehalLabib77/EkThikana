// Phase 3 — shared pieces of the Real Exam Simulator UI.
//
// Kept in one file so the setup, upload, hall and result screens agree on
// the clock format, on how an option becomes an answer letter, and on how a
// backend error is shown to a student.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../shared/states/gochano_states.dart';

/// MCQ answers travel as bare letters (A, B, C…) because that is what the
/// server grades against — sending the option text marks it wrong.
String examLetter(int optionIndex) =>
    String.fromCharCode(65 + optionIndex.clamp(0, 25));

/// 90 -> "01:30", 3725 -> "01:02:05". Never shows a negative clock: the
/// hall clamps to zero and auto-submits instead.
String examClock(int totalSeconds) {
  final seconds = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  final mm = minutes.toString().padLeft(2, '0');
  final ss = rest.toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
}

String examDurationLabel(int totalSeconds) {
  final minutes = (totalSeconds < 0 ? 0 : totalSeconds) ~/ 60;
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${minutes % 60} min';
}

int examInt(dynamic value) => value is num ? value.toInt() : 0;

double examDouble(dynamic value) =>
    value is num ? value.toDouble() : (double.tryParse('$value') ?? 0);

List<Map<String, dynamic>> examMapList(dynamic value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}

/// The one error surface every exam screen uses — a soft red strip with the
/// server's plain-language message, never a raw stack trace.
Widget examErrorBox(BuildContext context, String message) {
  final colors = context.colors;
  return Container(
    padding: const EdgeInsets.all(GochanoSpacing.sm),
    decoration: BoxDecoration(
      color: colors.errorSoft,
      borderRadius: GochanoRadius.mdAll,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.error_outline_rounded,
          size: GochanoSizes.iconSm,
          color: colors.error,
        ),
        const SizedBox(width: GochanoSpacing.xs),
        Expanded(
          child: Text(message, style: context.type.body),
        ),
      ],
    ),
  );
}

Widget examLoading(String message) => StaticLoadingState(message: message);

/// A big, tappable choice row used for the question source and the on/off
/// settings — the app does not use Material switches or radios anywhere.
class ExamChoiceTile extends StatelessWidget {
  const ExamChoiceTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tone = accent ?? colors.brand;

    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: GochanoRadius.mdAll,
        child: Container(
          padding: const EdgeInsets.all(GochanoSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? tone.withValues(alpha: 0.12) : colors.surface,
            borderRadius: GochanoRadius.mdAll,
            border: Border.all(
              color: selected ? tone : colors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: GochanoSizes.iconMd,
                color: selected ? tone : colors.textTertiary,
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.type.body),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: context.type.caption),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One "label / value" line of the score summary.
class ExamStatLine extends StatelessWidget {
  const ExamStatLine({
    super.key,
    required this.label,
    required this.value,
    this.tone,
  });

  final String label;
  final String value;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GochanoSpacing.xxs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: context.type.bodySecondary)),
          Text(
            value,
            style: context.type.body.copyWith(
              color: tone,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
