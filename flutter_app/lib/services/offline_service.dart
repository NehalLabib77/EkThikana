import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'api_service.dart';

/// PART 3 — Offline materials.
///
/// Per correction 2 the device-local file is the source of truth. The backend
/// `/api/offline/*` endpoints are used only to mirror lightweight metadata so
/// the server can re-surface this device's offline set in future clients.
class OfflineEntry {
  const OfflineEntry({
    required this.materialId,
    required this.title,
    required this.fileName,
    required this.localPath,
    required this.size,
    required this.mimeType,
    required this.savedAt,
  });

  final String materialId;
  final String title;
  final String fileName;
  final String localPath;
  final int size;
  final String mimeType;
  final DateTime savedAt;

  Map<String, dynamic> toJson() => {
        'materialId': materialId,
        'title': title,
        'fileName': fileName,
        'localPath': localPath,
        'size': size,
        'mimeType': mimeType,
        'savedAt': savedAt.toIso8601String(),
      };

  factory OfflineEntry.fromJson(Map<String, dynamic> json) {
    return OfflineEntry(
      materialId: json['materialId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      localPath: json['localPath']?.toString() ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      mimeType: json['mimeType']?.toString() ?? 'application/pdf',
      savedAt:
          DateTime.tryParse(json['savedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

class OfflineService {
  OfflineService._();

  static const _manifestName = 'offline_manifest.json';
  static const _folderName = 'offline';

  static Future<Directory> _baseDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/$_folderName');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> _manifestFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File('${docs.path}/$_manifestName');
  }

  static Future<List<OfflineEntry>> _readManifest() async {
    final file = await _manifestFile();
    if (!await file.exists()) return <OfflineEntry>[];
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <OfflineEntry>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <OfflineEntry>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(OfflineEntry.fromJson)
          .toList();
    } catch (_) {
      return <OfflineEntry>[];
    }
  }

  static Future<void> _writeManifest(List<OfflineEntry> entries) async {
    final file = await _manifestFile();
    await file.writeAsString(jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  /// Public counterpart used by non-PDF viewers that need a temp file path
  /// to hand to an external app. No manifest entry is written.
  static Future<File> writeTemp({
    required String materialId,
    required Uint8List bytes,
    required String mimeType,
    required String fileName,
  }) async {
    final dir = await _baseDir();
    final ext = _extensionFor(mimeType, fileName);
    final safeId = materialId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final f = File('${dir.path}/viewer_$safeId$ext');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }

  static String _extensionFor(String mimeType, String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.pdf')) return '.pdf';
    if (lower.endsWith('.docx')) return '.docx';
    if (lower.endsWith('.doc')) return '.doc';
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return '.jpg';
    final mime = mimeType.toLowerCase();
    if (mime == 'application/pdf') return '.pdf';
    if (mime ==
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document') {
      return '.docx';
    }
    if (mime == 'application/msword') return '.doc';
    if (mime == 'image/png') return '.png';
    if (mime == 'image/jpeg') return '.jpg';
    return '.bin';
  }

  /// Persists a material to device-local storage. The file is the source of
  /// truth; backend metadata is mirrored opportunistically and failures are
  /// logged but never block the local save.
  static Future<OfflineEntry> register({
    required String materialId,
    required String title,
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final dir = await _baseDir();
    final ext = _extensionFor(mimeType, fileName);
    final safeId = materialId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final path = '${dir.path}/$safeId$ext';
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);

    final entry = OfflineEntry(
      materialId: materialId,
      title: title.isEmpty ? fileName : title,
      fileName: fileName,
      localPath: path,
      size: bytes.length,
      mimeType: mimeType,
      savedAt: DateTime.now(),
    );

    final entries = await _readManifest();
    final filtered = entries.where((e) => e.materialId != materialId).toList()
      ..add(entry);
    await _writeManifest(filtered);

    // Mirror metadata. A backend failure here must not block the local save.
    try {
      await ApiService.registerOffline(
        materialId: materialId,
        title: entry.title,
        size: entry.size,
        localPath: entry.localPath,
        fileType: mimeType,
        originalFilename: fileName,
      );
    } catch (_) {
      // Swallowed — device-local is the source of truth.
    }

    return entry;
  }

  static Future<List<OfflineEntry>> list() async {
    final entries = await _readManifest();
    final out = <OfflineEntry>[];
    for (final e in entries) {
      final f = File(e.localPath);
      if (await f.exists()) {
        out.add(e);
      }
    }
    return out;
  }

  static Future<OfflineEntry?> find(String materialId) async {
    final entries = await list();
    for (final e in entries) {
      if (e.materialId == materialId) return e;
    }
    return null;
  }

  static Future<void> remove(String materialId) async {
    final entries = await _readManifest();
    OfflineEntry? target;
    final remaining = <OfflineEntry>[];
    for (final e in entries) {
      if (e.materialId == materialId) {
        target = e;
      } else {
        remaining.add(e);
      }
    }
    await _writeManifest(remaining);
    if (target != null) {
      final f = File(target.localPath);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {
          // ignore — manifest already updated
        }
      }
    }
    try {
      await ApiService.removeOffline(materialId);
    } catch (_) {
      // ignore — local cleanup succeeded
    }
  }
}
