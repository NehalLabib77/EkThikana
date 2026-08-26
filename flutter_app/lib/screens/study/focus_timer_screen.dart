import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/study_service.dart';

class FocusTimerScreen extends StatefulWidget {
  const FocusTimerScreen({super.key});

  @override
  State<FocusTimerScreen> createState() => _FocusTimerScreenState();
}

class _FocusTimerScreenState extends State<FocusTimerScreen> {
  FocusSession? _session;
  int _baselineElapsed = 0;
  DateTime? _resumedAt;
  Timer? _ticker;
  bool _busy = false;
  String _status = 'idle';

  final TextEditingController _label = TextEditingController();
  int _plannedMinutes = 25;

  @override
  void dispose() {
    _ticker?.cancel();
    _label.dispose();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  int get _displaySeconds {
    if (_session == null || _resumedAt == null) return _baselineElapsed;
    final delta = DateTime.now().difference(_resumedAt!).inSeconds;
    return _baselineElapsed + (delta < 0 ? 0 : delta);
  }

  String get _displayClock {
    final s = _displaySeconds;
    final mm = (s ~/ 60).toString().padLeft(2, '0');
    final ss = (s % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final session = await StudyService.start(
        label: _label.text.trim(),
        plannedMinutes: _plannedMinutes,
      );
      setState(() {
        _session = session;
        _baselineElapsed = session.elapsedSeconds;
        _resumedAt = DateTime.now();
        _status = 'running';
      });
      _startTicker();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _patch(String action) async {
    final s = _session;
    if (s == null) return;
    setState(() => _busy = true);
    try {
      final updated = await StudyService.patch(s.id, action);
      setState(() {
        _session = updated;
        if (action == 'pause') {
          _baselineElapsed = updated.elapsedSeconds;
          _resumedAt = null;
          _status = 'paused';
        } else if (action == 'resume') {
          _baselineElapsed = updated.elapsedSeconds;
          _resumedAt = DateTime.now();
          _status = 'running';
        } else if (action == 'complete' || action == 'cancel') {
          _baselineElapsed = updated.elapsedSeconds;
          _resumedAt = null;
          _status = action;
          _ticker?.cancel();
        }
      });
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Focus Timer')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _displayClock,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            if (_session == null) ...[
              TextField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'What are you focusing on?'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Planned minutes'),
                  Expanded(
                    child: Slider(
                      value: _plannedMinutes.toDouble(),
                      min: 5,
                      max: 90,
                      divisions: 17,
                      label: '$_plannedMinutes',
                      onChanged: (v) =>
                          setState(() => _plannedMinutes = v.round()),
                    ),
                  ),
                  SizedBox(width: 36, child: Text('$_plannedMinutes')),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _start,
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Start focus session'),
                ),
              ),
            ] else ...[
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _patch(_status == 'running' ? 'pause' : 'resume'),
                child: Text(_status == 'running' ? 'Pause' : 'Resume'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _busy ? null : () => _patch('complete'),
                child: const Text('Complete'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => _patch('cancel'),
                child: const Text('Cancel'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
