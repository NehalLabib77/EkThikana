// Exam Rescue Setup Sheet — Phase T3
// Interactive setup modal allowing students to configure an exam rescue plan.

import 'package:flutter/material.dart';

import '../../../../core/design_system/gochano_colors.dart';
import '../../../../core/design_system/gochano_spacing.dart';
import '../../../../core/design_system/gochano_typography.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/widgets/ai_widgets.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../ai/material_picker_sheet.dart';
import 'exam_rescue_models.dart';
import 'exam_rescue_preview_screen.dart';

typedef MaterialPickerFn = Future<List<Map<String, String>>?> Function(BuildContext context);

Future<void> showExamRescueSetupSheet(
  BuildContext context, {
  String? initialTitle,
  DateTime? initialDate,
  int initialDailyMinutes = 120,
  List<Map<String, String>> initialMaterials = const [],
  String? initialExtraTopics,
  ExamRescuePlanGenerator? planGenerator,
  MaterialPickerFn? materialPicker,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => ExamRescueSetupSheet(
      initialTitle: initialTitle,
      initialDate: initialDate,
      initialDailyMinutes: initialDailyMinutes,
      initialMaterials: initialMaterials,
      initialExtraTopics: initialExtraTopics,
      planGenerator: planGenerator,
      materialPicker: materialPicker,
    ),
  );
}

class ExamRescueSetupSheet extends StatefulWidget {
  final String? initialTitle;
  final DateTime? initialDate;
  final int initialDailyMinutes;
  final List<Map<String, String>> initialMaterials;
  final String? initialExtraTopics;
  final ExamRescuePlanGenerator? planGenerator;
  final MaterialPickerFn? materialPicker;

  const ExamRescueSetupSheet({
    super.key,
    this.initialTitle,
    this.initialDate,
    this.initialDailyMinutes = 120,
    this.initialMaterials = const [],
    this.initialExtraTopics,
    this.planGenerator,
    this.materialPicker,
  });

  @override
  State<ExamRescueSetupSheet> createState() => _ExamRescueSetupSheetState();
}

class _ExamRescueSetupSheetState extends State<ExamRescueSetupSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _extraTopicsCtrl;
  String? _titleError;

  late DateTime _examDate;
  int _datePresetIndex = 1; // 0: Today, 1: Tomorrow, 2: 3 Days, 3: 5 Days, 4: Custom

  late int _dailyMinutes;
  int _timePresetIndex = 1; // 0: 1h, 1: 2h, 2: 3h, 3: 4h, 4: Custom

  late List<Map<String, String>> _materials;
  bool _isGenerating = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.initialTitle ?? '');
    _extraTopicsCtrl = TextEditingController(text: widget.initialExtraTopics ?? '');

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (widget.initialDate != null) {
      _examDate = DateTime(
        widget.initialDate!.year,
        widget.initialDate!.month,
        widget.initialDate!.day,
      );
      final diff = _examDate.difference(today).inDays;
      if (diff == 0) {
        _datePresetIndex = 0;
      } else if (diff == 1) {
        _datePresetIndex = 1;
      } else if (diff == 3) {
        _datePresetIndex = 2;
      } else if (diff == 5) {
        _datePresetIndex = 3;
      } else {
        _datePresetIndex = 4;
      }
    } else {
      _examDate = today.add(const Duration(days: 1));
      _datePresetIndex = 1;
    }

    _dailyMinutes = widget.initialDailyMinutes;
    if (_dailyMinutes == 60) {
      _timePresetIndex = 0;
    } else if (_dailyMinutes == 120) {
      _timePresetIndex = 1;
    } else if (_dailyMinutes == 180) {
      _timePresetIndex = 2;
    } else if (_dailyMinutes == 240) {
      _timePresetIndex = 3;
    } else {
      _timePresetIndex = 4;
    }

    _materials = List<Map<String, String>>.from(widget.initialMaterials);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _extraTopicsCtrl.dispose();
    super.dispose();
  }

  String? _validateTitle(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return GochanoLanguage.text(
        'Please enter an exam or subject title.',
        'দয়া করে পরীক্ষা বা বিষয়ের নাম লিখুন।',
      );
    }
    if (trimmed.length < 2) {
      return GochanoLanguage.text(
        'Exam title must be at least 2 characters.',
        'পরীক্ষার নাম কমপক্ষে ২ অক্ষরের হতে হবে।',
      );
    }
    if (trimmed.length > 150) {
      return GochanoLanguage.text(
        'Exam title cannot exceed 150 characters.',
        'পরীক্ষার নাম ১৫০ অক্ষরের বেশি হতে পারবে না।',
      );
    }
    return null;
  }

  void _setDatePreset(int index) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _datePresetIndex = index;
      switch (index) {
        case 0:
          _examDate = today;
          break;
        case 1:
          _examDate = today.add(const Duration(days: 1));
          break;
        case 2:
          _examDate = today.add(const Duration(days: 3));
          break;
        case 3:
          _examDate = today.add(const Duration(days: 5));
          break;
      }
    });
  }

  Future<void> _pickCustomDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _examDate.isBefore(today) ? today : _examDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 14)),
    );
    if (picked != null) {
      setState(() {
        _examDate = DateTime(picked.year, picked.month, picked.day);
        final diff = _examDate.difference(today).inDays;
        if (diff == 0) {
          _datePresetIndex = 0;
        } else if (diff == 1) {
          _datePresetIndex = 1;
        } else if (diff == 3) {
          _datePresetIndex = 2;
        } else if (diff == 5) {
          _datePresetIndex = 3;
        } else {
          _datePresetIndex = 4;
        }
      });
    }
  }

  void _setTimePreset(int index) {
    setState(() {
      _timePresetIndex = index;
      switch (index) {
        case 0:
          _dailyMinutes = 60;
          break;
        case 1:
          _dailyMinutes = 120;
          break;
        case 2:
          _dailyMinutes = 180;
          break;
        case 3:
          _dailyMinutes = 240;
          break;
      }
    });
  }

  Future<void> _pickCustomTime() async {
    int tempMinutes = _dailyMinutes;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Text(
            GochanoLanguage.text('Custom Daily Study Time', 'কাস্টম দৈনিক পড়ার সময়'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${tempMinutes ~/ 60}h ${tempMinutes % 60}m',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: GochanoSpacing.md),
              Slider(
                value: tempMinutes.toDouble(),
                min: 30,
                max: 720,
                divisions: (720 - 30) ~/ 15,
                label: '${tempMinutes ~/ 60}h ${tempMinutes % 60}m',
                onChanged: (val) => setDlgState(() => tempMinutes = val.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(GochanoLanguage.text('Cancel', 'বাতিল')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(tempMinutes),
              child: Text(GochanoLanguage.text('Set', 'নির্ধারণ করুন')),
            ),
          ],
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _dailyMinutes = picked;
        if (_dailyMinutes == 60) {
          _timePresetIndex = 0;
        } else if (_dailyMinutes == 120) {
          _timePresetIndex = 1;
        } else if (_dailyMinutes == 180) {
          _timePresetIndex = 2;
        } else if (_dailyMinutes == 240) {
          _timePresetIndex = 3;
        } else {
          _timePresetIndex = 4;
        }
      });
    }
  }

  String _getRemainingDaysText() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = _examDate.difference(today).inDays;

    if (GochanoLanguage.current.value == GochanoLocale.bangla) {
      if (days <= 0) return 'পরীক্ষা আজকেই (১ দিনের ইমার্জেন্সি রিভিশন)';
      if (days == 1) return '১ দিন বাকি (আগামীকাল)';
      return '${GochanoLanguage.formatNumber(days)} দিন বাকি';
    }

    if (days <= 0) return 'Exam is today (1-day emergency cram)';
    if (days == 1) return '1 day remaining (Tomorrow)';
    return '$days days remaining';
  }

  Future<void> _pickMaterials() async {
    final picker = widget.materialPicker ?? showMaterialPicker;
    final picked = await picker(context);
    if (!mounted || picked == null || picked.isEmpty) return;

    setState(() {
      for (final item in picked) {
        if (_materials.length >= 3) break;
        final id = item['id'] ?? '';
        if (id.isNotEmpty && !_materials.any((m) => m['id'] == id)) {
          _materials.add(item);
        }
      }
    });
  }

  Future<void> _generatePlan() async {
    if (_isGenerating) return;

    final valErr = _validateTitle(_titleCtrl.text);
    if (valErr != null) {
      setState(() => _titleError = valErr);
      return;
    }
    setState(() => _titleError = null);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_examDate.isBefore(today)) {
      setState(() => _errorMessage = GochanoLanguage.text(
        'Exam date cannot be in the past.',
        'পরীক্ষার তারিখ অতীত হতে পারে না।',
      ));
      return;
    }
    if (_examDate.difference(today).inDays > 14) {
      setState(() => _errorMessage = GochanoLanguage.text(
        'Exam date cannot be more than 14 days away.',
        'পরীক্ষার তারিখ ১৪ দিনের বেশি দূরে হতে পারে না।',
      ));
      return;
    }

    if (_materials.isEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            GochanoLanguage.text('No Materials Selected', 'কোনো মেটেরিয়াল নির্বাচন করা হয়নি'),
          ),
          content: Text(
            GochanoLanguage.text(
              'No materials selected. Gochano will create a general subject-based rescue plan.',
              'কোনো মেটেরিয়াল নির্বাচন করা হয়নি। গচানো সাধারণ বিষয়-ভিত্তিক রেসকিউ প্ল্যান তৈরি করবে।',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                GochanoLanguage.text('Select Materials', 'মেটেরিয়াল বেছে নিন'),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                GochanoLanguage.text('Continue', 'চালিয়ে যান'),
              ),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    }

    if (!mounted || _isGenerating) return;

    setState(() {
      _isGenerating = true;
      _errorMessage = null;
    });

    try {
      final title = _titleCtrl.text.trim();
      final extraTopics = _extraTopicsCtrl.text.trim();
      final generator = widget.planGenerator ?? ApiService.generateExamRescuePlan;
      final plan = await generator(
        examTitle: title,
        examDate: _examDate,
        dailyMinutes: _dailyMinutes,
        materialIds: _materials
            .map((m) => m['id'] ?? '')
            .where((id) => id.isNotEmpty)
            .toList(),
        extraTopics: extraTopics.isNotEmpty ? extraTopics : null,
      );

      if (!mounted) return;
      setState(() => _isGenerating = false);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ExamRescuePreviewScreen(
            plan: plan,
            initialTitle: title,
            initialDate: _examDate,
            initialDailyMinutes: _dailyMinutes,
            initialMaterials: List.from(_materials),
            initialExtraTopics: extraTopics.isNotEmpty ? extraTopics : null,
            planGenerator: widget.planGenerator,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        if (e.statusCode == 429) {
          _errorMessage = GochanoLanguage.text(
            'Daily AI plan generation limit reached. Please try again tomorrow or upgrade your plan.',
            'আজকের এআই প্ল্যান তৈরির সীমা শেষ। আগামীকাল চেষ্টা করুন।',
          );
        } else if (e.statusCode == 401) {
          _errorMessage = GochanoLanguage.text(
            'Please sign in again to generate your rescue plan.',
            'রেসকিউ প্ল্যান তৈরি করতে পুনরায় সাইন ইন করুন।',
          );
        } else {
          _errorMessage = e.message.isNotEmpty
              ? e.message
              : GochanoLanguage.text(
                  'Failed to generate plan. Please try again.',
                  'প্ল্যান তৈরি করতে ব্যর্থ হয়েছে। আবার চেষ্টা করুন।',
                );
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _errorMessage = GochanoLanguage.text(
          'An unexpected error occurred. Please check your network and try again.',
          'একটি অপ্রত্যাশিত ত্রুটি ঘটেছে। নেটওয়ার্ক চেক করে আবার চেষ্টা করুন।',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: GochanoRadius.sheet,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height > 600
            ? 560
            : MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: GochanoSpacing.sm),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: GochanoSpacing.md,
                vertical: GochanoSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & Subtitle
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(GochanoSpacing.xs),
                        decoration: BoxDecoration(
                          color: colors.brandSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.bolt_rounded,
                          color: colors.brand,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: GochanoSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              GochanoLanguage.text('Exam Rescue', 'এক্সাম রেসকিউ'),
                              style: type.pageTitle.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              GochanoLanguage.text(
                                'Build a focused plan before your exam.',
                                'পরীক্ষার আগে একটি গোছানো ও বাস্তবসম্মত রিভিশন প্ল্যান তৈরি করুন।',
                              ),
                              style: type.bodySecondary.copyWith(color: colors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.md),

                  // Exam / Subject Field
                  Text(
                    GochanoLanguage.text('Exam / Subject', 'বিষয় / পরীক্ষার নাম'),
                    style: type.sectionHeading,
                  ),
                  const SizedBox(height: GochanoSpacing.xs),
                  TextField(
                    controller: _titleCtrl,
                    onChanged: (val) {
                      if (_titleError != null) {
                        setState(() => _titleError = _validateTitle(val));
                      }
                    },
                    decoration: InputDecoration(
                      hintText: GochanoLanguage.text(
                        'e.g. Optical Fiber Communication, Database Systems',
                        'যেমন: অপটিক্যাল ফাইবার, ডাটাবেজ সিস্টেম',
                      ),
                      errorText: _titleError,
                      border: OutlineInputBorder(
                        borderRadius: GochanoRadius.mdAll,
                        borderSide: BorderSide(color: colors.border),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: GochanoSpacing.md,
                        vertical: GochanoSpacing.sm,
                      ),
                    ),
                  ),
                  const SizedBox(height: GochanoSpacing.md),

                  // Exam Date Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        GochanoLanguage.text('Exam Date', 'পরীক্ষার তারিখ'),
                        style: type.sectionHeading,
                      ),
                      const SizedBox(width: GochanoSpacing.xs),
                      Flexible(
                        child: Text(
                          _getRemainingDaysText(),
                          style: type.caption.copyWith(
                            color: colors.brand,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.xs),
                  Wrap(
                    spacing: GochanoSpacing.xs,
                    runSpacing: GochanoSpacing.xs,
                    children: [
                      ChoiceChip(
                        label: Text(GochanoLanguage.text('Today', 'আজকে')),
                        selected: _datePresetIndex == 0,
                        onSelected: (_) => _setDatePreset(0),
                      ),
                      ChoiceChip(
                        label: Text(GochanoLanguage.text('Tomorrow', 'আগামীকাল')),
                        selected: _datePresetIndex == 1,
                        onSelected: (_) => _setDatePreset(1),
                      ),
                      ChoiceChip(
                        label: Text(GochanoLanguage.text('3 Days', '৩ দিন')),
                        selected: _datePresetIndex == 2,
                        onSelected: (_) => _setDatePreset(2),
                      ),
                      ChoiceChip(
                        label: Text(GochanoLanguage.text('5 Days', '৫ দিন')),
                        selected: _datePresetIndex == 3,
                        onSelected: (_) => _setDatePreset(3),
                      ),
                      ChoiceChip(
                        label: Text(GochanoLanguage.text('Custom', 'কাস্টম')),
                        selected: _datePresetIndex == 4,
                        onSelected: (_) => _pickCustomDate(),
                      ),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.md),

                  // Daily Study Time Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        GochanoLanguage.text('Daily Study Time', 'দৈনিক পড়ার সময়'),
                        style: type.sectionHeading,
                      ),
                      const SizedBox(width: GochanoSpacing.xs),
                      Flexible(
                        child: Text(
                          '${_dailyMinutes ~/ 60}h ${_dailyMinutes % 60}m',
                          style: type.caption.copyWith(
                            color: colors.brand,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.xs),
                  Wrap(
                    spacing: GochanoSpacing.xs,
                    runSpacing: GochanoSpacing.xs,
                    children: [
                      ChoiceChip(
                        label: Text(GochanoLanguage.text('1 hour', '১ ঘণ্টা')),
                        selected: _timePresetIndex == 0,
                        onSelected: (_) => _setTimePreset(0),
                      ),
                      ChoiceChip(
                        label: Text(GochanoLanguage.text('2 hours', '২ ঘণ্টা')),
                        selected: _timePresetIndex == 1,
                        onSelected: (_) => _setTimePreset(1),
                      ),
                      ChoiceChip(
                        label: Text(GochanoLanguage.text('3 hours', '৩ ঘণ্টা')),
                        selected: _timePresetIndex == 2,
                        onSelected: (_) => _setTimePreset(2),
                      ),
                      ChoiceChip(
                        label: Text(GochanoLanguage.text('4 hours', '৪ ঘণ্টা')),
                        selected: _timePresetIndex == 3,
                        onSelected: (_) => _setTimePreset(3),
                      ),
                      ChoiceChip(
                        label: Text(GochanoLanguage.text('Custom', 'কাস্টম')),
                        selected: _timePresetIndex == 4,
                        onSelected: (_) => _pickCustomTime(),
                      ),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.md),

                  // Study Materials Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        GochanoLanguage.text('Study Materials', 'স্টাডি মেটেরিয়ালস'),
                        style: type.sectionHeading,
                      ),
                      const SizedBox(width: GochanoSpacing.xs),
                      Flexible(
                        child: Text(
                          GochanoLanguage.text(
                            '${_materials.length} of 3 selected',
                            '${GochanoLanguage.formatNumber(_materials.length)} / ৩টি নির্বাচিত',
                          ),
                          style: type.caption.copyWith(color: colors.textSecondary),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: GochanoSpacing.xs),
                  if (_materials.isNotEmpty) ...[
                    ..._materials.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final mat = entry.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: GochanoSpacing.xs),
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.sm,
                          vertical: GochanoSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceVariant,
                          borderRadius: GochanoRadius.mdAll,
                          border: Border.all(color: colors.border),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.description_outlined,
                              size: 18,
                              color: colors.brand,
                            ),
                            const SizedBox(width: GochanoSpacing.xs),
                            Expanded(
                              child: Text(
                                mat['title'] ?? 'Material',
                                style: type.bodySecondary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              tooltip: 'Remove material',
                              onPressed: () {
                                setState(() {
                                  _materials.removeAt(idx);
                                });
                              },
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: GochanoSpacing.xs),
                  ],
                  if (_materials.length < 3)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text(
                        GochanoLanguage.text('+ Select Materials', '+ মেটেরিয়াল যোগ করুন'),
                      ),
                      onPressed: _pickMaterials,
                      style: OutlinedButton.styleFrom(
                        shape: const RoundedRectangleBorder(
                          borderRadius: GochanoRadius.mdAll,
                        ),
                      ),
                    ),
                  const SizedBox(height: GochanoSpacing.md),

                  // Extra Focus Topics Field (Optional)
                  Text(
                    GochanoLanguage.text(
                      'Extra Focus Topics (Optional)',
                      'অতিরিক্ত গুরুত্বপূর্ণ টপিক (ঐচ্ছিক)',
                    ),
                    style: type.sectionHeading,
                  ),
                  const SizedBox(height: GochanoSpacing.xs),
                  TextField(
                    controller: _extraTopicsCtrl,
                    maxLines: 2,
                    maxLength: 1000,
                    decoration: InputDecoration(
                      hintText: GochanoLanguage.text(
                        'e.g. Focus specifically on chapter 4 formulas and numerical problems',
                        'যেমন: অধ্যায় ৪-এর সূত্র ও গাণিতিক সমস্যার ওপর জোর দিন',
                      ),
                      border: OutlineInputBorder(
                        borderRadius: GochanoRadius.mdAll,
                        borderSide: BorderSide(color: colors.border),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: GochanoSpacing.md,
                        vertical: GochanoSpacing.sm,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Pinned Action Area at bottom
          Container(
            padding: const EdgeInsets.all(GochanoSpacing.md),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_errorMessage != null) ...[
                    AiErrorBanner(message: _errorMessage!),
                    const SizedBox(height: GochanoSpacing.sm),
                  ],
                  PrimaryButton(
                    label: GochanoLanguage.text(
                      'Generate Rescue Plan',
                      'রেসকিউ প্ল্যান তৈরি করুন',
                    ),
                    busy: _isGenerating,
                    busyLabel: GochanoLanguage.text(
                      'Generating Rescue Plan…',
                      'প্ল্যান তৈরি হচ্ছে…',
                    ),
                    onPressed: _isGenerating ? null : _generatePlan,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
