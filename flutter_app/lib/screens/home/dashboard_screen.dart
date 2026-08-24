import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/ui.dart';
import '../../services/api_service.dart';
import '../search/universal_search_screen.dart';
import '../tasks/tasks_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.role,
    required this.displayName,
  });

  final String role;
  final String displayName;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String backendStatus = 'Not checked';

  Future<void> checkBackend() async {
    setState(() => backendStatus = 'Connecting…');
    try {
      await ApiService.health();
      if (mounted) setState(() => backendStatus = 'Connected');
    } catch (e) {
      if (mounted) {
        setState(() => backendStatus = 'Unavailable');
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = widget.role == 'student';
    final name = widget.displayName.trim().isEmpty ? 'there' : widget.displayName.split(' ').first;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: [
          IconButton(
            tooltip: 'Search',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => UniversalSearchScreen(student: student)),
            ),
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text(
            'Welcome, $name',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(student ? 'Your study and everyday life, together.' : 'Your everyday life, organized.'),
          const SizedBox(height: 20),
          _HeroCard(
            title: student ? 'Student workspace' : 'Personal workspace',
            subtitle: student
                ? 'Study, shared materials, tasks and daily life.'
                : 'Tasks, medicine, shopping, family, rent, commute and wellness.',
            icon: student ? Icons.school_outlined : Icons.home_work_outlined,
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_outlined),
              title: const Text('Render API'),
              subtitle: Text(backendStatus),
              trailing: TextButton(
                onPressed: checkBackend,
                child: const Text('Check'),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.task_alt),
              title: const Text('Tasks & reminders'),
              subtitle: const Text('Manage deadlines and daily responsibilities.'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TasksScreen()),
              ),
            ),
          ),
          if (student) ...[
            const SizedBox(height: 12),
            const Card(
              child: ListTile(
                leading: Icon(Icons.verified_user_outlined),
                title: Text('Sharing model'),
                subtitle: Text('Private by default. Share with a group or publish to Student Community when you choose.'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            CircleAvatar(radius: 28, child: Icon(icon, size: 30)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Text(subtitle),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
