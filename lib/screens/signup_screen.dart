import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_colors.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';

const _bgAsset     = 'assets/background image .jpeg';
const _logoAsset   = 'assets/smartcrop_new.png';
const _googleAsset = 'assets/google.jpeg';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreeToTerms = false;
  bool _loading = false;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _onSignUp() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmPasswordController.text;

    if (email.isEmpty || password.isEmpty || confirm.isEmpty) {
      _showError('Please fill in all fields.');
      return;
    }

    if (password.length < 6) {
      _showError('Password must be at least 6 characters.');
      return;
    }

    if (password != confirm) {
      _showError('Passwords do not match.');
      return;
    }

    if (!_agreeToTerms) {
      _showError('Please agree to the Terms of Service and Privacy Policy.');
      return;
    }

    setState(() => _loading = true);

    try {
      await _authService.signUp(
        email,
        password,
        displayName: _nameController.text.trim(),
      );
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Account created! Please sign in.',
              style: GoogleFonts.plusJakartaSans(fontSize: 14),
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Sign up failed. Please try again.';
      if (e.code == 'email-already-in-use') {
        msg = 'An account with this email already exists.';
      } else if (e.code == 'weak-password') {
        msg = 'Password is too weak.';
      } else if (e.code == 'invalid-email') {
        msg = 'Please enter a valid email address.';
      }
      _showError(msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _loading = true);
    try {
      await _authService.signInWithGoogle();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    } on FirebaseAuthException catch (e) {
      _showError(e.message ?? 'Google sign-in failed.');
    } catch (e) {
      if (e.toString().contains('cancelled')) return;
      _showError('$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.plusJakartaSans(fontSize: 14)),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    final heroHeight = 320.0 + topPad;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: heroHeight,
              child: _SignupHeroSection(topPad: topPad),
            ),
            Padding(
              padding: EdgeInsets.only(top: heroHeight - 60),
              child: _SignupFormCard(
                loading: _loading,
                obscurePassword: _obscurePassword,
                obscureConfirm: _obscureConfirm,
                agreeToTerms: _agreeToTerms,
                nameController: _nameController,
                emailController: _emailController,
                passwordController: _passwordController,
                confirmPasswordController: _confirmPasswordController,
                onTogglePassword: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                onToggleConfirm: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                onAgreeChanged: (v) => setState(() => _agreeToTerms = v),
                onSignUpTap: _onSignUp,
                onLoginTap: () => Navigator.pop(context),
                onGoogleTap: _handleGoogleSignIn,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Hero Section ────────────────────────────────────────────────────────────

class _SignupHeroSection extends StatelessWidget {
  final double topPad;
  const _SignupHeroSection({required this.topPad});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 320 + topPad,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred background image
          ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
            child: Image.asset(_bgAsset, fit: BoxFit.cover),
          ),
          // Green gradient overlay
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x882D7D32), Color(0x442D7D32)],
              ),
            ),
          ),
          // Content
          Padding(
            padding: EdgeInsets.only(top: topPad + 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Back button
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5), width: 3),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      _logoAsset,
                      fit: BoxFit.contain,
                      alignment: const Alignment(0.24, 0.0),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'SmartCrop',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.4,
                    shadows: [
                      Shadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Smart Farming. Better Yield. Higher Profit.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.9),
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

// ─── Form Card ───────────────────────────────────────────────────────────────

class _SignupFormCard extends StatelessWidget {
  final bool obscurePassword;
  final bool obscureConfirm;
  final bool agreeToTerms;
  final bool loading;
  final TextEditingController nameController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;
  final ValueChanged<bool> onAgreeChanged;
  final VoidCallback onSignUpTap;
  final VoidCallback onLoginTap;
  final VoidCallback? onGoogleTap;

  const _SignupFormCard({
    required this.obscurePassword,
    required this.obscureConfirm,
    required this.agreeToTerms,
    required this.loading,
    required this.nameController,
    required this.emailController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.onTogglePassword,
    required this.onToggleConfirm,
    required this.onAgreeChanged,
    required this.onSignUpTap,
    required this.onLoginTap,
    this.onGoogleTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(40),
          topRight: Radius.circular(40),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 40,
            spreadRadius: -10,
            offset: Offset(0, -10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Text(
            'Create Account',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.onBackground,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Sign up to get started with SmartCrop',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: AppColors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // Full Name
          _AuthInputField(
            label: 'Full Name',
            hint: 'Enter your full name',
            prefixIcon: Icons.person_outline_rounded,
            keyboardType: TextInputType.name,
            textCapitalization: TextCapitalization.words,
            controller: nameController,
          ),
          const SizedBox(height: 20),

          // Email / Phone
          _AuthInputField(
            label: 'Email or Phone Number',
            hint: 'Enter email or phone number',
            prefixIcon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
            controller: emailController,
          ),
          const SizedBox(height: 20),

          // Password
          _PasswordField(
            label: 'Password',
            hint: 'Create a strong password',
            obscure: obscurePassword,
            onToggle: onTogglePassword,
            controller: passwordController,
          ),
          const SizedBox(height: 20),

          // Confirm Password
          _PasswordField(
            label: 'Confirm Password',
            hint: 'Re-enter your password',
            obscure: obscureConfirm,
            onToggle: onToggleConfirm,
            controller: confirmPasswordController,
          ),
          const SizedBox(height: 20),

          // Terms checkbox
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: agreeToTerms,
                  onChanged: (v) => onAgreeChanged(v ?? false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, color: AppColors.onSurfaceVariant),
                    children: [
                      const TextSpan(text: 'I agree to the '),
                      TextSpan(
                        text: 'Terms of Service',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const TextSpan(text: ' and '),
                      TextSpan(
                        text: 'Privacy Policy',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Sign Up button
          SizedBox(
            height: 56,
            child: ElevatedButton(
              onPressed: loading ? null : onSignUpTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 4,
                shadowColor: AppColors.primary.withValues(alpha: 0.3),
              ),
              child: loading
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : Text(
                      'Create Account',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
          const SizedBox(height: 20),

          // Divider
          _OrDivider(),
          const SizedBox(height: 20),

          // Social buttons
          _SocialButton(
            label: 'Continue with Google',
            icon: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.asset(_googleAsset, width: 22, height: 22,
                  fit: BoxFit.cover),
            ),
            onTap: onGoogleTap,
          ),
          const SizedBox(height: 24),

          // Login link
          Center(
            child: Text.rich(
              TextSpan(
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, color: AppColors.onSurfaceVariant),
                children: [
                  const TextSpan(text: 'Already have an account? '),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.baseline,
                    baseline: TextBaseline.alphabetic,
                    child: GestureDetector(
                      onTap: onLoginTap,
                      child: Text(
                        'Login',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 48),

          // Footer features
          Divider(color: AppColors.surfaceContainerHigh, thickness: 1),
          const SizedBox(height: 24),
          const Row(
            children: [
              _FeatureItem(icon: Icons.eco_rounded, label: 'Smart Insights'),
              _FeatureItem(
                  icon: Icons.trending_up_rounded, label: 'Better Decisions'),
              _FeatureItem(
                  icon: Icons.moving_rounded, label: 'Higher Yield'),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Shared Widgets ──────────────────────────────────────────────────────────

class _AuthInputField extends StatelessWidget {
  final String label;
  final String hint;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final TextEditingController? controller;

  const _AuthInputField({
    required this.label,
    required this.hint,
    required this.prefixIcon,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 14, color: AppColors.onBackground),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: AppColors.outline.withValues(alpha: 0.5)),
            prefixIcon:
                Icon(prefixIcon, color: AppColors.outline, size: 18),
          ),
        ),
      ],
    );
  }
}

class _PasswordField extends StatelessWidget {
  final String label;
  final String hint;
  final bool obscure;
  final VoidCallback onToggle;
  final TextEditingController? controller;

  const _PasswordField({
    required this.label,
    required this.hint,
    required this.obscure,
    required this.onToggle,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 14, color: AppColors.onBackground),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                color: AppColors.outline.withValues(alpha: 0.5)),
            prefixIcon: const Icon(Icons.lock_outline,
                color: AppColors.outline, size: 18),
            suffixIcon: GestureDetector(
              onTap: onToggle,
              child: Icon(
                obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppColors.outline.withValues(alpha: 0.7),
                size: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
            child: Divider(color: AppColors.outlineVariant, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OR',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.outline,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const Expanded(
            child: Divider(color: AppColors.outlineVariant, thickness: 1)),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback? onTap;

  const _SocialButton({required this.label, required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.outlineVariant),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: Colors.transparent,
          foregroundColor: AppColors.onBackground,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.onBackground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _FeatureItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

