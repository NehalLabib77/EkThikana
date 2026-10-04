// Phase 3 — the exam hall.
//
// Phase 6 moved the room itself into `real_exam_screen.dart` (the Pro hall:
// save progress, pause/resume, the marks on screen). `ExamHallScreen` is
// kept as an alias of `RealExamScreen` so every Phase 3 route, injection
// seam and test keeps working against one implementation — there is
// deliberately no second hall.

import 'real_exam_screen.dart';

/// The Phase 3 name for [RealExamScreen].
typedef ExamHallScreen = RealExamScreen;
