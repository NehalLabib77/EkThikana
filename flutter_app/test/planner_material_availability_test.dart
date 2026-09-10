import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 7.3 — Final Linked Material UI Closure
///
/// These tests verify the architectural guarantees of the material
/// availability resolution in the planner. Since the planner widget
/// requires Firebase for full widget tests, these tests verify the
/// behavioral contract through source-level assertions and logic checks.
void main() {
  group('Phase 7.3 — Material Availability Resolution', () {
    test('1. _PlannerItemRow is StatefulWidget with _materialExists field',
        () async {
      // Verify the planner row is a StatefulWidget that pre-resolves
      // material existence, not a StatelessWidget that checks on tap.
      // This ensures material availability is known BEFORE the menu is built.

      final source = await _readPlannerSource();

      // Must be StatefulWidget (not StatelessWidget)
      expect(source, contains('class _PlannerItemRow extends StatefulWidget'));
      expect(source, isNot(contains('class _PlannerItemRow extends StatelessWidget')));

      // Must have _materialExists field
      expect(source, contains('bool? _materialExists'));
    });

    test('2. Material existence check runs in initState, not in build',
        () async {
      final source = await _readPlannerSource();

      // initState must exist and call _checkMaterial
      expect(source, contains('void initState()'));
      expect(source, contains('_checkMaterial()'));

      // _checkMaterial must be async
      expect(source, contains('Future<void> _checkMaterial()'));
    });

    test('3. Menu item visibility requires _materialExists == true',
        () async {
      final source = await _readPlannerSource();

      // "Plan with this material" menu must check _materialExists == true
      expect(source, contains("_materialExists == true"));
    });

    test('4. Menu item hidden when _materialExists is false or null',
        () async {
      final source = await _readPlannerSource();

      // The menu condition must include _materialExists == true
      // (not just relatedMaterialId != null)
      final planWithMaterialIndex =
          source.indexOf("'Plan with this material'");
      expect(planWithMaterialIndex, isNot(-1));

      // Extract the menu builder context (500 chars before the menu label)
      final contextStart = (planWithMaterialIndex - 500).clamp(0, source.length);
      final menuContext = source.substring(contextStart, planWithMaterialIndex + 100);

      // Must require _materialExists == true
      expect(menuContext, contains('_materialExists == true'));
    });

    test('5. Disabled menu item shown when material existence is unknown',
        () async {
      final source = await _readPlannerSource();

      // When _materialExists is null (loading), a disabled variant should exist
      expect(source, contains("_materialExists == null"));
      expect(source, contains("enabled: false"));
    });

    test('6. Tap handler still has safety fallback for deleted material',
        () async {
      final source = await _readPlannerSource();

      // The tap handler must still check if material was deleted between
      // the initState check and the actual tap (race condition protection)
      expect(source, contains('mData == null'));
      expect(source, contains('no longer available'));
    });

    test('7. Valid material AI flow preserves all required parameters',
        () async {
      final source = await _readPlannerSource();

      // Navigate to AiAssistantScreen with all required parameters
      expect(source, contains('AiAssistantScreen('));
      expect(source, contains('contextMaterialId: materialId'));
      expect(source, contains('contextMaterialTitle:'));
      expect(source, contains('contextMimeType:'));
      expect(source, contains('contextFileName:'));
      expect(source, contains('enableContext: true'));
      expect(source, contains("prefilledQuestion:"));
    });

    test('8. _checkMaterial handles deleted material gracefully',
        () async {
      final source = await _readPlannerSource();

      // _checkMaterial must set _materialExists = false on error
      expect(source, contains('_materialExists = false'));

      // Must check snap.exists
      expect(source, contains('snap.exists'));
    });

    test('9. No permanent per-row Firestore listener', () async {
      final source = await _readPlannerSource();

      // _checkMaterial must use .get() (one-shot), NOT .snapshots() (listener)
      expect(source, contains('.get()'));
      expect(source, isNot(contains('.snapshots()')));
    });

    test('10. Material check is bounded to rows with relatedMaterialId',
        () async {
      final source = await _readPlannerSource();

      // _checkMaterial must early-return if no materialId
      expect(source, contains("materialId == null || materialId.isEmpty"));
      expect(source, contains('return;'));
    });

    test('11. normal Assignment Ask AI still available regardless of material',
        () async {
      final source = await _readPlannerSource();

      // The "Ask AI about this" menu item must NOT check _materialExists
      final askAiIndex = source.indexOf("'Ask AI about this'");
      expect(askAiIndex, isNot(-1));

      // Verify it's not nested inside a material existence check
      final contextStart = (askAiIndex - 300).clamp(0, source.length);
      final askAiContext = source.substring(contextStart, askAiIndex + 50);
      expect(askAiContext, isNot(contains('_materialExists')));
    });
  });
}

Future<String> _readPlannerSource() async {
  const path =
      'lib/features/study/presentation/planner/plan_view.dart';
  // Read relative to flutter_app
  final file = await _findFile(path);
  return file;
}

Future<String> _findFile(String relativePath) async {
  // Walk up from test/ to flutter_app/ and read the file
  final currentDir = Directory.current.path;
  // Try relative path first
  try {
    return await File('$currentDir/$relativePath').readAsString();
  } catch (_) {}
  // Try going up one level
  final parent = currentDir.substring(0, currentDir.lastIndexOf('\\'));
  try {
    return await File('$parent/$relativePath').readAsString();
  } catch (_) {}
  // Try the known project path
  return await File(
          'D:\\EkThikana_Full_Production_Starter\\flutter_app\\$relativePath')
      .readAsString();
}
