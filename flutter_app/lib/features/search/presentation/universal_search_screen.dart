// Universal Search across Gochano (Phase 2B).
//
// Searches across the 7 canonical student collections:
// 1. Task
// 2. Assignment
// 3. Note
// 4. PDF
// 5. Medicine
// 6. Expense (Daily expense & Dena/Pawna)
// 7. Trip (Planned commute trips)
//
// Pure client-side ranked search over cached/streamed owner records.
// Zero remote search service, zero composite indexes, zero duplicates.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/design_system/gochano_art.dart';
import '../../../core/design_system/gochano_colors.dart';
import '../../../core/design_system/gochano_spacing.dart';
import '../../../core/design_system/gochano_typography.dart';
import '../../../core/localization/gochano_language.dart';
import '../../../shared/states/gochano_states.dart';
import '../../../shared/widgets/gochano_controls.dart';
import '../../../shared/widgets/gochano_surfaces.dart';
import '../data/universal_search_coordinator.dart';
import '../domain/universal_search_models.dart';

class UniversalSearchScreen extends StatefulWidget {
  const UniversalSearchScreen({
    super.key,
    this.initialFilter = UniversalSearchType.all,
    this.initialQuery = '',
    this.initialItems,
    this.itemsStream,
  });

  final UniversalSearchType initialFilter;
  final String initialQuery;
  final List<UniversalSearchResult>? initialItems;
  final Stream<List<UniversalSearchResult>>? itemsStream;

  @override
  State<UniversalSearchScreen> createState() => _UniversalSearchScreenState();
}

class _UniversalSearchScreenState extends State<UniversalSearchScreen> {
  late final TextEditingController _controller;
  late UniversalSearchType _activeFilter;
  String _query = '';
  Timer? _debounceTimer;

  List<UniversalSearchResult> _allCachedItems = const [];
  StreamSubscription<List<UniversalSearchResult>>? _streamSubscription;
  bool _initialLoading = true;

  @override
  void initState() {
    super.initState();
    _activeFilter = widget.initialFilter;
    _query = widget.initialQuery;
    _controller = TextEditingController(text: widget.initialQuery);

    if (widget.initialItems != null) {
      _allCachedItems = widget.initialItems!;
      _initialLoading = false;
    }

    final stream =
        widget.itemsStream ?? UniversalSearchCoordinator.streamAllItems();
    _streamSubscription = stream.listen(
      (items) {
        if (!mounted) return;
        setState(() {
          _allCachedItems = items;
          _initialLoading = false;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _initialLoading = false);
      },
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _streamSubscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String rawValue) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      setState(() {
        _query = rawValue.trim();
      });
    });
  }

  void _onClearQuery() {
    _debounceTimer?.cancel();
    _controller.clear();
    setState(() {
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;

    final results = UniversalSearchCoordinator.search(
      allItems: _allCachedItems,
      query: _query,
      activeFilter: _activeFilter,
      limit: 50,
    );

    return GochanoScaffold(
      padBody: false,
      appBar: GochanoAppBar(title: GochanoLanguage.text('Search', 'অনুসন্ধান')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Search input bar
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GochanoSpacing.md,
              GochanoSpacing.xs,
              GochanoSpacing.md,
              GochanoSpacing.xs,
            ),
            child: SearchField(
              controller: _controller,
              autofocus: true,
              hint: GochanoLanguage.text(
                'Search tasks, notes, medicines…',
                'কাজ, নোট, ওষুধ খুঁজুন…',
              ),
              onChanged: _onQueryChanged,
              trailing: _controller.text.isNotEmpty
                  ? IconActionButton(
                      icon: Icons.close_rounded,
                      label: GochanoLanguage.text('Clear', 'মুছুন'),
                      onPressed: _onClearQuery,
                    )
                  : null,
            ),
          ),

          // 2. Horizontally scrollable category filter chips
          _buildFilterChips(colors, type),

          const SizedBox(height: GochanoSpacing.xxs),

          // 3. Search Results or Empty/Loading States
          Expanded(child: _buildBody(results)),
        ],
      ),
    );
  }

  Widget _buildFilterChips(GochanoColors colors, GochanoTypography type) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: GochanoSpacing.md,
        vertical: GochanoSpacing.xxs,
      ),
      child: Row(
        children: [
          for (final filterType in UniversalSearchType.values) ...[
            _buildChip(filterType, colors, type),
            const SizedBox(width: GochanoSpacing.xs),
          ],
        ],
      ),
    );
  }

  Widget _buildChip(
    UniversalSearchType filterType,
    GochanoColors colors,
    GochanoTypography type,
  ) {
    final selected = _activeFilter == filterType;

    return FilterChip(
      materialTapTargetSize: MaterialTapTargetSize.padded,
      selected: selected,
      showCheckmark: false,
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (filterType != UniversalSearchType.all) ...[
            Icon(
              filterType.icon,
              size: 16,
              color: selected ? colors.brand : colors.textSecondary,
            ),
            const SizedBox(width: 4),
          ],
          Text(filterType.displayName),
        ],
      ),
      onSelected: (_) {
        setState(() {
          _activeFilter = filterType;
        });
      },
      selectedColor: colors.brand.withValues(alpha: 0.14),
      backgroundColor: colors.surfaceVariant,
      side: BorderSide(
        color: selected ? colors.brand : colors.border,
        width: 1,
      ),
      shape: const StadiumBorder(),
      labelStyle: type.caption.copyWith(
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        color: selected ? colors.brand : colors.textSecondary,
      ),
    );
  }

  Widget _buildBody(List<UniversalSearchResult> results) {
    if (_query.isEmpty) {
      return EmptyState(
        illustration: GochanoArt.emptySearch,
        title: GochanoLanguage.text(
          'Search your Gochano',
          'আপনার গোছানো খুঁজুন',
        ),
        message: GochanoLanguage.text(
          'Tasks, notes, PDFs, medicines, expenses and trips.',
          'কাজ, অ্যাসাইনমেন্ট, নোট, পিডিএফ, ওষুধ, খরচ ও যাত্রা।',
        ),
      );
    }

    if (_initialLoading && _allCachedItems.isEmpty) {
      return Center(
        child: StaticLoadingState(
          message: GochanoLanguage.text(
            'Searching your Gochano…',
            'আপনার গোছানো খোঁজা হচ্ছে…',
          ),
        ),
      );
    }

    if (results.isEmpty) {
      return EmptyState(
        illustration: GochanoArt.emptySearch,
        title: GochanoLanguage.text(
          'No results for "$_query"',
          '"$_query"-এর জন্য কিছু পাওয়া যায়নি',
        ),
        message: GochanoLanguage.text(
          'Try a different search term or check spelling.',
          'অন্য শব্দ দিয়ে খুঁজুন বা বানান পরীক্ষা করুন।',
        ),
      );
    }

    return ListView.builder(
      padding: GochanoSpacing.scrollBody,
      itemCount: results.length,
      itemBuilder: (context, index) {
        return _SearchResultTile(result: results[index]);
      },
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.result});

  final UniversalSearchResult result;

  Color _accentColor(GochanoColors colors, UniversalSearchType type) {
    switch (type) {
      case UniversalSearchType.all:
      case UniversalSearchType.task:
      case UniversalSearchType.assignment:
        return colors.brand;
      case UniversalSearchType.note:
      case UniversalSearchType.pdf:
        return colors.study;
      case UniversalSearchType.medicine:
        return colors.medicine;
      case UniversalSearchType.expense:
        return colors.expense;
      case UniversalSearchType.trip:
        return colors.commute;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final type = context.type;
    final accent = _accentColor(colors, result.type);

    return Padding(
      padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
      child: AppCard(
        onTap: () => result.onTap?.call(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: GochanoRadius.smAll,
              ),
              child: Icon(result.type.icon, size: 20, color: accent),
            ),
            const SizedBox(width: GochanoSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          result.title,
                          style: type.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: GochanoSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: GochanoSpacing.xs,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceVariant,
                          borderRadius: GochanoRadius.smAll,
                        ),
                        child: Text(
                          result.type.displayName,
                          style: type.caption.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (result.subtitle != null &&
                      result.subtitle!.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      result.subtitle!,
                      style: type.caption.copyWith(color: colors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
