import 'package:flutter/material.dart';

import 'content_api_service.dart';

class AiTeacherScreen extends StatefulWidget {
  const AiTeacherScreen({super.key});

  @override
  State<AiTeacherScreen> createState() => _AiTeacherScreenState();
}

class _AiTeacherScreenState extends State<AiTeacherScreen> {
  final _topic = TextEditingController();
  final _source = TextEditingController();
  Future<Map<String, dynamic>>? _request;

  @override
  void dispose() {
    _topic.dispose();
    _source.dispose();
    super.dispose();
  }

  void _ask() {
    if (_topic.text.trim().isEmpty) return;
    setState(
      () => _request = ContentApiService.explain(
        topic: _topic.text.trim(),
        sourceText: _source.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ask Ziku')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _topic,
            decoration: const InputDecoration(labelText: 'Explain any topic'),
          ),
          TextField(
            controller: _source,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Paste notes (optional)',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _ask,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Teach me'),
          ),
          if (_request != null)
            FutureBuilder<Map<String, dynamic>>(
              future: _request,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.hasError) return Text(snapshot.error.toString());
                final result = snapshot.data ?? {};
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          result['simpleExplanation']?.toString() ?? '',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        Text('Analogy: ${result['analogy'] ?? ''}'),
                        Text('Formula: ${result['formula'] ?? ''}'),
                        Text('Example: ${result['example'] ?? ''}'),
                        Text('Practice: ${result['practiceQuestion'] ?? ''}'),
                      ],
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
