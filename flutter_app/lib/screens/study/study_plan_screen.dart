import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/api_service.dart';

class StudyPlanScreen extends StatefulWidget {
  const StudyPlanScreen({super.key});

  @override
  State<StudyPlanScreen> createState() => _StudyPlanScreenState();
}

class _StudyPlanScreenState extends State<StudyPlanScreen> {
  List<dynamic>? items;
  bool busy = false;

  Future<void> load() async {
    setState(() => busy = true);
    try {
      items = await ApiService.studyPlan();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Study plan')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.auto_graph),
                title: const Text('Deadline-based study plan'),
                subtitle: const Text(
                  'EkThikana ranks your unfinished tasks by deadline urgency. This is planning, not question generation.',
                ),
                trailing: FilledButton(
                  onPressed: busy ? null : load,
                  child: Text(busy ? 'Loading…' : 'Build'),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: items == null
                  ? const Center(child: Text('Tap Build to create a plan from your tasks.'))
                  : items!.isEmpty
                      ? const Center(child: Text('No unfinished tasks found.'))
                      : ListView.builder(
                          itemCount: items!.length,
                          itemBuilder: (context, i) {
                            final item = items![i] as Map<String, dynamic>;
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(child: Text('${i + 1}')),
                                title: Text(item['title']?.toString() ?? ''),
                                subtitle: Text(item['dueAt']?.toString() ?? 'No deadline'),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
