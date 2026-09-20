import 'package:flutter/material.dart';

import '../../../../core/localization/gochano_language.dart';

/// The 7 canonical searchable categories in Gochano plus the 'all' aggregator.
enum UniversalSearchType {
  all,
  task,
  assignment,
  note,
  pdf,
  medicine,
  expense,
  trip;

  String get labelEn {
    switch (this) {
      case UniversalSearchType.all:
        return 'All';
      case UniversalSearchType.task:
        return 'Tasks';
      case UniversalSearchType.assignment:
        return 'Assignments';
      case UniversalSearchType.note:
        return 'Notes';
      case UniversalSearchType.pdf:
        return 'PDFs';
      case UniversalSearchType.medicine:
        return 'Medicine';
      case UniversalSearchType.expense:
        return 'Expenses';
      case UniversalSearchType.trip:
        return 'Trips';
    }
  }

  String get labelBn {
    switch (this) {
      case UniversalSearchType.all:
        return 'সব';
      case UniversalSearchType.task:
        return 'কাজ';
      case UniversalSearchType.assignment:
        return 'অ্যাসাইনমেন্ট';
      case UniversalSearchType.note:
        return 'নোট';
      case UniversalSearchType.pdf:
        return 'পিডিএফ';
      case UniversalSearchType.medicine:
        return 'ওষুধ';
      case UniversalSearchType.expense:
        return 'খরচ';
      case UniversalSearchType.trip:
        return 'যাত্রা';
    }
  }

  String get displayName => GochanoLanguage.text(labelEn, labelBn);

  IconData get icon {
    switch (this) {
      case UniversalSearchType.all:
        return Icons.search_rounded;
      case UniversalSearchType.task:
        return Icons.check_circle_outline_rounded;
      case UniversalSearchType.assignment:
        return Icons.assignment_outlined;
      case UniversalSearchType.note:
        return Icons.description_outlined;
      case UniversalSearchType.pdf:
        return Icons.picture_as_pdf_outlined;
      case UniversalSearchType.medicine:
        return Icons.medication_outlined;
      case UniversalSearchType.expense:
        return Icons.account_balance_wallet_outlined;
      case UniversalSearchType.trip:
        return Icons.directions_bus_outlined;
    }
  }
}

/// Normalizes search queries for case-insensitivity, trimmed edges, and collapsed whitespace.
/// Preserves Bengali Unicode characters intact without destructive conversions.
class SearchQueryNormalizer {
  SearchQueryNormalizer._();

  static final RegExp _multiSpace = RegExp(r'\s+');

  static String normalize(String query) {
    if (query.isEmpty) return '';
    return query.toLowerCase().replaceAll(_multiSpace, ' ').trim();
  }
}

/// Normalized search result model representing an item from any of the 7 searchable categories.
class UniversalSearchResult {
  const UniversalSearchResult({
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    this.secondaryText,
    this.timestamp,
    this.rawData = const {},
    this.onTap,
  });

  /// Stable domain ID (e.g. Firestore document ID).
  final String id;

  /// Category of the result.
  final UniversalSearchType type;

  /// Primary display title.
  final String title;

  /// Short secondary context or metadata.
  final String? subtitle;

  /// Optional searchable content/notes (e.g. note body or expense note).
  final String? secondaryText;

  /// Associated date/time used as recency tie-breaker.
  final DateTime? timestamp;

  /// Raw document snapshot data.
  final Map<String, dynamic> rawData;

  /// Navigation callback when user taps this result.
  final void Function(BuildContext context)? onTap;

  /// Deterministic composite key preventing any duplicate rendering across sources.
  String get deduplicationKey => '${type.name}_$id';

  /// Computes a relevance score based on query match priority:
  /// 1. Exact title match (100)
  /// 2. Title starts with query (80)
  /// 3. Word in title starts with query (70)
  /// 4. Title contains query (60)
  /// 5. Secondary text / subtitle contains query (40)
  /// 0 if no match.
  int matchScore(String normalizedQuery) {
    if (normalizedQuery.isEmpty) return 0;

    final normalizedTitle = SearchQueryNormalizer.normalize(title);
    if (normalizedTitle == normalizedQuery) {
      return 100;
    }
    if (normalizedTitle.startsWith(normalizedQuery)) {
      return 80;
    }

    final words = normalizedTitle.split(' ');
    for (final word in words) {
      if (word.startsWith(normalizedQuery)) {
        return 70;
      }
    }

    if (normalizedTitle.contains(normalizedQuery)) {
      return 60;
    }

    final normalizedSecondary = SearchQueryNormalizer.normalize(
      '${subtitle ?? ''} ${secondaryText ?? ''}',
    );
    if (normalizedSecondary.contains(normalizedQuery)) {
      return 40;
    }

    return 0;
  }
}
