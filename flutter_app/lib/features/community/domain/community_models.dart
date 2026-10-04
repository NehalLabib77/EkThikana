// Phase 7 - Ziku Learning Community: wire models for the Question Bank,
// Learning Points and Exam Challenges (spec 7.3 / 7.4 / 7.6).
//
// These are thin `fromJson` holders. Every rule (duplicate detection,
// point awards, grading) stays server-side; the client only renders what
// the API returns.

import 'package:flutter/foundation.dart';

@immutable
class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.category,
    required this.authorId,
    required this.authorName,
    required this.subject,
    required this.chapter,
    required this.answerCount,
    required this.usefulCount,
    required this.acceptedAnswerId,
    required this.duplicateOf,
    required this.duplicateOfTitle,
    required this.duplicateConfidence,
    required this.groupId,
    required this.groupName,
    required this.usefulBy,
    required this.answers,
  });

  final String id;
  final String kind;
  final String title;
  final String body;
  final String category;
  final String authorId;
  final String authorName;
  final String subject;
  final String chapter;
  final int answerCount;
  final int usefulCount;
  final String acceptedAnswerId;
  final String duplicateOf;
  final String duplicateOfTitle;
  final double duplicateConfidence;
  final String groupId;
  final String groupName;
  final List<String> usefulBy;
  final List<CommunityAnswer> answers;

  bool get isQuestion => kind == 'question';
  bool get isNotes => kind == 'notes';
  bool get hasAcceptedAnswer => acceptedAnswerId.isNotEmpty;

  factory CommunityPost.fromJson(Map<String, dynamic> json) => CommunityPost(
    id: _s(json['id']),
    kind: _s(json['kind']),
    title: _s(json['title']),
    body: _s(json['body']),
    category: _s(json['category']),
    authorId: _s(json['authorId']),
    authorName: _s(json['authorName']),
    subject: _s(json['subject']),
    chapter: _s(json['chapter']),
    answerCount: _i(json['answerCount']),
    usefulCount: _i(json['usefulCount']),
    acceptedAnswerId: _s(json['acceptedAnswerId']),
    duplicateOf: _s(json['duplicateOf']),
    duplicateOfTitle: _s(json['duplicateOfTitle']),
    duplicateConfidence: _d(json['duplicateConfidence']),
    groupId: _s(json['groupId']),
    groupName: _s(json['groupName']),
    usefulBy: _list(json['usefulBy']),
    answers: _answers(json['answers']),
  );
}

@immutable
class CommunityAnswer {
  const CommunityAnswer({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.authorName,
    required this.body,
    required this.accepted,
    required this.helpful,
  });

  final String id;
  final String postId;
  final String authorId;
  final String authorName;
  final String body;
  final bool accepted;
  final bool helpful;

  factory CommunityAnswer.fromJson(Map<String, dynamic> json) => CommunityAnswer(
    id: _s(json['id']),
    postId: _s(json['postId']),
    authorId: _s(json['authorId']),
    authorName: _s(json['authorName']),
    body: _s(json['body']),
    accepted: json['accepted'] == true,
    helpful: json['helpful'] == true,
  );
}

@immutable
class ChallengeEntry {
  const ChallengeEntry({
    required this.id,
    required this.title,
    required this.status,
    required this.inviteCode,
    required this.questionCount,
    required this.timeLimitMinutes,
    required this.challengerId,
    required this.challengerName,
    required this.opponentId,
    required this.opponentName,
    required this.myRole,
    this.myScore,
    this.opponentScore,
  });

  final String id;
  final String title;

  /// pending | accepted | completed | declined | cancelled
  final String status;
  final String inviteCode;
  final int questionCount;
  final int timeLimitMinutes;
  final String challengerId;
  final String challengerName;
  final String opponentId;
  final String opponentName;

  /// 'challenger' | 'opponent'
  final String myRole;

  /// Present only after both students finished; null while open.
  final int? myScore;
  final int? opponentScore;

  bool get isOpen => status == 'pending' || status == 'accepted';

  bool get isFinished => status == 'completed';

  factory ChallengeEntry.fromJson(Map<String, dynamic> json) => ChallengeEntry(
    id: _s(json['id']),
    title: _s(json['title']),
    status: _s(json['status']),
    inviteCode: _s(json['inviteCode']),
    questionCount: _i(json['questionCount']),
    timeLimitMinutes: _i(json['timeLimitMinutes']),
    challengerId: _s(json['challengerId']),
    challengerName: _s(json['challengerName']),
    opponentId: _s(json['opponentId']),
    opponentName: _s(json['opponentName']),
    myRole: _s(json['myRole']),
    myScore: _optI(json['myResult'] is Map ? json['myResult']['score'] : null),
    opponentScore: _optI(
      json['opponentResult'] is Map ? json['opponentResult']['score'] : null,
    ),
  );
}

// ---------------------------------------------------------------------------
// Phase 7 seams.
//
// Every loader below has exactly the shape of the ApiService method it wraps,
// so a screen can take an optional `xxxFn` and fall back to the real service:
//
//   CommunityPostsFn get _posts => widget.postsFn ?? ApiService.listPosts;
//
// The pattern (and the name) is copied from the exam screens
// (`ExamCreateFn` / `ExamSetupScreen.createFn`), which is what lets a test
// drive a whole screen from canned JSON with no Firestore and no network.
// ---------------------------------------------------------------------------

/// GET /api/community/posts - the Question Bank feed.
typedef CommunityPostsFn = Future<Map<String, dynamic>> Function({
  String kind,
  String category,
  String groupId,
  bool popular,
  int limit,
});

/// POST /api/community/posts - one question / solution / notes / achievement.
typedef CommunityCreatePostFn = Future<Map<String, dynamic>> Function({
  required String kind,
  required String title,
  String body,
  String category,
  String groupId,
  List<Map<String, dynamic>> attachments,
});

/// GET /api/community/posts/{id} - one post plus its answers.
typedef CommunityPostFn = Future<Map<String, dynamic>> Function(String postId);

/// POST /api/community/posts/{id}/answers.
typedef CommunityAnswerFn = Future<Map<String, dynamic>> Function(
  String postId,
  String text,
);

/// POST .../accept or .../helpful - the two per-answer point awards.
typedef CommunityAnswerActionFn = Future<Map<String, dynamic>> Function(
  String postId,
  String answerId,
);

/// POST .../useful - Learning Points for the author of a notes post.
typedef CommunityPostActionFn = Future<Map<String, dynamic>> Function(
  String postId,
);

/// GET /api/community/leaderboard - Learning Points, global or per group.
typedef CommunityLeaderboardFn = Future<Map<String, dynamic>> Function({
  String scope,
  String groupId,
});

/// GET /api/community/challenges - the challenges I am part of.
typedef CommunityChallengeListFn = Future<Map<String, dynamic>> Function();

/// GET /api/community/challenges/{id}.
typedef CommunityGetChallengeFn = Future<Map<String, dynamic>> Function(
  String challengeId,
);

/// POST /api/community/challenges/join - accept an invite code.
typedef CommunityJoinChallengeFn = Future<Map<String, dynamic>> Function(
  String code,
);

/// POST /api/community/challenges/decline.
typedef CommunityDeclineChallengeFn = Future<Map<String, dynamic>> Function(
  String challengeId,
);

/// POST /api/community/challenges - challenge a classmate with a saved exam.
typedef CommunityCreateChallengeFn = Future<Map<String, dynamic>> Function({
  required String examId,
  String title,
  int questionCount,
  int timeLimitMinutes,
  String opponentId,
});

/// GET /api/exams - the paper picker behind "New challenge".
typedef CommunityExamsFn = Future<Map<String, dynamic>> Function({int limit});

/// POST /api/community/challenges/{id}/start - redacted questions + clock.
typedef CommunityStartChallengeFn = Future<Map<String, dynamic>> Function(
  String challengeId,
);

/// POST /api/community/challenges/{id}/submit - server-side grading.
typedef CommunitySubmitChallengeFn = Future<Map<String, dynamic>> Function(
  String challengeId, {
  required List<dynamic> answers,
  required int durationSeconds,
});

/// POST /api/groups/{id}/ziku/ask.
typedef CommunityZikuAskFn = Future<Map<String, dynamic>> Function(
  String groupId,
  String question,
);

/// POST /api/groups/{id}/ziku/moderate.
typedef CommunityZikuModerateFn = Future<Map<String, dynamic>> Function(
  String groupId, {
  required String claimA,
  required String claimB,
  String context,
});

/// POST /api/groups/{id}/ziku/topics.
typedef CommunityZikuTopicsFn = Future<Map<String, dynamic>> Function(
  String groupId,
);

/// POST /api/groups/{id}/ziku/quiz - Ziku writes a revision quiz.
typedef CommunityZikuQuizFn = Future<Map<String, dynamic>> Function(
  String groupId, {
  String topic,
  int questionCount,
});

/// POST /api/groups/{id}/quizzes/{quizId}/attempt - graded server-side.
typedef CommunityAttemptQuizFn = Future<Map<String, dynamic>> Function(
  String groupId,
  String quizId, {
  required List<dynamic> answers,
  int durationSeconds,
});

/// GET /api/groups/{id}/quizzes - the quizzes saved for this group.
typedef CommunityQuizzesFn = Future<Map<String, dynamic>> Function(String groupId);

/// GET /api/groups/{id}/insights - hot chapters, weak topics, counts.
typedef CommunityInsightsFn = Future<Map<String, dynamic>> Function(
  String groupId,
);

String _s(dynamic value) => value?.toString() ?? '';

int _i(dynamic value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int? _optI(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double _d(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

List<String> _list(dynamic value) =>
    ((value as List?) ?? const []).map((e) => e.toString()).toList();

List<CommunityAnswer> _answers(dynamic value) =>
    ((value as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CommunityAnswer.fromJson)
        .toList();
