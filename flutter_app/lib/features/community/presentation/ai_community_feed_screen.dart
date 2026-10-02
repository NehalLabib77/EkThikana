import 'package:flutter/material.dart';

import 'community_intelligence_api_service.dart';
import 'community_contribution_profile_screen.dart';

class AiCommunityFeedScreen extends StatefulWidget {
  const AiCommunityFeedScreen({super.key});

  @override
  State<AiCommunityFeedScreen> createState() => _AiCommunityFeedScreenState();
}

class _AiCommunityFeedScreenState extends State<AiCommunityFeedScreen> {
  late Future<Map<String, dynamic>> _feed;

  @override
  void initState() {
    super.initState();
    _feed = CommunityIntelligenceApiService.feed();
  }

  Future<void> _askQuestion() async {
    final title = TextEditingController();
    final body = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ask the learning community'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Question title'),
            ),
            TextField(
              controller: body,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Explain what you are stuck on',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Post question'),
          ),
        ],
      ),
    );
    if (submitted != true ||
        title.text.trim().isEmpty && body.text.trim().isEmpty) {
      return;
    }
    await CommunityIntelligenceApiService.askQuestion(
      title: title.text.trim(),
      body: body.text.trim(),
    );
    if (mounted) setState(() => _feed = CommunityIntelligenceApiService.feed());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Community Feed'),
        actions: [
          IconButton(
            onPressed: _askQuestion,
            icon: const Icon(Icons.add_comment_outlined),
            tooltip: 'Ask the community',
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CommunityContributionProfileScreen(),
              ),
            ),
            icon: const Icon(Icons.workspace_premium_outlined),
            tooltip: 'Contribution profile',
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _feed,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final posts = (snapshot.data?['posts'] as List?) ?? const [];
          if (posts.isEmpty) {
            return const Center(child: Text('No learning posts yet.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: posts.length,
            itemBuilder: (context, index) {
              final post = Map<String, dynamic>.from(posts[index] as Map);
              return Card(
                child: ListTile(
                  title: Text(
                    post['title']?.toString().isNotEmpty == true
                        ? post['title'].toString()
                        : post['body'].toString(),
                  ),
                  subtitle: Text(
                    '${post['subject'] ?? 'General'} • ${post['chapter'] ?? 'General'} • ${post['difficulty'] ?? 'medium'}\n${post['relatedToYourLearning'] == true ? 'Related to your learning' : 'Community learning'}',
                  ),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
