import 'package:flutter/material.dart';

import 'adaptive_api_service.dart';

class RevisionQueueScreen extends StatelessWidget {
  const RevisionQueueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Today's Revision Queue")),
      body: FutureBuilder<Map<String, dynamic>>(
        future: AdaptiveApiService.revisionQueue(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final items = (snapshot.data?['items'] as List?) ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('Nothing is due today.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(),
            itemBuilder: (context, index) {
              final item = Map<String, dynamic>.from(items[index] as Map);
              final reasons = (item['reason'] as List?)?.join(' • ') ?? '';
              return ListTile(
                leading: CircleAvatar(
                  child: Text('${item['priority'] ?? index + 1}'),
                ),
                title: Text(item['topic']?.toString() ?? 'Topic'),
                subtitle: Text(reasons),
              );
            },
          );
        },
      ),
    );
  }
}
