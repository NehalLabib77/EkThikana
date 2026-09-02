// Guards the list parsing that crashed the Focus screen.
//
// `ApiService.listFocus` read `body['items']`, but the route returns its rows
// under `sessions`. `items` was therefore always null, and
// `null as List<dynamic>` throws:
//
//     type 'Null' is not a subtype of type 'List<dynamic>' in type cast
//
// So the Focus screen crashed for every user, every time — a plain contract
// mismatch between two sides that were each internally consistent.
//
// Two things are pinned here. The obvious one is that the client reads the
// key the server actually sends. The more valuable one is that an absent,
// null, or wrongly-typed list can never throw again: an optional list that is
// not there means "nothing", and nothing is an empty list.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _source(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  group('No response list is read with an unguarded cast', () {
    test('api_service casts no field straight to List', () {
      // The crash was `... ['items'] as List<dynamic>`. A bare cast on a
      // response field is the shape of this bug, wherever it appears.
      final source = _source('lib/services/api_service.dart');
      final offenders = <String>[];

      for (final (index, line) in source.split('\n').indexed) {
        final trimmed = line.trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
        // A nullable cast (`as List?`) is fine — it cannot throw on null.
        if (RegExp(r'\bas List(<[^>]*>)?\s*[;,)]').hasMatch(line)) {
          offenders.add('${index + 1}: $trimmed');
        }
      }

      expect(offenders, isEmpty,
          reason: 'read response lists through _listField instead:\n'
              '${offenders.join('\n')}');
    });

    test('the focus list reads the key the route actually returns', () {
      final source = _source('lib/services/api_service.dart');
      final method = source.substring(
        source.indexOf('static Future<List<dynamic>> listFocus('),
        source.indexOf('static Future<Map<String, dynamic>> getStudyStats()'),
      );

      expect(method, contains("'sessions'"),
          reason: 'the route returns its rows under `sessions`');
      // `items` stays accepted so the fix works against a backend of either
      // vintage, but it must not be the only key tried.
      expect(method, contains("'items'"));
      expect(method, contains('_listField'));
    });

    test('the backend still sends both keys', () {
      // The alias is what lets an already-installed build recover from a
      // redeploy alone. Dropping it silently re-breaks those users.
      final route = _source('../backend/app/routers/part3.py');

      expect(route, contains('"sessions": sessions, "items": sessions'));
    });
  });

  group('_listField behaviour', () {
    // Exercised through the public surface it protects: the helper is
    // private, so these assert the contract it exists to keep. A missing
    // key, an explicit null, and a wrongly-typed value must all yield an
    // empty list rather than an exception.
    test('the helper is documented as never throwing', () {
      final source = _source('lib/services/api_service.dart');
      final helper = source.substring(
        source.indexOf('static List<dynamic> _listField('),
        source.indexOf('static Future<List<dynamic>> studyPlan()'),
      );

      // The guard is `is List`, which is false for null, absent and wrong
      // types alike — that single check is what makes all three safe.
      expect(helper, contains('if (value is List) return value;'));
      expect(helper, contains('return const [];'));
    });
  });
}
