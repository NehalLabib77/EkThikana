import 'package:flutter/material.dart';

import 'adaptive_api_service.dart';

class AdaptiveDashboardScreen extends StatefulWidget {
  const AdaptiveDashboardScreen({super.key});

  @override
  State<AdaptiveDashboardScreen> createState() =>
      _AdaptiveDashboardScreenState();
}

class _AdaptiveDashboardScreenState extends State<AdaptiveDashboardScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = AdaptiveApiService.curriculum();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Today's Adaptive Plan")),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final items = (snapshot.data?['items'] as List?) ?? const [];
          if (items.isEmpty) {
            return const Center(child: Text('No adaptive plan yet.'));
          }
          return RefreshIndicator(
            onRefresh: () async =>
                setState(() => _future = AdaptiveApiService.curriculum()),
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = Map<String, dynamic>.from(items[index] as Map);
                return Card(
                  child: ListTile(
                    title: Text(item['topic']?.toString() ?? 'Topic'),
                    subtitle: Text(item['reason']?.toString() ?? 'Weak area'),
                    trailing: Text('${item['totalMinutes'] ?? 0} min'),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
