import 'dart:convert';

import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FieldLocation {
  final double latitude;
  final double longitude;
  final String name;

  const FieldLocation({
    required this.latitude,
    required this.longitude,
    required this.name,
  });
}

class LocationSearchResult {
  final String name;
  final String? admin1;
  final String? country;
  final double latitude;
  final double longitude;

  const LocationSearchResult({
    required this.name,
    required this.admin1,
    required this.country,
    required this.latitude,
    required this.longitude,
  });

  String get displayName {
    final parts = <String>[
      name,
      if (admin1 != null && admin1!.trim().isNotEmpty) admin1!,
      if (country != null && country!.trim().isNotEmpty) country!,
    ];

    return parts.join(', ');
  }

  FieldLocation toFieldLocation() {
    return FieldLocation(
      latitude: latitude,
      longitude: longitude,
      name: displayName,
    );
  }
}

class LocationService {
  static const String _latitudeKey = 'field_latitude';
  static const String _longitudeKey = 'field_longitude';
  static const String _nameKey = 'field_location_name';

  static final Geocoding _geocoding = Geocoding();

  // ─────────────────────────────────────────────
  // SAVED LOCATION
  // ─────────────────────────────────────────────

  static Future<FieldLocation?> getSavedLocation() async {
    final prefs = await SharedPreferences.getInstance();

    final latitude = prefs.getDouble(_latitudeKey);
    final longitude = prefs.getDouble(_longitudeKey);
    final name = prefs.getString(_nameKey);

    if (latitude == null ||
        longitude == null ||
        name == null) {
      return null;
    }

    return FieldLocation(
      latitude: latitude,
      longitude: longitude,
      name: name,
    );
  }

  // ─────────────────────────────────────────────
  // SAVE LOCATION
  // ─────────────────────────────────────────────

  static Future<void> saveLocation(
    FieldLocation location,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setDouble(
      _latitudeKey,
      location.latitude,
    );

    await prefs.setDouble(
      _longitudeKey,
      location.longitude,
    );

    await prefs.setString(
      _nameKey,
      location.name,
    );
  }

  // ─────────────────────────────────────────────
  // CURRENT GPS LOCATION
  // ─────────────────────────────────────────────

  static Future<FieldLocation> getCurrentLocation() async {
    final serviceEnabled =
        await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception(
        'Location services are disabled. Please turn on GPS/location services.',
      );
    }

    LocationPermission permission =
        await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      throw Exception(
        'Location permission was denied.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is permanently denied. Please enable it from phone settings.',
      );
    }

    final position =
        await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    String locationName = 'Current Location';

    try {
      final placemarks =
          await _geocoding.placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;

        final parts = <String>[];

        if (place.locality != null &&
            place.locality!.trim().isNotEmpty) {
          parts.add(place.locality!.trim());
        }

        if (place.administrativeArea != null &&
            place.administrativeArea!.trim().isNotEmpty &&
            !parts.contains(
              place.administrativeArea!.trim(),
            )) {
          parts.add(
            place.administrativeArea!.trim(),
          );
        }

        if (parts.isNotEmpty) {
          locationName = parts.join(', ');
        }
      }
    } catch (_) {
      // GPS coordinates remain valid even if
      // reverse geocoding fails.
    }

    return FieldLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      name: locationName,
    );
  }

  // ─────────────────────────────────────────────
  // SEARCH LOCATIONS
  // ─────────────────────────────────────────────

  static Future<List<LocationSearchResult>> searchLocations(
    String query,
  ) async {
    final trimmedQuery = query.trim();

    if (trimmedQuery.isEmpty) {
      return [];
    }

    final uri = Uri.parse(
      'https://geocoding-api.open-meteo.com/v1/search',
    ).replace(
      queryParameters: {
        'name': trimmedQuery,
        'count': '8',
        'language': 'en',
        'format': 'json',
      },
    );

    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
      },
    ).timeout(
      const Duration(seconds: 15),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Unable to search for this location.',
      );
    }

    final json =
        jsonDecode(response.body) as Map<String, dynamic>;

    final results =
        json['results'] as List<dynamic>? ?? [];

    return results.map((item) {
      final data = item as Map<String, dynamic>;

      return LocationSearchResult(
        name: data['name']?.toString() ?? 'Unknown',
        admin1: data['admin1']?.toString(),
        country: data['country']?.toString(),
        latitude:
            (data['latitude'] as num?)?.toDouble() ?? 0,
        longitude:
            (data['longitude'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
  }

  // ─────────────────────────────────────────────
  // CLEAR LOCATION
  // ─────────────────────────────────────────────

  static Future<void> clearLocation() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_latitudeKey);
    await prefs.remove(_longitudeKey);
    await prefs.remove(_nameKey);
  }
}