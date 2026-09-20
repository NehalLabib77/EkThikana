// Community — create / join group bottom sheets.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../services/api_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';

enum _GroupSheetAction { create, join }

Future<void> showGroupActionsSheet(BuildContext context) async {
  final action = await showModalBottomSheet<_GroupSheetAction>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.group_add_rounded),
            title: Text(
              GochanoLanguage.text('Create a group', 'গ্রুপ তৈরি করুন'),
            ),
            subtitle: Text(
              GochanoLanguage.text(
                'You become the admin and get an invite code to share.',
                'আপনি অ্যাডমিন হবেন এবং শেয়ার করার জন্য একটি ইনভাইট কোড পাবেন।',
              ),
            ),
            onTap: () =>
                Navigator.of(sheetContext).pop(_GroupSheetAction.create),
          ),
          ListTile(
            leading: const Icon(Icons.login_rounded),
            title: Text(
              GochanoLanguage.text('Join with a code', 'কোড দিয়ে যোগ দিন'),
            ),
            subtitle: Text(
              GochanoLanguage.text(
                'Enter the invite code a classmate shared with you.',
                'সহপাঠীর দেওয়া ইনভাইট কোড লিখুন।',
              ),
            ),
            onTap: () => Navigator.of(sheetContext).pop(_GroupSheetAction.join),
          ),
          const SizedBox(height: GochanoSpacing.sm),
        ],
      ),
    ),
  );

  if (!context.mounted || action == null) return;
  if (action == _GroupSheetAction.create) {
    await showCreateGroupSheet(context);
  } else if (action == _GroupSheetAction.join) {
    await showJoinGroupSheet(context);
  }
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
            ? GochanoLanguage.text(
                'Enter the invite code.',
                'ইনভাইট কোড লিখুন।',
              )
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
            ? GochanoLanguage.text(
                'You joined the group.',
                'আপনি গ্রুপে যোগ দিয়েছেন।',
              )
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
                    : GochanoLanguage.text(
                        'CSE 5th Semester',
                        'সিএসই ৫ম সেমিস্টার',
                      ),
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
