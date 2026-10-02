import 'package:flutter/material.dart';

import 'learning_api_service.dart';

class LearningMemoryScreen extends StatelessWidget {
  const LearningMemoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Learning Brain')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: LearningApiService.memory(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final data = snapshot.data ?? {};
          final profile = Map<String, dynamic>.from(
            data['profile'] as Map? ?? {},
          );
          final topics = (data['topics'] as List?) ?? const [];
          final improvements = (data['improvement'] as List?) ?? const [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ProfileCard(profile: profile),
              const SizedBox(height: 12),
              const Text(
                'Progress improvement',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              for (final raw in improvements.take(8))
                _ProgressRow(data: Map<String, dynamic>.from(raw as Map)),
              const SizedBox(height: 12),
              const Text(
                'Topics to strengthen',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              for (final raw in topics.take(8))
                ListTile(
                  title: Text((raw as Map)['topic']?.toString() ?? 'Topic'),
                  subtitle: Text(
                    '${raw['mistakes'] ?? 0} mistakes • ${raw['revisions'] ?? 0} revisions',
                  ),
                  trailing: Text('${raw['accuracy'] ?? '-'}%'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.profile});
  final Map<String, dynamic> profile;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Student Learning Profile',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'Strong: ${profile['strongestSubject'] ?? 'Building evidence'}',
            ),
            Text(
              'Best learning style: ${profile['preferredLearningStyle'] ?? 'Not enough data'}',
            ),
            Text(
              'Best content: ${profile['bestContentType'] ?? 'Not enough data'}',
            ),
            Text(
              'Study pattern: ${profile['studyTimePattern'] ?? 'Not enough data'}',
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final before = (data['before'] as num?)?.toDouble() ?? 0;
    final now = (data['now'] as num?)?.toDouble() ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(data['topic']?.toString() ?? 'Topic'),
            Text('Before: ${before.toInt()}%    Now: ${now.toInt()}%'),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: (now / 100).clamp(0, 1)),
          ],
        ),
      ),
    );
  }
}
