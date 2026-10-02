import 'package:flutter/material.dart';

import 'content_api_service.dart';

class RevisionSheetScreen extends StatefulWidget {
  const RevisionSheetScreen({super.key});

  @override
  State<RevisionSheetScreen> createState() => _RevisionSheetScreenState();
}

class _RevisionSheetScreenState extends State<RevisionSheetScreen> {
  final _topic = TextEditingController();
  Future<Map<String, dynamic>>? _request;

  @override
  void dispose() {
    _topic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Before Exam Revision Sheet')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _topic,
            decoration: const InputDecoration(labelText: 'Exam topic'),
          ),
          FilledButton(
            onPressed: () => setState(
              () => _request = ContentApiService.revisionSheet(
                topic: _topic.text.trim(),
              ),
            ),
            child: const Text('Generate revision sheet'),
          ),
          if (_request != null)
            FutureBuilder<Map<String, dynamic>>(
              future: _request,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LinearProgressIndicator();
                }
                if (snapshot.hasError) return Text(snapshot.error.toString());
                final sheet = snapshot.data?['generatedContent'] as Map? ?? {};
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      sheet.entries
                          .map((entry) => '${entry.key}: ${entry.value}')
                          .join('\n\n'),
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
