import 'package:flutter/material.dart';

import 'content_api_service.dart';

class StudyPackScreen extends StatefulWidget {
  const StudyPackScreen({super.key});

  @override
  State<StudyPackScreen> createState() => _StudyPackScreenState();
}

class _StudyPackScreenState extends State<StudyPackScreen> {
  final _topic = TextEditingController();
  final _source = TextEditingController();
  final _materialId = TextEditingController();
  Future<Map<String, dynamic>>? _request;

  @override
  void dispose() {
    _topic.dispose();
    _source.dispose();
    _materialId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Complete Study Pack')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Use an existing uploaded PDF/material or paste lecture notes.',
          ),
          TextField(
            controller: _topic,
            decoration: const InputDecoration(labelText: 'Topic'),
          ),
          TextField(
            controller: _materialId,
            decoration: const InputDecoration(
              labelText: 'Uploaded material ID (optional)',
            ),
          ),
          TextField(
            controller: _source,
            maxLines: 5,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          FilledButton.icon(
            onPressed: () => setState(
              () => _request = ContentApiService.studyPack(
                topic: _topic.text.trim(),
                sourceText: _source.text.trim(),
                materialId: _materialId.text.trim(),
              ),
            ),
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Generate study pack'),
          ),
          if (_request != null)
            FutureBuilder<Map<String, dynamic>>(
              future: _request,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.hasError) return Text(snapshot.error.toString());
                final pack = snapshot.data?['generatedContent'] as Map? ?? {};
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      pack.keys.map((key) => key.toString()).join(' • '),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
