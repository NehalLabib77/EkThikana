// Community — study groups (spec §70, §71).
//
// A note on scope
// ---------------
// Gochano's Community is **study groups**, not a social feed. There is no
// posts/comments backend in this project — no endpoints, no Firestore
// collection — so this screen does not pretend otherwise (spec §90: do not
// fake features, do not show "Coming Soon"). What exists and works is: create
// a group, join by invite code, share resources, chat when the group admin
// enables it, and see who is in it.
//
// That is also what spec §70 actually asks for: academic, student-focused,
// with the content dominant and no follower counts or engagement tricks.

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
import '../../../widgets/language_toggle.dart';
import 'group_detail_screen.dart';

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: GochanoLanguage.text('Community', 'কমিউনিটি'),
        subtitle: GochanoLanguage.text(
          'Study together, share materials',
          'একসাথে পড়ুন, উপকরণ শেয়ার করুন',
        ),
        automaticallyImplyLeading: false,
        actions: const [LanguageToggle(), SizedBox(width: GochanoSpacing.xs)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showGroupActionsSheet(context),
        icon: const Icon(Icons.group_add_rounded),
        label: Text(GochanoLanguage.text('New group', 'নতুন গ্রুপ')),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirestoreService.myGroups(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return StaticLoadingState(
              message: GochanoLanguage.text(
                'Loading your groups…',
                'আপনার গ্রুপ লোড হচ্ছে…',
              ),
            );
          }
          if (snapshot.hasError) {
            return ErrorState(message: friendlyErrorMessage(snapshot.error));
          }

          final groups = [...?snapshot.data?.docs]
            ..sort((a, b) => (a.data()['name']?.toString() ?? '')
                .compareTo(b.data()['name']?.toString() ?? ''));

          if (groups.isEmpty) {
            return EmptyState(
              illustration: GochanoArt.featureGroups,
              title: GochanoLanguage.text(
                'No study groups yet',
                'এখনো কোনো স্টাডি গ্রুপ নেই',
              ),
              message: GochanoLanguage.text(
                'Create a group for your class, or join one with an invite '
                'code from a classmate.',
                'আপনার ক্লাসের জন্য একটি গ্রুপ তৈরি করুন, অথবা সহপাঠীর ইনভাইট কোড দিয়ে যোগ দিন।',
              ),
              actionLabel:
                  GochanoLanguage.text('Create a group', 'গ্রুপ তৈরি করুন'),
              onAction: () => showCreateGroupSheet(context),
              secondaryActionLabel:
                  GochanoLanguage.text('Join with a code', 'কোড দিয়ে যোগ দিন'),
              onSecondaryAction: () => showJoinGroupSheet(context),
            );
          }

          return ListView.builder(
            padding: GochanoSpacing.scrollBody,
            itemCount: groups.length,
            itemBuilder: (context, i) => Padding(
              padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
              child: _GroupCard(doc: groups[i]),
            ),
          );
        },
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.doc});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final data = doc.data();
    final name = data['name']?.toString() ?? '';
    final description = data['description']?.toString() ?? '';
    final members = ((data['memberIds'] as List?) ?? const []).length;
    final chatEnabled = data['chatEnabled'] == true;

    return AppCard(
      accent: colors.community,
      onTap: () => Navigator.of(context).push(
        GochanoRoute.to(
          builder: (_) => GroupDetailScreen(groupId: doc.id, groupName: name),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GochanoIllustrationTile(
                GochanoArt.featureGroups,
                accent: colors.community,
                plateSize: 48,
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name, style: context.type.sectionHeading),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: context.type.bodySecondary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: GochanoSpacing.sm),
          Wrap(
            spacing: GochanoSpacing.xxs,
            children: [
              GochanoBadge(
                label: GochanoLanguage.text(
                  members == 1 ? '1 member' : '$members members',
                  '$members জন সদস্য',
                ),
                icon: Icons.people_outline_rounded,
              ),
              if (chatEnabled)
                GochanoBadge(
                  label: GochanoLanguage.text('Chat on', 'চ্যাট চালু'),
                  tone: GochanoBadgeTone.info,
                  icon: Icons.chat_bubble_outline_rounded,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Create / join
// ---------------------------------------------------------------------------

Future<void> showGroupActionsSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.group_add_rounded),
            title: Text(GochanoLanguage.text('Create a group', 'গ্রুপ তৈরি করুন')),
            subtitle: Text(
              GochanoLanguage.text(
                'You become the admin and get an invite code to share.',
                'আপনি অ্যাডমিন হবেন এবং শেয়ার করার জন্য একটি ইনভাইট কোড পাবেন।',
              ),
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showCreateGroupSheet(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.login_rounded),
            title: Text(GochanoLanguage.text('Join with a code', 'কোড দিয়ে যোগ দিন')),
            subtitle: Text(
              GochanoLanguage.text(
                'Enter the invite code a classmate shared with you.',
                'সহপাঠীর দেওয়া ইনভাইট কোড লিখুন।',
              ),
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              showJoinGroupSheet(context);
            },
          ),
          const SizedBox(height: GochanoSpacing.sm),
        ],
      ),
    ),
  );
}

Future<void> showCreateGroupSheet(BuildContext context) =>
    _showGroupForm(context, join: false);

Future<void> showJoinGroupSheet(BuildContext context) =>
    _showGroupForm(context, join: true);

Future<void> _showGroupForm(BuildContext context, {required bool join}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _GroupForm(join: join),
    ),
  );
}

class _GroupForm extends StatefulWidget {
  const _GroupForm({required this.join});

  final bool join;

  @override
  State<_GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends State<_GroupForm> {
  final _first = TextEditingController();
  final _description = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final value = _first.text.trim();
    if (value.isEmpty) {
      setState(() {
        _error = widget.join
            ? GochanoLanguage.text('Enter the invite code.', 'ইনভাইট কোড লিখুন।')
            : GochanoLanguage.text('Name your group.', 'গ্রুপের নাম দিন।');
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (widget.join) {
        await ApiService.joinGroup(value);
      } else {
        await ApiService.createGroup(value, _description.text.trim());
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showGochanoMessage(
        context,
        widget.join
            ? GochanoLanguage.text('You joined the group.', 'আপনি গ্রুপে যোগ দিয়েছেন।')
            : GochanoLanguage.text('Group created.', 'গ্রুপ তৈরি হয়েছে।'),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          GochanoSpacing.lg,
          GochanoSpacing.xs,
          GochanoSpacing.lg,
          GochanoSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.join
                  ? GochanoLanguage.text('Join a group', 'গ্রুপে যোগ দিন')
                  : GochanoLanguage.text('Create a group', 'গ্রুপ তৈরি করুন'),
              style: context.type.sectionHeading,
            ),
            const SizedBox(height: GochanoSpacing.md),
            TextField(
              controller: _first,
              autofocus: true,
              textCapitalization: widget.join
                  ? TextCapitalization.characters
                  : TextCapitalization.words,
              decoration: InputDecoration(
                labelText: widget.join
                    ? GochanoLanguage.text('Invite code', 'ইনভাইট কোড')
                    : GochanoLanguage.text('Group name', 'গ্রুপের নাম'),
                hintText: widget.join
                    ? 'AB12CD'
                    : GochanoLanguage.text('CSE 5th Semester', 'সিএসই ৫ম সেমিস্টার'),
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (!widget.join) ...[
              const SizedBox(height: GochanoSpacing.sm),
              TextField(
                controller: _description,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: GochanoLanguage.text(
                    'What is it for? (optional)',
                    'কীসের জন্য? (ঐচ্ছিক)',
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                _error!,
                style: context.type.bodySecondary.copyWith(color: colors.error),
              ),
            ],
            const SizedBox(height: GochanoSpacing.md),
            PrimaryButton(
              label: widget.join
                  ? GochanoLanguage.text('Join', 'যোগ দিন')
                  : GochanoLanguage.text('Create', 'তৈরি করুন'),
              busy: _busy,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
