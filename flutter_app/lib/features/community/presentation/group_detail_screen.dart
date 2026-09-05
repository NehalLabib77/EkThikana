// Study group — Overview / Resources / Chat / Projects (spec §42, §43).
//
// Four tabs rather than one overloaded screen. Each maps to a real backend
// surface:
//
//   Overview   the `groups/{id}` document: name, description, invite code,
//              and members with nicknames.
//   Resources  `materials` where groupId == this group and visibility ==
//              'group'. Uploading goes through the same authenticated
//              /api/materials/upload the private library uses, so the
//              per-user quota and the file-type check are identical
//              (spec §45).
//   Chat       GET/POST /api/groups/{id}/chat. Both are member-only and the
//              POST additionally requires chatEnabled — a non-member gets a
//              403 from the server, not just a hidden button (spec §44).
//   Projects   `groups/{id}/projects` subcollection: project cards with
//              task progress, admin controls, assignment, and reminders.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_illustration.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../services/api_service.dart';
import '../../../services/firestore_service.dart';
import '../../../services/notification_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../../study/presentation/materials/material_reader_screen.dart';
import '../../study/presentation/materials/material_upload_screen.dart';
import '../../study/presentation/notes/note_editor_screen.dart';
import 'group_chat_view.dart';

class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.db
          .collection('groups')
          .doc(widget.groupId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? const <String, dynamic>{};
        final name = data['name']?.toString() ?? widget.groupName;
        final memberIds = ((data['memberIds'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList();
        final adminIds = ((data['adminIds'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList();
        final chatEnabled = data['chatEnabled'] == true;
        final ownerId = data['ownerId']?.toString() ?? '';
        final currentUid = FirestoreService.uid;
        final isAdmin =
            currentUid != null &&
            (adminIds.contains(currentUid) ||
                (ownerId.isNotEmpty && ownerId == currentUid));

        return GochanoScaffold(
          padBody: false,
          appBar: GochanoAppBar(
            title: name,
            subtitle: GochanoLanguage.text(
              '${memberIds.length} members',
              '${memberIds.length} জন সদস্য',
            ),
            actions: [
              GochanoOverflowMenu(
                items: [
                  if (isAdmin)
                    GochanoMenuAction(
                      label: chatEnabled
                          ? GochanoLanguage.text('Turn chat off', 'চ্যাট বন্ধ')
                          : GochanoLanguage.text('Turn chat on', 'চ্যাট চালু'),
                      icon: chatEnabled
                          ? Icons.chat_bubble_outline_rounded
                          : Icons.chat_rounded,
                      onSelected: () => _toggleChat(context, !chatEnabled),
                    ),
                  if (isAdmin)
                    GochanoMenuAction(
                      label: GochanoLanguage.text(
                        'Reset invite code',
                        'ইনভাইট কোড রিসেট',
                      ),
                      icon: Icons.refresh_rounded,
                      onSelected: () => _resetInvite(context),
                    ),
                  GochanoMenuAction(
                    label: GochanoLanguage.text('Leave group', 'গ্রুপ ছাড়ুন'),
                    icon: Icons.logout_rounded,
                    destructive: true,
                    onSelected: () => _leave(context, name),
                  ),
                ],
              ),
            ],
            bottom: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: GochanoLanguage.text('Chat', 'চ্যাট')),
                Tab(text: GochanoLanguage.text('Projects', 'প্রজেক্ট')),
                Tab(text: GochanoLanguage.text('Resources', 'উপকরণ')),
                Tab(text: GochanoLanguage.text('Overview', 'সারাংশ')),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: [
              GroupChatView(
                groupId: widget.groupId,
                chatEnabled: chatEnabled,
                isAdmin: isAdmin,
              ),
              _ProjectsTab(
                groupId: widget.groupId,
                isAdmin: isAdmin,
                memberIds: memberIds,
                adminIds: adminIds,
              ),
              _ResourcesTab(groupId: widget.groupId, groupName: name),
              _OverviewTab(
                data: data,
                isAdmin: isAdmin,
                memberIds: memberIds,
                adminIds: adminIds,
                onOpenResources: () => _tabs.animateTo(2),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggleChat(BuildContext context, bool enabled) async {
    try {
      await ApiService.setGroupChatEnabled(widget.groupId, enabled);
    } catch (error) {
      if (context.mounted) {
        showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
      }
    }
  }

  Future<void> _resetInvite(BuildContext context) async {
    try {
      final code = await ApiService.resetGroupInvite(widget.groupId);
      if (!context.mounted) return;
      showGochanoMessage(
        context,
        GochanoLanguage.text(
          'New invite code: $code',
          'নতুন ইনভাইট কোড: $code',
        ),
      );
    } catch (error) {
      if (context.mounted) {
        showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
      }
    }
  }

  Future<void> _leave(BuildContext context, String name) async {
    final confirmed = await showConfirmationSheet(
      context,
      title: GochanoLanguage.text('Leave this group?', 'গ্রুপটি ছাড়বেন?'),
      message: GochanoLanguage.text(
        'You will lose access to "$name" resources and chat. Anything you '
            'shared stays with the group.',
        '"$name" এর উপকরণ ও চ্যাটে আপনার অ্যাক্সেস থাকবে না। আপনি যা শেয়ার করেছেন তা গ্রুপে থেকে যাবে।',
      ),
      confirmLabel: GochanoLanguage.text('Leave', 'ছাড়ুন'),
    );
    if (!confirmed || !context.mounted) return;
    try {
      await ApiService.leaveGroup(widget.groupId);
      if (context.mounted) Navigator.of(context).pop();
    } catch (error) {
      if (context.mounted) {
        showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.data,
    required this.isAdmin,
    required this.memberIds,
    required this.adminIds,
    required this.onOpenResources,
  });

  final Map<String, dynamic> data;
  final bool isAdmin;
  final List<String> memberIds;
  final List<String> adminIds;
  final VoidCallback onOpenResources;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final description = data['description']?.toString() ?? '';
    final inviteCode = data['inviteCode']?.toString() ?? '';

    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: [
        if (description.isNotEmpty) ...[
          AppCard(child: Text(description, style: context.type.body)),
          const SizedBox(height: GochanoSpacing.md),
        ],

        // The invite code is the whole joining mechanism, so it gets a
        // surface of its own rather than being buried in a menu.
        if (inviteCode.isNotEmpty)
          AppCard(
            accent: colors.community,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  GochanoLanguage.text('Invite code', 'ইনভাইট কোড'),
                  style: context.type.label,
                ),
                const SizedBox(height: GochanoSpacing.xxs),
                Row(
                  children: [
                    SelectableText(
                      inviteCode,
                      style: context.type.statistic.copyWith(letterSpacing: 4),
                    ),
                    const SizedBox(width: GochanoSpacing.xs),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      tooltip: GochanoLanguage.text('Copy code', 'কোড কপি'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: inviteCode));
                        showGochanoMessage(
                          context,
                          GochanoLanguage.text(
                            'Invite code copied!',
                            'ইনভাইট কোড কপি হয়েছে!',
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.xxs),
                Text(
                  GochanoLanguage.text(
                    'Share this with classmates so they can join.',
                    'সহপাঠীদের সাথে শেয়ার করুন যাতে তারা যোগ দিতে পারে।',
                  ),
                  style: context.type.caption,
                ),
              ],
            ),
          ),

        SectionHeader(
          title: GochanoLanguage.text('Shared resources', 'শেয়ার করা উপকরণ'),
          action: TextButton(
            onPressed: onOpenResources,
            child: Text(GochanoLanguage.text('Open', 'খুলুন')),
          ),
        ),
        AppCard(
          onTap: onOpenResources,
          child: Row(
            children: [
              GochanoIllustrationTile(
                GochanoArt.emptyGroupResources,
                accent: colors.community,
                plateSize: 48,
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Text(
                  GochanoLanguage.text(
                    'PDFs, images and documents everyone in the group can open.',
                    'পিডিএফ, ছবি ও ডকুমেন্ট, যা গ্রুপের সবাই খুলতে পারবে।',
                  ),
                  style: context.type.bodySecondary,
                ),
              ),
            ],
          ),
        ),

        if (memberIds.isNotEmpty) ...[
          const SizedBox(height: GochanoSpacing.md),
          SectionHeader(
            title: GochanoLanguage.text(
              'Members (${memberIds.length})',
              'সদস্য (${memberIds.length})',
            ),
          ),
          CardGroup(
            children: [
              for (final uid in memberIds)
                _MemberRow(uid: uid, isAdmin: adminIds.contains(uid)),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Resources (spec §45)
// ---------------------------------------------------------------------------

class _ResourcesTab extends StatelessWidget {
  const _ResourcesTab({required this.groupId, required this.groupName});

  final String groupId;
  final String groupName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showShareOptions(context, groupId, groupName),
        icon: const Icon(Icons.add_rounded),
        label: Text(GochanoLanguage.text('Share', 'শেয়ার')),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.groupMaterials(groupId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return StaticLoadingState(
              message: GochanoLanguage.text(
                'Loading shared resources…',
                'শেয়ার করা উপকরণ লোড হচ্ছে…',
              ),
            );
          }
          if (snapshot.hasError) {
            return ErrorState(message: friendlyErrorMessage(snapshot.error));
          }

          final docs = [...?snapshot.data?.docs]
            ..sort((a, b) {
              final at = a.data()['createdAt'];
              final bt = b.data()['createdAt'];
              if (at is Timestamp && bt is Timestamp) return bt.compareTo(at);
              return 0;
            });

          if (docs.isEmpty) {
            return EmptyState(
              illustration: GochanoArt.emptyGroupResources,
              title: GochanoLanguage.text(
                'No shared resources',
                'কোনো শেয়ার করা উপকরণ নেই',
              ),
              message: GochanoLanguage.text(
                'Share the first resource with your group.',
                'আপনার গ্রুপে প্রথম উপকরণটি শেয়ার করুন।',
              ),
            );
          }

          return ListView.builder(
            padding: GochanoSpacing.scrollBody,
            // One extra slot at the end for the shared-notes section.
            itemCount: docs.length + 1,
            itemBuilder: (context, i) {
              if (i == docs.length) return _GroupNotes(groupId: groupId);
              final doc = docs[i];
              final data = doc.data();
              final title = data['title']?.toString().trim().isNotEmpty == true
                  ? data['title'].toString()
                  : data['fileName']?.toString() ?? '';
              final fileName = data['fileName']?.toString() ?? '';
              final mimeType = data['mimeType']?.toString() ?? '';

              return Padding(
                padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: GochanoListRow(
                    illustration: GochanoArt.fileIdFor(
                      fileName: fileName,
                      mimeType: mimeType,
                    ),
                    accent: context.colors.community,
                    title: title,
                    subtitle: data['ownerName']?.toString(),
                    metadata: [
                      _fileSize(data['sizeBytes']),
                      _date(data['createdAt']),
                    ],
                    onTap: () => Navigator.of(context).push(
                      GochanoRoute.to(
                        builder: (_) => MaterialReaderScreen(
                          materialId: doc.id,
                          title: title,
                          mimeType: mimeType,
                          fileName: fileName,
                        ),
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

/// Shared text notes, which live in `notes` rather than `materials`.
///
/// Kept as a separate stream because a note is authored in the app and stays
/// editable by its owner, while a material is an uploaded file.
class _GroupNotes extends StatelessWidget {
  const _GroupNotes({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirestoreService.groupNotes(groupId),
      builder: (context, snapshot) {
        final docs = [...?snapshot.data?.docs];
        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: GochanoLanguage.text('Shared notes', 'শেয়ার করা নোট'),
            ),
            CardGroup(
              children: [
                for (final doc in docs)
                  GochanoListRow(
                    illustration: GochanoArt.fileNote,
                    accent: context.colors.community,
                    title: doc.data()['title']?.toString() ?? '',
                    subtitle: doc.data()['ownerName']?.toString(),
                    onTap: () => Navigator.of(context).push(
                      GochanoRoute.to(
                        builder: (_) => NoteEditorScreen(
                          noteId: doc.id,
                          initialData: doc.data(),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Asks whether to share a file or write a note into the group.
Future<void> _showShareOptions(
  BuildContext context,
  String groupId,
  String groupName,
) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.upload_file_rounded),
            title: Text(GochanoLanguage.text('Share a file', 'ফাইল শেয়ার')),
            subtitle: Text(
              GochanoLanguage.text(
                'PDF, JPEG or PNG image, or a Word document.',
                'পিডিএফ, জেপিইজি বা পিএনজি ছবি, অথবা ওয়ার্ড ডকুমেন্ট।',
              ),
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).push(
                GochanoRoute.to(
                  builder: (_) => MaterialUploadScreen(
                    groupId: groupId,
                    groupName: groupName,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_note_rounded),
            title: Text(GochanoLanguage.text('Write a note', 'নোট লিখুন')),
            subtitle: Text(
              GochanoLanguage.text(
                'A text note everyone in the group can read.',
                'একটি লেখা নোট, যা গ্রুপের সবাই পড়তে পারবে।',
              ),
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Navigator.of(context).push(
                GochanoRoute.to(
                  builder: (_) => NoteEditorScreen(
                    initialVisibility: 'group',
                    initialGroupId: groupId,
                    initialGroupName: groupName,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: GochanoSpacing.sm),
        ],
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Projects
// ---------------------------------------------------------------------------

class _ProjectsTab extends StatelessWidget {
  const _ProjectsTab({
    required this.groupId,
    required this.isAdmin,
    required this.memberIds,
    required this.adminIds,
  });

  final String groupId;
  final bool isAdmin;
  final List<String> memberIds;
  final List<String> adminIds;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateProjectSheet(context, groupId),
              icon: const Icon(Icons.add_rounded),
              label: Text(GochanoLanguage.text('New project', 'নতুন প্রজেক্ট')),
            )
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.groupProjects(groupId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return StaticLoadingState(
              message: GochanoLanguage.text(
                'Loading projects…',
                'প্রজেক্ট লোড হচ্ছে…',
              ),
            );
          }
          if (snapshot.hasError) {
            return ErrorState(message: friendlyErrorMessage(snapshot.error));
          }

          final docs = [...?snapshot.data?.docs];
          if (docs.isEmpty) {
            return EmptyState(
              illustration: GochanoArt.featureTasks,
              title: GochanoLanguage.text(
                'No projects yet',
                'এখনো কোনো প্রজেক্ট নেই',
              ),
              message: isAdmin
                  ? GochanoLanguage.text(
                      'Create the first project for your group.',
                      'আপনার গ্রুপের জন্য প্রথম প্রজেক্ট তৈরি করুন।',
                    )
                  : GochanoLanguage.text(
                      'No projects have been created yet.',
                      'এখনো কোনো প্রজেক্ট তৈরি হয়নি।',
                    ),
            );
          }

          return ListView.builder(
            padding: GochanoSpacing.scrollBody,
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();
              return _ProjectCard(
                groupId: groupId,
                projectId: doc.id,
                data: data,
                isAdmin: isAdmin,
                memberIds: memberIds,
                adminIds: adminIds,
              );
            },
          );
        },
      ),
    );
  }
}

/// A single project card with progress bar.
class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.groupId,
    required this.projectId,
    required this.data,
    required this.isAdmin,
    required this.memberIds,
    required this.adminIds,
  });

  final String groupId;
  final String projectId;
  final Map<String, dynamic> data;
  final bool isAdmin;
  final List<String> memberIds;
  final List<String> adminIds;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final name = data['name']?.toString() ?? '';
    final description = data['description']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.projectTasks(groupId, projectId),
        builder: (context, snapshot) {
          final tasks = [...?snapshot.data?.docs];
          final total = tasks.length;
          final completed = tasks
              .where((t) => t.data()['completed'] == true)
              .length;
          final progress = total > 0 ? completed / total : 0.0;
          final progressPercent = (progress * 100).round();

          final progressColor = progress < 0.4
              ? colors.error
              : progress < 0.8
              ? colors.warning
              : colors.success;

          return AppCard(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _ProjectDetailScreen(
                  groupId: groupId,
                  projectId: projectId,
                  projectName: name,
                  isAdmin: isAdmin,
                  memberIds: memberIds,
                  adminIds: adminIds,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: context.type.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isAdmin)
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert_rounded,
                          size: 20,
                          color: colors.textTertiary,
                        ),
                        onSelected: (action) => _handleProjectAction(
                          context,
                          action,
                          groupId,
                          projectId,
                          data,
                        ),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text(
                              GochanoLanguage.text('Edit', 'সম্পাদনা'),
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              GochanoLanguage.text('Delete', 'মুছুন'),
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: GochanoSpacing.xxs),
                  Text(
                    description,
                    style: context.type.caption,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: GochanoSpacing.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: colors.border,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  ),
                ),
                const SizedBox(height: GochanoSpacing.xxs),
                Text(
                  total > 0
                      ? GochanoLanguage.text(
                          '$progressPercent% complete · $completed/$total tasks',
                          '$progressPercent% সম্পন্ন · $completed/$total কাজ',
                        )
                      : GochanoLanguage.text(
                          'No tasks yet',
                          'এখনো কোনো কাজ নেই',
                        ),
                  style: context.type.caption.copyWith(color: progressColor),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

Future<void> _showCreateProjectSheet(
  BuildContext context,
  String groupId,
) async {
  final nameCtl = TextEditingController();
  final descCtl = TextEditingController();

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        left: GochanoSpacing.lg,
        right: GochanoSpacing.lg,
        top: GochanoSpacing.lg,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                GochanoLanguage.text('New project', 'নতুন প্রজেক্ট'),
                style: sheetContext.type.pageTitle,
              ),
              const SizedBox(height: GochanoSpacing.md),
              TextField(
                controller: nameCtl,
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text(
                    'Project name',
                    'প্রজেক্টের নাম',
                  ),
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
              ),
              const SizedBox(height: GochanoSpacing.sm),
              TextField(
                controller: descCtl,
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text(
                    'Description (optional)',
                    'বিবরণ (ঐচ্ছিক)',
                  ),
                  border: const OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLength: 240,
                maxLines: 2,
              ),
              const SizedBox(height: GochanoSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: Text(GochanoLanguage.text('Cancel', 'বাতিল')),
                    ),
                  ),
                  const SizedBox(width: GochanoSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: Text(GochanoLanguage.text('Create', 'তৈরি')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: GochanoSpacing.sm),
            ],
          ),
        ),
      ),
    ),
  );

  if (result != true || !context.mounted) return;
  final name = nameCtl.text.trim();
  if (name.isEmpty) return;

  try {
    await FirestoreService.createProject(
      groupId: groupId,
      name: name,
      description: descCtl.text.trim().isNotEmpty ? descCtl.text.trim() : null,
    );
    if (context.mounted) {
      showGochanoMessage(
        context,
        GochanoLanguage.text('Project created.', 'প্রজেক্ট তৈরি হয়েছে।'),
      );
    }
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

void _handleProjectAction(
  BuildContext context,
  String action,
  String groupId,
  String projectId,
  Map<String, dynamic> data,
) async {
  if (action == 'edit') {
    final nameCtl = TextEditingController(text: data['name']?.toString() ?? '');
    final descCtl = TextEditingController(
      text: data['description']?.toString() ?? '',
    );

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          left: GochanoSpacing.lg,
          right: GochanoSpacing.lg,
          top: GochanoSpacing.lg,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  GochanoLanguage.text('Edit project', 'প্রজেক্ট সম্পাদনা'),
                  style: sheetContext.type.pageTitle,
                ),
                const SizedBox(height: GochanoSpacing.md),
                TextField(
                  controller: nameCtl,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text(
                      'Project name',
                      'প্রজেক্টের নাম',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 80,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                TextField(
                  controller: descCtl,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text(
                      'Description (optional)',
                      'বিবরণ (ঐচ্ছিক)',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 240,
                  maxLines: 2,
                ),
                const SizedBox(height: GochanoSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: Text(GochanoLanguage.text('Cancel', 'বাতিল')),
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        child: Text(GochanoLanguage.text('Save', 'সংরক্ষণ')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.sm),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != true || !context.mounted) return;
    final name = nameCtl.text.trim();
    if (name.isEmpty) return;

    try {
      await FirestoreService.updateProject(
        groupId: groupId,
        projectId: projectId,
        fields: {'name': name, 'description': descCtl.text.trim()},
      );
    } catch (error) {
      if (context.mounted) {
        showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
      }
    }
  } else if (action == 'delete') {
    final confirmed = await showConfirmationSheet(
      context,
      title: GochanoLanguage.text('Delete project?', 'প্রজেক্ট মুছবেন?'),
      message: GochanoLanguage.text(
        'This will permanently delete the project and all its tasks.',
        'এটি প্রজেক্ট এবং এর সব কাজ স্থায়ীভাবে মুছে ফেলবে।',
      ),
      confirmLabel: GochanoLanguage.text('Delete', 'মুছুন'),
    );
    if (!confirmed || !context.mounted) return;

    try {
      await FirestoreService.deleteProject(
        groupId: groupId,
        projectId: projectId,
      );
      if (context.mounted) {
        showGochanoMessage(
          context,
          GochanoLanguage.text(
            'Project deleted.',
            'প্রজেক্ট মুছে ফেলা হয়েছে।',
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Project Detail
// ---------------------------------------------------------------------------

class _ProjectDetailScreen extends StatefulWidget {
  const _ProjectDetailScreen({
    required this.groupId,
    required this.projectId,
    required this.projectName,
    required this.isAdmin,
    required this.memberIds,
    required this.adminIds,
  });

  final String groupId;
  final String projectId;
  final String projectName;
  final bool isAdmin;
  final List<String> memberIds;
  final List<String> adminIds;

  @override
  State<_ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<_ProjectDetailScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.projectName)),
      floatingActionButton: widget.isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateTaskSheet(
                context,
                widget.groupId,
                widget.projectId,
                widget.memberIds,
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text(GochanoLanguage.text('Add task', 'কাজ যোগ')),
            )
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.projectTasks(widget.groupId, widget.projectId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return StaticLoadingState(
              message: GochanoLanguage.text('Loading tasks…', 'কাজ লোড হচ্ছে…'),
            );
          }
          if (snapshot.hasError) {
            return ErrorState(message: friendlyErrorMessage(snapshot.error));
          }

          final docs = [...?snapshot.data?.docs];
          if (docs.isEmpty) {
            return EmptyState(
              illustration: GochanoArt.emptyTasks,
              title: GochanoLanguage.text('No tasks yet', 'এখনো কোনো কাজ নেই'),
              message: widget.isAdmin
                  ? GochanoLanguage.text(
                      'Add the first task to this project.',
                      'এই প্রজেক্টে প্রথম কাজ যোগ করুন।',
                    )
                  : GochanoLanguage.text(
                      'No tasks have been added yet.',
                      'এখনো কোনো কাজ যোগ হয়নি।',
                    ),
            );
          }

          // Separate into incomplete and completed
          final incomplete = docs
              .where((d) => d.data()['completed'] != true)
              .toList();
          final completed = docs
              .where((d) => d.data()['completed'] == true)
              .toList();

          return ListView(
            padding: GochanoSpacing.scrollBody,
            children: [
              if (incomplete.isNotEmpty) ...[
                for (final doc in incomplete)
                  _TaskTile(
                    groupId: widget.groupId,
                    projectId: widget.projectId,
                    taskData: doc.data(),
                    taskId: doc.id,
                    isAdmin: widget.isAdmin,
                    memberIds: widget.memberIds,
                    adminIds: widget.adminIds,
                  ),
              ],
              if (completed.isNotEmpty) ...[
                SectionHeader(
                  title: GochanoLanguage.text(
                    'Completed (${completed.length})',
                    'সম্পন্ন (${completed.length})',
                  ),
                ),
                for (final doc in completed)
                  _TaskTile(
                    groupId: widget.groupId,
                    projectId: widget.projectId,
                    taskData: doc.data(),
                    taskId: doc.id,
                    isAdmin: widget.isAdmin,
                    memberIds: widget.memberIds,
                    adminIds: widget.adminIds,
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Task Tile
// ---------------------------------------------------------------------------

class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.groupId,
    required this.projectId,
    required this.taskData,
    required this.taskId,
    required this.isAdmin,
    required this.memberIds,
    required this.adminIds,
  });

  final String groupId;
  final String projectId;
  final Map<String, dynamic> taskData;
  final String taskId;
  final bool isAdmin;
  final List<String> memberIds;
  final List<String> adminIds;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = taskData['title']?.toString() ?? '';
    final description = taskData['description']?.toString() ?? '';
    final assigneeId = taskData['assigneeId']?.toString();
    final completed = taskData['completed'] == true;
    final deadline = taskData['deadline'];
    final currentUid = FirestoreService.uid;
    final isMyTask =
        assigneeId != null && currentUid != null && assigneeId == currentUid;

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (assigneeId != null)
              GestureDetector(
                onTap: (isAdmin || isMyTask)
                    ? () => _toggleTaskComplete(
                        context,
                        groupId,
                        projectId,
                        taskId,
                        !completed,
                      )
                    : null,
                child: Container(
                  width: 24,
                  height: 24,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: completed ? colors.success : colors.border,
                    border: Border.all(
                      color: completed ? colors.success : colors.textTertiary,
                    ),
                  ),
                  child: completed
                      ? Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: colors.onBrand,
                        )
                      : null,
                ),
              ),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: context.type.body.copyWith(
                      decoration: completed ? TextDecoration.lineThrough : null,
                      color: completed ? colors.textTertiary : null,
                    ),
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: GochanoSpacing.xxs),
                    Text(
                      description,
                      style: context.type.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: GochanoSpacing.xxs),
                  Wrap(
                    spacing: GochanoSpacing.xs,
                    runSpacing: GochanoSpacing.xxs,
                    children: [
                      if (assigneeId != null)
                        _FutureChip(
                          uid: assigneeId,
                          icon: Icons.person_outline_rounded,
                        ),
                      if (deadline != null)
                        Text(
                          _formatDeadline(deadline),
                          style: context.type.caption.copyWith(
                            color: _deadlineColor(context, deadline, completed),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (isAdmin)
              PopupMenuButton<String>(
                icon: Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: colors.textTertiary,
                ),
                onSelected: (action) => _handleTaskAction(
                  context,
                  action,
                  groupId,
                  projectId,
                  taskId,
                  taskData,
                  memberIds,
                ),
                itemBuilder: (_) => [
                  if (isMyTask)
                    PopupMenuItem(
                      value: 'reminder',
                      child: Text(
                        GochanoLanguage.text('Set reminder', 'রিমাইন্ডার সেট'),
                      ),
                    ),
                  PopupMenuItem(
                    value: 'assign',
                    child: Text(GochanoLanguage.text('Assign', 'নির্ধারণ')),
                  ),
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(GochanoLanguage.text('Edit', 'সম্পাদনা')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      GochanoLanguage.text('Delete', 'মুছুন'),
                      style: TextStyle(color: colors.error),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// In-memory cache for user profiles to avoid repeated Firestore reads.
/// Each _FutureChip used to fire an uncached get() per uid, causing
/// 20+ network round trips for a group with 20 members.
/// Cache persists for the app session; entries are small and bounded by
/// the number of users the student interacts with.
class _UserProfileCache {
  static final Map<String, Map<String, dynamic>> _cache = {};

  static Future<Map<String, dynamic>?> get(String uid) async {
    if (_cache.containsKey(uid)) return _cache[uid];
    final snap = await FirestoreService.db.collection('users').doc(uid).get();
    final data = snap.data();
    if (data != null) _cache[uid] = data;
    return data;
  }
}

class _FutureChip extends StatelessWidget {
  const _FutureChip({required this.uid, required this.icon});

  final String uid;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _UserProfileCache.get(uid),
      builder: (context, snapshot) {
        final data = snapshot.data;
        // Prefer nickname over displayName.
        final name = (data?['nickname']?.toString().isNotEmpty == true)
            ? data!['nickname']!.toString()
            : data?['displayName']?.toString();
        if (name == null || name.isEmpty) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: context.colors.textTertiary),
            const SizedBox(width: 2),
            Text(
              name,
              style: context.type.caption.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ],
        );
      },
    );
  }
}

String _formatDeadline(dynamic deadline) {
  if (deadline is! Timestamp) return '';
  final dt = deadline.toDate();
  final now = DateTime.now();
  final diff = dt.difference(now);
  if (diff.isNegative) return 'Overdue';
  if (diff.inDays == 0) return 'Today';
  if (diff.inDays == 1) return 'Tomorrow';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${dt.day} ${months[dt.month - 1]}';
}

Color _deadlineColor(BuildContext context, dynamic deadline, bool completed) {
  if (completed) return context.colors.textTertiary;
  if (deadline is! Timestamp) return context.colors.textTertiary;
  final diff = deadline.toDate().difference(DateTime.now());
  if (diff.isNegative) return context.colors.error;
  if (diff.inDays < 2) return context.colors.warning;
  return context.colors.textSecondary;
}

Future<void> _toggleTaskComplete(
  BuildContext context,
  String groupId,
  String projectId,
  String taskId,
  bool completed,
) async {
  try {
    await FirestoreService.updateTask(
      groupId: groupId,
      projectId: projectId,
      taskId: taskId,
      fields: {'completed': completed},
    );

    // Cancel the assignee's reminder when they complete the task.
    if (completed) {
      final currentUid = FirestoreService.uid;
      if (currentUid != null) {
        await NotificationService.cancelCommunityTaskReminder(
          groupId: groupId,
          projectId: projectId,
          taskId: taskId,
          userId: currentUid,
        );
      }
    }
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

Future<void> _showCreateTaskSheet(
  BuildContext context,
  String groupId,
  String projectId,
  List<String> memberIds,
) async {
  final titleCtl = TextEditingController();
  final descCtl = TextEditingController();
  String? selectedAssignee;
  DateTime? deadline;
  int reminderPreset = 0; // 0=None, 1=10min, 2=30min, 3=1hr

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        left: GochanoSpacing.lg,
        right: GochanoSpacing.lg,
        top: GochanoSpacing.lg,
      ),
      child: StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  GochanoLanguage.text('New task', 'নতুন কাজ'),
                  style: sheetContext.type.pageTitle,
                ),
                const SizedBox(height: GochanoSpacing.md),
                TextField(
                  controller: titleCtl,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('Task name', 'কাজের নাম'),
                    border: const OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 80,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                TextField(
                  controller: descCtl,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text(
                      'Description (optional)',
                      'বিবরণ (ঐচ্ছিক)',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 240,
                  maxLines: 2,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                DropdownButtonFormField<String>(
                  initialValue: selectedAssignee,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text(
                      'Assign to (optional)',
                      'কাউকে দিন (ঐচ্ছিক)',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(
                        GochanoLanguage.text('Unassigned', 'নির্ধারিত নয়'),
                      ),
                    ),
                    for (final uid in memberIds)
                      DropdownMenuItem(
                        value: uid,
                        child: _FutureChip(
                          uid: uid,
                          icon: Icons.person_outline_rounded,
                        ),
                      ),
                  ],
                  onChanged: (v) => setSheetState(() => selectedAssignee = v),
                ),
                const SizedBox(height: GochanoSpacing.sm),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_today_rounded),
                  title: Text(
                    deadline != null
                        ? '${deadline!.day}/${deadline!.month}/${deadline!.year}'
                        : GochanoLanguage.text(
                            'Set deadline',
                            'সময়সীমা নির্ধারণ',
                          ),
                  ),
                  subtitle: Text(
                    GochanoLanguage.text('Optional', 'ঐচ্ছিক'),
                    style: sheetContext.type.caption,
                  ),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: sheetContext,
                      initialDate: deadline ?? DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null && sheetContext.mounted) {
                      final time = await showTimePicker(
                        context: sheetContext,
                        initialTime: TimeOfDay.fromDateTime(
                          deadline ?? DateTime.now(),
                        ),
                      );
                      setSheetState(() {
                        deadline = DateTime(
                          picked.year,
                          picked.month,
                          picked.day,
                          time?.hour ?? 23,
                          time?.minute ?? 59,
                        );
                      });
                    }
                  },
                ),
                if (deadline != null) ...[
                  const SizedBox(height: GochanoSpacing.sm),
                  Text(
                    GochanoLanguage.text('Reminder', 'রিমাইন্ডার'),
                    style: sheetContext.type.label,
                  ),
                  const SizedBox(height: GochanoSpacing.xs),
                  Wrap(
                    spacing: GochanoSpacing.xs,
                    children: [
                      _reminderChip(
                        sheetContext,
                        setSheetState,
                        0,
                        'None',
                        'নেই',
                        reminderPreset,
                        (v) => reminderPreset = v,
                      ),
                      _reminderChip(
                        sheetContext,
                        setSheetState,
                        1,
                        '10 min before',
                        '১০ মিনিট আগে',
                        reminderPreset,
                        (v) => reminderPreset = v,
                      ),
                      _reminderChip(
                        sheetContext,
                        setSheetState,
                        2,
                        '30 min before',
                        '৩০ মিনিট আগে',
                        reminderPreset,
                        (v) => reminderPreset = v,
                      ),
                      _reminderChip(
                        sheetContext,
                        setSheetState,
                        3,
                        '1 hour before',
                        '১ ঘণ্টা আগে',
                        reminderPreset,
                        (v) => reminderPreset = v,
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: GochanoSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: Text(GochanoLanguage.text('Cancel', 'বাতিল')),
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        child: Text(GochanoLanguage.text('Create', 'তৈরি')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.sm),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  if (result != true || !context.mounted) return;
  final title = titleCtl.text.trim();
  if (title.isEmpty) return;

  try {
    final doc = await FirestoreService.createTask(
      groupId: groupId,
      projectId: projectId,
      title: title,
      description: descCtl.text.trim().isNotEmpty ? descCtl.text.trim() : null,
      assigneeId: selectedAssignee,
      deadline: deadline,
    );

    // Schedule per-user reminder if an assignee was set and a preset was chosen.
    if (selectedAssignee != null && reminderPreset > 0 && deadline != null) {
      final reminderTime = _reminderOffset(deadline!, reminderPreset);
      if (reminderTime != null && reminderTime.isAfter(DateTime.now())) {
        await FirestoreService.setTaskReminder(
          groupId: groupId,
          projectId: projectId,
          taskId: doc.id,
          userId: selectedAssignee!,
          reminderAt: reminderTime,
        );
        await NotificationService.scheduleCommunityTaskReminder(
          groupId: groupId,
          projectId: projectId,
          taskId: doc.id,
          userId: selectedAssignee!,
          title: title,
          when: reminderTime,
        );
      }
    }

    if (context.mounted) {
      showGochanoMessage(
        context,
        GochanoLanguage.text('Task created.', 'কাজ তৈরি হয়েছে।'),
      );
    }
  } catch (error) {
    if (context.mounted) {
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    }
  }
}

Widget _reminderChip(
  BuildContext context,
  StateSetter setSheetState,
  int value,
  String en,
  String bn,
  int current,
  ValueChanged<int> onSelect,
) {
  final selected = current == value;
  return ChoiceChip(
    label: Text(GochanoLanguage.text(en, bn)),
    selected: selected,
    onSelected: (_) => setSheetState(() {
      onSelect(value);
    }),
  );
}

DateTime? _reminderOffset(DateTime deadline, int preset) {
  switch (preset) {
    case 1:
      return deadline.subtract(const Duration(minutes: 10));
    case 2:
      return deadline.subtract(const Duration(minutes: 30));
    case 3:
      return deadline.subtract(const Duration(hours: 1));
    default:
      return null;
  }
}

void _handleTaskAction(
  BuildContext context,
  String action,
  String groupId,
  String projectId,
  String taskId,
  Map<String, dynamic> taskData,
  List<String> memberIds,
) async {
  if (action == 'reminder') {
    final userId = FirestoreService.uid;
    if (userId == null) return;
    final deadline = taskData['deadline'];
    if (deadline is! Timestamp) return;
    final deadlineDt = deadline.toDate();

    // Read current reminder for this user.
    final reminderByUser = taskData['reminderByUser'];
    final currentReminder = reminderByUser is Map
        ? reminderByUser[userId]
        : null;
    int currentPreset = 0;
    if (currentReminder is Timestamp) {
      final diff = deadlineDt.difference(currentReminder.toDate()).inMinutes;
      if (diff <= 10) {
        currentPreset = 1;
      } else if (diff <= 30) {
        currentPreset = 2;
      } else if (diff <= 60) {
        currentPreset = 3;
      }
    }

    int selectedPreset = currentPreset;

    final result = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  GochanoLanguage.text('Set reminder', 'রিমাইন্ডার সেট'),
                  style: sheetContext.type.sectionHeading,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: GochanoSpacing.md,
                ),
                child: Wrap(
                  spacing: GochanoSpacing.xs,
                  children: [
                    _reminderChip(
                      sheetContext,
                      setSheetState,
                      0,
                      'None',
                      'নেই',
                      selectedPreset,
                      (v) => selectedPreset = v,
                    ),
                    _reminderChip(
                      sheetContext,
                      setSheetState,
                      1,
                      '10 min before',
                      '১০ মিনিট আগে',
                      selectedPreset,
                      (v) => selectedPreset = v,
                    ),
                    _reminderChip(
                      sheetContext,
                      setSheetState,
                      2,
                      '30 min before',
                      '৩০ মিনিট আগে',
                      selectedPreset,
                      (v) => selectedPreset = v,
                    ),
                    _reminderChip(
                      sheetContext,
                      setSheetState,
                      3,
                      '1 hour before',
                      '১ ঘণ্টা আগে',
                      selectedPreset,
                      (v) => selectedPreset = v,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(GochanoSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: Text(GochanoLanguage.text('Cancel', 'বাতিল')),
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        child: Text(GochanoLanguage.text('Save', 'সংরক্ষণ')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result != true || !context.mounted) return;

    final title = taskData['title']?.toString() ?? '';
    final reminderTime = selectedPreset > 0
        ? _reminderOffset(deadlineDt, selectedPreset)
        : null;

    try {
      await FirestoreService.setTaskReminder(
        groupId: groupId,
        projectId: projectId,
        taskId: taskId,
        userId: userId,
        reminderAt: reminderTime,
      );
      await NotificationService.rescheduleCommunityTaskReminder(
        groupId: groupId,
        projectId: projectId,
        taskId: taskId,
        userId: userId,
        title: title,
        when: reminderTime,
      );
      if (context.mounted) {
        showGochanoMessage(
          context,
          reminderTime != null
              ? GochanoLanguage.text('Reminder set.', 'রিমাইন্ডার সেট হয়েছে।')
              : GochanoLanguage.text(
                  'Reminder cleared.',
                  'রিমাইন্ডার মুছে ফেলা হয়েছে।',
                ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
      }
    }
  } else if (action == 'assign') {
    String? selected = taskData['assigneeId']?.toString();
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  GochanoLanguage.text('Assign to', 'কাউকে দিন'),
                  style: sheetContext.type.sectionHeading,
                ),
              ),
              for (final uid in memberIds)
                ListTile(
                  leading: Radio<String>(
                    value: uid,
                    // ignore: deprecated_member_use
                    groupValue: selected,
                    // ignore: deprecated_member_use
                    onChanged: (v) => setSheetState(() => selected = v),
                  ),
                  title: _FutureChip(
                    uid: uid,
                    icon: Icons.person_outline_rounded,
                  ),
                  onTap: () => setSheetState(() => selected = uid),
                ),
              Padding(
                padding: const EdgeInsets.all(GochanoSpacing.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        child: Text(GochanoLanguage.text('Cancel', 'বাতিল')),
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: () =>
                            Navigator.of(sheetContext).pop(selected),
                        child: Text(GochanoLanguage.text('Save', 'সংরক্ষণ')),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!context.mounted) return;
    try {
      final oldAssigneeId = taskData['assigneeId']?.toString();

      await FirestoreService.updateTask(
        groupId: groupId,
        projectId: projectId,
        taskId: taskId,
        fields: {'assigneeId': result},
      );

      // Cancel the old assignee's reminder if they were unassigned.
      if (oldAssigneeId != null && oldAssigneeId != result) {
        await NotificationService.cancelCommunityTaskReminder(
          groupId: groupId,
          projectId: projectId,
          taskId: taskId,
          userId: oldAssigneeId,
        );
      }
    } catch (error) {
      if (context.mounted) {
        showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
      }
    }
  } else if (action == 'edit') {
    final titleCtl = TextEditingController(
      text: taskData['title']?.toString() ?? '',
    );
    final descCtl = TextEditingController(
      text: taskData['description']?.toString() ?? '',
    );

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          left: GochanoSpacing.lg,
          right: GochanoSpacing.lg,
          top: GochanoSpacing.lg,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  GochanoLanguage.text('Edit task', 'কাজ সম্পাদনা'),
                  style: sheetContext.type.pageTitle,
                ),
                const SizedBox(height: GochanoSpacing.md),
                TextField(
                  controller: titleCtl,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text('Task name', 'কাজের নাম'),
                    border: const OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 80,
                ),
                const SizedBox(height: GochanoSpacing.sm),
                TextField(
                  controller: descCtl,
                  decoration: InputDecoration(
                    labelText: GochanoLanguage.text(
                      'Description (optional)',
                      'বিবরণ (ঐচ্ছিক)',
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 240,
                  maxLines: 2,
                ),
                const SizedBox(height: GochanoSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        child: Text(GochanoLanguage.text('Cancel', 'বাতিল')),
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.sm),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        child: Text(GochanoLanguage.text('Save', 'সংরক্ষণ')),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: GochanoSpacing.sm),
              ],
            ),
          ),
        ),
      ),
    );

    if (result != true || !context.mounted) return;
    final title = titleCtl.text.trim();
    if (title.isEmpty) return;

    try {
      await FirestoreService.updateTask(
        groupId: groupId,
        projectId: projectId,
        taskId: taskId,
        fields: {'title': title, 'description': descCtl.text.trim()},
      );
    } catch (error) {
      if (context.mounted) {
        showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
      }
    }
  } else if (action == 'delete') {
    final confirmed = await showConfirmationSheet(
      context,
      title: GochanoLanguage.text('Delete task?', 'কাজ মুছবেন?'),
      message: GochanoLanguage.text(
        'This will permanently delete the task.',
        'এটি কাজটি স্থায়ীভাবে মুছে ফেলবে।',
      ),
      confirmLabel: GochanoLanguage.text('Delete', 'মুছুন'),
    );
    if (!confirmed || !context.mounted) return;

    try {
      // Cancel all user reminders for this task before deleting.
      final reminderByUser = taskData['reminderByUser'];
      if (reminderByUser is Map) {
        for (final uid in reminderByUser.keys) {
          await NotificationService.cancelCommunityTaskReminder(
            groupId: groupId,
            projectId: projectId,
            taskId: taskId,
            userId: uid.toString(),
          );
        }
      }

      await FirestoreService.deleteTask(
        groupId: groupId,
        projectId: projectId,
        taskId: taskId,
      );
    } catch (error) {
      if (context.mounted) {
        showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Members (now shown in Overview tab)
// ---------------------------------------------------------------------------

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.uid, required this.isAdmin});

  final String uid;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirestoreService.db.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        // Prefer nickname over displayName for primary display.
        final name = (data?['nickname']?.toString().isNotEmpty == true)
            ? data!['nickname']!.toString()
            : (data?['displayName']?.toString() ?? '');
        final currentUid = FirestoreService.uid;
        final isMe = currentUid != null && uid == currentUid;

        return GochanoListRow(
          illustration: GochanoArt.featureProfile,
          accent: context.colors.community,
          title: name.isEmpty
              ? GochanoLanguage.text('Group member', 'গ্রুপ সদস্য')
              : name,
          subtitle: isMe ? GochanoLanguage.text('You', 'আপনি') : null,
          badge: isAdmin
              ? GochanoBadge(
                  label: GochanoLanguage.text('Admin', 'অ্যাডমিন'),
                  tone: GochanoBadgeTone.brand,
                  icon: Icons.shield_outlined,
                )
              : null,
        );
      },
    );
  }
}

String _fileSize(Object? sizeBytes) {
  final bytes = (sizeBytes as num?)?.toInt() ?? 0;
  if (bytes <= 0) return '';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _date(Object? value) {
  if (value is! Timestamp) return '';
  final when = value.toDate();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${when.day} ${months[when.month - 1]}';
}
