// Gochano static illustration catalogue.
//
// Every drawing in this file obeys the same rules so the set reads as one
// visual language (spec §95):
//
//   * 96×96 viewBox, artwork inset ~10px from the edge;
//   * stroke width 3.4, round caps and joins;
//   * soft, simplified, cartoon-*inspired* geometry — friendly shapes and
//     rounded corners, but no faces, no mascots, no preschool stickers
//     (spec §19: "must NOT look like children's preschool stickers");
//   * exactly three colour slots — `{ink}`, `{fill}`, `{paper}` — resolved
//     from the active theme by `GochanoIllustration` (spec §18).
//
// Nothing here animates and nothing here may be made to animate (spec §11).
//
// Adding a drawing: append a `static const` id, add the body to [_bodies],
// and — if it is a subject — add its keywords to [subjectIdFor].

/// Ids and SVG bodies for every Gochano illustration.
abstract final class GochanoArt {
  // --- Subjects (spec §19) ----------------------------------------------
  static const String subjectProgramming = 'subject.programming';
  static const String subjectAi = 'subject.ai';
  static const String subjectDatabase = 'subject.database';
  static const String subjectNetworking = 'subject.networking';
  static const String subjectMath = 'subject.math';
  static const String subjectPhysics = 'subject.physics';
  static const String subjectChemistry = 'subject.chemistry';
  static const String subjectBiology = 'subject.biology';
  static const String subjectSoftwareEngineering = 'subject.software';
  static const String subjectEnglish = 'subject.english';
  static const String subjectBusiness = 'subject.business';
  static const String subjectGeneric = 'subject.generic';

  // --- Resource / file types (spec §21) ---------------------------------
  static const String filePdf = 'file.pdf';
  static const String fileImage = 'file.image';
  static const String fileNote = 'file.note';
  static const String fileDoc = 'file.doc';
  static const String fileSlides = 'file.slides';
  static const String fileGeneric = 'file.generic';

  // --- Features ----------------------------------------------------------
  static const String featureStudy = 'feature.study';
  static const String featureAi = 'feature.ai';
  static const String featureGroups = 'feature.groups';
  static const String featureChat = 'feature.chat';
  static const String featureMembers = 'feature.members';
  static const String featureExpense = 'feature.expense';
  static const String featureGrocery = 'feature.grocery';
  static const String featureBudget = 'feature.budget';
  static const String featureCalendar = 'feature.calendar';
  static const String featureMedicine = 'feature.medicine';
  static const String featurePrescription = 'feature.prescription';
  static const String featureReminder = 'feature.reminder';
  static const String featureCommute = 'feature.commute';
  static const String featureCommunity = 'feature.community';
  static const String featureTasks = 'feature.tasks';
  static const String featurePlanner = 'feature.planner';
  static const String featureFocus = 'feature.focus';
  static const String featureProfile = 'feature.profile';
  static const String featureHome = 'feature.home';

  // --- Transport modes (spec §61) ---------------------------------------
  static const String modeWalk = 'mode.walk';
  static const String modeBus = 'mode.bus';
  static const String modeMetro = 'mode.metro';
  static const String modeRickshaw = 'mode.rickshaw';
  static const String modeCng = 'mode.cng';
  static const String modeTrain = 'mode.train';
  static const String modeBoat = 'mode.boat';
  static const String modeCar = 'mode.car';
  static const String pinOrigin = 'pin.origin';
  static const String pinDestination = 'pin.destination';

  // --- Empty / status states (spec §22, §75, §76) ------------------------
  static const String emptySubjects = 'empty.subjects';
  static const String emptyMaterials = 'empty.materials';
  static const String emptyTasks = 'empty.tasks';
  static const String emptyGroupResources = 'empty.groupResources';
  static const String emptyExpenses = 'empty.expenses';
  static const String emptyMedicines = 'empty.medicines';
  static const String emptyCommute = 'empty.commute';
  static const String emptyMessages = 'empty.messages';
  static const String emptySearch = 'empty.search';
  static const String stateError = 'state.error';
  static const String stateOffline = 'state.offline';
  static const String stateTaken = 'state.taken';
  static const String stateSkipped = 'state.skipped';

  /// Neutral fallback used whenever an id is unknown (spec §20 — a custom
  /// subject name must never produce a missing or broken visual).
  static const String generic = 'generic';

  /// Returns a ready-to-render SVG document for [id] with theme colours
  /// substituted. Unknown ids resolve to [generic].
  static String resolve(
    String id, {
    required Object ink,
    required Object fill,
    required Object paper,
  }) {
    final body = _bodies[id] ?? _bodies[generic]!;
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96" '
            'fill="none" stroke-linecap="round" stroke-linejoin="round">$body</svg>'
        .replaceAll('{ink}', _hex(ink))
        .replaceAll('{fill}', _hex(fill))
        .replaceAll('{paper}', _hex(paper));
  }

  /// Maps a free-text subject name onto a subject illustration id.
  ///
  /// Students type their own subject names, so this is keyword matching, not
  /// a fixed enum (spec §20). Matching is case-insensitive and substring
  /// based; the first matching group wins. Anything unmatched falls back to
  /// [subjectGeneric] rather than to a missing icon.
  static String subjectIdFor(String? subjectName) {
    final name = (subjectName ?? '').toLowerCase().trim();
    if (name.isEmpty) return subjectGeneric;

    bool has(List<String> keys) => keys.any(name.contains);

    // Order matters: more specific groups are tested before broader ones so
    // "machine learning lab" resolves to AI rather than to Programming.
    if (has(const [
      'artificial intelligence',
      'machine learning',
      'deep learning',
      'neural',
      'data science',
      ' ai ',
      'ai ',
      ' ai',
      'nlp',
      'computer vision',
    ]) ||
        name == 'ai') {
      return subjectAi;
    }
    if (has(const [
      'database',
      'dbms',
      'sql',
      'data management',
      'ডাটাবেজ',
      'ডাটাবেস',
    ])) {
      return subjectDatabase;
    }
    if (has(const [
      'network',
      'computer network',
      'ccna',
      'routing',
      'protocol',
      'নেটওয়ার্ক',
    ])) {
      return subjectNetworking;
    }
    if (has(const [
      'software engineering',
      'software design',
      'system analysis',
      'architecture',
      'design pattern',
      'operating system',
    ])) {
      return subjectSoftwareEngineering;
    }
    if (has(const [
      'programming',
      'algorithm',
      'data structure',
      'python',
      'java',
      'c++',
      'coding',
      'compiler',
      'web develop',
      'app develop',
      'প্রোগ্রামিং',
    ])) {
      return subjectProgramming;
    }
    if (has(const [
      'math',
      'calculus',
      'algebra',
      'geometry',
      'statistic',
      'discrete',
      'linear',
      'probability',
      'গণিত',
    ])) {
      return subjectMath;
    }
    if (has(const ['physic', 'mechanic', 'thermodynam', 'optic', 'পদার্থ'])) {
      return subjectPhysics;
    }
    if (has(const ['chemistr', 'organic', 'inorganic', 'রসায়ন'])) {
      return subjectChemistry;
    }
    if (has(const [
      'biolog',
      'botany',
      'zoolog',
      'anatomy',
      'genetic',
      'microbio',
      'জীব',
    ])) {
      return subjectBiology;
    }
    if (has(const [
      'english',
      'literature',
      'language',
      'grammar',
      'writing',
      'ইংরেজি',
      'বাংলা',
    ])) {
      return subjectEnglish;
    }
    if (has(const [
      'business',
      'account',
      'econom',
      'management',
      'marketing',
      'finance',
      'entrepreneur',
      'হিসাব',
      'ব্যবসা',
    ])) {
      return subjectBusiness;
    }
    return subjectGeneric;
  }

  /// Maps a file name / MIME type onto a resource illustration id (spec §21).
  static String fileIdFor({String? fileName, String? mimeType}) {
    final mime = (mimeType ?? '').toLowerCase();
    final name = (fileName ?? '').toLowerCase();
    String ext = '';
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) ext = name.substring(dot + 1);

    if (mime.contains('pdf') || ext == 'pdf') return filePdf;
    if (mime.startsWith('image/') ||
        const {'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic', 'bmp'}
            .contains(ext)) {
      return fileImage;
    }
    if (const {'ppt', 'pptx', 'odp'}.contains(ext) ||
        mime.contains('presentation')) {
      return fileSlides;
    }
    if (const {'doc', 'docx', 'odt', 'rtf'}.contains(ext) ||
        mime.contains('word') ||
        mime.contains('officedocument.wordprocessing')) {
      return fileDoc;
    }
    if (const {'txt', 'md', 'note'}.contains(ext) || mime.startsWith('text/')) {
      return fileNote;
    }
    return fileGeneric;
  }

  /// Maps a transport mode id from the commute backend onto an illustration.
  static String transportIdFor(String? mode) {
    switch ((mode ?? '').toLowerCase().trim()) {
      case 'walk':
      case 'walking':
      case 'foot':
        return modeWalk;
      case 'bus':
      case 'brta':
      case 'minibus':
        return modeBus;
      case 'metro':
      case 'mrt':
      case 'metrorail':
        return modeMetro;
      case 'rickshaw':
        return modeRickshaw;
      case 'cng':
      case 'auto':
      case 'autorickshaw':
      case 'auto_rickshaw':
        return modeCng;
      case 'train':
      case 'rail':
        return modeTrain;
      case 'boat':
      case 'launch':
      case 'ferry':
        return modeBoat;
      case 'car':
      case 'taxi':
      case 'ride':
      case 'rideshare':
        return modeCar;
      default:
        return modeBus;
    }
  }

  static String _hex(Object color) {
    // Accepts a dart:ui Color without importing Flutter into this file, so
    // the catalogue stays a pure-data module that unit tests can read
    // without a widget binding.
    final value = (color as dynamic);
    int argb;
    try {
      argb = ((value.a * 255).round() << 24) |
          ((value.r * 255).round() << 16) |
          ((value.g * 255).round() << 8) |
          (value.b * 255).round();
    } catch (_) {
      argb = 0xFF000000;
    }
    final rgb = (argb & 0x00FFFFFF).toRadixString(16).padLeft(6, '0');
    return '#$rgb';
  }

  // -----------------------------------------------------------------------
  // Drawings
  // -----------------------------------------------------------------------
  static const Map<String, String> _bodies = <String, String>{
    // --- Subjects --------------------------------------------------------
    subjectProgramming: '''
<rect x="12" y="20" width="72" height="46" rx="7" fill="{fill}"/>
<rect x="12" y="20" width="72" height="46" rx="7" stroke="{ink}" stroke-width="3.4"/>
<path d="M8 74h80" stroke="{ink}" stroke-width="3.4"/>
<path d="M38 34l-9 9 9 9" stroke="{ink}" stroke-width="3.4"/>
<path d="M58 34l9 9-9 9" stroke="{ink}" stroke-width="3.4"/>
<path d="M52 31l-8 24" stroke="{ink}" stroke-width="3.4"/>''',

    subjectAi: '''
<path d="M48 16c-11 0-19 7-19 16 0 4 1 7 3 10-3 3-4 7-4 11 0 10 9 17 20 17s20-7 20-17c0-4-1-8-4-11 2-3 3-6 3-10 0-9-8-16-19-16z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M48 26v44" stroke="{ink}" stroke-width="3.4"/>
<path d="M48 38l-10 6M48 52l10 6" stroke="{ink}" stroke-width="3.4"/>
<circle cx="38" cy="44" r="4.5" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="58" cy="58" r="4.5" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>''',

    subjectDatabase: '''
<path d="M22 26v44c0 5 12 9 26 9s26-4 26-9V26" fill="{fill}"/>
<ellipse cx="48" cy="26" rx="26" ry="9" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M22 26v44c0 5 12 9 26 9s26-4 26-9V26" stroke="{ink}" stroke-width="3.4"/>
<path d="M22 44c0 5 12 9 26 9s26-4 26-9" stroke="{ink}" stroke-width="3.4"/>
<path d="M22 58c0 5 12 9 26 9s26-4 26-9" stroke="{ink}" stroke-width="3.4"/>''',

    subjectNetworking: '''
<circle cx="48" cy="20" r="9" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="20" cy="70" r="9" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="48" cy="70" r="9" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="76" cy="70" r="9" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M48 29v14M48 43H20v18M48 43h28v18M48 43v18" stroke="{ink}" stroke-width="3.4"/>''',

    subjectMath: '''
<rect x="22" y="12" width="52" height="72" rx="9" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<rect x="31" y="21" width="34" height="15" rx="4" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M33 50h10M38 45v10" stroke="{ink}" stroke-width="3.4"/>
<path d="M53 50h10" stroke="{ink}" stroke-width="3.4"/>
<path d="M33 66h10" stroke="{ink}" stroke-width="3.4"/>
<path d="M53 63h10M53 70h10" stroke="{ink}" stroke-width="3.4"/>''',

    subjectPhysics: '''
<circle cx="48" cy="48" r="7" fill="{ink}"/>
<ellipse cx="48" cy="48" rx="34" ry="14" stroke="{ink}" stroke-width="3.4"/>
<ellipse cx="48" cy="48" rx="34" ry="14" stroke="{ink}" stroke-width="3.4" transform="rotate(60 48 48)"/>
<ellipse cx="48" cy="48" rx="34" ry="14" stroke="{ink}" stroke-width="3.4" transform="rotate(120 48 48)"/>''',

    subjectChemistry: '''
<path d="M40 12h16v24l17 30c3 6-1 13-8 13H31c-7 0-11-7-8-13l17-30V12z" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M31 56h34l8 14c3 6-1 9-8 9H31c-7 0-11-3-8-9l8-14z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M36 12h24" stroke="{ink}" stroke-width="3.4"/>
<circle cx="42" cy="68" r="3.5" fill="{ink}"/>
<circle cx="55" cy="63" r="2.5" fill="{ink}"/>''',

    subjectBiology: '''
<path d="M74 20C48 20 26 34 26 58c0 8 3 14 3 14s20-2 33-15c11-11 12-37 12-37z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M18 80c8-18 22-32 42-44" stroke="{ink}" stroke-width="3.4"/>
<path d="M46 40c4 5 6 11 6 17M60 32c3 6 4 13 3 20" stroke="{ink}" stroke-width="3.4"/>''',

    subjectSoftwareEngineering: '''
<rect x="16" y="16" width="64" height="18" rx="6" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<rect x="16" y="39" width="64" height="18" rx="6" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<rect x="16" y="62" width="64" height="18" rx="6" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="27" cy="25" r="3" fill="{ink}"/>
<circle cx="27" cy="48" r="3" fill="{ink}"/>
<circle cx="27" cy="71" r="3" fill="{ink}"/>''',

    subjectEnglish: '''
<path d="M48 28c-7-6-17-8-30-7v50c13-1 23 1 30 7 7-6 17-8 30-7V21c-13-1-23 1-30 7z" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M48 28v50" stroke="{ink}" stroke-width="3.4"/>
<path d="M28 42h12M28 54h12" stroke="{ink}" stroke-width="3.4"/>
<path d="M57 55l7-16 7 16M59.5 50h9" stroke="{ink}" stroke-width="3.4"/>''',

    subjectBusiness: '''
<rect x="12" y="30" width="72" height="46" rx="8" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M36 30v-6a6 6 0 016-6h12a6 6 0 016 6v6" stroke="{ink}" stroke-width="3.4"/>
<path d="M12 48h72" stroke="{ink}" stroke-width="3.4"/>
<path d="M32 66v-8M44 66v-14M56 66v-11M68 66v-17" stroke="{ink}" stroke-width="3.4"/>''',

    subjectGeneric: '''
<rect x="16" y="24" width="46" height="58" rx="6" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<rect x="28" y="14" width="46" height="58" rx="6" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M38 30h26M38 42h26M38 54h16" stroke="{ink}" stroke-width="3.4"/>''',

    // --- Resource / file types ------------------------------------------
    filePdf: '''
<path d="M24 12h32l18 18v54a6 6 0 01-6 6H24a6 6 0 01-6-6V18a6 6 0 016-6z" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M56 12v18h18" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<rect x="26" y="52" width="44" height="22" rx="5" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M34 68V58h4a3.5 3.5 0 010 7h-4" stroke="{ink}" stroke-width="3"/>
<path d="M47 68V58h3.5a5 5 0 010 10H47z" stroke="{ink}" stroke-width="3"/>
<path d="M62 68V58h5M62 63h4" stroke="{ink}" stroke-width="3"/>''',

    fileImage: '''
<rect x="14" y="20" width="68" height="56" rx="8" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="34" cy="38" r="6" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M14 66l18-18 14 14 12-11 24 21" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>''',

    fileNote: '''
<rect x="18" y="14" width="52" height="68" rx="7" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M30 32h28M30 44h28M30 56h16" stroke="{ink}" stroke-width="3.4"/>
<path d="M62 70l16-16 8 8-16 16-10 2 2-10z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>''',

    fileDoc: '''
<path d="M24 12h32l18 18v54a6 6 0 01-6 6H24a6 6 0 01-6-6V18a6 6 0 016-6z" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M56 12v18h18" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M30 46h36M30 58h36M30 70h22" stroke="{ink}" stroke-width="3.4"/>''',

    fileSlides: '''
<rect x="12" y="18" width="72" height="46" rx="8" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<rect x="22" y="28" width="30" height="26" rx="4" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M60 30h14M60 40h14M60 50h9" stroke="{ink}" stroke-width="3.4"/>
<path d="M48 64v12M34 84l14-8 14 8" stroke="{ink}" stroke-width="3.4"/>''',

    fileGeneric: '''
<path d="M24 12h32l18 18v54a6 6 0 01-6 6H24a6 6 0 01-6-6V18a6 6 0 016-6z" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M56 12v18h18" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>''',

    // --- Features --------------------------------------------------------
    featureStudy: '''
<path d="M10 34l38-16 38 16-38 16-38-16z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M24 41v20c0 6 11 11 24 11s24-5 24-11V41" stroke="{ink}" stroke-width="3.4"/>
<path d="M82 37v20" stroke="{ink}" stroke-width="3.4"/>''',

    featureAi: '''
<rect x="14" y="18" width="50" height="62" rx="8" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M26 36h26M26 48h26M26 60h14" stroke="{ink}" stroke-width="3.4"/>
<path d="M70 20l4.5 11L86 35.5 74.5 40 70 51l-4.5-11L54 35.5 65.5 31 70 20z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M76 62l2.5 6 6 2.5-6 2.5-2.5 6-2.5-6-6-2.5 6-2.5 2.5-6z" fill="{fill}" stroke="{ink}" stroke-width="3"/>''',

    featureGroups: '''
<circle cx="48" cy="30" r="12" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M28 72c0-11 9-18 20-18s20 7 20 18" stroke="{ink}" stroke-width="3.4"/>
<circle cx="19" cy="42" r="9" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="77" cy="42" r="9" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M8 72c0-8 5-13 11-13M88 72c0-8-5-13-11-13" stroke="{ink}" stroke-width="3.4"/>''',

    featureChat: '''
<path d="M14 26a8 8 0 018-8h34a8 8 0 018 8v20a8 8 0 01-8 8H34l-12 10V54h-0a8 8 0 01-8-8V26z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M66 38h12a8 8 0 018 8v18a8 8 0 01-8 8h-2v9l-11-9H50a8 8 0 01-8-8" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>''',

    featureMembers: '''
<circle cx="34" cy="32" r="12" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M14 74c0-12 9-20 20-20s20 8 20 20" stroke="{ink}" stroke-width="3.4"/>
<circle cx="68" cy="38" r="10" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M60 74c0-11 4-16 8-16 7 0 14 6 14 16" stroke="{ink}" stroke-width="3.4"/>''',

    featureExpense: '''
<rect x="12" y="26" width="72" height="46" rx="10" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M12 40h72" stroke="{ink}" stroke-width="3.4"/>
<rect x="58" y="48" width="26" height="16" rx="6" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="70" cy="56" r="3.5" fill="{ink}"/>''',

    featureGrocery: '''
<path d="M16 34h64l-7 40a8 8 0 01-8 7H31a8 8 0 01-8-7l-7-40z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M33 34V26a15 15 0 0130 0v8" stroke="{ink}" stroke-width="3.4"/>
<path d="M36 50v14M48 50v14M60 50v14" stroke="{ink}" stroke-width="3.4"/>''',

    featureBudget: '''
<rect x="12" y="24" width="72" height="52" rx="10" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M12 40h72" stroke="{ink}" stroke-width="3.4"/>
<path d="M26 66V54M40 66V46M54 66V58M68 66V50" stroke="{ink}" stroke-width="3.4"/>
<circle cx="48" cy="32" r="3" fill="{ink}"/>''',

    featureCalendar: '''
<rect x="14" y="22" width="68" height="60" rx="9" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M14 40h68" stroke="{ink}" stroke-width="3.4"/>
<path d="M32 14v14M64 14v14" stroke="{ink}" stroke-width="3.4"/>
<rect x="28" y="50" width="12" height="10" rx="3" fill="{fill}"/>
<rect x="48" y="50" width="12" height="10" rx="3" fill="{fill}"/>
<rect x="28" y="66" width="12" height="8" rx="3" fill="{fill}"/>''',

    featureMedicine: '''
<rect x="18" y="26" width="60" height="56" rx="10" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<rect x="32" y="14" width="32" height="14" rx="5" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M48 42v24M36 54h24" stroke="{ink}" stroke-width="5"/>''',

    featurePrescription: '''
<rect x="20" y="12" width="56" height="72" rx="8" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M32 28h20M32 40h32" stroke="{ink}" stroke-width="3.4"/>
<path d="M32 54h14" stroke="{ink}" stroke-width="3.4"/>
<rect x="50" y="52" width="28" height="18" rx="9" fill="{fill}" stroke="{ink}" stroke-width="3.4" transform="rotate(-20 64 61)"/>
<path d="M58 55l7 12" stroke="{ink}" stroke-width="3.4" transform="rotate(-20 64 61)"/>''',

    featureReminder: '''
<circle cx="46" cy="52" r="30" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M46 34v18l12 8" stroke="{ink}" stroke-width="3.4"/>
<path d="M24 20l-8 8M68 20l8 8" stroke="{ink}" stroke-width="3.4"/>
<rect x="62" y="60" width="26" height="16" rx="8" fill="{fill}" stroke="{ink}" stroke-width="3.4" transform="rotate(-25 75 68)"/>''',

    featureCommute: '''
<rect x="14" y="20" width="68" height="48" rx="10" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<rect x="24" y="30" width="20" height="16" rx="4" fill="{paper}" stroke="{ink}" stroke-width="3"/>
<rect x="52" y="30" width="20" height="16" rx="4" fill="{paper}" stroke="{ink}" stroke-width="3"/>
<path d="M14 56h68" stroke="{ink}" stroke-width="3.4"/>
<circle cx="28" cy="74" r="7" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="68" cy="74" r="7" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>''',

    featureCommunity: '''
<path d="M12 30a8 8 0 018-8h44a8 8 0 018 8v22a8 8 0 01-8 8H36L22 72V60h-2a8 8 0 01-8-8V30z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="30" cy="41" r="4" fill="{ink}"/>
<circle cx="42" cy="41" r="4" fill="{ink}"/>
<circle cx="54" cy="41" r="4" fill="{ink}"/>
<circle cx="76" cy="66" r="10" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>''',

    featureTasks: '''
<rect x="18" y="18" width="60" height="66" rx="9" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<rect x="36" y="10" width="24" height="14" rx="5" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M30 40l5 5 9-10" stroke="{ink}" stroke-width="3.4"/>
<path d="M30 58l5 5 9-10" stroke="{ink}" stroke-width="3.4"/>
<path d="M52 41h16M52 60h16" stroke="{ink}" stroke-width="3.4"/>''',

    featurePlanner: '''
<rect x="12" y="22" width="60" height="58" rx="9" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M12 38h60" stroke="{ink}" stroke-width="3.4"/>
<path d="M28 14v14M56 14v14" stroke="{ink}" stroke-width="3.4"/>
<path d="M24 52h20M24 64h14" stroke="{ink}" stroke-width="3.4"/>
<circle cx="70" cy="64" r="18" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M70 54v10l7 4" stroke="{ink}" stroke-width="3.4"/>''',

    featureFocus: '''
<circle cx="48" cy="54" r="30" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M48 54V36" stroke="{ink}" stroke-width="3.4"/>
<path d="M48 54l14 9" stroke="{ink}" stroke-width="3.4"/>
<path d="M38 12h20" stroke="{ink}" stroke-width="3.4"/>
<path d="M48 12v12" stroke="{ink}" stroke-width="3.4"/>
<path d="M78 54a30 30 0 00-30-30" stroke="{ink}" stroke-width="5"/>''',

    featureProfile: '''
<rect x="12" y="20" width="72" height="58" rx="10" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="36" cy="42" r="10" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M22 64c0-8 6-12 14-12s14 4 14 12" stroke="{ink}" stroke-width="3.4"/>
<path d="M60 38h14M60 50h14M60 62h9" stroke="{ink}" stroke-width="3.4"/>''',

    featureHome: '''
<path d="M14 44L48 16l34 28" fill="none" stroke="{ink}" stroke-width="3.4"/>
<path d="M24 40v34a6 6 0 006 6h36a6 6 0 006-6V40" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<rect x="40" y="56" width="16" height="24" rx="4" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>''',

    // --- Transport modes -------------------------------------------------
    modeWalk: '''
<circle cx="54" cy="18" r="8" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M54 30l-9 16 9 10v22" stroke="{ink}" stroke-width="3.4"/>
<path d="M54 56l12 8 4 14" stroke="{ink}" stroke-width="3.4"/>
<path d="M45 46L30 40" stroke="{ink}" stroke-width="3.4"/>
<path d="M45 78H32" stroke="{ink}" stroke-width="3.4"/>''',

    modeBus: '''
<rect x="14" y="20" width="68" height="46" rx="9" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<rect x="24" y="29" width="21" height="15" rx="4" fill="{paper}" stroke="{ink}" stroke-width="3"/>
<rect x="51" y="29" width="21" height="15" rx="4" fill="{paper}" stroke="{ink}" stroke-width="3"/>
<path d="M14 54h68" stroke="{ink}" stroke-width="3.4"/>
<circle cx="29" cy="72" r="7" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="67" cy="72" r="7" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>''',

    modeMetro: '''
<rect x="20" y="14" width="56" height="54" rx="14" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<rect x="30" y="24" width="36" height="18" rx="5" fill="{paper}" stroke="{ink}" stroke-width="3"/>
<circle cx="34" cy="55" r="4" fill="{ink}"/>
<circle cx="62" cy="55" r="4" fill="{ink}"/>
<path d="M30 68l-8 14M66 68l8 14" stroke="{ink}" stroke-width="3.4"/>
<path d="M14 82h68" stroke="{ink}" stroke-width="3.4"/>''',

    modeRickshaw: '''
<path d="M22 60V40a18 18 0 0136 0v20" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M58 60h14l8-14" stroke="{ink}" stroke-width="3.4"/>
<path d="M18 60h58" stroke="{ink}" stroke-width="3.4"/>
<circle cx="30" cy="72" r="10" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="66" cy="72" r="8" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M76 46l6-8" stroke="{ink}" stroke-width="3.4"/>''',

    modeCng: '''
<path d="M20 62V44c0-11 8-18 18-18h18c9 0 16 6 18 15l3 21" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M32 34h22v14H30" fill="{paper}" stroke="{ink}" stroke-width="3"/>
<path d="M16 62h64" stroke="{ink}" stroke-width="3.4"/>
<circle cx="30" cy="72" r="9" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="68" cy="72" r="9" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>''',

    modeTrain: '''
<rect x="18" y="16" width="60" height="50" rx="10" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<rect x="28" y="26" width="40" height="18" rx="5" fill="{paper}" stroke="{ink}" stroke-width="3"/>
<circle cx="34" cy="55" r="4" fill="{ink}"/>
<circle cx="62" cy="55" r="4" fill="{ink}"/>
<path d="M28 66l-8 16M68 66l8 16" stroke="{ink}" stroke-width="3.4"/>
<path d="M12 74h72" stroke="{ink}" stroke-width="3.4"/>''',

    modeBoat: '''
<path d="M16 60h64l-8 14a10 10 0 01-9 5H33a10 10 0 01-9-5l-8-14z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M48 60V18" stroke="{ink}" stroke-width="3.4"/>
<path d="M48 22l22 14H48" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M26 50h44" stroke="{ink}" stroke-width="3.4"/>''',

    modeCar: '''
<path d="M18 62V50l8-16a8 8 0 017-4h30a8 8 0 017 4l8 16v12" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M28 34h40" stroke="{ink}" stroke-width="3.4"/>
<path d="M14 50h68" stroke="{ink}" stroke-width="3.4"/>
<circle cx="30" cy="66" r="8" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="66" cy="66" r="8" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>''',

    pinOrigin: '''
<circle cx="48" cy="48" r="26" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="48" cy="48" r="9" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M48 8v10M48 78v10M8 48h10M78 48h10" stroke="{ink}" stroke-width="3.4"/>''',

    pinDestination: '''
<path d="M48 12c-13 0-24 10-24 23 0 17 24 45 24 45s24-28 24-45c0-13-11-23-24-23z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="48" cy="35" r="9" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>''',

    // --- Empty / status states ------------------------------------------
    emptySubjects: '''
<rect x="10" y="34" width="42" height="50" rx="6" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<rect x="24" y="24" width="42" height="50" rx="6" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M34 40h22M34 52h22" stroke="{ink}" stroke-width="3.4"/>
<circle cx="74" cy="30" r="10" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M60 76c0-9 6-16 14-16s14 7 14 16" stroke="{ink}" stroke-width="3.4"/>''',

    emptyMaterials: '''
<path d="M12 30a7 7 0 017-7h20l8 9h25a7 7 0 017 7v37a7 7 0 01-7 7H19a7 7 0 01-7-7V30z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M12 46h72" stroke="{ink}" stroke-width="3.4"/>
<path d="M36 62h24" stroke="{ink}" stroke-width="3.4"/>''',

    emptyTasks: '''
<rect x="16" y="18" width="64" height="66" rx="9" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<rect x="36" y="10" width="24" height="14" rx="5" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<rect x="27" y="36" width="14" height="14" rx="4" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<rect x="27" y="58" width="14" height="14" rx="4" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M50 43h20M50 65h20" stroke="{ink}" stroke-width="3.4"/>''',

    emptyGroupResources: '''
<path d="M10 34a7 7 0 017-7h18l7 9h22a7 7 0 017 7v33a7 7 0 01-7 7H17a7 7 0 01-7-7V34z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="74" cy="30" r="9" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<circle cx="86" cy="54" r="7" fill="{paper}" stroke="{ink}" stroke-width="3"/>
<path d="M74 39v6M79 52l-4-4" stroke="{ink}" stroke-width="3"/>''',

    emptyExpenses: '''
<path d="M22 12h44a4 4 0 014 4v68l-9-6-9 6-9-6-9 6-9-6-8 6V16a4 4 0 014-4z" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M32 32h32M32 46h32M32 60h18" stroke="{ink}" stroke-width="3.4"/>''',

    emptyMedicines: '''
<rect x="16" y="28" width="64" height="54" rx="10" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<rect x="32" y="16" width="32" height="14" rx="5" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M48 44v22M37 55h22" stroke="{ink}" stroke-width="5"/>''',

    emptyCommute: '''
<path d="M10 26l26-10 24 10 26-10v56l-26 10-24-10-26 10V26z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M36 16v56M60 26v56" stroke="{ink}" stroke-width="3.4"/>
<path d="M56 30c-7 0-13 6-13 13 0 9 13 24 13 24s13-15 13-24c0-7-6-13-13-13z" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>''',

    emptyMessages: '''
<path d="M14 28a9 9 0 019-9h50a9 9 0 019 9v28a9 9 0 01-9 9H40L24 78V65h-1a9 9 0 01-9-9V28z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M32 36h32M32 50h20" stroke="{ink}" stroke-width="3.4"/>''',

    emptySearch: '''
<circle cx="42" cy="42" r="26" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M61 61l22 22" stroke="{ink}" stroke-width="5"/>
<path d="M32 42h20" stroke="{ink}" stroke-width="3.4"/>''',

    stateError: '''
<path d="M48 14L86 78H10L48 14z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M48 38v18" stroke="{ink}" stroke-width="4.4"/>
<circle cx="48" cy="66" r="3.4" fill="{ink}"/>''',

    stateOffline: '''
<path d="M26 68a18 18 0 010-36 24 24 0 0146-6 16 16 0 012 42H26z" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M20 20l56 56" stroke="{ink}" stroke-width="4.4"/>''',

    stateTaken: '''
<circle cx="48" cy="48" r="32" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M33 49l11 11 20-22" stroke="{ink}" stroke-width="5"/>''',

    stateSkipped: '''
<circle cx="48" cy="48" r="32" fill="{fill}" stroke="{ink}" stroke-width="3.4"/>
<path d="M33 48h30" stroke="{ink}" stroke-width="5"/>''',

    // --- Fallback --------------------------------------------------------
    generic: '''
<rect x="20" y="14" width="56" height="68" rx="8" fill="{paper}" stroke="{ink}" stroke-width="3.4"/>
<path d="M20 30h56" stroke="{ink}" stroke-width="3.4"/>
<path d="M32 46h32M32 58h32M32 70h18" stroke="{ink}" stroke-width="3.4"/>''',
  };

  /// Every registered id. Used by the widget test that asserts each drawing
  /// parses and contains no hardcoded colour outside the three slots.
  static Iterable<String> get allIds => _bodies.keys;
}
