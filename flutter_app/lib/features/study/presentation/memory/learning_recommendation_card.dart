import 'package:flutter/material.dart';

import 'learning_api_service.dart';
import 'learning_memory_screen.dart';

class LearningRecommendationCard extends StatelessWidget {
  const LearningRecommendationCard({
    super.key,
    this.initialData,
  });

  /// Optional preloaded bootstrap data from consolidated Home startup.
  final Map<String, dynamic>? initialData;

  @override
  Widget build(BuildContext context) {
    if (initialData != null) {
      if (initialData!['available'] == false) {
        return const SizedBox.shrink();
      }
      return _buildCard(context, initialData!);
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: LearningApiService.recommendations(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(child: LinearProgressIndicator());
        }
        if (snapshot.hasError) {
          return const SizedBox.shrink();
        }
        final data = snapshot.data;
        if (data == null) return const SizedBox.shrink();
        return _buildCard(context, data);
      },
    );
  }

  Widget _buildCard(BuildContext context, Map<String, dynamic> data) {
    final items = (data['items'] as List?) ?? const [];
    if (items.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ziku Suggests',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final raw in items.take(3))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline),
                title: Text(
                  (raw as Map)['title']?.toString() ?? 'Study next',
                ),
                subtitle: Text((raw['reason'] ?? '').toString()),
              ),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LearningMemoryScreen(),
                ),
              ),
              icon: const Icon(Icons.insights_outlined),
              label: const Text('View learning profile'),
            ),
          ],
        ),
      ),
    );
  }
}
