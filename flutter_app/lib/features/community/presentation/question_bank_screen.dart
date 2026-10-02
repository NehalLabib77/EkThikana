// Phase 7 - Question Bank (spec 7.3) and Learning Points (spec 7.6).
//
// The bank is the Community tab's "Questions" segment: one feed of
// question / solution / notes / achievement posts, filterable by kind and
// sorted by recency or by how much use they got, with the Learning Points
// leaderboard underneath (spec 7.6 - the only reward surface in Community).
//
// Everything is behind an injectable seam (`postsFn`, `createPostFn`, ...)
// following the exam screens' `ExamCreateFn` pattern, so a test can drive
// the whole view from canned JSON without Firestore and without a network.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_illustration.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../core/page_route.dart';
import '../../../services/api_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../domain/community_models.dart';
import 'community_labels.dart';
import 'question_detail_screen.dart';

/// The body of the Community "Questions" segment. No scaffold, no app bar:
/// `CommunityView` owns the frame and the segment switch.
class QuestionBankView extends StatefulWidget {
  const QuestionBankView({
    super.key,
    this.postsFn,
    this.leaderboardFn,
    this.createPostFn,
    this.postDetailFn,
    this.category = '',
    this.initialKind = '',
    this.initialSort = kPostSortRecent,
  });

  final CommunityPostsFn? postsFn;
  final CommunityLeaderboardFn? leaderboardFn;
  final CommunityCreatePostFn? createPostFn;
  final CommunityPostFn? postDetailFn;

  /// Filters the feed to one study category. Empty means every category.
  final String category;
  final String initialKind;
  final String initialSort;

  @override
  State<QuestionBankView> createState() => _QuestionBankViewState();
}

class _QuestionBankViewState extends State<QuestionBankView> {
  late String _kind;
  late String _sort;
  bool _loading = true;
  String? _error;
  List<CommunityPost> _posts = const <CommunityPost>[];
  List<Map<String, dynamic>> _leaders = const <Map<String, dynamic>>[];

  CommunityPostsFn get _fetchPosts => widget.postsFn ?? ApiService.listPosts;
  CommunityCreatePostFn get _createPost =>
      widget.createPostFn ?? ApiService.createPost;
  CommunityLeaderboardFn get _fetchLeaders =>
      widget.leaderboardFn ?? ApiService.leaderboard;

  @override
  void initState() {
    super.initState();
    _kind = widget.initialKind;
    _sort = widget.initialSort;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final Map<String, dynamic> payload;
    try {
      payload = await _fetchPosts(
        kind: _kind,
        category: widget.category,
        popular: _sort == kPostSortPopular,
        limit: 30,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(error);
      });
      return;
    }
    final rows = ((payload['posts'] as List?) ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(CommunityPost.fromJson)
        .toList();
    if (!mounted) return;
    setState(() {
      _posts = rows;
      _loading = false;
    });
    unawaited(_loadLeaders());
  }

  /// Best effort: the leaderboard is a bonus under the feed, never a reason
  /// for the feed itself to report a failure.
  Future<void> _loadLeaders() async {
    final List<Map<String, dynamic>> rows;
    try {
      final payload = await _fetchLeaders(scope: 'global');
      rows = ((payload['entries'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    setState(() => _leaders = rows.take(5).toList());
  }

  Future<void> _compose() async {
    await showQuestionComposerSheet(
      context,
      createPost: _createPost,
      category: widget.category,
      onPosted: _load,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GochanoSpacing.md,
            GochanoSpacing.sm,
            GochanoSpacing.md,
            GochanoSpacing.xs,
          ),
          child: FilterChipBar<String>(
            options: kPostKinds,
            selected: _kind,
            onSelected: (value) {
              setState(() => _kind = value);
              _load();
            },
            labelOf: postKindLabel,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            GochanoSpacing.md,
            0,
            GochanoSpacing.md,
            GochanoSpacing.xs,
          ),
          child: FilterChipBar<String>(
            options: kPostSorts,
            selected: _sort,
            onSelected: (value) {
              setState(() => _sort = value);
              _load();
            },
            labelOf: postSortLabel,
          ),
        ),
        Expanded(child: _buildBody(context)),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return StaticLoadingState(
        compact: true,
        message: GochanoLanguage.text(
          'Loading questions…',
          'প্রশ্ন লোড হচ্ছে…',
        ),
      );
    }
    if (_error != null) {
      return ErrorState(compact: true, message: _error!, onRetry: _load);
    }
    if (_posts.isEmpty && _leaders.isEmpty) {
      return EmptyState(
        compact: true,
        illustration: GochanoArt.featureCommunity,
        accent: context.colors.community,
        title: GochanoLanguage.text('No questions yet', 'এখনো কোনো প্রশ্ন নেই'),
        message: GochanoLanguage.text(
          'Ask the first one - your group answers, and you both earn '
              'Learning Points.',
          'প্রথমটি করুন - আপনার গ্রুপ উত্তর দেবে, আপনারা দুজনেই লার্নিং '
              'পয়েন্ট পাবেন।',
        ),
        actionLabel: GochanoLanguage.text('Ask a question', 'প্রশ্ন করুন'),
        onAction: _compose,
      );
    }

    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Question Bank', 'প্রশ্ন ব্যাংক'),
          subtitle: GochanoLanguage.text(
            'Ask, answer, and share what worked.',
            'প্রশ্ন করুন, উত্তর দিন, যা কাজ করেছে শেয়ার করুন।',
          ),
          action: PrimaryButton(
            label: GochanoLanguage.text('Ask', 'প্রশ্ন'),
            icon: Icons.add_rounded,
            expand: false,
            onPressed: _compose,
          ),
        ),
        for (final post in _posts) _postCard(context, post),
        if (_leaders.isNotEmpty) ...[
          SectionHeader(
            title: GochanoLanguage.text('Top contributors', 'সেরা অবদানকারী'),
            subtitle: GochanoLanguage.text(
              'Learning Points earned by helping others.',
              'অন্যদের সাহায্য করে অর্জিত লার্নিং পয়েন্ট।',
            ),
          ),
          for (var i = 0; i < _leaders.length; i++)
            _leaderCard(context, i, _leaders[i]),
        ],
      ],
    );
  }

  Widget _postCard(BuildContext context, CommunityPost post) {
    final colors = context.colors;
    final type = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      child: AppCard(
        accent: colors.community,
        semanticLabel: post.title,
        onTap: () => Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) => QuestionDetailScreen(
              postId: post.id,
              postFn: widget.postDetailFn,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GochanoIllustrationTile(
                  GochanoArt.featureCommunity,
                  accent: colors.community,
                  plateSize: 40,
                ),
                const SizedBox(width: GochanoSpacing.sm),
                Expanded(
                  child: Text(
                    post.title,
                    style: type.cardHeading,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (post.body.isNotEmpty) ...[
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                post.body,
                style: type.bodySecondary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: GochanoSpacing.sm),
            Wrap(
              spacing: GochanoSpacing.xxs,
              runSpacing: GochanoSpacing.xxs,
              children: [
                GochanoBadge(label: postKindLabel(post.kind)),
                if (post.category.isNotEmpty)
                  GochanoBadge(
                    label: studyCategoryLabel(post.category),
                    tone: GochanoBadgeTone.info,
                  ),
                GochanoBadge(
                  label: _answersLabel(post.answerCount),
                  icon: Icons.chat_bubble_outline_rounded,
                ),
                GochanoBadge(
                  label: _usefulLabel(post.usefulCount),
                  icon: Icons.thumb_up_alt_outlined,
                ),
                if (post.hasAcceptedAnswer)
                  GochanoBadge(
                    label: GochanoLanguage.text('Solved', 'সমাধান হয়েছে'),
                    tone: GochanoBadgeTone.success,
                    icon: Icons.check_circle_outline_rounded,
                  ),
                if (post.duplicateOf.isNotEmpty)
                  GochanoBadge(
                    label: GochanoLanguage.text(
                      'Similar question exists',
                      'মিল থাকা প্রশ্ন আছে',
                    ),
                    tone: GochanoBadgeTone.warning,
                    icon: Icons.content_copy_rounded,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _leaderCard(
    BuildContext context,
    int rank,
    Map<String, dynamic> entry,
  ) {
    final points = (entry['points'] is int)
        ? entry['points'] as int
        : int.tryParse('${entry['points']}') ?? 0;
    final name = '${entry['displayName'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
      child: AppCard(
        padding: const EdgeInsets.symmetric(
          horizontal: GochanoSpacing.md,
          vertical: GochanoSpacing.sm,
        ),
        child: Row(
          children: [
            Text('${rank + 1}', style: context.type.cardHeading),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: Text(
                name.isEmpty
                    ? GochanoLanguage.text(
                        'Anonymous student',
                        'নামহীন শিক্ষার্থী',
                      )
                    : name,
                style: context.type.body,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GochanoBadge(
              label: _pointsLabel(points),
              tone: GochanoBadgeTone.brand,
              icon: Icons.emoji_events_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

String _answersLabel(int count) {
  if (count == 1) {
    return GochanoLanguage.text('1 answer', '১টি উত্তর');
  }
  return GochanoLanguage.text('$count answers', '$countটি উত্তর');
}

String _usefulLabel(int count) {
  if (count == 1) {
    return GochanoLanguage.text('1 useful', '১টি উপকারী');
  }
  return GochanoLanguage.text('$count useful', '$countটি উপকারী');
}

String _pointsLabel(int points) {
  return GochanoLanguage.text('$points points', '$points পয়েন্ট');
}

/// The composer: one sheet for a question, a solution, notes or an
/// achievement. The kind and the category are pickers rather than free text
/// so every post the API receives carries a value it accepts (spec 7.5).
Future<void> showQuestionComposerSheet(
  BuildContext context, {
  required CommunityCreatePostFn createPost,
  String category = '',
  VoidCallback? onPosted,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
      ),
      child: _QuestionComposer(
        createPost: createPost,
        category: category,
        onPosted: onPosted,
      ),
    ),
  );
}

class _QuestionComposer extends StatefulWidget {
  const _QuestionComposer({
    required this.createPost,
    required this.category,
    this.onPosted,
  });

  final CommunityCreatePostFn createPost;
  final String category;
  final VoidCallback? onPosted;

  @override
  State<_QuestionComposer> createState() => _QuestionComposerState();
}

class _QuestionComposerState extends State<_QuestionComposer> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _kind = 'question';
  String _category = '';
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _category = widget.category;
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() {
        _error = GochanoLanguage.text(
          'Give it a title first.',
          'আগে শিরোনাম দিন।',
        );
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.createPost(
        kind: _kind,
        title: title,
        body: _body.text.trim(),
        category: _category,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      showGochanoMessage(
        context,
        GochanoLanguage.text('Posted to the bank.', 'ব্যাংকে পোস্ট হয়েছে।'),
      );
      widget.onPosted?.call();
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
              GochanoLanguage.text('Ask the bank', 'ব্যাংকে জিজ্ঞাসা করুন'),
              style: context.type.sectionHeading,
            ),
            const SizedBox(height: GochanoSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _kind,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text('Kind', 'ধরন'),
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final kind in kPostKinds.where((k) => k.isNotEmpty))
                  DropdownMenuItem(
                    value: kind,
                    child: Text(postKindLabel(kind)),
                  ),
              ],
              onChanged: (value) => setState(() => _kind = value ?? _kind),
            ),
            const SizedBox(height: GochanoSpacing.sm),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text('Title', 'শিরোনাম'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: GochanoSpacing.sm),
            TextField(
              controller: _body,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text('Details', 'বিস্তারিত'),
                hintText: GochanoLanguage.text(
                  'What you tried, and where you got stuck.',
                  'আপনি কী চেষ্টা করেছেন, কোথায় আটকেছেন।',
                ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: GochanoSpacing.sm),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: InputDecoration(
                labelText: GochanoLanguage.text('Category', 'বিভাগ'),
                border: const OutlineInputBorder(),
              ),
              items: [
                DropdownMenuItem(
                  value: '',
                  child: Text(
                    GochanoLanguage.text('Any subject', 'যেকোনো বিষয়'),
                  ),
                ),
                for (final value in kStudyCategories)
                  DropdownMenuItem(
                    value: value,
                    child: Text(studyCategoryLabel(value)),
                  ),
              ],
              onChanged: (value) => setState(() => _category = value ?? ''),
            ),
            if (_error != null) ...[
              const SizedBox(height: GochanoSpacing.xs),
              Text(
                _error!,
                style: context.type.bodySecondary.copyWith(color: colors.error),
              ),
            ],
            const SizedBox(height: GochanoSpacing.md),
            PrimaryButton(
              label: GochanoLanguage.text('Post', 'পোস্ট'),
              busy: _busy,
              busyLabel: GochanoLanguage.text('Posting.', 'পোস্ট হচ্ছে।'),
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}
