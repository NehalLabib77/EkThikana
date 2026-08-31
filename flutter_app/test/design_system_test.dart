// Guards for the Gochano design system.
//
// These assert the properties the spec actually cares about — theme-aware
// illustrations, no decorative animation, no leaked internals in error copy —
// rather than pixel-comparing screenshots.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:gochano/core/design_system/gochano_art.dart';
import 'package:gochano/core/design_system/gochano_colors.dart';
import 'package:gochano/core/design_system/gochano_illustration.dart';
import 'package:gochano/core/design_system/gochano_theme.dart';
import 'package:gochano/core/localization/gochano_language.dart';
import 'package:gochano/shared/states/gochano_states.dart';
import 'package:gochano/shared/widgets/gochano_surfaces.dart';

void main() {
  group('Illustration catalogue', () {
    test('every drawing uses only the three theme colour slots', () {
      // A hardcoded colour is the exact defect the old
      // `assets/illustrations/*.svg` set had: `fill="#FFFFFF"` punched a
      // white hole through every dark-mode screen (spec §18).
      final offenders = <String>[];
      for (final id in GochanoArt.allIds) {
        final svg = GochanoArt.resolve(
          id,
          ink: const Color(0xFF111111),
          fill: const Color(0xFF222222),
          paper: const Color(0xFF333333),
        );
        // After substitution the only hex values left must be the three we
        // supplied. Anything else is a literal baked into the drawing.
        final hexes = RegExp(r'#[0-9a-fA-F]{3,8}')
            .allMatches(svg)
            .map((m) => m.group(0)!.toLowerCase())
            .toSet();
        final unexpected =
            hexes.difference({'#111111', '#222222', '#333333'});
        if (unexpected.isNotEmpty) offenders.add('$id -> $unexpected');
      }
      expect(offenders, isEmpty,
          reason: 'drawings must not hardcode colours: $offenders');
    });

    test('every drawing is a well-formed single svg root', () {
      for (final id in GochanoArt.allIds) {
        final svg = GochanoArt.resolve(
          id,
          ink: const Color(0xFF000000),
          fill: const Color(0xFF000000),
          paper: const Color(0xFF000000),
        );
        expect(svg.startsWith('<svg '), isTrue, reason: id);
        expect(svg.endsWith('</svg>'), isTrue, reason: id);
        expect('<svg '.allMatches(svg).length, 1, reason: id);
        // Balanced tags: every element is either self-closing or paired.
        expect(svg.contains('<script'), isFalse, reason: id);
      }
    });

    test('an unknown id falls back instead of rendering nothing', () {
      final unknown = GochanoArt.resolve(
        'no.such.drawing',
        ink: const Color(0xFF000000),
        fill: const Color(0xFF000000),
        paper: const Color(0xFF000000),
      );
      final fallback = GochanoArt.resolve(
        GochanoArt.generic,
        ink: const Color(0xFF000000),
        fill: const Color(0xFF000000),
        paper: const Color(0xFF000000),
      );
      expect(unknown, equals(fallback));
    });
  });

  group('Subject keyword mapping (spec §20)', () {
    final cases = <String, String>{
      'Artificial Intelligence': GochanoArt.subjectAi,
      'AI': GochanoArt.subjectAi,
      'Machine Learning Lab': GochanoArt.subjectAi,
      'Database Management Systems': GochanoArt.subjectDatabase,
      'Computer Networks': GochanoArt.subjectNetworking,
      'Data Structures & Algorithms': GochanoArt.subjectProgramming,
      'Software Engineering': GochanoArt.subjectSoftwareEngineering,
      'Discrete Mathematics': GochanoArt.subjectMath,
      'Physics I': GochanoArt.subjectPhysics,
      'Organic Chemistry': GochanoArt.subjectChemistry,
      'Microbiology': GochanoArt.subjectBiology,
      'English Literature': GochanoArt.subjectEnglish,
      'Financial Accounting': GochanoArt.subjectBusiness,
      'পদার্থবিজ্ঞান': GochanoArt.subjectPhysics,
      'গণিত': GochanoArt.subjectMath,
      'Underwater Basket Weaving': GochanoArt.subjectGeneric,
      '': GochanoArt.subjectGeneric,
    };

    for (final entry in cases.entries) {
      test('"${entry.key}" -> ${entry.value}', () {
        expect(GochanoArt.subjectIdFor(entry.key), entry.value);
      });
    }

    test('a null subject name never produces a missing visual', () {
      expect(GochanoArt.subjectIdFor(null), GochanoArt.subjectGeneric);
      expect(GochanoArt.allIds, contains(GochanoArt.subjectIdFor(null)));
    });
  });

  group('File type mapping (spec §21)', () {
    test('recognises the backend-supported types', () {
      expect(GochanoArt.fileIdFor(fileName: 'notes.pdf'), GochanoArt.filePdf);
      expect(GochanoArt.fileIdFor(mimeType: 'application/pdf'),
          GochanoArt.filePdf);
      expect(GochanoArt.fileIdFor(fileName: 'scan.JPG'), GochanoArt.fileImage);
      expect(GochanoArt.fileIdFor(mimeType: 'image/png'), GochanoArt.fileImage);
      expect(GochanoArt.fileIdFor(fileName: 'report.docx'), GochanoArt.fileDoc);
      expect(GochanoArt.fileIdFor(fileName: 'deck.pptx'), GochanoArt.fileSlides);
      expect(GochanoArt.fileIdFor(fileName: 'todo.txt'), GochanoArt.fileNote);
      expect(GochanoArt.fileIdFor(fileName: 'archive.bin'),
          GochanoArt.fileGeneric);
      expect(GochanoArt.fileIdFor(), GochanoArt.fileGeneric);
    });
  });

  group('Transport mode mapping (spec §61)', () {
    test('maps every backend fare mode to a distinct drawing', () {
      expect(GochanoArt.transportIdFor('walk'), GochanoArt.modeWalk);
      expect(GochanoArt.transportIdFor('bus'), GochanoArt.modeBus);
      expect(GochanoArt.transportIdFor('metro'), GochanoArt.modeMetro);
      expect(GochanoArt.transportIdFor('rickshaw'), GochanoArt.modeRickshaw);
      expect(GochanoArt.transportIdFor('cng'), GochanoArt.modeCng);
      expect(GochanoArt.transportIdFor('train'), GochanoArt.modeTrain);
      expect(GochanoArt.transportIdFor('launch'), GochanoArt.modeBoat);
      // Distinct so a student can tell them apart at a glance.
      final ids = <String>{
        for (final m in ['walk', 'bus', 'metro', 'rickshaw', 'cng', 'train'])
          GochanoArt.transportIdFor(m),
      };
      expect(ids.length, 6);
    });
  });

  group('Theme', () {
    test('light and dark register the GochanoColors extension', () {
      expect(GochanoTheme.light().extension<GochanoColors>(),
          same(GochanoColors.light));
      expect(GochanoTheme.dark().extension<GochanoColors>(),
          same(GochanoColors.dark));
    });

    test('dark mode is not a mechanical inversion (spec §18)', () {
      const l = GochanoColors.light;
      const d = GochanoColors.dark;
      // Dark surfaces step *up* from the background rather than being pure
      // black on black.
      expect(d.surface.computeLuminance(),
          greaterThan(d.background.computeLuminance()));
      expect(d.surfaceElevated.computeLuminance(),
          greaterThan(d.surface.computeLuminance()));
      // And light mode keeps the same relationship in reverse: the scaffold
      // is slightly tinted so white cards read as raised (spec §17).
      expect(l.surface.computeLuminance(),
          greaterThan(l.background.computeLuminance()));
      // Illustration paper follows the surface, so drawings never punch a
      // white hole in dark mode.
      expect(d.illustrationPaper.computeLuminance(), lessThan(0.2));
    });

    test('body text meets the 4.5:1 contrast floor on every surface', () {
      double contrast(Color fg, Color bg) {
        final a = fg.computeLuminance();
        final b = bg.computeLuminance();
        final lighter = a > b ? a : b;
        final darker = a > b ? b : a;
        return (lighter + 0.05) / (darker + 0.05);
      }

      for (final c in [GochanoColors.light, GochanoColors.dark]) {
        for (final bg in [c.background, c.surface, c.surfaceVariant]) {
          expect(contrast(c.textPrimary, bg), greaterThanOrEqualTo(4.5),
              reason: 'textPrimary on $bg');
          expect(contrast(c.textSecondary, bg), greaterThanOrEqualTo(4.5),
              reason: 'textSecondary on $bg');
        }
        // Status colours carry meaning, so they must be readable too.
        for (final pair in [
          (c.success, c.successSoft),
          (c.warning, c.warningSoft),
          (c.error, c.errorSoft),
          (c.info, c.infoSoft),
        ]) {
          expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5),
              reason: 'status pair ${pair.$1} on ${pair.$2}');
        }
      }
    });
  });

  group('Error copy never leaks internals (spec §76)', () {
    setUp(() => GochanoLanguage.current.value = GochanoLocale.english);

    test('exception dumps are replaced with a human sentence', () {
      final leaky = [
        'SocketException: Failed host lookup: api.example.com',
        'ClientException with SocketException',
        'TimeoutException after 0:01:40.000000',
        "FirebaseException: [cloud_firestore/permission-denied]",
        'psycopg2.errors.UndefinedTable: relation "x" does not exist',
        'Traceback (most recent call last):\n  File "main.py"',
        '#0      ApiService._decode (package:gochano/services/api_service.dart)',
        '{"detail": {"loc": ["body"], "msg": "field required"}}',
      ];
      for (final raw in leaky) {
        final message = friendlyErrorMessage(raw);
        expect(message, isNot(contains('Exception')), reason: raw);
        expect(message, isNot(contains('Traceback')), reason: raw);
        expect(message, isNot(contains('psycopg')), reason: raw);
        expect(message, isNot(contains('#0')), reason: raw);
        expect(message, isNot(contains('{')), reason: raw);
        expect(message.trim(), isNotEmpty, reason: raw);
      }
    });

    test('a deliberate backend sentence is passed through', () {
      expect(
        friendlyErrorMessage('Prescription file must be 10 MB or smaller'),
        'Prescription file must be 10 MB or smaller',
      );
    });

    test('recognised conditions get a specific message', () {
      expect(friendlyErrorMessage('SocketException: x'),
          contains('No connection'));
      expect(friendlyErrorMessage('Daily AI limit reached'),
          contains('daily AI limit'));
      expect(friendlyErrorMessage('404 not found'),
          contains('no longer available'));
    });

    test('messages are translated when Bangla is active', () {
      GochanoLanguage.current.value = GochanoLocale.bangla;
      final message = friendlyErrorMessage('SocketException: x');
      expect(message, contains('ইন্টারনেট'));
      GochanoLanguage.current.value = GochanoLocale.english;
    });
  });

  group('Widgets render in both themes', () {
    Future<void> pumpBoth(WidgetTester tester, Widget child) async {
      for (final theme in [GochanoTheme.light(), GochanoTheme.dark()]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }

    testWidgets('EmptyState', (tester) async {
      await pumpBoth(
        tester,
        const EmptyState(
          illustration: GochanoArt.emptySubjects,
          title: 'No subjects yet',
          message: 'Create your first subject to organize your study materials.',
        ),
      );
      expect(find.text('No subjects yet'), findsOneWidget);
    });

    testWidgets('ErrorState', (tester) async {
      await pumpBoth(
        tester,
        const ErrorState(message: 'Something went wrong. Try again.'),
      );
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    });

    testWidgets('StaticLoadingState shows a percentage when known', (tester) async {
      await pumpBoth(
        tester,
        const StaticLoadingState(message: 'Uploading', progress: 0.45),
      );
      expect(find.textContaining('45%'), findsOneWidget);
    });

    testWidgets('StatCard announces label and value together', (tester) async {
      await pumpBoth(
        tester,
        const StatCard(label: 'Remaining', value: '৳1,250'),
      );
      expect(find.text('৳1,250'), findsOneWidget);
    });

    testWidgets('illustration renders at the requested size', (tester) async {
      await pumpBoth(
        tester,
        const GochanoIllustration(GochanoArt.featureCommute, size: 48),
      );
      final box = tester.getSize(
        find.byType(GochanoIllustration).first,
      );
      expect(box.width, 48);
      expect(box.height, 48);
    });
  });
}
