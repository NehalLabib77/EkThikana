// Phase 7 - one Question Bank entry (spec 7.3) with its answers, the
// accepted-answer control that earns the asker's +5, the peer "helpful"
// control that earns the answerer's +3, and the notes "useful" control
// that earns the author's +10 (spec 7.6).
//
// All three point awards are server decisions: the screen only decides
// which controls a given viewer is allowed to *see*, using the post's
// author and the signed-in uid.

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_illustration.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../services/api_service.dart';
import '../../../services/firestore_service.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../domain/community_models.dart';
import 'community_labels.dart';

class QuestionDetailScreen extends StatefulWidget {
  const QuestionDetailScreen({
    super.key,
    required this.postId,
    this.postFn,
    this.answerFn,
    this.acceptFn,
    this.helpfulFn,
    this.usefulFn,
    this.currentUid,
  });

  final String postId;

  final CommunityPostFn? postFn;
  final CommunityAnswerFn? answerFn;
  final CommunityAnswerActionFn? acceptFn;
  final CommunityAnswerActionFn? helpfulFn;
  final CommunityPostActionFn? usefulFn;

  /// Overrides the signed-in uid. Tests pass one so the asker-only and the
  /// peer-only controls can both be exercised; production passes nothing
  /// and reads `FirestoreService.uid`.
  final String? currentUid;

  @override
  State<QuestionDetailScreen> createState() => _QuestionDetailScreenState();
}

class _QuestionDetailScreenState extends State<QuestionDetailScreen> {
  final _reply = TextEditingController();
  CommunityPost? _post;
  bool _loading = true;
  bool _busy = false;
  String? _error;

  CommunityPostFn get _fetchPost => widget.postFn ?? ApiService.getPost;
  CommunityAnswerFn get _addAnswer => widget.answerFn ?? ApiService.addAnswer;
  CommunityAnswerActionFn get _accept =>
      widget.acceptFn ?? ApiService.acceptAnswer;
  CommunityAnswerActionFn get _helpful =>
      widget.helpfulFn ?? ApiService.markAnswerHelpful;
  CommunityPostActionFn get _useful =>
      widget.usefulFn ?? ApiService.markPostUseful;

  String get _uid => widget.currentUid ?? FirestoreService.uid ?? '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = await _fetchPost(widget.postId);
      final post = CommunityPost.fromJson(payload);
      if (!mounted) return;
      setState(() {
        _post = post;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      await _addAnswer(widget.postId, text);
      _reply.clear();
      await _load();
    } catch (error) {
      if (!mounted) return;
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (error) {
      if (!mounted) return;
      showGochanoMessage(context, friendlyErrorMessage(error), isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _canAccept(CommunityAnswer answer) {
    final post = _post;
    return post != null &&
        _uid.isNotEmpty &&
        _uid == post.authorId &&
        !post.hasAcceptedAnswer &&
        answer.authorId != _uid;
  }

  bool _canMarkHelpful(CommunityAnswer answer) =>
      _uid.isNotEmpty && answer.authorId != _uid && !answer.helpful;

  bool _canMarkUseful(CommunityPost post) =>
      post.isNotes && _uid.isNotEmpty && _uid != post.authorId;

  @override
  Widget build(BuildContext context) {
    final post = _post;
    final String? title;
    if (post != null && post.title.isNotEmpty) {
      title = post.title;
    } else {
      title = GochanoLanguage.text('Question', 'প্রশ্ন');
    }

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(
        title: title,
        subtitle: post == null
            ? null
            : post.category.isEmpty
            ? postKindLabel(post.kind)
            : '${postKindLabel(post.kind)} · '
                  '${studyCategoryLabel(post.category)}',
      ),
      bottomBar: post == null || post.kind != 'question'
          ? null
          : Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _reply,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: GochanoLanguage.text(
                        'Write an answer',
                        'উত্তর লিখুন',
                      ),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _sendReply(),
                  ),
                ),
                const SizedBox(width: GochanoSpacing.sm),
                PrimaryButton(
                  label: GochanoLanguage.text('Send', 'পাঠান'),
                  expand: false,
                  busy: _busy,
                  onPressed: _sendReply,
                ),
              ],
            ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return StaticLoadingState(
        message: GochanoLanguage.text(
          'Opening the question…',
          'প্রশ্নটি খোলা হচ্ছে…',
        ),
      );
    }
    if (_error != null) {
      return ErrorState(message: _error!, onRetry: _load);
    }
    final post = _post;
    if (post == null) {
      return EmptyState(
        illustration: GochanoArt.featureCommunity,
        title: GochanoLanguage.text('Post not found', 'পোস্ট পাওয়া যায়নি'),
        message: GochanoLanguage.text(
          'It may have been removed.',
          'সরানো হয়ে থাকতে পারে।',
        ),
      );
    }

    return ListView(
      padding: GochanoSpacing.scrollBody,
      children: [
        _postCard(context, post),
        SectionHeader(
          title: GochanoLanguage.text('Answers', 'উত্তর'),
          subtitle: GochanoLanguage.text(
            '${post.answerCount} so far',
            'এখন পর্যন্ত ${post.answerCount}',
          ),
        ),
        if (post.answers.isEmpty)
          AppCard(
            child: Text(
              GochanoLanguage.text(
                'No answers yet - be the first to help.',
                'এখনো উত্তর নেই - প্রথম সাহায্যকারী হন।',
              ),
              style: context.type.bodySecondary,
            ),
          )
        else
          for (final answer in post.answers) _answerCard(context, answer),
      ],
    );
  }

  Widget _postCard(BuildContext context, CommunityPost post) {
    final colors = context.colors;
    return AppCard(
      accent: colors.community,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GochanoIllustrationTile(
                post.kind == 'notes'
                    ? GochanoArt.fileNote
                    : GochanoArt.featureCommunity,
                accent: colors.community,
                plateSize: 40,
              ),
              const SizedBox(width: GochanoSpacing.sm),
              Expanded(
                child: Text(post.title, style: context.type.cardHeading),
              ),
            ],
          ),
          if (post.authorName.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.xs),
            Text(post.authorName, style: context.type.caption),
          ],
          if (post.body.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.sm),
            Text(post.body, style: context.type.body),
          ],
          if (post.duplicateOf.isNotEmpty) ...[
            const SizedBox(height: GochanoSpacing.sm),
            Text(
              GochanoLanguage.text(
                'Similar to an existing question: ',
                'বিদ্যমান প্রশ্নের সাথে মিল: ',
              ),
              style: context.type.caption,
            ),
            Text(post.duplicateOfTitle, style: context.type.bodySecondary),
          ],
          const SizedBox(height: GochanoSpacing.sm),
          Wrap(
            spacing: GochanoSpacing.xxs,
            runSpacing: GochanoSpacing.xxs,
            children: [
              GochanoBadge(label: postKindLabel(post.kind)),
              if (post.hasAcceptedAnswer)
                GochanoBadge(
                  label: GochanoLanguage.text('Solved', 'সমাধান হয়েছে'),
                  tone: GochanoBadgeTone.success,
                  icon: Icons.check_circle_outline_rounded,
                ),
              GochanoBadge(
                label: _usefulLabel(post.usefulCount),
                icon: Icons.thumb_up_alt_outlined,
              ),
            ],
          ),
          if (_canMarkUseful(post)) ...[
            const SizedBox(height: GochanoSpacing.sm),
            SecondaryButton(
              label: GochanoLanguage.text('Mark useful', 'উপকারী চিহ্নিত'),
              icon: Icons.thumb_up_alt_outlined,
              expand: false,
              onPressed: () => _run(() => _useful(widget.postId)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _answerCard(BuildContext context, CommunityAnswer answer) {
    final colors = context.colors;
    final canAccept = _canAccept(answer);
    final canHelpful = _canMarkHelpful(answer);
    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.sm),
      child: AppCard(
        accent: answer.accepted ? colors.success : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    answer.authorName.isEmpty
                        ? GochanoLanguage.text('Student', 'শিক্ষার্থী')
                        : answer.authorName,
                    style: context.type.cardHeading,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (answer.accepted)
                  GochanoBadge(
                    label: GochanoLanguage.text('Accepted', 'গৃহীত'),
                    tone: GochanoBadgeTone.success,
                    icon: Icons.check_circle_rounded,
                  )
                else if (answer.helpful)
                  GochanoBadge(
                    label: GochanoLanguage.text('Helpful', 'সহায়ক'),
                    tone: GochanoBadgeTone.info,
                    icon: Icons.favorite_border_rounded,
                  ),
              ],
            ),
            const SizedBox(height: GochanoSpacing.xs),
            Text(answer.body, style: context.type.body),
            if (canAccept || canHelpful) ...[
              const SizedBox(height: GochanoSpacing.sm),
              Wrap(
                spacing: GochanoSpacing.xs,
                children: [
                  if (canAccept)
                    SecondaryButton(
                      label: GochanoLanguage.text(
                        'Accept answer',
                        'উত্তর গ্রহণ করুন',
                      ),
                      icon: Icons.check_rounded,
                      expand: false,
                      onPressed: () =>
                          _run(() => _accept(widget.postId, answer.id)),
                    ),
                  if (canHelpful)
                    SecondaryButton(
                      label: GochanoLanguage.text(
                        'Mark helpful',
                        'সহায়ক চিহ্নিত',
                      ),
                      icon: Icons.favorite_border_rounded,
                      expand: false,
                      onPressed: () =>
                          _run(() => _helpful(widget.postId, answer.id)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _usefulLabel(int count) {
  if (count == 1) {
    return GochanoLanguage.text('1 useful', '১টি উপকারী');
  }
  return GochanoLanguage.text('$count useful', '$countটি উপকারী');
}
