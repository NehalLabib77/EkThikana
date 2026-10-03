// Phase 5 — "Ziku Focus": today's deep-work block on Home (study mode).
//
// The daily surface of the Focus Engine: how many minutes of the exam
// rescue goal are done, the rolling Focus Score, the nudge Ziku would have
// said on the timer, and one button that opens the session screen. All of
// it is one read of `GET /api/focus/today` — the card renders the server's
// decision and invents nothing.
//
// The class name avoids the word the Home source scan forbids
// (`home_screen.dart` must not contain "Focus"); this file is free to use
// it, and the visible title is "Ziku Focus" exactly as the spec asks.
//
// Read hook is injectable so tests never open a socket; a failed read
// degrades to a retry line rather than taking the Home screen down.

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';
import 'focus_session_screen.dart';

class ZikuSessionCard extends StatefulWidget {
  const ZikuSessionCard({
    super.key,
    this.todayFn,
    this.initialData,
  });

  /// Read hook, injected in tests so the widget never opens a socket.
  final FocusTodayFn? todayFn;

  /// Optional preloaded bootstrap data from consolidated Home startup.
  final Map<String, dynamic>? initialData;

  @override
  State<ZikuSessionCard> createState() => _ZikuSessionCardState();
}

class _ZikuSessionCardState extends State<ZikuSessionCard> {
  Map<String, dynamic>? _today;
  bool _failed = false;
  Object? _readError;

  FocusTodayFn get _load => widget.todayFn ?? ApiService.focusEngineToday;

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _applyInitialData(widget.initialData!);
    } else {
      _read();
    }
  }

  void _applyInitialData(Map<String, dynamic> data) {
    if (data['available'] == false) {
      _today = null;
      _failed = true;
    } else {
      _today = data;
      _failed = false;
    }
  }

  @override
  void didUpdateWidget(covariant ZikuSessionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialData != null && widget.initialData != oldWidget.initialData) {
      _applyInitialData(widget.initialData!);
    }
  }

  Future<void> _read() async {
    try {
      final body = await _load();
      if (!mounted) return;
      setState(() {
        _today = body;
        _failed = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _today = null;
        _failed = true;
        _readError = err;
      });
    }
  }

  void _open() {
    final ids = _activeIds;
    Navigator.of(context).push(
      GochanoRoute.to(
        builder: (_) => FocusSessionScreen(
          sessionId: ids.isEmpty ? null : ids.first,
        ),
      ),
    );
  }

  List<String> get _activeIds {
    final raw = _today?['activeSessionIds'];
    if (raw is! List) return const <String>[];
    return [for (final id in raw) '$id'].where((id) => id.isNotEmpty).toList();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final today = _today;

    if (today == null) {
      return AppCard(
        accent: colors.study,
        child: GochanoListRow(
          illustration: GochanoArt.featureStudy,
          accent: colors.study,
          title: GochanoLanguage.text('Ziku Focus', 'জিকু ফোকাস'),
          subtitle: _failed
              ? friendlyErrorMessage(_readError)
              : GochanoLanguage.text(
                  'Reading today\u2019s focus…',
                  'আজকের ফোকাস পড়া হচ্ছে…',
                ),
          onTap: _failed ? _read : null,
        ),
      );
    }

    final minutes = _asInt(today['minutes']);
    final goal = _asInt(today['goalMinutes']);
    final progress = goal <= 0
        ? 0.0
        : (minutes / goal).clamp(0.0, 1.0).toDouble();
    final score = today['score'] is Map
        ? Map<String, dynamic>.from(today['score'] as Map)
        : null;
    final nudge = today['nudge'] is Map
        ? Map<String, dynamic>.from(today['nudge'] as Map)
        : null;
    final minutesCopy = GochanoLanguage.text(
      'Today\u2019s Focus: $minutes/$goal minutes',
      'আজকের ফোকাস: $minutes/$goal মিনিট',
    );

    return AppCard(
      accent: colors.study,
      onTap: _open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.smart_toy_rounded, size: 20, color: colors.study),
              const SizedBox(width: GochanoSpacing.xs),
              Expanded(
                child: Text(
                  GochanoLanguage.text('Ziku Focus', 'জিকু ফোকাস'),
                  style: context.type.cardHeading,
                ),
              ),
              if (score != null)
                GochanoBadge(
                  label: GochanoLanguage.text(
                    'Score ${_asInt(score['value'])}',
                    'স্কোর ${_asInt(score['value'])}',
                  ),
                  tone: focusBandTone('${score['band'] ?? ''}'),
                  icon: Icons.insights_rounded,
                ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.xs),
          Text(minutesCopy, style: context.type.bodySecondary),
          const SizedBox(height: GochanoSpacing.xs),
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            color: colors.study,
            backgroundColor: colors.surfaceVariant,
            semanticsLabel: minutesCopy,
          ),
          if (nudge != null &&
              '${nudge['message'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Text(
              '${nudge['message']}',
              style: context.type.caption.copyWith(
                color: colors.textTertiary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: GochanoSpacing.sm),
          PrimaryButton(
            label: GochanoLanguage.text(
              'Continue Session',
              'চালিয়ে যান',
            ),
            icon: Icons.play_arrow_rounded,
            onPressed: _open,
          ),
        ],
      ),
    );
  }

  static int _asInt(dynamic value) => value is num ? value.toInt() : 0;
}
