import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../core/localization/gochano_dates.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../core/page_route.dart';
import '../../../../services/firestore_service.dart';
import '../../life/presentation/commute/plan_trip_sheet.dart';
import '../../life/presentation/commute/planned_trip_models.dart';
import '../../life/presentation/expense/add_expense_sheet.dart';
import '../../life/presentation/expense/dena_pawna_tab.dart';
import '../../life/presentation/medicine/medicine_form_screen.dart';
import '../../study/presentation/materials/material_reader_screen.dart';
import '../../study/presentation/notes/note_editor_screen.dart';
import '../../tasks/presentation/add_task_sheet.dart';
import '../domain/universal_search_models.dart';

/// Coordinator that converts owner-scoped documents from Gochano's 7 canonical categories
/// into normalized, deduplicated [UniversalSearchResult]s and executes ranked client-side search.
class UniversalSearchCoordinator {
  UniversalSearchCoordinator._();

  /// Converts a task document into a [UniversalSearchResult] for Task or Assignment.
  static UniversalSearchResult? mapTaskDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;

    final rawType = data['type']?.toString().toLowerCase().trim();
    final isAssignment = rawType == 'assignment';
    final type = isAssignment
        ? UniversalSearchType.assignment
        : UniversalSearchType.task;

    final title = data['title']?.toString().trim() ?? '';
    if (title.isEmpty) return null;

    final dueAt = (data['dueAt'] as Timestamp?)?.toDate();
    final done = data['done'] == true;
    final note = data['description']?.toString() ?? data['note']?.toString();

    String? subtitle;
    if (dueAt != null) {
      final formattedDate = formatShortDate(dueAt);
      final formattedTime = formatClock12(dueAt);
      subtitle = isAssignment
          ? GochanoLanguage.text(
              'Due $formattedDate • $formattedTime',
              'জমা $formattedDate • $formattedTime',
            )
          : GochanoLanguage.text(
              'Due $formattedDate • $formattedTime',
              'সময় $formattedDate • $formattedTime',
            );
    } else if (done) {
      subtitle = GochanoLanguage.text('Completed', 'সম্পন্ন');
    }

    final timestamp =
        (data['updatedAt'] as Timestamp?)?.toDate() ??
        dueAt ??
        (data['createdAt'] as Timestamp?)?.toDate();

    return UniversalSearchResult(
      id: doc.id,
      type: type,
      title: title,
      subtitle: subtitle,
      secondaryText: note,
      timestamp: timestamp,
      rawData: data,
      onTap: (context) {
        showAddTaskSheet(
          context,
          existing: doc,
          type: isAssignment ? 'assignment' : 'task',
        );
      },
    );
  }

  /// Converts a note document into a [UniversalSearchResult].
  static UniversalSearchResult? mapNoteDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;

    final title = data['title']?.toString().trim() ?? '';
    final content = data['content']?.toString().trim() ?? '';
    if (title.isEmpty && content.isEmpty) return null;

    final displayTitle = title.isNotEmpty
        ? title
        : GochanoLanguage.text('Untitled note', 'শিরোনামহীন নোট');

    final preview = content.replaceAll('\n', ' ').trim();
    final subtitle = preview.isNotEmpty
        ? (preview.length > 80 ? '${preview.substring(0, 80)}…' : preview)
        : null;

    final timestamp =
        (data['updatedAt'] as Timestamp?)?.toDate() ??
        (data['createdAt'] as Timestamp?)?.toDate();

    return UniversalSearchResult(
      id: doc.id,
      type: UniversalSearchType.note,
      title: displayTitle,
      subtitle: subtitle,
      secondaryText: content,
      timestamp: timestamp,
      rawData: data,
      onTap: (context) {
        Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) => NoteEditorScreen(noteId: doc.id, initialData: data),
          ),
        );
      },
    );
  }

  /// Converts a material document into a [UniversalSearchResult] ONLY if it is a PDF.
  static UniversalSearchResult? mapMaterialDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;

    final mimeType = data['mimeType']?.toString().toLowerCase() ?? '';
    final fileName = data['fileName']?.toString() ?? '';
    final isPdf =
        mimeType.contains('pdf') || fileName.toLowerCase().endsWith('.pdf');

    if (!isPdf) return null;

    final rawTitle = data['title']?.toString().trim() ?? '';
    final displayTitle = rawTitle.isNotEmpty ? rawTitle : fileName;
    if (displayTitle.isEmpty) return null;

    final subject = data['subject']?.toString().trim();
    final subtitle = subject != null && subject.isNotEmpty ? subject : 'PDF';

    final timestamp =
        (data['updatedAt'] as Timestamp?)?.toDate() ??
        (data['createdAt'] as Timestamp?)?.toDate();

    return UniversalSearchResult(
      id: doc.id,
      type: UniversalSearchType.pdf,
      title: displayTitle,
      subtitle: subtitle,
      secondaryText: '$fileName ${subject ?? ''}',
      timestamp: timestamp,
      rawData: data,
      onTap: (context) {
        Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) => MaterialReaderScreen(
              materialId: doc.id,
              title: displayTitle,
              mimeType: mimeType,
              fileName: fileName,
            ),
          ),
        );
      },
    );
  }

  /// Converts a medicine document into a [UniversalSearchResult].
  static UniversalSearchResult? mapMedicineDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;

    final name = data['name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;

    final strength = data['strength']?.toString().trim() ?? '';
    final instruction = data['instruction']?.toString().trim() ?? '';
    final schedule =
        data['schedule']?.toString().trim() ??
        ((data['times'] as List?)?.join(', ') ?? '');

    final subtitleParts = <String>[];
    if (strength.isNotEmpty) subtitleParts.add(strength);
    if (schedule.isNotEmpty) subtitleParts.add(schedule);

    final timestamp =
        (data['updatedAt'] as Timestamp?)?.toDate() ??
        (data['createdAt'] as Timestamp?)?.toDate();

    return UniversalSearchResult(
      id: doc.id,
      type: UniversalSearchType.medicine,
      title: name,
      subtitle: subtitleParts.isNotEmpty ? subtitleParts.join(' • ') : null,
      secondaryText: '$instruction $strength',
      timestamp: timestamp,
      rawData: data,
      onTap: (context) {
        Navigator.of(context).push(
          GochanoRoute.to(
            builder: (_) => MedicineFormScreen(medicineId: doc.id),
          ),
        );
      },
    );
  }

  /// Converts a daily expense document into a [UniversalSearchResult].
  static UniversalSearchResult? mapDailyExpenseDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;

    final rawTitle = data['title']?.toString().trim() ?? '';
    final category = data['category']?.toString().trim() ?? '';
    final displayTitle = rawTitle.isNotEmpty
        ? rawTitle
        : (category.isNotEmpty ? category : 'Expense');

    final amountNum = (data['amount'] as num?)?.toDouble() ?? 0.0;
    final amountFormatted = amountNum == amountNum.roundToDouble()
        ? amountNum.toStringAsFixed(0)
        : amountNum.toStringAsFixed(2);

    final note = data['note']?.toString().trim();
    final date = (data['date'] as Timestamp?)?.toDate();

    final subtitle = category.isNotEmpty
        ? '৳$amountFormatted • $category'
        : '৳$amountFormatted';

    final timestamp =
        date ??
        (data['updatedAt'] as Timestamp?)?.toDate() ??
        (data['createdAt'] as Timestamp?)?.toDate();

    return UniversalSearchResult(
      id: doc.id,
      type: UniversalSearchType.expense,
      title: displayTitle,
      subtitle: subtitle,
      secondaryText: '$note $category',
      timestamp: timestamp,
      rawData: data,
      onTap: (context) {
        showAddExpenseSheet(
          context,
          expenseId: doc.id,
          initialCategory: category,
          initialTitle: rawTitle,
          initialAmount: amountNum,
          initialDate: date,
        );
      },
    );
  }

  /// Converts a Dena/Pawna document into a [UniversalSearchResult] labeled as an Expense record.
  static UniversalSearchResult? mapDenaPawnaDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    if (data == null) return null;

    final personName = data['personName']?.toString().trim() ?? '';
    if (personName.isEmpty) return null;

    final typeStr = data['type']?.toString().toLowerCase().trim() ?? 'dena';
    final isDena = typeStr == 'dena';
    final typeLabel = isDena
        ? GochanoLanguage.text('Dena (You owe)', 'দেনা (পাবেন)')
        : GochanoLanguage.text('Pawna (Owed to you)', 'পাওনা (দেবেন)');

    final amountNum =
        (data['outstandingAmount'] as num?)?.toDouble() ??
        (data['amount'] as num?)?.toDouble() ??
        0.0;
    final amountFormatted = amountNum == amountNum.roundToDouble()
        ? amountNum.toStringAsFixed(0)
        : amountNum.toStringAsFixed(2);

    final note = data['note']?.toString().trim();
    final date = (data['date'] as Timestamp?)?.toDate();

    final timestamp =
        date ??
        (data['updatedAt'] as Timestamp?)?.toDate() ??
        (data['createdAt'] as Timestamp?)?.toDate();

    return UniversalSearchResult(
      id: doc.id,
      type: UniversalSearchType.expense,
      title: personName,
      subtitle: '$typeLabel • ৳$amountFormatted',
      secondaryText: '$note $typeStr',
      timestamp: timestamp,
      rawData: data,
      onTap: (context) {
        showDenaPawnaSheet(context, existing: doc);
      },
    );
  }

  /// Converts a planned commute trip into a [UniversalSearchResult].
  static UniversalSearchResult mapPlannedTrip(PlannedCommuteTrip trip) {
    final origin = trip.originName.trim();
    final destination = trip.destinationName.trim();
    final title = '$origin → $destination';

    final formattedDate = formatShortDate(trip.departureTime);
    final formattedTime = formatClock12(trip.departureTime);
    final subtitle = '$formattedDate • $formattedTime';

    return UniversalSearchResult(
      id: trip.id,
      type: UniversalSearchType.trip,
      title: title,
      subtitle: subtitle,
      secondaryText: '$origin $destination',
      timestamp: trip.departureTime,
      rawData: trip.toMap(),
      onTap: (context) {
        showPlanTripSheet(context, existingTrip: trip);
      },
    );
  }

  /// Executes ranked search and filtering over [allItems].
  ///
  /// Ranking order:
  /// 1. Exact title match (score 100)
  /// 2. Title starts with query (score 80)
  /// 3. Word in title starts with query (score 70)
  /// 4. Title contains query (score 60)
  /// 5. Secondary text contains query (score 40)
  /// Ties broken by recency of [timestamp], then alphabetical title.
  static List<UniversalSearchResult> search({
    required List<UniversalSearchResult> allItems,
    required String query,
    required UniversalSearchType activeFilter,
    int limit = 50,
  }) {
    final normalizedQuery = SearchQueryNormalizer.normalize(query);
    if (normalizedQuery.isEmpty) return const [];

    final deduplicated = <String, UniversalSearchResult>{};
    for (final item in allItems) {
      deduplicated.putIfAbsent(item.deduplicationKey, () => item);
    }

    final scored = <({UniversalSearchResult item, int score})>[];

    for (final item in deduplicated.values) {
      if (activeFilter != UniversalSearchType.all &&
          item.type != activeFilter) {
        continue;
      }

      final score = item.matchScore(normalizedQuery);
      if (score > 0) {
        scored.add((item: item, score: score));
      }
    }

    scored.sort((a, b) {
      final scoreCompare = b.score.compareTo(a.score);
      if (scoreCompare != 0) return scoreCompare;

      final aTime = a.item.timestamp;
      final bTime = b.item.timestamp;
      if (aTime != null && bTime != null) {
        final timeCompare = bTime.compareTo(aTime);
        if (timeCompare != 0) return timeCompare;
      } else if (aTime != null) {
        return -1;
      } else if (bTime != null) {
        return 1;
      }

      return a.item.title.toLowerCase().compareTo(b.item.title.toLowerCase());
    });

    return scored.take(limit).map((s) => s.item).toList();
  }

  /// Bounded owner streams combining the 7 canonical collections.
  static Stream<List<UniversalSearchResult>> streamAllItems() {
    late StreamController<List<UniversalSearchResult>> controller;
    final subscriptions = <StreamSubscription>[];

    final taskItems = <UniversalSearchResult>[];
    final noteItems = <UniversalSearchResult>[];
    final materialItems = <UniversalSearchResult>[];
    final medicineItems = <UniversalSearchResult>[];
    final dailyExpenseItems = <UniversalSearchResult>[];
    final denaPawnaItems = <UniversalSearchResult>[];
    final tripItems = <UniversalSearchResult>[];

    void emitLatest() {
      if (controller.isClosed) return;
      final all = <UniversalSearchResult>[
        ...taskItems,
        ...noteItems,
        ...materialItems,
        ...medicineItems,
        ...dailyExpenseItems,
        ...denaPawnaItems,
        ...tripItems,
      ];
      controller.add(all);
    }

    controller = StreamController<List<UniversalSearchResult>>(
      onListen: () {
        subscriptions.add(
          FirestoreService.ownerStream('tasks', limit: 300).listen((snap) {
            taskItems.clear();
            for (final doc in snap.docs) {
              final r = mapTaskDoc(doc);
              if (r != null) taskItems.add(r);
            }
            emitLatest();
          }, onError: (_) {}),
        );
        subscriptions.add(
          FirestoreService.ownerStream('notes', limit: 300).listen((snap) {
            noteItems.clear();
            for (final doc in snap.docs) {
              final r = mapNoteDoc(doc);
              if (r != null) noteItems.add(r);
            }
            emitLatest();
          }, onError: (_) {}),
        );
        subscriptions.add(
          FirestoreService.ownerStream('materials', limit: 300).listen((snap) {
            materialItems.clear();
            for (final doc in snap.docs) {
              final r = mapMaterialDoc(doc);
              if (r != null) materialItems.add(r);
            }
            emitLatest();
          }, onError: (_) {}),
        );
        subscriptions.add(
          FirestoreService.ownerStream('medicines', limit: 300).listen((snap) {
            medicineItems.clear();
            for (final doc in snap.docs) {
              final r = mapMedicineDoc(doc);
              if (r != null) medicineItems.add(r);
            }
            emitLatest();
          }, onError: (_) {}),
        );
        subscriptions.add(
          FirestoreService.ownerStream('daily_expenses', limit: 300).listen((
            snap,
          ) {
            dailyExpenseItems.clear();
            for (final doc in snap.docs) {
              final r = mapDailyExpenseDoc(doc);
              if (r != null) dailyExpenseItems.add(r);
            }
            emitLatest();
          }, onError: (_) {}),
        );
        subscriptions.add(
          FirestoreService.ownerStream('dena_pawna_items', limit: 300).listen((
            snap,
          ) {
            denaPawnaItems.clear();
            for (final doc in snap.docs) {
              final r = mapDenaPawnaDoc(doc);
              if (r != null) denaPawnaItems.add(r);
            }
            emitLatest();
          }, onError: (_) {}),
        );
        subscriptions.add(
          CommuteTripService.streamPlannedTrips().listen((trips) {
            tripItems.clear();
            for (final trip in trips) {
              tripItems.add(mapPlannedTrip(trip));
            }
            emitLatest();
          }, onError: (_) {}),
        );
      },
      onCancel: () {
        for (final sub in subscriptions) {
          sub.cancel();
        }
        subscriptions.clear();
      },
    );

    return controller.stream;
  }
}
