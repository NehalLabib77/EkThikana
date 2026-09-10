/// Unified student data foundation.
///
/// This package provides the canonical, read-only models and aggregation
/// layer for student context data.  No new Firestore collections are
/// created; everything is derived from existing sources.
library;

export 'student_context.dart';
export 'student_context_service.dart';
export 'student_event.dart';
export 'student_signal.dart';
export 'student_signal_service.dart';
