import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/location_service.dart';
import '../theme/app_colors.dart';

class FieldLocationScreen extends StatefulWidget {
  const FieldLocationScreen({super.key});

  @override
  State<FieldLocationScreen> createState() =>
      _FieldLocationScreenState();
}

class _FieldLocationScreenState
    extends State<FieldLocationScreen> {
  FieldLocation? _location;

  bool _loading = true;
  bool _gettingLocation = false;
  bool _searching = false;

  final TextEditingController _searchController =
      TextEditingController();

  List<LocationSearchResult> _searchResults = [];

  @override
  void initState() {
    super.initState();
    _loadLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    final location =
        await LocationService.getSavedLocation();

    if (!mounted) return;

    setState(() {
      _location = location;
      _loading = false;
    });
  }

  // ─────────────────────────────────────────────
  // CURRENT LOCATION
  // ─────────────────────────────────────────────

  Future<void> _useCurrentLocation() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _gettingLocation = true;
      _searchResults = [];
    });

    try {
      final location =
          await LocationService.getCurrentLocation();

      await LocationService.saveLocation(location);

      if (!mounted) return;

      setState(() {
        _location = location;
        _gettingLocation = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Field location updated to ${location.name}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _gettingLocation = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
          ),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────
  // SEARCH
  // ─────────────────────────────────────────────

  Future<void> _searchLocation() async {
    final query = _searchController.text.trim();

    if (query.isEmpty) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _searching = true;
      _searchResults = [];
    });

    try {
      final results =
          await LocationService.searchLocations(query);

      if (!mounted) return;

      setState(() {
        _searchResults = results;
        _searching = false;
      });

      if (results.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No locations found. Try another city or area.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _searching = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst(
              'Exception: ',
              '',
            ),
          ),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────
  // SELECT SEARCH RESULT
  // ─────────────────────────────────────────────

  Future<void> _selectLocation(
    LocationSearchResult result,
  ) async {
    final location = result.toFieldLocation();

    await LocationService.saveLocation(location);

    if (!mounted) return;

    setState(() {
      _location = location;
      _searchResults = [];
      _searchController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Field location set to ${location.name}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Field Location',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Field Location',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Set the location of your field. SmartCrop will use it for weather forecasts and irrigation recommendations.',
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ─────────────────────────────
                  // CURRENT SAVED LOCATION
                  // ─────────────────────────────

                  if (_location != null)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius:
                            BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.location_on_rounded,
                            color: Colors.white,
                            size: 30,
                          ),

                          const SizedBox(height: 12),

                          Text(
                            _location!.name,
                            style:
                                GoogleFonts.plusJakartaSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),

                          const SizedBox(height: 8),

                          Text(
                            'Latitude: ${_location!.latitude.toStringAsFixed(6)}',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),

                          Text(
                            'Longitude: ${_location!.longitude.toStringAsFixed(6)}',
                            style: GoogleFonts.manrope(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius:
                            BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.location_off_rounded,
                            size: 40,
                          ),

                          const SizedBox(height: 10),

                          Text(
                            'No field location saved',
                            style:
                                GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 24),

                  // ─────────────────────────────
                  // GPS BUTTON
                  // ─────────────────────────────

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _gettingLocation
                          ? null
                          : _useCurrentLocation,
                      icon: _gettingLocation
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.my_location_rounded,
                            ),
                      label: Text(
                        _gettingLocation
                            ? 'Getting Location...'
                            : 'Use My Current Location',
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ─────────────────────────────
                  // OR
                  // ─────────────────────────────

                  Row(
                    children: [
                      const Expanded(
                        child: Divider(),
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 12,
                        ),
                        child: Text(
                          'OR',
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color:
                                AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const Expanded(
                        child: Divider(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ─────────────────────────────
                  // SEARCH
                  // ─────────────────────────────

                  Text(
                    'Search for a location',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),

                  const SizedBox(height: 10),

                  TextField(
                    controller: _searchController,
                    textInputAction:
                        TextInputAction.search,
                    onSubmitted: (_) =>
                        _searchLocation(),
                    decoration: InputDecoration(
                      hintText:
                          'Enter city or area name',
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                      ),
                      suffixIcon: IconButton(
                        onPressed: _searching
                            ? null
                            : _searchLocation,
                        icon: _searching
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.arrow_forward_rounded,
                              ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(14),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ─────────────────────────────
                  // SEARCH RESULTS
                  // ─────────────────────────────

                  if (_searchResults.isNotEmpty)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius:
                            BorderRadius.circular(14),
                        border: Border.all(
                          color:
                              AppColors.outlineVariant,
                        ),
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics:
                            const NeverScrollableScrollPhysics(),
                        itemCount:
                            _searchResults.length,
                        separatorBuilder: (_, _) =>
                            const Divider(height: 1),
                        itemBuilder:
                            (context, index) {
                          final result =
                              _searchResults[index];

                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(
                                Icons.location_on_rounded,
                              ),
                            ),
                            title: Text(
                              result.name,
                              style: GoogleFonts
                                  .plusJakartaSans(
                                fontSize: 14,
                                fontWeight:
                                    FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              [
                                if (result.admin1 != null)
                                  result.admin1!,
                                if (result.country != null)
                                  result.country!,
                              ].join(', '),
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                              ),
                            ),
                            trailing: const Icon(
                              Icons
                                  .arrow_forward_ios_rounded,
                              size: 14,
                            ),
                            onTap: () =>
                                _selectLocation(result),
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
    );
  }
}