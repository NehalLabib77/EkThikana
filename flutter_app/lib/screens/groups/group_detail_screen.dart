import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/api_service.dart';
import '../../services/firestore_service.dart';
import '../study/materials_screen.dart';
import '../study/notes_screen.dart';
import 'group_chat_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({
    super.key,
    required this.groupId,
    required this.group,
  });

  final String groupId;
  final Map<String, dynamic> group;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  late Map<String, dynamic> group;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    group = {...widget.group};
  }

  bool get _isAdmin {
    final raw = group['adminIds'];
    if (raw is List && raw.contains(FirestoreService.uid)) return true;
    return group['adminId']?.toString() == FirestoreService.uid;
  }

  bool get _chatEnabled => group['chatEnabled'] == true;

  Future<void> leave() async {
    final ok = await confirmAction(
      context,
      title: 'Leave this study group?',
      message:
          'You will lose access to its Shared Box, group notes and chat. '
          'Materials you saved to your private library remain saved references while still accessible.',
      action: 'Leave',
    );
    if (!ok) return;

    setState(() => busy = true);
    try {
      await ApiService.leaveGroup(widget.groupId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetInvite() async {
    final ok = await confirmAction(
      context,
      title: 'Reset invite code?',
      message: 'The old invite code will stop working.',
      action: 'Reset',
    );
    if (!ok) return;

    setState(() => busy = true);
    try {
      final code = await ApiService.resetGroupInvite(widget.groupId);
      if (!mounted) return;
      setState(() => group['inviteCode'] = code);
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('New invite code'),
          content: SelectableText(code),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(d),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> toggleChat(bool enabled) async {
    final previous = _chatEnabled;
    setState(() {
      group['chatEnabled'] = enabled;
      busy = true;
    });
    try {
      await ApiService.setGroupChatEnabled(widget.groupId, enabled);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled ? 'Group chat enabled.' : 'Group chat disabled.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => group['chatEnabled'] = previous);
      showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = group['name']?.toString() ?? 'Study group';
    final description = group['description']?.toString() ?? '';
    final inviteCode = group['inviteCode']?.toString() ?? '';
    final members = (group['memberIds'] as List?)?.length ??
        group['memberCount'] ??
        1;

    return Scaffold(
      appBar: AppBar(
        title: Text(name),
        actions: [
          PopupMenuButton<String>(
            enabled: !busy,
            onSelected: (value) {
              if (value == 'reset') {
                resetInvite();
              } else if (value == 'leave') {
                leave();
              }
            },
            itemBuilder: (_) => [
              if (_isAdmin)
                const PopupMenuItem(
                  value: 'reset',
                  child: Text('Reset invite code'),
                ),
              const PopupMenuItem(
                value: 'leave',
                child: Text('Leave group'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (description.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(description),
                  ],
                  const SizedBox(height: 12),
                  Text('$members members'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text('Invite code: '),
                      Expanded(
                        child: SelectableText(
                          inviteCode,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_isAdmin) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Group chat',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    _chatEnabled
                        ? 'Members can post text and attachments in the chat.'
                        : 'Chat is disabled. Enable it to let members post messages.',
                  ),
                  value: _chatEnabled,
                  onChanged: busy ? null : toggleChat,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              leading: const CircleAvatar(
                child: Icon(Icons.inventory_2_outlined),
              ),
              title: const Text(
                'Shared Box',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'PDFs, images and Office docs shared by group members.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MaterialsScreen(
                    groupId: widget.groupId,
                    groupName: name,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              leading: const CircleAvatar(
                child: Icon(Icons.note_alt_outlined),
              ),
              title: const Text(
                'Shared notes',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Combined text notes visible to group members.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NotesScreen(
                    groupId: widget.groupId,
                    groupName: name,
                  ),
                ),
              ),
            ),
          ),
          if (_chatEnabled) ...[
            const SizedBox(height: 10),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 10,
                ),
                leading: const CircleAvatar(
                  child: Icon(Icons.chat_bubble_outline),
                ),
                title: const Text(
                  'Group chat',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Text and attachments shared with the group.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GroupChatScreen(
                      groupId: widget.groupId,
                      groupName: name,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
