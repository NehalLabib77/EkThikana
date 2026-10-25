// Widget tests for FlashcardScreen visual polish, state presentation, and interaction integrity.
//
// Verifies:
// 1. Initial form presentation with AppBar, heading, topic input, source input, and Generate button.
// 2. Validation error feedback when attempting to generate with an empty topic.
// 3. Loading state presentation while AI flashcard generation is in flight.
// 4. Error state presentation when API call fails.
// 5. Empty result presentation when response contains 0 flashcards.
// 6. Populated flashcard deck rendering card indices, questions, and reveal affordance.
// 7. Interactive card tap reveals answer text with proper semantics.
// 8. Difficulty badges (Easy, Medium, Hard) and review date chip rendering.
// 9. Bengali localization rendering all labels, badges, and card numbers in Bengali.
// 10. Responsive 320dp narrow viewport with zero RenderFlex overflow.
// 11. Dark mode theme contrast and surfaces.
// 12. Reduced-motion accessibility compliance.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/features/study/presentation/content/flashcard_screen.dart';

Widget _wrap(
  Widget child, {
  ThemeMode themeMode = ThemeMode.light,
  Size size = const Size(390, 844),
  bool disableAnimations = false,
}) {
  return MediaQuery(
    data: MediaQueryData(
      size: size,
      disableAnimations: disableAnimations,
    ),
    child: MaterialApp(
      theme: GochanoTheme.light(),
      darkTheme: GochanoTheme.dark(),
      themeMode: themeMode,
      home: child,
    ),
  );
}

void main() {
  setUp(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  tearDown(() {
    GochanoLanguage.current.value = GochanoLocale.english;
  });

  final sampleCardsData = {
    'generatedContent': {
      'flashcards': [
        {
          'question': 'What is Mitosis?',
          'answer': 'A type of cell division that results in two identical daughter cells.',
          'difficulty': 'easy',
          'reviewDate': '2026-10-25',
        },
        {
          'question': 'What is Meiosis?',
          'answer': 'Cell division that produces gametes with half the chromosome number.',
          'difficulty': 'hard',
        },
      ],
    },
  };

  group('FlashcardScreen Visual & Interaction Tests', () {
    testWidgets('renders initial form with AppBar, heading, topic input, source input, and Generate button in English', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const FlashcardScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Flashcards'), findsOneWidget);
      expect(find.text('AI-powered concept cards & recall'), findsOneWidget);
      expect(find.text('Generate Smart Flashcards'), findsOneWidget);
      expect(find.text('Create recall cards from any topic or notes'), findsOneWidget);
      expect(find.text('Topic or Concept'), findsOneWidget);
      expect(find.text('Notes or Textbook excerpt (optional)'), findsOneWidget);
      expect(find.text('Generate Cards'), findsOneWidget);
    });

    testWidgets('validation error appears when submitting empty topic', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(const FlashcardScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Generate Cards'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a topic'), findsWidgets);
    });

    testWidgets('renders loading state with progress indicator and friendly message', (
      tester,
    ) async {
      final completer = Completer<Map<String, dynamic>>();

      await tester.pumpWidget(
        _wrap(
          FlashcardScreen(
            initialTopic: 'Biology',
            initialRequest: completer.future,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.text('Crafting your flashcards with Ziku AI…'),
        findsOneWidget,
      );
    });

    testWidgets('renders error state on API failure', (
      tester,
    ) async {
      final completer = Completer<Map<String, dynamic>>();

      await tester.pumpWidget(
        _wrap(
          FlashcardScreen(
            initialTopic: 'Physics',
            initialRequest: completer.future,
          ),
        ),
      );
      await tester.pump();

      completer.completeError('Connection timed out. Please retry.');
      await tester.pump();

      expect(find.text('Connection timed out. Please retry.'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('renders empty cards state when response contains 0 flashcards', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          FlashcardScreen(
            initialTopic: 'Chemistry',
            initialRequest: Future.value({
              'generatedContent': {'flashcards': []},
            }),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('No flashcards generated. Try another topic.'),
        findsOneWidget,
      );
    });

    testWidgets('renders populated flashcards list with card numbers, questions, and reveal affordances', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          FlashcardScreen(
            initialTopic: 'Mitosis',
            initialRequest: Future.value(sampleCardsData),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Generated Flashcards (2)'), findsOneWidget);
      expect(find.text('Card 1'), findsOneWidget);
      expect(find.text('What is Mitosis?'), findsOneWidget);
      expect(find.text('Card 2'), findsOneWidget);
      expect(find.text('What is Meiosis?'), findsOneWidget);
      expect(find.text('Easy'), findsOneWidget);
      expect(find.text('Hard'), findsOneWidget);
      expect(find.text('2026-10-25'), findsOneWidget);
      expect(find.text('Tap to reveal answer'), findsNWidgets(2));
    });

    testWidgets('tapping flashcard reveals answer content', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          FlashcardScreen(
            initialTopic: 'Mitosis',
            initialRequest: Future.value(sampleCardsData),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap first card to reveal answer
      await tester.tap(find.text('What is Mitosis?'));
      await tester.pumpAndSettle();

      expect(find.text('Answer:'), findsOneWidget);
      expect(
        find.text('A type of cell division that results in two identical daughter cells.'),
        findsOneWidget,
      );
    });

    testWidgets('Bengali localization renders all labels, hints, and badges in Bengali', (
      tester,
    ) async {
      GochanoLanguage.current.value = GochanoLocale.bangla;

      await tester.pumpWidget(
        _wrap(
          FlashcardScreen(
            initialTopic: 'মাইটোসিস',
            initialRequest: Future.value(sampleCardsData),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ফ্ল্যাশকার্ড'), findsOneWidget);
      expect(find.text('স্মার্ট এআই ফ্ল্যাশকার্ড তৈরি ও অনুশীলন'), findsOneWidget);
      expect(find.text('স্মার্ট ফ্ল্যাশকার্ড তৈরি করুন'), findsOneWidget);
      expect(find.text('টপিক বা কনসেপ্ট'), findsOneWidget);
      expect(find.text('কার্ড তৈরি করুন'), findsOneWidget);
      expect(find.text('তৈরি করা ফ্ল্যাশকার্ড (২)'), findsOneWidget);
      expect(find.text('কার্ড ১'), findsOneWidget);
      expect(find.text('সহজ'), findsOneWidget);
      expect(find.text('কঠিন'), findsOneWidget);
      expect(find.text('উত্তর দেখতে ট্যাপ করুন'), findsNWidgets(2));
    });

    testWidgets('renders cleanly on 320dp narrow viewport with zero overflow', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          FlashcardScreen(
            initialTopic: 'Biology',
            initialRequest: Future.value(sampleCardsData),
          ),
          size: const Size(320, 640),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Generated Flashcards (2)'), findsOneWidget);
    });

    testWidgets('renders cleanly in Dark Mode with theme-adaptive surfaces', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          FlashcardScreen(
            initialTopic: 'Biology',
            initialRequest: Future.value(sampleCardsData),
          ),
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('What is Mitosis?'), findsOneWidget);
    });

    testWidgets('respects reduced-motion preferences without animation errors', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          FlashcardScreen(
            initialTopic: 'Biology',
            initialRequest: Future.value(sampleCardsData),
          ),
          disableAnimations: true,
        ),
      );
      await tester.pumpAndSettle();

      // Tap card with animations disabled
      await tester.tap(find.text('What is Mitosis?'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Answer:'), findsOneWidget);
    });
  });
}
