import 'package:flutter/material.dart';

import 'content_api_service.dart';

class FlashcardScreen extends StatefulWidget {
  const FlashcardScreen({super.key});

  @override
  State<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends State<FlashcardScreen> {
  final _topic = TextEditingController();
  final _source = TextEditingController();
  Future<Map<String, dynamic>>? _request;

  @override
  void dispose() {
    _topic.dispose();
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My AI Flashcards')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _topic,
            decoration: const InputDecoration(labelText: 'Topic'),
          ),
          TextField(
            controller: _source,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notes or textbook content',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => setState(
              () => _request = ContentApiService.flashcards(
                topic: _topic.text.trim(),
                sourceText: _source.text.trim(),
              ),
            ),
            child: const Text('Generate cards'),
          ),
          if (_request != null)
            FutureBuilder<Map<String, dynamic>>(
              future: _request,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.hasError) return Text(snapshot.error.toString());
                final cards =
                    (snapshot.data?['generatedContent'] as Map?)?['flashcards']
                        as List? ??
                    const [];
                return Column(
                  children: [
                    for (final card in cards)
                      Card(
                        child: ListTile(
                          title: Text(
                            (card as Map)['question']?.toString() ?? '',
                          ),
                          subtitle: Text((card['answer'] ?? '').toString()),
                          trailing: Text((card['reviewDate'] ?? '').toString()),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
