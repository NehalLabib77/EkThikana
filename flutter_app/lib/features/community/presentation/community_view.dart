// Community View — Study Mode Connect Surface (IA 13, 14, 15, 17, 18, 19, 20, 25).
//
// North Star: Community = CONNECT
// "Where do I connect, discuss, learn with others, and discover useful
// student conversations or groups?"
//
// Hierarchy:
// 1. Pinned Contextual AppStudyHeader (logo, EN | বাংলা, single universal search surface)
// 2. Compact Community Intro
// 3. Compact Composer / Ask-Share Card
// 4. Segmented Content Switcher (For You | Discussions | Study Groups)
// 5. Lazy Sliver-based Feed & Groups surfaces
// 6. Caching & Safe Cursor/Limit Pagination with Deduplication
// 7. Backward-compatible seams for existing Phase 7 tests

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/design_system/app_gradients.dart';
import '../../../core/design_system/components/app_study_header.dart';
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
import '../domain/community_models.dart';
import 'challenge_list_screen.dart';
import 'community_labels.dart';
import 'group_actions.dart' show showGroupActionsSheet;
import 'group_detail_screen.dart';
import 'question_bank_screen.dart';
import 'question_detail_screen.dart';
import 'shared_box_screen.dart';

class CommunityView extends StatefulWidget {
  const CommunityView({
    super.key,
    this.initialSegment = 'for_you',
    this.postsFn,
    this.leaderboardFn,
    this.createPostFn,
    this.postDetailFn,
    this.challengesFn,
    this.showHeader = true,
    this.mockGroups,
    this.groupsStream,
    this.onOpenGroup,
    this.onOpenSharedBox,
  });

  /// Which segment to open on. ('for_you', 'discussions', 'groups', 'challenges')
  final String initialSegment;

  final CommunityPostsFn? postsFn;
  final CommunityLeaderboardFn? leaderboardFn;
  final CommunityCreatePostFn? createPostFn;
  final CommunityPostFn? postDetailFn;
  final CommunityChallengeListFn? challengesFn;

  /// Whether to render the pinned contextual AppStudyHeader.
  final bool showHeader;

  /// Offline/mock groups list for deterministic widget testing without Firestore.
  final List<Map<String, dynamic>>? mockGroups;

  /// Injected groups stream for testing.
  final Stream<QuerySnapshot<Map<String, dynamic>>>? groupsStream;

  /// Optional navigation callback for opening a group.
  final void Function(String groupId, String groupName)? onOpenGroup;

  /// Optional navigation callback for opening Shared Box.
  final VoidCallback? onOpenSharedBox;

  @override
  State<CommunityView> createState() => _CommunityViewState();
}

class _CommunityViewState extends State<CommunityView>
    with AutomaticKeepAliveClientMixin {
  late String _segment;
  final ScrollController _scrollController = ScrollController();

  // Posts / feed state
  bool _loadingPosts = true;
  bool _loadingMore = false;
  String? _postsError;
  String? _loadMoreError;
  List<CommunityPost> _posts = const <CommunityPost>[];
  int _limit = 15;
  bool _hasMore = true;

  // Discussions state
  String _kind = '';
  String _sort = kPostSortRecent;
  String _category = '';
  List<Map<String, dynamic>> _leaders = const <Map<String, dynamic>>[];

  CommunityPostsFn get _fetchPosts => widget.postsFn ?? ApiService.listPosts;
  CommunityCreatePostFn get _createPost =>
      widget.createPostFn ?? ApiService.createPost;
  CommunityLeaderboardFn get _fetchLeaders =>
      widget.leaderboardFn ?? ApiService.leaderboard;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _segment = _canonicalSegment(widget.initialSegment);
    _scrollController.addListener(_onScroll);
    if (_segment != 'groups' && _segment != 'challenges') {
      _loadPosts(refresh: true);
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  String _canonicalSegment(String raw) {
    if (raw == 'questions') return 'discussions';
    return raw;
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    if (maxScroll - currentScroll <= 250 &&
        !_loadingMore &&
        !_loadingPosts &&
        _hasMore &&
        (_segment == 'for_you' || _segment == 'discussions')) {
      _loadMorePosts();
    }
  }

  Future<void> _loadPosts({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _limit = 15;
        _hasMore = true;
        _loadingPosts = true;
        _postsError = null;
        _loadMoreError = null;
      });
    }

    try {
      final payload = await _fetchPosts(
        kind: _segment == 'discussions' ? _kind : '',
        category: _segment == 'discussions' ? _category : '',
        popular: _segment == 'discussions' && _sort == kPostSortPopular,
        limit: _limit,
      );

      final rawList = ((payload['posts'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(CommunityPost.fromJson)
          .toList();

      // Duplicate post protection by document/post ID
      final seenIds = <String>{};
      final deduplicated = <CommunityPost>[];
      for (final post in rawList) {
        if (seenIds.add(post.id)) {
          deduplicated.add(post);
        }
      }

      if (!mounted) return;
      setState(() {
        _posts = deduplicated;
        _loadingPosts = false;
        // If server returned fewer items than requested or reached max cap (50), no more pages
        if (deduplicated.length < _limit || _limit >= 50) {
          _hasMore = false;
        }
      });

      if (_segment == 'discussions') {
        unawaited(_loadLeaders());
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingPosts = false;
        _postsError = friendlyErrorMessage(error);
      });
    }
  }

  Future<void> _loadMorePosts() async {
    if (_loadingMore || !_hasMore) return;
    setState(() {
      _loadingMore = true;
      _loadMoreError = null;
    });

    final nextLimit = (_limit + 15).clamp(15, 50);

    try {
      final payload = await _fetchPosts(
        kind: _segment == 'discussions' ? _kind : '',
        category: _segment == 'discussions' ? _category : '',
        popular: _segment == 'discussions' && _sort == kPostSortPopular,
        limit: nextLimit,
      );

      final rawList = ((payload['posts'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(CommunityPost.fromJson)
          .toList();

      final seenIds = <String>{};
      final deduplicated = <CommunityPost>[];
      for (final post in rawList) {
        if (seenIds.add(post.id)) {
          deduplicated.add(post);
        }
      }

      if (!mounted) return;
      setState(() {
        _limit = nextLimit;
        _loadingMore = false;
        if (deduplicated.length <= _posts.length || deduplicated.length < nextLimit || nextLimit >= 50) {
          _hasMore = false;
        }
        _posts = deduplicated;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _loadMoreError = friendlyErrorMessage(error);
      });
    }
  }

  Future<void> _loadLeaders() async {
    try {
      final payload = await _fetchLeaders(scope: 'global');
      final rows = ((payload['entries'] as List?) ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .toList();
      if (!mounted) return;
      setState(() => _leaders = rows.take(5).toList());
    } catch (_) {
      // Best-effort bonus
    }
  }

  Future<void> _openComposer() async {
    await showQuestionComposerSheet(
      context,
      createPost: _createPost,
      category: _category,
      onPosted: () => _loadPosts(refresh: true),
    );
  }

  Future<void> _handleRefresh() async {
    if (_segment == 'for_you' || _segment == 'discussions') {
      await _loadPosts(refresh: true);
    } else {
      // Trigger a state reload for groups
      setState(() {});
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  void _switchSegment(String newSegment) {
    if (_segment == newSegment) return;
    setState(() {
      _segment = newSegment;
    });
    if (newSegment == 'for_you' || newSegment == 'discussions') {
      _loadPosts(refresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = context.isDark;
    final width = MediaQuery.of(context).size.width;
    final isVeryNarrow = width < 340;

    // Shared purple top-wash background for both challenge and main views
    final Widget topWash = isDark
        ? const SizedBox.shrink()
        : Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 250,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppGradients.communityPage,
              ),
            ),
          );

    if (_segment == 'challenges') {
      return Stack(
        children: [
          topWash,
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                if (widget.showHeader)
                  AppStudyHeader(
                    showSearch: true,
                    trailingAction: SizedBox(
                      width: 44,
                      height: 44,
                      child: IconButton(
                        key: const ValueKey(
                            'community_header_group_options_button'),
                        icon: Icon(Icons.group_add_outlined,
                            size: isVeryNarrow ? 19 : 20),
                        tooltip:
                            GochanoLanguage.text('Group options', 'গ্রুপ অপশন'),
                        onPressed: () => showGroupActionsSheet(context),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                Expanded(
                  child: ChallengeListView(challengesFn: widget.challengesFn),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Stack(
      children: [
        topWash,
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              if (widget.showHeader)
                AppStudyHeader(
                  showSearch: true,
                  trailingAction: SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton(
                      key: const ValueKey(
                          'community_header_group_options_button'),
                      icon: Icon(Icons.group_add_outlined,
                          size: isVeryNarrow ? 19 : 20),
                      tooltip:
                          GochanoLanguage.text('Group options', 'গ্রুপ অপশন'),
                      onPressed: () => showGroupActionsSheet(context),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _handleRefresh,
                  child: CustomScrollView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isVeryNarrow ? 10 : 16,
                            vertical: 6,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildIntro(context),
                              const SizedBox(height: 10),
                              _buildComposerCard(context),
                              const SizedBox(height: 12),
                              _buildSegmentSwitcher(context),
                              if (_segment == 'discussions') ...[
                                const SizedBox(height: 10),
                                _buildDiscussionFilters(context),
                              ],
                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ),
                      ..._buildSegmentSlivers(context),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 32),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  Widget _buildIntro(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          GochanoLanguage.text('Community', 'কমিউনিটি'),
          style: type.pageTitle.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          GochanoLanguage.text(
            'Learn together. Share ideas. Stay connected.',
            'একসাথে শিখুন। ভাবনা শেয়ার করুন। যুক্ত থাকুন।',
          ),
          style: type.bodySecondary.copyWith(
            fontSize: 13,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildComposerCard(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Semantics(
      button: true,
      label: GochanoLanguage.text(
        'Ask a question or share something',
        'প্রশ্ন করুন বা কিছু শেয়ার করুন',
      ),
      child: Material(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _openComposer,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border.withValues(alpha: 0.6)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.community.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.edit_note_rounded,
                    size: 18,
                    color: colors.community,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    GochanoLanguage.text(
                      'Ask a question or share something…',
                      'প্রশ্ন করুন বা কিছু শেয়ার করুন…',
                    ),
                    style: type.bodySecondary.copyWith(
                      color: colors.textTertiary,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: colors.community,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 14, color: colors.onBrand),
                      const SizedBox(width: 4),
                      Text(
                        GochanoLanguage.text('Ask', 'প্রশ্ন'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.onBrand,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentSwitcher(BuildContext context) {
    final colors = context.colors;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<String>(
        showSelectedIcon: false,
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.padded,
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colors.community.withValues(alpha: 0.15);
            }
            return colors.surfaceElevated;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return colors.community;
            }
            return colors.textSecondary;
          }),
          side: WidgetStateProperty.all(
            BorderSide(color: colors.border.withValues(alpha: 0.7)),
          ),
        ),
        segments: [
          for (final value in kCommunitySegments)
            ButtonSegment<String>(
              value: value,
              label: Text(
                communitySegmentLabel(value),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
        ],
        selected: {
          if (kCommunitySegments.contains(_segment)) _segment else 'for_you',
        },
        onSelectionChanged: (selection) => _switchSegment(selection.first),
      ),
    );
  }

  Widget _buildDiscussionFilters(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Question Bank', 'প্রশ্ন ব্যাংক'),
          subtitle: GochanoLanguage.text(
            'Ask, answer, and share what worked.',
            'প্রশ্ন করুন, উত্তর দিন, যা কাজ করেছে শেয়ার করুন।',
          ),
        ),
        const SizedBox(height: 4),
        FilterChipBar<String>(
          options: kPostKinds,
          selected: _kind,
          onSelected: (value) {
            setState(() => _kind = value);
            _loadPosts(refresh: true);
          },
          labelOf: postKindLabel,
        ),
        const SizedBox(height: 6),
        FilterChipBar<String>(
          options: ['', ...kStudyCategories],
          selected: _category,
          onSelected: (value) {
            setState(() => _category = value);
            _loadPosts(refresh: true);
          },
          labelOf: studyCategoryLabel,
        ),
        const SizedBox(height: 6),
        FilterChipBar<String>(
          options: kPostSorts,
          selected: _sort,
          onSelected: (value) {
            setState(() => _sort = value);
            _loadPosts(refresh: true);
          },
          labelOf: postSortLabel,
        ),
      ],
    );
  }

  List<Widget> _buildSegmentSlivers(BuildContext context) {
    switch (_segment) {
      case 'discussions':
      case 'questions':
        return _buildPostsSlivers(context, isDiscussions: true);
      case 'challenges':
        return [
          SliverToBoxAdapter(
            child: ChallengeListView(challengesFn: widget.challengesFn),
          ),
        ];
      case 'groups':
        return _buildGroupsSlivers(context);
      case 'for_you':
      default:
        return _buildPostsSlivers(context, isDiscussions: false);
    }
  }

  List<Widget> _buildPostsSlivers(BuildContext context, {required bool isDiscussions}) {
    final colors = context.colors;
    final width = MediaQuery.of(context).size.width;
    final hPad = width < 340 ? 10.0 : 16.0;

    if (_loadingPosts) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
            child: _buildSkeletonLoader(context),
          ),
        ),
      ];
    }

    if (_postsError != null) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 24),
            child: AppCard(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off_rounded, size: 36, color: colors.error),
                    const SizedBox(height: 8),
                    Text(
                      GochanoLanguage.text(
                        "Couldn't load Community.",
                        'কমিউনিটি লোড করা যায়নি।',
                      ),
                      style: context.type.sectionHeading,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _postsError!,
                      style: context.type.bodySecondary,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 44,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(GochanoLanguage.text('Retry', 'পুনরায় চেষ্টা')),
                        onPressed: () => _loadPosts(refresh: true),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ];
    }

    if (_posts.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 24),
            child: EmptyState(
              illustration: GochanoArt.featureCommunity,
              title: GochanoLanguage.text(
                'No discussions yet',
                'এখনো কোনো আলোচনা নেই',
              ),
              message: GochanoLanguage.text(
                'Start a conversation or check back later.',
                'একটি আলোচনা শুরু করুন বা পরে আবার দেখুন।',
              ),
              actionLabel: GochanoLanguage.text('Ask a question', 'প্রশ্ন করুন'),
              onAction: _openComposer,
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: hPad),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final post = _posts[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildPostCard(context, post),
              );
            },
            childCount: _posts.length,
          ),
        ),
      ),
      if (isDiscussions && _leaders.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 8),
            child: _buildLeaderboardSection(context),
          ),
        ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: _buildPaginationFooter(context),
        ),
      ),
    ];
  }

  Widget _buildPostCard(BuildContext context, CommunityPost post) {
    final colors = context.colors;
    final type = context.type;

    return Semantics(
      button: true,
      label: post.title,
      child: Material(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(
            GochanoRoute.to(
              builder: (_) => QuestionDetailScreen(
                postId: post.id,
                postFn: widget.postDetailFn,
              ),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border.withValues(alpha: 0.7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Author row
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: colors.community.withValues(alpha: 0.15),
                      child: Text(
                        post.authorName.isNotEmpty
                            ? post.authorName.substring(0, 1).toUpperCase()
                            : 'S',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colors.community,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        post.authorName.isNotEmpty ? post.authorName : 'Student',
                        style: type.bodySecondary.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (post.category.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.brandSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          studyCategoryLabel(post.category),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: colors.brand,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),

                // Post Title
                Text(
                  post.title,
                  style: type.cardHeading.copyWith(fontSize: 15),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),

                // Body preview
                if (post.body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    post.body,
                    style: type.bodySecondary.copyWith(
                      color: colors.textSecondary,
                      fontSize: 13,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                const SizedBox(height: 10),

                // Footer interactions & metadata
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildStatPill(
                      context,
                      icon: Icons.chat_bubble_outline_rounded,
                      label: '${post.answerCount}',
                    ),
                    _buildStatPill(
                      context,
                      icon: Icons.thumb_up_alt_outlined,
                      label: '${post.usefulCount}',
                    ),
                    if (post.hasAcceptedAnswer)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: colors.successSoft,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_rounded, size: 12, color: colors.success),
                            const SizedBox(width: 4),
                            Text(
                              GochanoLanguage.text('Solved', 'সমাধান'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (post.kind.isNotEmpty)
                      Text(
                        '· ${postKindLabel(post.kind)}',
                        style: type.bodySecondary.copyWith(
                          fontSize: 11,
                          color: colors.textTertiary,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatPill(BuildContext context, {required IconData icon, required String label}) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.textSecondary),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboardSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: GochanoLanguage.text('Top contributors', 'সেরা অবদানকারী'),
          subtitle: GochanoLanguage.text(
            'Learning Points earned by helping others.',
            'অন্যদের সাহায্য করে অর্জিত লার্নিং পয়েন্ট।',
          ),
        ),
        for (var i = 0; i < _leaders.length; i++)
          _buildLeaderCard(context, i, _leaders[i]),
      ],
    );
  }

  Widget _buildLeaderCard(BuildContext context, int rank, Map<String, dynamic> entry) {
    final colors = context.colors;
    final type = context.type;
    final points = (entry['points'] is int)
        ? entry['points'] as int
        : int.tryParse('${entry['points']}') ?? 0;
    final name = '${entry['displayName'] ?? ''}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.border.withValues(alpha: 0.6)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: colors.brandSoft,
              child: Text(
                '${rank + 1}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colors.brand),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name.isNotEmpty ? name : 'Student',
                style: type.bodySecondary.copyWith(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              GochanoLanguage.text('$points pts', '$points পয়েন্ট'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.community,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginationFooter(BuildContext context) {
    final colors = context.colors;

    if (_loadingMore) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_loadMoreError != null) {
      return Center(
        child: SizedBox(
          height: 44,
          child: TextButton.icon(
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text(
              GochanoLanguage.text('Load more', 'আরও লোড করুন'),
            ),
            onPressed: _loadMorePosts,
          ),
        ),
      );
    }

    if (!_hasMore && _posts.isNotEmpty) {
      return Center(
        child: Text(
          GochanoLanguage.text("You're all caught up", 'সব দেখা শেষ'),
          style: TextStyle(
            fontSize: 12,
            color: colors.textTertiary,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildSkeletonLoader(BuildContext context) {
    final colors = context.colors;
    return Column(
      children: List.generate(
        3,
        (_) => Container(
          height: 90,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.border.withValues(alpha: 0.4)),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildGroupsSlivers(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final hPad = width < 340 ? 10.0 : 16.0;

    // Bridge card to Shared Box & Create Group Header
    final topCard = SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 4),
        child: Column(
          children: [
            _buildSharedBoxBridge(context),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  GochanoLanguage.text('Study Groups', 'স্টাডি গ্রুপ'),
                  style: context.type.sectionHeading,
                ),
                SizedBox(
                  height: 44,
                  child: TextButton.icon(
                    icon: const Icon(Icons.group_add_rounded, size: 18),
                    label: Text(GochanoLanguage.text('New group', 'নতুন গ্রুপ')),
                    onPressed: () => showGroupActionsSheet(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    // If mockGroups provided, render them deterministically
    if (widget.mockGroups != null) {
      final groups = widget.mockGroups!;
      if (groups.isEmpty) {
        return [
          topCard,
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
              child: _buildEmptyGroups(context),
            ),
          ),
        ];
      }
      return [
        topCard,
        SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildRawGroupCard(context, groups[i]),
              ),
              childCount: groups.length,
            ),
          ),
        ),
      ];
    }

    // Stream-backed groups
    final stream = widget.groupsStream ?? FirestoreService.myGroups();

    return [
      topCard,
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: stream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 20),
                child: StaticLoadingState(
                  message: GochanoLanguage.text(
                    'Loading your groups…',
                    'আপনার গ্রুপ লোড হচ্ছে…',
                  ),
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            return SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 20),
                child: ErrorState(message: friendlyErrorMessage(snapshot.error)),
              ),
            );
          }

          final groups = [...?snapshot.data?.docs]
            ..sort(
              (a, b) => (a.data()['name']?.toString() ?? '').compareTo(
                b.data()['name']?.toString() ?? '',
              ),
            );

          if (groups.isEmpty) {
            return SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
                child: _buildEmptyGroups(context),
              ),
            );
          }

          return SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: hPad),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _GroupCard(
                    doc: groups[i],
                    onOpenGroup: widget.onOpenGroup,
                  ),
                ),
                childCount: groups.length,
              ),
            ),
          );
        },
      ),
    ];
  }

  Widget _buildSharedBoxBridge(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Semantics(
      button: true,
      label: GochanoLanguage.text(
        'Shared Box resources',
        'শেয়ার্ড বক্স উপকরণ',
      ),
      child: Material(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: widget.onOpenSharedBox ??
              () => Navigator.of(context).push(
                    GochanoRoute.to(builder: (_) => const SharedBoxScreen()),
                  ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border.withValues(alpha: 0.7)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: colors.study.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.folder_shared_outlined, size: 20, color: colors.study),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        GochanoLanguage.text('Shared Box', 'শেয়ার্ড বক্স'),
                        style: type.bodySecondary.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        GochanoLanguage.text(
                          'Materials shared across your study groups',
                          'আপনার স্টাডি গ্রুপে শেয়ার করা উপকরণ',
                        ),
                        style: type.bodySecondary.copyWith(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: colors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyGroups(BuildContext context) {
    return EmptyState(
      illustration: GochanoArt.featureGroups,
      title: GochanoLanguage.text(
        'No study groups yet',
        'এখনো কোনো স্টাডি গ্রুপ নেই',
      ),
      message: GochanoLanguage.text(
        'Create a group for your class, or join one with an invite code from a classmate.',
        'আপনার ক্লাসের জন্য একটি গ্রুপ তৈরি করুন, অথবা সহপাঠীর ইনভাইট কোড দিয়ে যোগ দিন।',
      ),
      actionLabel: GochanoLanguage.text('New group', 'নতুন গ্রুপ'),
      onAction: () => showGroupActionsSheet(context),
    );
  }

  Widget _buildRawGroupCard(BuildContext context, Map<String, dynamic> data) {
    final colors = context.colors;
    final name = data['name']?.toString() ?? '';
    final description = data['description']?.toString() ?? '';
    final members = ((data['memberIds'] as List?) ?? const []).length;
    final chatEnabled = data['chatEnabled'] == true;
    final groupId = data['id']?.toString() ?? '';

    return AppCard(
      accent: colors.community,
      onTap: () {
        if (widget.onOpenGroup != null) {
          widget.onOpenGroup!(groupId, name);
        } else {
          Navigator.of(context).push(
            GochanoRoute.to(
              builder: (_) => GroupDetailScreen(groupId: groupId, groupName: name),
            ),
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GochanoIllustrationTile(
                GochanoArt.featureGroups,
                accent: colors.community,
                plateSize: 44,
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

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.doc, this.onOpenGroup});

  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final void Function(String groupId, String groupName)? onOpenGroup;

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
      onTap: () {
        if (onOpenGroup != null) {
          onOpenGroup!(doc.id, name);
        } else {
          Navigator.of(context).push(
            GochanoRoute.to(
              builder: (_) => GroupDetailScreen(groupId: doc.id, groupName: name),
            ),
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GochanoIllustrationTile(
                GochanoArt.featureGroups,
                accent: colors.community,
                plateSize: 44,
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
