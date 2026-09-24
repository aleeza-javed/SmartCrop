import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/crop_api_service.dart';
import '../models/sensor_data.dart';
import '../theme/app_colors.dart';

// TODO: No live rainfall sensor exists yet. The model was trained on annual
// rainfall in mm, but the ESP32 only provides RainPercent (0–100). Using a
// regional average placeholder until a mm-based rainfall source is available.
const double kDefaultRegionalRainfallMm = 100.0;

class AiCropScreen extends StatefulWidget {
  final SensorData? sensorData;
  final String crop;
  final ValueChanged<String>? onAcceptCrop;
  const AiCropScreen({
    super.key,
    this.sensorData,
    this.crop = 'wheat',
    this.onAcceptCrop,
  });

  @override
  State<AiCropScreen> createState() => _AiCropScreenState();
}

class _AiCropScreenState extends State<AiCropScreen> {
  bool _loading = false;
  List<CropPrediction> _predictedCrops = [];

  SensorData get _sensorData => widget.sensorData ?? const SensorData(
    airHumidity: 0,
    airTemp: 0,
    ec: 0,
    k: 0,
    n: 0,
    p: 0,
    rainPercent: 0,
    soilHumidity: 0,
    soilMoisturePercent: 0,
    soilTemp: 0,
    pH: 0,
  );

  Future<void> _runAnalysis() async {
    setState(() {
      _loading = true;
      _predictedCrops = [];
    });

    try {
      final crops = await CropApiService.predictCrops(
        nitrogen: _sensorData.n,
        phosphorus: _sensorData.p,
        potassium: _sensorData.k,
        temperature: _sensorData.airTemp,
        humidity: _sensorData.airHumidity,
        ph: _sensorData.pH,
        rainfall: kDefaultRegionalRainfallMm,
      );

      setState(() {
        _predictedCrops = crops;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to predict crops: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _Header(topPad: MediaQuery.of(context).padding.top),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SoilSnapshotCard(sensorData: _sensorData),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.crop[0].toUpperCase() + widget.crop.substring(1),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _sectionTitle('Top Crop Matches'),
                  const SizedBox(height: 12),

                  if (_loading)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (_predictedCrops.isEmpty)
                    _EmptyCropMatches()
                  else
                    ...List.generate(
                      _predictedCrops.length,
                      (index) => _CropMatchCard(
                        cropName: _predictedCrops[index].name,
                        matchPct: _predictedCrops[index].confidence.round(),
                        index: index,
                        onAccept: widget.onAcceptCrop != null
                            ? () => widget.onAcceptCrop!(_predictedCrops[index].name)
                            : null,
                      ),
                    ),

                  const SizedBox(height: 28),

                  if (widget.onAcceptCrop != null && _predictedCrops.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () => widget.onAcceptCrop!(_predictedCrops.first.name),
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text(
                          'Use Recommended Crop',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1B5E20),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                      ),
                    ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _runAnalysis,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                      label: Text(
                        _loading ? 'Analyzing...' : 'Run New Analysis',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: AppColors.outlineVariant, width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.model_training_rounded,
                              size: 14, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(
                            'Powered by SmartCrop ML Model',
                            style: GoogleFonts.manrope(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
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

class _EmptyCropMatches extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.eco_outlined,
              size: 48,
              color: AppColors.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              'No predictions yet',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap "Run New Analysis" to get crop recommendations',
              style: GoogleFonts.manrope(
                fontSize: 11,
                color: AppColors.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CropMatchCard extends StatelessWidget {
  final String cropName;
  final int matchPct;
  final int index;
  final VoidCallback? onAccept;
  const _CropMatchCard({
    required this.cropName,
    required this.matchPct,
    required this.index,
    this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: index == 0
            ? Border.all(
                color: AppColors.primary.withValues(alpha: 0.4), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(_iconForCrop(cropName), style: const TextStyle(fontSize: 26)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      cropName[0].toUpperCase() + cropName.substring(1),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onBackground,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (index == 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Best Match',
                          style: GoogleFonts.manrope(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _seasonForCrop(cropName),
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _MiniTag(label: 'Water: ${_waterForCrop(cropName)}'),
                    const SizedBox(width: 6),
                    _MiniTag(label: 'Profit: ${_profitForCrop(cropName)}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              Text(
                '$matchPct%',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  height: 1,
                ),
              ),
              Text(
                'match',
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  color: AppColors.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (onAccept != null)
                GestureDetector(
                  onTap: onAccept,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B5E20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Use',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: 36,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: matchPct / 100,
                    minHeight: 5,
                    backgroundColor: AppColors.surfaceContainerHigh,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _iconForCrop(String crop) {
    final icons = {
      'wheat': '🌾',
      'rice': '🌿',
      'maize': '🌽',
      'cotton': '🧶',
      'sugarcane': '🍃',
      'mango': '🥭',
      'apple': '🍎',
      'banana': '🍌',
      'coconut': '🥥',
      'coffee': '☕',
      'grapes': '🍇',
      'jute': '🌿',
      'kidneybeans': '🫘',
      'lentil': '🌿',
      'muskmelon': '🍈',
      'mustard': '🌻',
      'orange': '🍊',
      'papaya': '🍈',
      'pigeonpeas': '🫘',
      'pomegranate': '🍎',
      'sorghum': '🌾',
      'sunflower': '🌻',
      'tobacco': '🍃',
      'tomato': '🍅',
      'watermelon': '🍉',
    };
    return icons[crop.toLowerCase()] ?? '🌱';
  }

  String _seasonForCrop(String crop) {
    final seasons = {
      'wheat': 'Rabi (Oct - Mar)',
      'rice': 'Kharif (Jun - Sep)',
      'maize': 'Kharif (May - Aug)',
      'cotton': 'Kharif (Apr - Aug)',
      'sugarcane': 'Year-round',
      'mango': 'Summer (Mar - Jun)',
      'apple': 'Autumn (Aug - Nov)',
      'banana': 'Year-round',
      'coconut': 'Year-round',
      'coffee': 'Monsoon (Jun - Sep)',
      'grapes': 'Winter (Nov - Feb)',
      'jute': 'Kharif (Mar - Jul)',
      'kidneybeans': 'Kharif (Jun - Jul)',
      'lentil': 'Rabi (Nov - Feb)',
      'muskmelon': 'Summer (Feb - Apr)',
      'mustard': 'Rabi (Oct - Mar)',
      'orange': 'Winter (Nov - Feb)',
      'papaya': 'Year-round',
      'pigeonpeas': 'Kharif (Jun - Jul)',
      'pomegranate': 'Winter (Oct - Feb)',
      'sorghum': 'Kharif (Jun - Sep)',
      'sunflower': 'Rabi (Sep - Dec)',
      'tobacco': 'Rabi (Nov - Mar)',
      'tomato': 'Year-round',
      'watermelon': 'Summer (Feb - Apr)',
    };
    return seasons[crop.toLowerCase()] ?? 'Season varies';
  }

  String _waterForCrop(String crop) {
    final water = {
      'wheat': 'Low',
      'rice': 'High',
      'maize': 'Medium',
      'cotton': 'Medium',
      'sugarcane': 'High',
      'mango': 'Medium',
      'apple': 'Medium',
      'banana': 'High',
      'coconut': 'High',
      'coffee': 'High',
      'grapes': 'Low',
      'jute': 'High',
      'kidneybeans': 'Low',
      'lentil': 'Low',
      'muskmelon': 'Low',
      'mustard': 'Low',
      'orange': 'Medium',
      'papaya': 'Medium',
      'pigeonpeas': 'Low',
      'pomegranate': 'Low',
      'sorghum': 'Medium',
      'sunflower': 'Low',
      'tobacco': 'Medium',
      'tomato': 'Medium',
      'watermelon': 'High',
    };
    return water[crop.toLowerCase()] ?? 'Medium';
  }

  String _profitForCrop(String crop) {
    final profit = {
      'wheat': 'High',
      'rice': 'Medium',
      'maize': 'Medium',
      'cotton': 'High',
      'sugarcane': 'High',
      'mango': 'High',
      'apple': 'High',
      'banana': 'Medium',
      'coconut': 'High',
      'coffee': 'High',
      'grapes': 'High',
      'jute': 'Medium',
      'kidneybeans': 'Medium',
      'lentil': 'Medium',
      'muskmelon': 'Medium',
      'mustard': 'Medium',
      'orange': 'High',
      'papaya': 'Medium',
      'pigeonpeas': 'Low',
      'pomegranate': 'High',
      'sorghum': 'Low',
      'sunflower': 'Medium',
      'tobacco': 'High',
      'tomato': 'High',
      'watermelon': 'Medium',
    };
    return profit[crop.toLowerCase()] ?? 'Medium';
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  const _MiniTag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.manrope(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SoilSnapshotCard extends StatelessWidget {
  final SensorData sensorData;
  const _SoilSnapshotCard({required this.sensorData});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.grain_rounded, color: Colors.white70, size: 14),
              const SizedBox(width: 6),
              Text(
                'Current Soil Profile',
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _SoilStat(label: 'N', value: '${sensorData.n.toStringAsFixed(0)} ppm'),
              _SoilStat(label: 'P', value: '${sensorData.p.toStringAsFixed(0)} ppm'),
              _SoilStat(label: 'K', value: '${sensorData.k.toStringAsFixed(0)} ppm'),
              _SoilStat(label: 'pH', value: sensorData.pH.toStringAsFixed(1)),
              _SoilStat(label: 'Moisture', value: '${sensorData.soilHumidity.toStringAsFixed(0)}%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _SoilStat extends StatelessWidget {
  final String label;
  final String value;
  const _SoilStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 10,
            color: Colors.white60,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final double topPad;
  const _Header({required this.topPad});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(4, topPad + 8, 16, 12),
      color: Colors.white,
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 20, color: AppColors.onBackground),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Crop Prediction',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onBackground,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Based on current soil readings',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    color: AppColors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              children: [
                const Icon(Icons.circle, size: 7, color: AppColors.primary),
                const SizedBox(width: 5),
                Text(
                  'Live Data',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Text _sectionTitle(String t) => Text(
      t,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: AppColors.onBackground,
      ),
    );