import 'package:flutter/material.dart';

import 'adaptive_api_service.dart';

class AiTextbookScreen extends StatelessWidget {
  const AiTextbookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My AI Textbook')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: AdaptiveApiService.textbook(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final chapters = (snapshot.data?['chapters'] as List?) ?? const [];
          if (chapters.isEmpty) {
            return const Center(
              child: Text('Your textbook will grow as you practice.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final raw in chapters)
                Card(
                  child: ExpansionTile(
                    title: Text(
                      (raw as Map)['chapter']?.toString() ?? 'Chapter',
                    ),
                    children: [
                      ListTile(
                        title: Text(
                          'Correction: ${(raw['correction'] ?? '').toString()}',
                        ),
                      ),
                      for (final error
                          in ((raw['yourMistakes'] as List?) ?? const []))
                        ListTile(
                          leading: const Icon(Icons.error_outline),
                          title: Text(error.toString()),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
