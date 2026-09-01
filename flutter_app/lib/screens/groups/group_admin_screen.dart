import 'package:flutter/material.dart';

import '../../core/ui.dart';
import '../../services/api_service.dart';

class GroupAdminScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  const GroupAdminScreen({super.key, required this.groupId, required this.groupName});

  @override
  State<GroupAdminScreen> createState() => _GroupAdminScreenState();
}

class _GroupAdminScreenState extends State<GroupAdminScreen> {
  bool? _chatEnabled;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadChatStatus();
  }

  Future<void> _loadChatStatus() async {
    try {
      final res = await ApiService.getGroupChat(widget.groupId, limit: 1);
      final enabled = (res['enabled'] ?? res['chat_enabled'] ?? res['chatEnabled']) == true;
      if (!mounted) return;
      setState(() => _chatEnabled = enabled);
    } catch (e) {
      // not fatal — backend may not yet support chat toggles for every group
      if (mounted) setState(() => _chatEnabled = true);
    }
  }

  Future<void> _setChat(bool enabled) async {
    setState(() => _busy = true);
    try {
      await ApiService.setGroupChatEnabled(widget.groupId, enabled);
      if (!mounted) return;
      setState(() => _chatEnabled = enabled);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Admin · ${widget.groupName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: SwitchListTile(
              title: const Text('Group chat'),
              subtitle: const Text('Allow members to post messages in this group.'),
              value: _chatEnabled ?? true,
              onChanged: _busy ? null : _setChat,
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'Only group admins can change these settings. Chat history is preserved when chat is disabled.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        ],
      ),
    );
  }
}
