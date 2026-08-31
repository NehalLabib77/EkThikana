// Static guard: every endpoint Flutter calls must exist on the backend with
// the same HTTP method.
//
// This exists because that invariant was silently broken in production:
// `ApiService.patchFocus` sent **POST** to `/api/study/focus/{id}`, which
// FastAPI declares as **PATCH**. Every pause, resume and finish on a focus
// session got a 405 and never reached the server. Nothing caught it, because
// the Flutter tests mock `ApiService` and the backend tests never see Flutter.
//
// The test reads the FastAPI routers directly, so it stays true as routes
// change rather than encoding a snapshot of them.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// One declared HTTP endpoint.
typedef Endpoint = ({String method, String path});

/// `/api/materials/{id}/url` and `/api/materials/$id/url` must compare equal.
String _normalise(String path) {
  return path
      // FastAPI path params: {material_id}
      .replaceAll(RegExp(r'\{[^}]+\}'), '{}')
      // Dart interpolation: $id, ${group.id}
      .replaceAll(RegExp(r'\$\{[^}]+\}'), '{}')
      .replaceAll(RegExp(r'\$\w+'), '{}');
}

Directory _repoRoot() {
  // Tests run with CWD = flutter_app/.
  var dir = Directory.current;
  for (var i = 0; i < 5; i++) {
    if (Directory('${dir.path}/backend/app/routers').existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.parent;
}

Set<Endpoint> _backendEndpoints(Directory repo) {
  final mainSrc = File('${repo.path}/backend/app/main.py').readAsStringSync();

  // module name -> url prefix, from app.include_router(...) calls.
  final prefixes = <String, String>{};
  final includeRe = RegExp(
    r'app\.include_router\(\s*(\w+)\.router\s*(?:,\s*prefix\s*=\s*"([^"]*)")?',
  );
  for (final m in includeRe.allMatches(mainSrc)) {
    prefixes[m.group(1)!] = m.group(2) ?? '';
  }

  final routeRe = RegExp(
    r'@router\.(get|post|put|patch|delete)\(\s*"([^"]*)"',
    caseSensitive: false,
  );

  final endpoints = <Endpoint>{};
  final routerDir = Directory('${repo.path}/backend/app/routers');
  for (final entity in routerDir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.py')) continue;
    final module = entity.uri.pathSegments.last.replaceAll('.py', '');
    if (module == '__init__') continue;
    final prefix = prefixes[module];
    if (prefix == null) continue; // router not mounted
    for (final m in routeRe.allMatches(entity.readAsStringSync())) {
      final path = '$prefix${m.group(2)!}';
      endpoints.add((
        method: m.group(1)!.toUpperCase(),
        path: _normalise(path.isEmpty ? '/' : path),
      ));
    }
  }
  return endpoints;
}

Set<Endpoint> _flutterCalls() {
  final src = File('lib/services/api_service.dart').readAsStringSync();
  final calls = <Endpoint>{};

  // _get('/path') / _post('/path') / _patch(...) / _delete(...)
  final helperRe = RegExp(r"_(get|post|put|patch|delete)\(\s*'([^']+)'");
  for (final m in helperRe.allMatches(src)) {
    calls.add((method: m.group(1)!.toUpperCase(), path: _normalise(m.group(2)!)));
  }

  // http.verb(_uri('/path')) and _client.verb(_uri('/path'))
  final directRe = RegExp(
    r"(?:http|_client)\s*\.\s*(get|post|put|patch|delete)\(\s*\n?\s*_uri\(\s*'([^']+)'",
  );
  for (final m in directRe.allMatches(src)) {
    calls.add((method: m.group(1)!.toUpperCase(), path: _normalise(m.group(2)!)));
  }

  // MultipartRequest('POST', _uri('/path'))
  final multipartRe = RegExp(
    r"MultipartRequest\(\s*'(\w+)'\s*,\s*_uri\(\s*'([^']+)'",
  );
  for (final m in multipartRe.allMatches(src)) {
    calls.add((method: m.group(1)!.toUpperCase(), path: _normalise(m.group(2)!)));
  }

  return calls;
}

void main() {
  final repo = _repoRoot();

  test('the backend routers are readable from the test', () {
    expect(
      Directory('${repo.path}/backend/app/routers').existsSync(),
      isTrue,
      reason: 'could not locate backend/app/routers from ${repo.path}',
    );
    expect(_backendEndpoints(repo), isNotEmpty);
    expect(_flutterCalls(), isNotEmpty);
  });

  test('every Flutter API call matches a backend route and method', () {
    final backend = _backendEndpoints(repo);
    final calls = _flutterCalls();

    final mismatches = <String>[];
    for (final call in calls) {
      if (backend.contains(call)) continue;

      // Distinguish "wrong verb" from "no such path" — the first is a live
      // 405 in production, the second is a typo or a removed route.
      final sameP =
          backend.where((e) => e.path == call.path).map((e) => e.method).toList()
            ..sort();
      mismatches.add(
        sameP.isEmpty
            ? '${call.method} ${call.path}  -> no such backend path'
            : '${call.method} ${call.path}  -> backend declares $sameP',
      );
    }

    expect(
      mismatches,
      isEmpty,
      reason: 'Flutter would receive 404/405 for:\n  ${mismatches.join('\n  ')}',
    );
  });

  test('health is the only unauthenticated call', () {
    // Everything else must send the Firebase ID token (spec §82).
    final src = File('lib/services/api_service.dart').readAsStringSync();
    final unauthenticated = RegExp(r"_(?:get|post|put|patch|delete)\(\s*'([^']+)'[^;]*?auth:\s*false")
        .allMatches(src)
        .map((m) => m.group(1)!)
        .toSet();
    expect(unauthenticated, {'/api/health'});
  });
}
