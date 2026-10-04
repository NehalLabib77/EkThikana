// Phase 7 - Ziku Learning Community 2.0, client side.
//
// What the client owes Phase 7 on top of Phases 1-6:
//   * the Community tab gains a segment switch into a Question Bank
//     (spec 7.3) and Exam Challenges (spec 7.4), keeping study groups as
//     the default segment (spec 7.1);
//   * the question detail carries the three Learning Point controls -
//     accept, helpful and useful - and shows each only to the viewer the
//     server would allow (spec 7.6);
//   * Ziku's six moderator jobs live behind one screen inside a group
//     (spec 7.2), and the create-group form offers the study categories
//     the API accepts (spec 7.5).
//
// Everything networked is injected, so no test here opens a socket and no
// test touches Firestore.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/features/community/domain/community_models.dart';
import 'package:gochano/features/community/presentation/challenge_list_screen.dart';
import 'package:gochano/features/community/presentation/challenge_take_screen.dart';
import 'package:gochano/features/community/presentation/community_view.dart';
import 'package:gochano/features/community/presentation/group_moderator_screen.dart';
import 'package:gochano/features/community/presentation/question_bank_screen.dart';
import 'package:gochano/features/community/presentation/question_detail_screen.dart';
import 'package:gochano/shared/widgets/gochano_controls.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

/// The screens are long lists; a default 800x600 test surface only builds
/// the first screenful, so content tests open a taller one.
Future<void> _tallSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Future<void> _type(WidgetTester tester, String label, String value) async {
  await tester.enterText(find.widgetWithText(TextField, label).first, value);
  await tester.pump();
}

// ---------------------------------------------------------------------------
// canned payloads shaped like the Phase 7 backend responses
// ---------------------------------------------------------------------------

Map<String, dynamic> _post({
  String id = 'post_1',
  String kind = 'question',
  String title = 'Why does the derivative vanish here?',
  String body = 'I followed every step and still get zero.',
  String authorId = 'u_asker',
  String acceptedAnswerId = '',
  String duplicateOf = '',
  String duplicateOfTitle = '',
  int answerCount = 1,
  int usefulCount = 0,
  List<Map<String, dynamic>> answers = const <Map<String, dynamic>>[],
  String category = 'hsc',
}) =>
    {
      'id': id,
      'kind': kind,
      'title': title,
      'body': body,
      'category': category,
      'authorId': authorId,
      'authorName': 'Ayesha',
      'subject': 'Mathematics',
      'chapter': 'Differentiation',
      'answerCount': answerCount,
      'usefulCount': usefulCount,
      'acceptedAnswerId': acceptedAnswerId,
      'duplicateOf': duplicateOf,
      'duplicateOfTitle': duplicateOfTitle,
      'duplicateConfidence': 0.86,
      'groupId': '',
      'groupName': '',
      'createdAtIso': '2026-10-01T10:00:00Z',
      'answers': answers,
    };

Map<String, dynamic> _answer({
  String id = 'a_1',
  String authorId = 'u_peer',
  bool accepted = false,
  bool helpful = false,
}) =>
    {
      'id': id,
      'postId': 'post_1',
      'authorId': authorId,
      'authorName': 'Rafi',
      'body': 'The derivative is zero because the tangent is flat.',
      'accepted': accepted,
      'helpful': helpful,
      'createdAtIso': '2026-10-01T11:00:00Z',
    };

Map<String, dynamic> _challenge({
  String status = 'pending',
  String myRole = 'challenger',
  String inviteCode = 'AB12CD',
}) =>
    {
      'id': 'ch_1',
      'title': 'Physics mock challenge',
      'status': status,
      'inviteCode': inviteCode,
      'questionCount': 10,
      'timeLimitMinutes': 15,
      'challengerId': 'u_me',
      'challengerName': 'Me',
      'opponentId': '',
      'opponentName': '',
      'myRole': myRole,
      'myResult': null,
      'opponentResult': null,
    };

Map<String, dynamic> _question({
  int index = 0,
  String text = 'What is the derivative of x squared?',
  List<String> options = const <String>['2x', 'x', 'x squared', '2'],
}) =>
    {
      'index': index,
      'question': text,
      'type': 'mcq',
      'options': options,
      'topic': 'Differentiation',
      'marks': 1.0,
    };

// ---------------------------------------------------------------------------
// seams
// ---------------------------------------------------------------------------

Future<Map<String, dynamic>> _emptyPosts({
  String kind = '',
  String category = '',
  String groupId = '',
  bool popular = false,
  int limit = 30,
}) async =>
    {'posts': <Map<String, dynamic>>[], 'popular': popular};

Future<Map<String, dynamic>> _emptyLeaders({
  String scope = 'global',
  String groupId = '',
}) async =>
    {'scope': scope, 'entries': <Map<String, dynamic>>[]};

Future<Map<String, dynamic>> _emptyChallenges() async =>
    {'challenges': <Map<String, dynamic>>[]};

Future<Map<String, dynamic>> _noQuizzes(String groupId) async =>
    {'groupId': groupId, 'quizzes': <Map<String, dynamic>>[]};

Future<Map<String, dynamic>> _noExams({int limit = 20}) async =>
    {'exams': <Map<String, dynamic>>[], 'count': 0};

void main() {
  group('Phase 7 models (spec 7.3 / 7.4)', () {
    test('CommunityPost carries duplicate detection and its answers', () {
      final post = CommunityPost.fromJson(
        _post(
          acceptedAnswerId: 'a_1',
          duplicateOf: 'post_9',
          duplicateOfTitle: 'Derivative of x squared',
          answers: [_answer()],
        ),
      );

      expect(post.isQuestion, isTrue);
      expect(post.hasAcceptedAnswer, isTrue);
      expect(post.duplicateOf, 'post_9');
      expect(post.duplicateOfTitle, 'Derivative of x squared');
      expect(post.duplicateConfidence, closeTo(0.86, 0.001));
      expect(post.answers, hasLength(1));
      expect(post.answers.single.accepted, isFalse);
      expect(post.category, 'hsc');
    });

    test('ChallengeEntry exposes open state and both results', () {
      final open = ChallengeEntry.fromJson(_challenge());
      expect(open.isOpen, isTrue);
      expect(open.isFinished, isFalse);
      expect(open.inviteCode, 'AB12CD');
      expect(open.myScore, isNull);

      final done = ChallengeEntry.fromJson(
        _challenge(
          status: 'completed',
          myRole: 'opponent',
        )..['myResult'] = {'score': 7, 'total': 10}
         ..['opponentResult'] = {'score': 6, 'total': 10},
      );
      expect(done.isFinished, isTrue);
      expect(done.myScore, 7);
      expect(done.opponentScore, 6);
    });
  });

  group('Question Bank (spec 7.3)', () {
    testWidgets('renders injected posts and the Learning Points leaders',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          QuestionBankView(
            postsFn: ({
              String kind = '',
              String category = '',
              String groupId = '',
              bool popular = false,
              int limit = 30,
            }) async =>
                {'posts': [_post()], 'popular': popular},
            leaderboardFn: ({
              String scope = 'global',
              String groupId = '',
            }) async =>
                {
                  'scope': scope,
                  'entries': [
                    {'uid': 'u1', 'displayName': 'Nusrat', 'points': 42},
                  ],
                },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Why does the derivative vanish here?'), findsOneWidget);
      expect(find.text('Top contributors'), findsOneWidget);
      expect(find.text('Nusrat'), findsOneWidget);
      expect(find.text('42 points'), findsOneWidget);
      expect(find.text('Solved'), findsNothing);
    });

    testWidgets('choosing a kind reloads the feed with that kind',
        (tester) async {
      await _tallSurface(tester);
      final kinds = <String>[];
      final populars = <bool>[];

      await tester.pumpWidget(
        _app(
          QuestionBankView(
            postsFn: ({
              String kind = '',
              String category = '',
              String groupId = '',
              bool popular = false,
              int limit = 30,
            }) async {
              kinds.add(kind);
              populars.add(popular);
              return {'posts': <Map<String, dynamic>>[], 'popular': popular};
            },
            leaderboardFn: _emptyLeaders,
          ),
        ),
      );
      await tester.pumpAndSettle();
      kinds.clear();

      await tester.tap(find.text('Notes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Popular'));
      await tester.pumpAndSettle();

      expect(kinds, ['notes', 'notes']);
      expect(populars.last, isTrue);
    });

    testWidgets('the composer posts a question with its kind and category',
        (tester) async {
      await _tallSurface(tester);
      Map<String, dynamic>? sent;

      await tester.pumpWidget(
        _app(
          QuestionBankView(
            postsFn: _emptyPosts,
            leaderboardFn: _emptyLeaders,
            createPostFn: ({
              required String kind,
              required String title,
              String body = '',
              String category = '',
              String groupId = '',
              List<Map<String, dynamic>> attachments = const [],
            }) async {
              sent = {
                'kind': kind,
                'title': title,
                'body': body,
                'category': category,
              };
              return {'id': 'post_new'};
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ask a question'));
      await tester.pumpAndSettle();

      await _type(tester, 'Title', 'How do I integrate by parts?');
      await _type(tester, 'Details', 'I keep losing a sign.');
      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();

      expect(sent, isNotNull);
      expect(sent!['kind'], 'question');
      expect(sent!['title'], 'How do I integrate by parts?');
      expect(sent!['body'], 'I keep losing a sign.');
      expect(sent!['category'], '');
      // The sheet is gone and the feed reloaded without a crash.
      expect(find.widgetWithText(TextField, 'Title'), findsNothing);
    });

    testWidgets('an empty bank still offers the Ask a question action',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          QuestionBankView(
            postsFn: _emptyPosts,
            leaderboardFn: _emptyLeaders,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No questions yet'), findsOneWidget);
      expect(find.text('Ask a question'), findsOneWidget);
    });
  });

  group('Question detail and Learning Points (spec 7.6)', () {
    Widget detail({
      required String uid,
      String kind = 'question',
      String authorId = 'u_asker',
      String acceptedAnswerId = '',
      bool answerAccepted = false,
      int usefulCount = 0,
      CommunityAnswerActionFn? acceptFn,
      CommunityPostActionFn? usefulFn,
      CommunityAnswerFn? answerFn,
    }) =>
        _app(
          QuestionDetailScreen(
            postId: 'post_1',
            currentUid: uid,
            answerFn: answerFn,
            acceptFn: acceptFn,
            usefulFn: usefulFn,
            postFn: (String postId) async => _post(
              kind: kind,
              authorId: authorId,
              acceptedAnswerId: acceptedAnswerId,
              usefulCount: usefulCount,
              answers: [_answer(accepted: answerAccepted)],
            ),
          ),
        );

    testWidgets('Accept answer is offered only to the asker', (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(detail(uid: 'u_asker'));
      await tester.pumpAndSettle();
      expect(find.text('Accept answer'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(detail(uid: 'u_viewer'));
      await tester.pumpAndSettle();
      expect(find.text('Accept answer'), findsNothing);
      expect(find.text('Mark helpful'), findsOneWidget);
    });

    testWidgets('an accepted answer stops offering Accept', (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        detail(
          uid: 'u_asker',
          acceptedAnswerId: 'a_1',
          answerAccepted: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Accept answer'), findsNothing);
      expect(find.text('Solved'), findsOneWidget);
      expect(find.text('Accepted'), findsOneWidget);
    });

    testWidgets('a notes post offers Mark useful to a peer', (tester) async {
      await _tallSurface(tester);
      Map<String, dynamic>? used;
      await tester.pumpWidget(
        detail(
          uid: 'u_peer',
          kind: 'notes',
          usefulFn: (String postId) async {
            used = {'postId': postId};
            return {'postId': postId, 'usefulCount': 1, 'pointsAwarded': 10};
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mark useful'), findsOneWidget);

      await tester.tap(find.text('Mark useful'));
      await tester.pumpAndSettle();

      expect(used?['postId'], 'post_1');
    });

    testWidgets('the reply composer sends the answer', (tester) async {
      await _tallSurface(tester);
      String? sent;
      await tester.pumpWidget(
        detail(
          uid: 'u_peer',
          answerFn: (String postId, String text) async {
            sent = text;
            return _answer();
          },
        ),
      );
      await tester.pumpAndSettle();

      await _type(tester, 'Write an answer', 'Because the tangent is flat.');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(sent, 'Because the tangent is flat.');
    });
  });

  group('Exam Challenges (spec 7.4)', () {
    testWidgets('an empty challenge list offers both ways in', (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          ChallengeListView(
            challengesFn: _emptyChallenges,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No challenges yet'), findsOneWidget);
      expect(find.text('New challenge'), findsWidgets);
      expect(find.text('Join with code'), findsWidgets);
    });

    testWidgets('joining with a code calls the join seam', (tester) async {
      await _tallSurface(tester);
      String? code;

      await tester.pumpWidget(
        _app(
          ChallengeListView(
            challengesFn: () async =>
                {'challenges': [_challenge()]},
            joinFn: (String value) async {
              code = value;
              return _challenge(status: 'accepted');
            },
            examsFn: _noExams,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('AB12CD'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);

      await tester.tap(find.text('Join with code'));
      await tester.pumpAndSettle();
      await _type(tester, 'Invite code', 'XY99ZZ');
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();

      expect(code, 'XY99ZZ');
    });

    testWidgets('an accepted challenge opens a timed run and submits',
        (tester) async {
      await _tallSurface(tester);
      List<dynamic>? sentAnswers;
      int? sentDuration;

      await tester.pumpWidget(
        _app(
          ChallengeListView(
            challengesFn: () async =>
                {'challenges': [_challenge(status: 'accepted')]},
            examsFn: _noExams,
            startFn: (String challengeId) async => {
              'id': challengeId,
              'status': 'accepted',
              'timeLimitSeconds': 0,
              'questions': [_question()],
            },
            submitFn: (
              String challengeId, {
              required List<dynamic> answers,
              required int durationSeconds,
            }) async {
              sentAnswers = answers;
              sentDuration = durationSeconds;
              return {
                'id': challengeId,
                'status': 'completed',
                'myResult': {
                  'score': 1,
                  'total': 1,
                  'accuracy': 100.0,
                  'durationSeconds': 0,
                },
                'opponentResult': null,
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ready'), findsOneWidget);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(
        find.text('What is the derivative of x squared?'),
        findsOneWidget,
      );

      await tester.tap(find.text('A. 2x'));
      await tester.pump();
      await tester.tap(find.text('Submit answers'));
      await tester.pumpAndSettle();

      expect(sentAnswers, ['0']);
      expect(sentDuration, 0);
      expect(find.text('Result'), findsOneWidget);
    });

    testWidgets('the countdown stops when the run screen goes away',
        (tester) async {
      await tester.pumpWidget(
        _app(
          ChallengeTakeScreen(
            challengeId: 'ch_1',
            startFn: (String challengeId) async => {
              'id': challengeId,
              'status': 'accepted',
              'timeLimitSeconds': 120,
              'questions': [_question()],
            },
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('02:00'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text('01:59'), findsOneWidget);

      // Dispose must cancel the periodic timer; if it does not, the test
      // binding fails the test with "A Timer is still pending".
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(find.text('01:59'), findsNothing);
    });
  });

  group('Ziku Moderator (spec 7.2 / 7.6)', () {
    Widget moderator({
      CommunityZikuAskFn? askFn,
      CommunityZikuModerateFn? moderateFn,
      CommunityZikuQuizFn? quizFn,
      CommunityAttemptQuizFn? attemptFn,
      CommunityQuizzesFn? quizzesFn,
      CommunityInsightsFn? insightsFn,
      CommunityLeaderboardFn? leaderboardFn,
      CommunityZikuTopicsFn? topicsFn,
      String initialSection = 'ask',
    }) =>
        _app(
          GroupModeratorScreen(
            groupId: 'g1',
            groupName: 'CSE 5th Semester',
            initialSection: initialSection,
            askFn: askFn,
            moderateFn: moderateFn,
            quizFn: quizFn,
            attemptFn: attemptFn,
            quizzesFn: quizzesFn,
            insightsFn: insightsFn,
            leaderboardFn: leaderboardFn,
            topicsFn: topicsFn,
          ),
        );

    testWidgets('asking Ziku sends the question and renders the answer',
        (tester) async {
      await _tallSurface(tester);
      String? question;
      String? seenGroup;

      await tester.pumpWidget(
        moderator(
          askFn: (String groupId, String value) async {
            seenGroup = groupId;
            question = value;
            return {
              'groupId': groupId,
              'question': value,
              'answer': 'Because the slope is constant there.',
            };
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ziku Moderator'), findsOneWidget);

      await _type(
        tester,
        'Your question',
        'Why is the slope constant here?',
      );
      await tester.tap(find.widgetWithText(PrimaryButton, 'Ask Ziku'));
      await tester.pumpAndSettle();

      expect(seenGroup, 'g1');
      expect(question, 'Why is the slope constant here?');
      expect(find.text('Because the slope is constant there.'), findsOneWidget);
    });

    testWidgets('moderating sends both competing claims', (tester) async {
      await _tallSurface(tester);
      String? a;
      String? b;

      await tester.pumpWidget(
        moderator(
          moderateFn: (
            String groupId, {
            required String claimA,
            required String claimB,
            String context = '',
          }) async {
            a = claimA;
            b = claimB;
            return {
              'groupId': groupId,
              'claimA': claimA,
              'claimB': claimB,
              'analysis': "Let's analyze both solutions...",
            };
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Moderate'));
      await tester.pumpAndSettle();

      await _type(tester, 'Student A says', 'The limit is 2.');
      await _type(tester, 'Student B says', 'The limit does not exist.');
      await tester.tap(find.text('Compare'));
      await tester.pumpAndSettle();

      expect(a, 'The limit is 2.');
      expect(b, 'The limit does not exist.');
      expect(find.text("Let's analyze both solutions..."), findsOneWidget);
    });

    testWidgets('a generated quiz is taken and graded through the API',
        (tester) async {
      await _tallSurface(tester);
      List<dynamic>? sentAnswers;

      await tester.pumpWidget(
        moderator(
          quizzesFn: _noQuizzes,
          quizFn: (
            String groupId, {
            String topic = '',
            int questionCount = 5,
          }) async =>
              {
                'quizId': 'qz_1',
                'title': 'Differentiation drill',
                'topic': topic.isEmpty ? 'Differentiation' : topic,
                'groupId': groupId,
                'questions': [_question(text: 'Pick the gradient.')],
              },
          attemptFn: (
            String groupId,
            String quizId, {
            required List<dynamic> answers,
            int durationSeconds = 0,
          }) async {
            sentAnswers = answers;
            return {
              'quizId': quizId,
              'score': 1,
              'total': 1,
              'accuracy': 100.0,
              'topicScores': {
                'Differentiation': {'correct': 1, 'total': 1},
              },
            };
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Quiz'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate quiz'));
      await tester.pumpAndSettle();

      expect(find.text('Pick the gradient.'), findsOneWidget);

      await tester.tap(find.text('2x'));
      await tester.pump();
      await tester.tap(find.text('Submit answers'));
      await tester.pumpAndSettle();

      expect(sentAnswers, ['0']);
      expect(find.textContaining('1 / 1'), findsOneWidget);
    });

    testWidgets('the points section reads the group leaderboard',
        (tester) async {
      await _tallSurface(tester);
      String? seenScope;

      await tester.pumpWidget(
        moderator(
          initialSection: 'points',
          leaderboardFn: ({
            String scope = 'global',
            String groupId = '',
          }) async {
            seenScope = scope;
            return {
              'scope': scope,
              'entries': [
                {'uid': 'u1', 'displayName': 'Tanvir', 'points': 30},
              ],
            };
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(seenScope, 'group');
      expect(find.text('Learning Points'), findsOneWidget);
      expect(find.text('Tanvir'), findsOneWidget);
      expect(find.text('30 points'), findsOneWidget);
    });

    testWidgets('the insights section renders hot chapters and counts',
        (tester) async {
      await _tallSurface(tester);

      await tester.pumpWidget(
        moderator(
          initialSection: 'insights',
          insightsFn: (String groupId) async => {
            'groupId': groupId,
            'hotChapters': [
              {'chapter': 'Integration', 'subject': 'Mathematics', 'count': 6},
            ],
            'weakTopics': [
              {'topic': 'Limits', 'accuracy': 40.0, 'attempts': 5},
            ],
            'questionCount': 12,
            'quizCount': 3,
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Group signals'), findsOneWidget);
      expect(find.text('Integration · 6'), findsOneWidget);
      expect(find.text('Limits · 40.0%'), findsOneWidget);
    });
  });

  group('Community segments (spec 7.1)', () {
    testWidgets('opens on the Questions segment without touching Firestore',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          CommunityView(
            initialSegment: 'questions',
            postsFn: ({
              String kind = '',
              String category = '',
              String groupId = '',
              bool popular = false,
              int limit = 30,
            }) async =>
                {'posts': [_post()], 'popular': popular},
            leaderboardFn: _emptyLeaders,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('Questions'), findsOneWidget);
      expect(find.text('Challenges'), findsOneWidget);
      expect(find.text('Question Bank'), findsOneWidget);
      expect(find.text('Why does the derivative vanish here?'), findsOneWidget);
    });

    testWidgets('switching to Challenges shows the challenge segment',
        (tester) async {
      await _tallSurface(tester);
      await tester.pumpWidget(
        _app(
          CommunityView(
            initialSegment: 'challenges',
            challengesFn: _emptyChallenges,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No challenges yet'), findsOneWidget);
    });
  });

  group('Wiring', () {
    late String groupDetail;
    late String groupActions;
    late String communityView;
    late String communityScreen;

    setUpAll(() {
      groupDetail = _read(
        'lib/features/community/presentation/group_detail_screen.dart',
      );
      groupActions = _read(
        'lib/features/community/presentation/group_actions.dart',
      );
      communityView = _read(
        'lib/features/community/presentation/community_view.dart',
      );
      communityScreen = _read(
        'lib/features/community/presentation/community_screen.dart',
      );
    });

    test('the group app bar opens the Ziku Moderator screen', () {
      expect(groupDetail, contains('GroupModeratorScreen('));
      expect(groupDetail, contains("'Ziku Moderator'"));
      expect(groupDetail, contains('IconActionButton('));
    });

    test('creating a group offers the study categories the API accepts', () {
      expect(groupActions, contains('DropdownButtonFormField<String>('));
      expect(groupActions, contains('kStudyCategories'));
      expect(groupActions, contains('category: _category'));
    });

    test('CommunityView exposes the three Phase 7 segments', () {
      expect(communityView, contains('SegmentedButton<String>('));
      expect(communityView, contains("case 'questions':"));
      expect(communityView, contains("case 'challenges':"));
      expect(communityView, contains('default:'));
    });

    test('the Community screen comment reflects the Phase 7 surfaces', () {
      expect(communityScreen, contains('Question Bank'));
      expect(communityScreen, isNot(contains('FloatingActionButton')));
    });
  });
}
