import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';

class DevicePairingScreen extends StatefulWidget {
  const DevicePairingScreen({super.key});

  @override
  State<DevicePairingScreen> createState() => _DevicePairingScreenState();
}

class _DevicePairingScreenState extends State<DevicePairingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final AnimationController _blinkCtrl;

  int _currentStep = 1; // 0=Power, 1=Scan, 2=Configure
  bool _scanning = true;
  int? _connectingIndex;
  String _pairedDeviceName = '';

  static const _devices = [
    _DeviceInfo(
      name: 'SmartCrop Pro #8241',
      mac: 'SC:48:7A:82:41',
      signal: _Signal.strong,
      status: 'Ready to pair',
      isPrimary: true,
    ),
    _DeviceInfo(
      name: 'Arduino_Agri_Node',
      mac: 'A4:CF:12:89:3E',
      signal: _Signal.moderate,
      status: 'Available',
      isPrimary: false,
    ),
    _DeviceInfo(
      name: 'Unidentified Sensor',
      mac: 'E2:11:00:CC:F4',
      signal: _Signal.weak,
      status: 'Weak signal',
      isPrimary: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _blinkCtrl.dispose();
    super.dispose();
  }

  Future<void> _onConnect(int index) async {
    setState(() => _connectingIndex = index);
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    setState(() {
      _connectingIndex = null;
      _pairedDeviceName = _devices[index].name;
      _currentStep = 2;
    });
  }

  void _onRefresh() {
    setState(() => _scanning = true);
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _AppBar(topPad: topPad, onClose: () => Navigator.pop(context)),
          Expanded(
            child: _currentStep == 2
                ? _ConfigureStep(
                    deviceName: _pairedDeviceName,
                    stepIndicator: _StepIndicator(current: _currentStep),
                    onFinish: () => Navigator.pop(context),
                  )
                : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Step indicator ──
                  _StepIndicator(current: _currentStep),
                  const SizedBox(height: 24),

                  // ── Setup instructions ──
                  _SetupInstructionsCard(blinkCtrl: _blinkCtrl),
                  const SizedBox(height: 16),

                  // ── Bluetooth notice ──
                  _BluetoothNotice(),
                  const SizedBox(height: 24),

                  // ── Scanning section ──
                  Row(
                    children: [
                      Text(
                        _scanning ? 'Scanning for devices...' : 'Devices Found',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onBackground,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: _onRefresh,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: AppColors.outlineVariant),
                          ),
                          child: Row(
                            children: [
                              AnimatedBuilder(
                                animation: _pulseCtrl,
                                builder: (context, child) => Transform.rotate(
                                  angle: _scanning
                                      ? _pulseCtrl.value * 2 * 3.14159
                                      : 0,
                                  child: child,
                                ),
                                child: const Icon(Icons.refresh_rounded,
                                    size: 14, color: AppColors.primary),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Refresh',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Pulse radar ──
                  if (_scanning) ...[
                    _PulseRadar(controller: _pulseCtrl),
                    const SizedBox(height: 20),
                  ],

                  // ── Device list ──
                  ..._devices.asMap().entries.map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _DeviceTile(
                          device: e.value,
                          connecting: _connectingIndex == e.key,
                          onConnect: () => _onConnect(e.key),
                        ),
                      )),

                  const SizedBox(height: 8),

                  // ── Manual entry ──
                  Center(
                    child: GestureDetector(
                      onTap: () => _showMacEntrySheet(context),
                      child: Text(
                        'Enter MAC address manually',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Troubleshooting ──
                  _TroubleshootCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMacEntrySheet(BuildContext context) {
    final ctrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
            24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter MAC Address',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.onBackground,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Found on the label at the back of your sensor device.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: ctrl,
              style: GoogleFonts.jetBrainsMono(
                  fontSize: 15, color: AppColors.onBackground),
              decoration: InputDecoration(
                hintText: 'e.g. A4:CF:12:89:3E',
                hintStyle: GoogleFonts.jetBrainsMono(
                    fontSize: 15,
                    color: AppColors.outline.withValues(alpha: 0.5)),
                prefixIcon: const Icon(Icons.bluetooth_rounded,
                    color: AppColors.primary, size: 20),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'Connect',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── App Bar ──────────────────────────────────────────────────────────────────

class _AppBar extends StatelessWidget {
  final double topPad;
  final VoidCallback onClose;
  const _AppBar({required this.topPad, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(16, topPad + 10, 8, 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.bluetooth_rounded,
                color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SmartCrop Setup',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onBackground,
                ),
              ),
              Text(
                'Device Pairing',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            color: AppColors.onSurfaceVariant,
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

// ─── Step Indicator ───────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int current; // 0, 1, 2

  static const _steps = [
    (icon: Icons.power_settings_new_rounded, label: 'Power'),
    (icon: Icons.bluetooth_searching_rounded, label: 'Scan'),
    (icon: Icons.settings_rounded, label: 'Configure'),
  ];

  const _StepIndicator({required this.current});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
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
      child: Row(
        children: List.generate(_steps.length * 2 - 1, (i) {
          if (i.isOdd) {
            // Connector line
            final stepIndex = i ~/ 2;
            final done = stepIndex < current;
            return Expanded(
              child: Container(
                height: 2,
                decoration: BoxDecoration(
                  color: done ? AppColors.primary : AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            );
          }
          final stepIndex = i ~/ 2;
          final done = stepIndex < current;
          final active = stepIndex == current;

          return Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: done
                      ? AppColors.primary
                      : active
                          ? AppColors.primary.withValues(alpha: 0.12)
                          : AppColors.surfaceContainerLow,
                  shape: BoxShape.circle,
                  border: active
                      ? Border.all(color: AppColors.primary, width: 2)
                      : null,
                ),
                child: done
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 18)
                    : Icon(
                        _steps[stepIndex].icon,
                        size: 18,
                        color: active
                            ? AppColors.primary
                            : AppColors.onSurfaceVariant,
                      ),
              ),
              const SizedBox(height: 6),
              Text(
                _steps[stepIndex].label,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  fontWeight: active || done
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: active || done
                      ? AppColors.primary
                      : AppColors.onSurfaceVariant,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

// ─── Setup Instructions Card ──────────────────────────────────────────────────

class _SetupInstructionsCard extends StatelessWidget {
  final AnimationController blinkCtrl;
  const _SetupInstructionsCard({required this.blinkCtrl});

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
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1B5E20).withValues(alpha: 0.3),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sensors_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(
                'Connecting to Sensor',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InstructionRow(
            icon: Icons.power_outlined,
            text: 'Ensure your soil monitor is powered on.',
          ),
          const SizedBox(height: 8),
          _InstructionRow(
            icon: Icons.social_distance_rounded,
            text: 'Position within 10 meters of your device.',
          ),
          const SizedBox(height: 12),
          // LED indicator row
          Row(
            children: [
              AnimatedBuilder(
                animation: blinkCtrl,
                builder: (context, child) => Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      const Color(0xFF69F0AE),
                      const Color(0xFF00C853),
                      blinkCtrl.value,
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00C853)
                            .withValues(alpha: blinkCtrl.value * 0.7),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Look for blinking green LED on device',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InstructionRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InstructionRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Colors.white70, size: 15),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.85),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Bluetooth Notice ─────────────────────────────────────────────────────────

class _BluetoothNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth_rounded,
              color: Color(0xFF1565C0), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Bluetooth must be enabled on your smartphone to continue setup.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: const Color(0xFF1565C0),
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pulse Radar ─────────────────────────────────────────────────────────────

class _PulseRadar extends StatelessWidget {
  final AnimationController controller;
  const _PulseRadar({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 120,
        height: 120,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, child) {
            return CustomPaint(
              painter: _RadarPainter(progress: controller.value),
              child: child,
            );
          },
          child: Center(
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primary, width: 1.5),
              ),
              child: const Icon(Icons.bluetooth_rounded,
                  color: AppColors.primary, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double progress;
  const _RadarPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.width / 2;

    for (int i = 0; i < 3; i++) {
      final delay = i / 3;
      final p = ((progress - delay) % 1.0).clamp(0.0, 1.0);
      final radius = p * maxR;
      final opacity = (1 - p) * 0.35;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = AppColors.primary.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.progress != progress;
}

// ─── Device Tile ──────────────────────────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  final _DeviceInfo device;
  final bool connecting;
  final VoidCallback onConnect;

  const _DeviceTile({
    required this.device,
    required this.connecting,
    required this.onConnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: device.isPrimary
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 1.5)
            : Border.all(color: AppColors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: device.isPrimary ? 0.08 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Device icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: device.isPrimary
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              device.signal == _Signal.weak
                  ? Icons.sensors_off_rounded
                  : Icons.sensors_rounded,
              color: device.isPrimary
                  ? AppColors.primary
                  : AppColors.onSurfaceVariant,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),

          // Device info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        device.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onBackground,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                    if (device.isPrimary) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Best',
                          style: GoogleFonts.manrope(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _SignalBars(signal: device.signal),
                    const SizedBox(width: 6),
                    Flexible(
                      flex: 0,
                      fit: FlexFit.loose,
                      child: Text(
                        device.signal.label,
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: device.signal.color,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '· ${device.mac}',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: AppColors.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Action
          if (device.isPrimary)
            SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: connecting ? null : onConnect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  elevation: 0,
                ),
                child: connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        'Connect',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, fontWeight: FontWeight.w700),
                      ),
              ),
            )
          else
            Icon(Icons.chevron_right_rounded,
                color: AppColors.onSurfaceVariant, size: 22),
        ],
      ),
    );
  }
}

// ─── Signal Bars ─────────────────────────────────────────────────────────────

class _SignalBars extends StatelessWidget {
  final _Signal signal;
  const _SignalBars({required this.signal});

  @override
  Widget build(BuildContext context) {
    final filled = switch (signal) {
      _Signal.strong => 3,
      _Signal.moderate => 2,
      _Signal.weak => 1,
    };
    return Row(
      children: List.generate(3, (i) {
        final active = i < filled;
        return Container(
          width: 4,
          height: 8.0 + i * 3,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: active ? signal.color : AppColors.outlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

// ─── Troubleshoot Card ────────────────────────────────────────────────────────

class _TroubleshootCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline_rounded,
                  color: AppColors.primary, size: 16),
              const SizedBox(width: 8),
              Text(
                'Device not showing up?',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onBackground,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Hold the reset button on your sensor for 5 seconds until the LED flashes red, then release. The device will restart in pairing mode.',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppColors.onSurfaceVariant,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _FooterLink(
                icon: Icons.menu_book_outlined,
                label: 'Documentation',
              ),
              const SizedBox(width: 20),
              _FooterLink(
                icon: Icons.support_agent_rounded,
                label: 'Contact Support',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FooterLink({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 5),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

// ─── Configure Step ──────────────────────────────────────────────────────────

class _ConfigureStep extends StatefulWidget {
  final String deviceName;
  final Widget stepIndicator;
  final VoidCallback onFinish;

  const _ConfigureStep({
    required this.deviceName,
    required this.stepIndicator,
    required this.onFinish,
  });

  @override
  State<_ConfigureStep> createState() => _ConfigureStepState();
}

class _ConfigureStepState extends State<_ConfigureStep> {
  final _nameCtrl = TextEditingController();
  String _selectedField = 'Main Field';
  int _selectedRate = 1; // index into _rates
  bool _saving = false;

  static const _fields = ['Main Field', 'North Field', 'South Field', 'East Field'];
  static const _rates = ['Every 5 min', 'Every 15 min', 'Every 30 min', 'Every 1 hour'];

  @override
  void initState() {
    super.initState();
    _nameCtrl.text = widget.deviceName;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _onFinish() async {
    setState(() => _saving = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    widget.onFinish();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Step indicator (passed in so it reflects current=2)
          widget.stepIndicator,
          const SizedBox(height: 24),

          // Success banner
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF1B5E20).withValues(alpha: 0.3),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bluetooth_connected_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Device Paired!',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.deviceName,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section label
          _ConfigSectionLabel(label: 'Sensor Configuration'),
          const SizedBox(height: 14),

          // Sensor display name
          _ConfigField(
            label: 'Sensor Display Name',
            child: TextFormField(
              controller: _nameCtrl,
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: AppColors.onBackground),
              decoration: InputDecoration(
                hintText: 'e.g. North Plot Sensor',
                hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: AppColors.outline.withValues(alpha: 0.5)),
                prefixIcon: const Icon(Icons.edit_outlined,
                    color: AppColors.outline, size: 18),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Assign to field
          _ConfigField(
            label: 'Assign to Field',
            child: DropdownButtonFormField<String>(
              initialValue: _selectedField,
              onChanged: (v) => setState(() => _selectedField = v ?? _selectedField),
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  color: AppColors.outline),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14, color: AppColors.onBackground),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.location_on_outlined,
                    color: AppColors.outline, size: 18),
              ),
              items: _fields
                  .map((f) => DropdownMenuItem(
                        value: f,
                        child: Text(f,
                            style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 24),

          // Section label
          _ConfigSectionLabel(label: 'Data Settings'),
          const SizedBox(height: 14),

          // Sampling rate
          _ConfigField(
            label: 'Sampling Rate',
            child: Column(
              children: List.generate(_rates.length, (i) {
                final selected = i == _selectedRate;
                return GestureDetector(
                  onTap: () => setState(() => _selectedRate = i),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 13),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.07)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : AppColors.outlineVariant,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.timer_outlined,
                            size: 16,
                            color: selected
                                ? AppColors.primary
                                : AppColors.outline),
                        const SizedBox(width: 10),
                        Text(
                          _rates[i],
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: selected
                                ? AppColors.primary
                                : AppColors.onBackground,
                          ),
                        ),
                        const Spacer(),
                        if (selected)
                          const Icon(Icons.check_circle_rounded,
                              color: AppColors.primary, size: 18),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 28),

          // Finish button
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: _saving ? null : _onFinish,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.primary.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 4,
                shadowColor: AppColors.primary.withValues(alpha: 0.3),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.check_rounded, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Finish Setup',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 16, fontWeight: FontWeight.w700),
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

class _ConfigSectionLabel extends StatelessWidget {
  final String label;
  const _ConfigSectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.onBackground,
          ),
        ),
      ],
    );
  }
}

class _ConfigField extends StatelessWidget {
  final String label;
  final Widget child;
  const _ConfigField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

// ─── Data models ─────────────────────────────────────────────────────────────

enum _Signal {
  strong,
  moderate,
  weak;

  String get label => switch (this) {
        _Signal.strong => 'Strong Signal',
        _Signal.moderate => 'Moderate Signal',
        _Signal.weak => 'Weak Signal',
      };

  Color get color => switch (this) {
        _Signal.strong => AppColors.primary,
        _Signal.moderate => const Color(0xFFE65100),
        _Signal.weak => const Color(0xFFBA1A1A),
      };
}

class _DeviceInfo {
  final String name;
  final String mac;
  final _Signal signal;
  final String status;
  final bool isPrimary;

  const _DeviceInfo({
    required this.name,
    required this.mac,
    required this.signal,
    required this.status,
    required this.isPrimary,
  });
}
