// Phase 7 - the shared vocabulary of the Question Bank, Exam Challenges and
// the Ziku Moderator.
//
// These labels are derived from the backend's own constants
// (`STUDY_CATEGORIES` / `POST_KINDS` / challenge statuses) so the app can
// never offer a filter the API would answer with a 400, and so every screen
// that shows a category or a post kind says the same thing about it.

import '../../../core/localization/gochano_language.dart';

/// Mirrors `app.services.community_service.STUDY_CATEGORIES`.
const List<String> kStudyCategories = <String>[
  'hsc',
  'university',
  'admission',
  'ielts',
  'coding',
  'engineering',
];

/// Mirrors `app.services.community_service.POST_KINDS`, with '' as "any".
const List<String> kPostKinds = <String>[
  '',
  'question',
  'solution',
  'notes',
  'achievement',
];

const String kPostSortRecent = 'recent';
const String kPostSortPopular = 'popular';

const List<String> kPostSorts = <String>[kPostSortRecent, kPostSortPopular];

const List<String> kCommunitySegments = <String>[
  'groups',
  'questions',
  'challenges',
];

/// '' is the "no category" option a student can clear back to.
String studyCategoryLabel(String value) {
  switch (value) {
    case 'hsc':
      return GochanoLanguage.text('HSC', 'এইচএসসি');
    case 'university':
      return GochanoLanguage.text('University', 'বিশ্ববিদ্যালয়');
    case 'admission':
      return GochanoLanguage.text('Admission', 'ভর্তি');
    case 'ielts':
      return GochanoLanguage.text('IELTS', 'আইইএলটিএস');
    case 'coding':
      return GochanoLanguage.text('Coding', 'কোডিং');
    case 'engineering':
      return GochanoLanguage.text('Engineering', 'ইঞ্জিনিয়ারিং');
    default:
      return GochanoLanguage.text('Any subject', 'যেকোনো বিষয়');
  }
}

String postKindLabel(String kind) {
  switch (kind) {
    case 'question':
      return GochanoLanguage.text('Question', 'প্রশ্ন');
    case 'solution':
      return GochanoLanguage.text('Solution', 'সমাধান');
    case 'notes':
      return GochanoLanguage.text('Notes', 'নোট');
    case 'achievement':
      return GochanoLanguage.text('Achievement', 'অর্জন');
    default:
      return GochanoLanguage.text('All', 'সব');
  }
}

String postSortLabel(String sort) {
  switch (sort) {
    case kPostSortPopular:
      return GochanoLanguage.text('Popular', 'জনপ্রিয়');
    default:
      return GochanoLanguage.text('Recent', 'সাম্প্রতিক');
  }
}

String communitySegmentLabel(String segment) {
  switch (segment) {
    case 'questions':
      return GochanoLanguage.text('Questions', 'প্রশ্ন');
    case 'challenges':
      return GochanoLanguage.text('Challenges', 'চ্যালেঞ্জ');
    default:
      return GochanoLanguage.text('Groups', 'গ্রুপ');
  }
}

String challengeStatusLabel(String status) {
  switch (status) {
    case 'pending':
      return GochanoLanguage.text('Waiting', 'অপেক্ষমাণ');
    case 'accepted':
      return GochanoLanguage.text('Ready', 'প্রস্তুত');
    case 'completed':
      return GochanoLanguage.text('Finished', 'শেষ');
    case 'declined':
      return GochanoLanguage.text('Declined', 'প্রত্যাখ্যাত');
    case 'cancelled':
      return GochanoLanguage.text('Cancelled', 'বাতিল');
    default:
      return GochanoLanguage.text('Open', 'খোলা');
  }
}

/// The moderator's own action vocabulary, shared by its chips and its
/// section headers so the two never drift apart.
const List<String> kModeratorSections = <String>[
  'ask',
  'moderate',
  'topics',
  'quiz',
  'insights',
  'points',
];

String moderatorSectionLabel(String section) {
  switch (section) {
    case 'moderate':
      return GochanoLanguage.text('Moderate', 'মডারেট');
    case 'topics':
      return GochanoLanguage.text('Topics', 'টপিক');
    case 'quiz':
      return GochanoLanguage.text('Quiz', 'কুইজ');
    case 'insights':
      return GochanoLanguage.text('Insights', 'সংকেত');
    case 'points':
      return GochanoLanguage.text('Points', 'পয়েন্ট');
    default:
      return GochanoLanguage.text('Ask', 'জিজ্ঞাসা');
  }
}
