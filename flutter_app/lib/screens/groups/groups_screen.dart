import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import 'group_detail_screen.dart';

class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key});

  Future<void> _createGroup(BuildContext context) async {
    final name = TextEditingController();
    final description = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create study group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: description,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 10),
            const Text(
              'Gochano groups have no chat. They are only for organized shared study materials.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (ok != true || name.text.trim().length < 2) {
      name.dispose();
      description.dispose();
      return;
    }

    try {
      final result = await ApiService.createGroup(
        name.text.trim(),
        description.text.trim(),
      );

      if (context.mounted) {
        final code = result['inviteCode']?.toString() ?? '';
        await showDialog<void>(
          context: context,
          builder: (d) => AlertDialog(
            title: const Text('Group created'),
            content: SelectableText(
              'Invite code: $code\n\nShare this code only with students you want inside the group.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(d),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    } finally {
      name.dispose();
      description.dispose();
    }
  }

  Future<void> _joinGroup(BuildContext context) async {
    final code = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join study group'),
        content: TextField(
          controller: code,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Invite code'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Join'),
          ),
        ],
      ),
    );

    if (ok != true || code.text.trim().isEmpty) {
      code.dispose();
      return;
    }

    try {
      await ApiService.joinGroup(code.text.trim().toUpperCase());
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You joined the group.')),
        );
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    } finally {
      code.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Study groups'),
        actions: [
          IconButton(
            tooltip: 'Join with invite code',
            onPressed: () => _joinGroup(context),
            icon: const Icon(Icons.group_add_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createGroup(context),
        icon: const Icon(Icons.add),
        label: const Text('Group'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.myGroups(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final groups = snap.data!.docs;
          if (groups.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No study groups yet.\nCreate one or join with an invite code.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final doc = groups[i];
              final data = doc.data();
              return Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  leading: const CircleAvatar(
                    child: Icon(Icons.groups_outlined),
                  ),
                  title: Text(
                    data['name']?.toString() ?? 'Study group',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '${data['memberCount'] ?? (data['memberIds'] as List?)?.length ?? 1} members'
                    '${(data['description']?.toString() ?? '').trim().isEmpty ? '' : ' • ${data['description']}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupDetailScreen(
                        groupId: doc.id,
                        group: data,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
