import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/firestore_service.dart';
import '../../services/study_service.dart';

class StudyStatsScreen extends StatefulWidget {
  const StudyStatsScreen({super.key});

  @override
  State<StudyStatsScreen> createState() => _StudyStatsScreenState();
}

class _StudyStatsScreenState extends State<StudyStatsScreen> {
  StudyStats? _stats;
  bool _loading = true;
  int _completedTaskCount = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final s = await StudyService.stats();
      final user = FirebaseAuth.instance.currentUser;
      final tasksSnap = user == null
          ? null
          : await FirestoreService.db
              .collection('tasks')
              .where('ownerId', isEqualTo: user.uid)
              .get();
      final count = tasksSnap == null
          ? 0
          : tasksSnap.docs
              .where((d) => (d.data()['completed'] as bool?) == true)
              .length;
      if (!mounted) return;
      setState(() {
        _stats = s;
        _completedTaskCount = count;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        showError(context, e);
        setState(() => _loading = false);
      }
    }
  }

  String _fmt(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Study Stats'),
        actions: [
          IconButton(onPressed: _loading ? null : _refresh, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _stats == null
              ? const Center(child: Text('No stats yet.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _tile('Today', _fmt(_stats!.todaySeconds)),
                    _tile('This month', _fmt(_stats!.monthSeconds)),
                    _tile('Streak', '${_stats!.streakDays} day${_stats!.streakDays == 1 ? '' : 's'}'),
                    _tile('Completed tasks', '$_completedTaskCount'),
                  ],
                ),
    );
  }

  Widget _tile(String label, String value) {
    return Card(
      child: ListTile(
        title: Text(label),
        trailing: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
