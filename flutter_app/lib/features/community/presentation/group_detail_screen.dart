// Study group — Overview / Resources / Chat / Members (spec §42, §43).
//
// Four tabs rather than one overloaded screen. Each maps to a real backend
// surface:
//
//   Overview   the `groups/{id}` document: name, description, invite code.
//   Resources  `materials` where groupId == this group and visibility ==
//              'group'. Uploading goes through the same authenticated
//              /api/materials/upload the private library uses, so the
//              per-user quota and the file-type check are identical
//              (spec §45).
//   Chat       GET/POST /api/groups/{id}/chat. Both are member-only and the
//              POST additionally requires chatEnabled — a non-member gets a
//              403 from the server, not just a hidden button (spec §44).
//   Members    the memberIds on the group document.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_illustration.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../services/api_service.dart';
import '../../../services/firestore_service.dart';
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
        final memberIds =
            ((data['memberIds'] as List?) ?? const []).map((e) => e.toString()).toList();
        final adminIds =
            ((data['adminIds'] as List?) ?? const []).map((e) => e.toString()).toList();
        final chatEnabled = data['chatEnabled'] == true;
        final isAdmin = adminIds.contains(FirestoreService.uid);

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
                Tab(text: GochanoLanguage.text('Overview', 'সারাংশ')),
                Tab(text: GochanoLanguage.text('Resources', 'উপকরণ')),
                Tab(text: GochanoLanguage.text('Chat', 'চ্যাট')),
                Tab(text: GochanoLanguage.text('Members', 'সদস্য')),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: [
              _OverviewTab(
                data: data,
                isAdmin: isAdmin,
                onOpenResources: () => _tabs.animateTo(1),
              ),
              _ResourcesTab(groupId: widget.groupId, groupName: name),
              GroupChatView(
                groupId: widget.groupId,
                chatEnabled: chatEnabled,
                isAdmin: isAdmin,
              ),
              _MembersTab(memberIds: memberIds, adminIds: adminIds),
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
    required this.onOpenResources,
  });

  final Map<String, dynamic> data;
  final bool isAdmin;
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
          AppCard(
            child: Text(description, style: context.type.body),
          ),
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
                SelectableText(
                  inviteCode,
                  style: context.type.statistic.copyWith(letterSpacing: 4),
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
              actionLabel: GochanoLanguage.text('Share a file', 'একটি ফাইল শেয়ার'),
              onAction: () => _showShareOptions(context, groupId, groupName),
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
// Members
// ---------------------------------------------------------------------------

class _MembersTab extends StatelessWidget {
  const _MembersTab({required this.memberIds, required this.adminIds});

  final List<String> memberIds;
  final List<String> adminIds;

  @override
  Widget build(BuildContext context) {
    if (memberIds.isEmpty) {
      return EmptyState(
        illustration: GochanoArt.featureMembers,
        title: GochanoLanguage.text('No members yet', 'এখনো কোনো সদস্য নেই'),
        message: GochanoLanguage.text(
          'Share the invite code so classmates can join.',
          'সহপাঠীরা যোগ দিতে পারে সেজন্য ইনভাইট কোড শেয়ার করুন।',
        ),
      );
    }

    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: [
        CardGroup(
          children: [
            for (final uid in memberIds)
              _MemberRow(uid: uid, isAdmin: adminIds.contains(uid)),
          ],
        ),
      ],
    );
  }
}

/// A member row, resolved from their public profile.
///
/// Only the display name is shown. Email and any other profile field stay
/// private to the account that owns them (spec §82).
class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.uid, required this.isAdmin});

  final String uid;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirestoreService.db.collection('users').doc(uid).get(),
      builder: (context, snapshot) {
        final name = snapshot.data?.data()?['displayName']?.toString() ?? '';
        final isMe = uid == FirestoreService.uid;

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
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${when.day} ${months[when.month - 1]}';
}
