// Place search for CommuteBD (spec §60).
//
// Two sources, clearly separated:
//
//   * **CommuteBD places** — canonical stops and landmarks from the
//     PostgreSQL/PostGIS dataset. These carry a `placeId`, which is what the
//     route endpoint needs to look up an *official* BRTA bus fare or a metro
//     fare. Choosing one of these is what unlocks the accurate fare.
//
//   * **Map results** — free-text geocoding for anywhere else in Bangladesh.
//     These give a working route but only distance-based fare estimates.
//
// The distinction is shown rather than hidden, because it changes how much a
// student should trust the fare they get back.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/design_system/app_design_system.dart';
import '../../../../core/design_system/gochano_art.dart';
import '../../../../core/localization/gochano_language.dart';
import '../../../../services/api_service.dart';
import '../../../../shared/states/gochano_states.dart';
import '../../../../shared/widgets/gochano_controls.dart';
import '../../../../shared/widgets/gochano_surfaces.dart';

/// A place a trip can start from or end at.
class CommutePlace {
  const CommutePlace({
    required this.name,
    this.placeId,
    this.lat,
    this.lon,
    this.isDatasetPlace = false,
    this.detail,
  });

  final String name;

  /// Canonical CommuteBD id. Present only for dataset places; this is what
  /// enables official BRTA/metro fare lookup.
  final String? placeId;

  final double? lat;
  final double? lon;

  /// True when this came from the CommuteBD dataset rather than the geocoder.
  final bool isDatasetPlace;

  /// Secondary line — an address, an area, a stop code.
  final String? detail;
}

/// Opens the place picker. Returns the chosen place, or null if dismissed.
Future<CommutePlace?> showCommutePlacePicker(
  BuildContext context, {
  required String title,
}) {
  return showModalBottomSheet<CommutePlace>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _PlacePicker(title: title),
  );
}

class _PlacePicker extends StatefulWidget {
  const _PlacePicker({required this.title});

  final String title;

  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  final _query = TextEditingController();
  Timer? _debounce;

  bool _searching = false;
  bool _locating = false;
  String _error = '';
  List<CommutePlace> _datasetResults = const [];
  List<CommutePlace> _mapResults = const [];
  bool _hasSearched = false;

  /// Resolves the device's current position into a usable origin.
  ///
  /// Each failure gets its own sentence, because "location unavailable" is
  /// useless: services off, permission denied and permission permanently
  /// denied each need a different action from the student (spec §76).
  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _error = '';
    });

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const _LocationFailure.servicesOff();
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        throw const _LocationFailure.deniedForever();
      }
      if (permission == LocationPermission.denied) {
        throw const _LocationFailure.denied();
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        CommutePlace(
          name: GochanoLanguage.text('Current location', 'বর্তমান লোকেশন'),
          lat: position.latitude,
          lon: position.longitude,
        ),
      );
    } on _LocationFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _error = failure.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _error = friendlyErrorMessage(
          error,
          fallback: GochanoLanguage.text(
            'Could not get your location. Try searching for a place instead.',
            'আপনার লোকেশন পাওয়া যায়নি। পরিবর্তে একটি স্থান খুঁজে দেখুন।',
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // Debounce so a four-letter place name is one request, not four
    // (spec §83 — avoid repeated API calls).
    _debounce?.cancel();
    if (value.trim().length < 2) {
      setState(() {
        _datasetResults = const [];
        _mapResults = const [];
        _hasSearched = false;
        _error = '';
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(value));
  }

  Future<void> _search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.length < 2) return;

    setState(() {
      _searching = true;
      _error = '';
    });

    try {
      // `/api/commute/search` returns both sources in one round trip: the
      // local dataset and the geocoder, with the geocoder failing softly.
      final body = await ApiService.commuteSearch(query);

      final dataset = ((body['local'] as List?) ?? const [])
          .whereType<Map>()
          .map((raw) {
            final e = raw.map((k, v) => MapEntry(k.toString(), v));
            return CommutePlace(
              name:
                  e['name']?.toString() ??
                  e['nameEn']?.toString() ??
                  e['name_en']?.toString() ??
                  '',
              placeId: e['placeId']?.toString() ?? e['place_id']?.toString(),
              lat:
                  (e['latitude'] as num?)?.toDouble() ??
                  (e['lat'] as num?)?.toDouble(),
              lon:
                  (e['longitude'] as num?)?.toDouble() ??
                  (e['lon'] as num?)?.toDouble(),
              isDatasetPlace: true,
              detail:
                  e['area']?.toString() ??
                  e['district']?.toString() ??
                  e['type']?.toString(),
            );
          })
          .where((p) => p.name.isNotEmpty)
          .toList();

      final geocoded = ((body['geocoded'] as List?) ?? const [])
          .whereType<Map>()
          .map((raw) {
            final e = raw.map((k, v) => MapEntry(k.toString(), v));
            final display = e['displayName']?.toString() ?? '';
            // Nominatim display names are long; the first segment is the
            // place, the rest is the address.
            final parts = display.split(',');
            // If the backend resolved a canonical place ID, use it so
            // direct bus matching works for geocoded results.
            final canonicalId = e['canonicalPlaceId']?.toString();
            final canonicalName = e['canonicalName']?.toString();
            return CommutePlace(
              name: canonicalName ?? parts.first.trim(),
              placeId: canonicalId,
              lat: (e['lat'] as num?)?.toDouble(),
              lon: (e['lon'] as num?)?.toDouble(),
              isDatasetPlace: canonicalId != null,
              detail: parts.length > 1
                  ? parts.skip(1).take(3).join(',').trim()
                  : null,
            );
          })
          .where((p) => p.name.isNotEmpty && p.lat != null && p.lon != null)
          .toList();

      if (!mounted) return;
      setState(() {
        _searching = false;
        _hasSearched = true;
        _datasetResults = dataset;
        _mapResults = geocoded;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _hasSearched = true;
        _error = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isOrigin = widget.title.toLowerCase().contains('from') ||
        widget.title.contains('থেকে');

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.82,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(
              color: colors.border,
              width: GochanoBorders.hairline,
            ),
          ),
          child: Column(
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(
                    top: GochanoSpacing.xs,
                    bottom: GochanoSpacing.xs,
                  ),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header: Contextual icon, title, subtitle, and close button
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  GochanoSpacing.md,
                  GochanoSpacing.xs,
                  GochanoSpacing.xs,
                  GochanoSpacing.xs,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: isOrigin
                            ? colors.commute.withValues(alpha: 0.12)
                            : colors.info.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isOrigin
                            ? Icons.trip_origin_rounded
                            : Icons.location_on_rounded,
                        size: 20,
                        color: isOrigin ? colors.commute : colors.info,
                      ),
                    ),
                    const SizedBox(width: GochanoSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            style: context.type.sectionHeading,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isOrigin
                                ? GochanoLanguage.text(
                                    'Choose starting location',
                                    'শুরুর স্থান নির্বাচন করুন',
                                  )
                                : GochanoLanguage.text(
                                    'Choose destination place',
                                    'গন্তব্যের স্থান নির্বাচন করুন',
                                  ),
                            style: context.type.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        size: 22,
                        color: colors.textSecondary,
                      ),
                      tooltip: GochanoLanguage.text('Close', 'বন্ধ করুন'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Search input and Current location action
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  GochanoSpacing.md,
                  GochanoSpacing.xs,
                  GochanoSpacing.md,
                  GochanoSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _query,
                      builder: (context, value, _) {
                        return SearchField(
                          controller: _query,
                          autofocus: true,
                          hint: GochanoLanguage.text(
                            'Search a place, stop or station',
                            'স্থান, স্টপ বা স্টেশন খুঁজুন',
                          ),
                          onChanged: _onChanged,
                          onSubmitted: _search,
                          trailing: value.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 20,
                                  ),
                                  tooltip: GochanoLanguage.text(
                                    'Clear search',
                                    'অনুসন্ধান মুছুন',
                                  ),
                                  onPressed: () {
                                    _query.clear();
                                    _onChanged('');
                                  },
                                )
                              : null,
                        );
                      },
                    ),
                    const SizedBox(height: GochanoSpacing.xs),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        onTap: _locating ? null : _useCurrentLocation,
                        borderRadius: GochanoRadius.mdAll,
                        child: AnimatedContainer(
                          duration: AppMotion.duration(
                            context,
                            AppMotion.selectionTransition,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: GochanoSpacing.sm,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: colors.commute.withValues(alpha: 0.08),
                            borderRadius: GochanoRadius.mdAll,
                            border: Border.all(
                              color: colors.commute.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_locating) ...[
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colors.commute,
                                  ),
                                ),
                                const SizedBox(width: GochanoSpacing.xs),
                              ] else ...[
                                Icon(
                                  Icons.my_location_rounded,
                                  size: 16,
                                  color: colors.commute,
                                ),
                                const SizedBox(width: GochanoSpacing.xs),
                              ],
                              Flexible(
                                child: Text(
                                  _locating
                                      ? GochanoLanguage.text(
                                          'Finding you…',
                                          'আপনাকে খোঁজা হচ্ছে…',
                                        )
                                      : GochanoLanguage.text(
                                          'Use my current location',
                                          'আমার বর্তমান লোকেশন',
                                        ),
                                  style: context.type.bodySecondary.copyWith(
                                    color: colors.commute,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Results Area
              Expanded(
                child: _buildResults(context, scrollController, colors),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(
    BuildContext context,
    ScrollController controller,
    GochanoColors colors,
  ) {
    if (_searching) {
      return StaticLoadingState(
        message: GochanoLanguage.text('Searching…', 'খোঁজা হচ্ছে…'),
      );
    }
    if (_error.isNotEmpty) {
      return ErrorState(
        compact: true,
        message: _error,
        onRetry: () => _search(_query.text),
      );
    }
    if (!_hasSearched) {
      return EmptyState(
        compact: true,
        illustration: GochanoArt.emptySearch,
        title: GochanoLanguage.text('Search for a place', 'একটি স্থান খুঁজুন'),
        message: GochanoLanguage.text(
          'Type at least two letters.',
          'অন্তত দুটি অক্ষর লিখুন।',
        ),
      );
    }
    if (_datasetResults.isEmpty && _mapResults.isEmpty) {
      return EmptyState(
        compact: true,
        illustration: GochanoArt.emptySearch,
        title: GochanoLanguage.text('Nothing found', 'কিছু পাওয়া যায়নি'),
        message: GochanoLanguage.text(
          'Try a different spelling, or a nearby landmark.',
          'অন্য বানান বা কাছের কোনো পরিচিত জায়গা লিখে দেখুন।',
        ),
      );
    }

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(
        GochanoSpacing.md,
        0,
        GochanoSpacing.md,
        GochanoSpacing.xl,
      ),
      children: [
        if (_datasetResults.isNotEmpty) ...[
          SectionHeader(
            title: GochanoLanguage.text('CommuteBD places', 'কমিউটবিডি স্থান'),
            subtitle: GochanoLanguage.text(
              'Official bus and metro fares are available for these.',
              'এগুলোর জন্য সরকারি বাস ও মেট্রো ভাড়া পাওয়া যায়।',
            ),
            padding: const EdgeInsets.only(bottom: GochanoSpacing.xs),
          ),
          CardGroup(
            children: [
              for (final place in _datasetResults)
                _PlaceRow(
                  place: place,
                  onTap: () => Navigator.of(context).pop(place),
                ),
            ],
          ),
        ],
        if (_mapResults.isNotEmpty) ...[
          SectionHeader(
            title: GochanoLanguage.text('Map results', 'মানচিত্রের ফলাফল'),
            subtitle: GochanoLanguage.text(
              'Routes work, but fares are distance estimates.',
              'রুট কাজ করবে, তবে ভাড়া হবে দূরত্বভিত্তিক আনুমানিক।',
            ),
          ),
          CardGroup(
            children: [
              for (final place in _mapResults)
                _PlaceRow(
                  place: place,
                  onTap: () => Navigator.of(context).pop(place),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({required this.place, required this.onTap});

  final CommutePlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GochanoListRow(
      illustration: place.isDatasetPlace
          ? GochanoArt.modeBus
          : GochanoArt.pinDestination,
      accent: place.isDatasetPlace
          ? context.colors.commute
          : context.colors.info,
      title: place.name,
      subtitle: place.detail,
      badge: place.isDatasetPlace
          ? GochanoBadge(
              label: GochanoLanguage.text('Official stop', 'অফিশিয়াল স্টপ'),
              tone: GochanoBadgeTone.brand,
            )
          : null,
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 20,
        color: context.colors.textTertiary,
      ),
      onTap: onTap,
    );
  }
}

/// A location failure that already carries a sentence for the student.
class _LocationFailure implements Exception {
  const _LocationFailure.servicesOff() : _kind = 'servicesOff';
  const _LocationFailure.denied() : _kind = 'denied';
  const _LocationFailure.deniedForever() : _kind = 'deniedForever';

  final String _kind;

  String get message => switch (_kind) {
    'servicesOff' => GochanoLanguage.text(
      'Location is turned off on this phone. Turn it on and try again.',
      'এই ফোনে লোকেশন বন্ধ আছে। চালু করে আবার চেষ্টা করুন।',
    ),
    'deniedForever' => GochanoLanguage.text(
      'Location permission is blocked. Allow it for Gochano in Android '
          'settings, or search for a place instead.',
      'লোকেশন অনুমতি ব্লক করা আছে। Android সেটিংসে গোছানোর জন্য অনুমতি দিন, অথবা একটি স্থান খুঁজুন।',
    ),
    _ => GochanoLanguage.text(
      'Location permission was not given. You can still search for a '
          'place.',
      'লোকেশন অনুমতি দেওয়া হয়নি। আপনি চাইলে স্থান খুঁজে নিতে পারেন।',
    ),
  };
}
