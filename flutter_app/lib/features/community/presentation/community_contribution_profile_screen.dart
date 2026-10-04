import 'package:flutter/material.dart';

import 'community_intelligence_api_service.dart';

class CommunityContributionProfileScreen extends StatelessWidget {
  const CommunityContributionProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contribution Profile')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: CommunityIntelligenceApiService.leaderboard(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text(snapshot.error.toString()));
          }
          final entries =
              (snapshot.data?['entries'] as List?) ??
              (snapshot.data?['leaderboard'] as List?) ??
              const [];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Card(
                child: ListTile(
                  title: Text('Learning contribution'),
                  subtitle: Text(
                    'Points come from helpful answers, accepted solutions, useful notes and quizzes.',
                  ),
                ),
              ),
              for (final raw in entries.take(20))
                ListTile(
                  leading: CircleAvatar(
                    child: Text('${(raw as Map)['rank'] ?? ''}'),
                  ),
                  title: Text(
                    (raw['displayName'] ?? raw['name'] ?? 'Student').toString(),
                  ),
                  trailing: Text('${raw['points'] ?? 0} points'),
                ),
            ],
          );
        },
      ),
    );
  }
}
