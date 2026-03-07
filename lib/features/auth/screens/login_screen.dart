import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants/app_constants.dart';
import '../services/auth_service.dart';
import '../../shipment_groups/screens/shipment_groups_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _instanceCtrl = TextEditingController(
      text: AppConstants.defaultInstanceUrl);
  final _userIdCtrl   = TextEditingController();
  final _passwordCtrl = TextEditingController();

  final _userIdFocus   = FocusNode();
  final _passwordFocus = FocusNode();

  bool _loading         = false;
  bool _obscurePassword = true;
  bool _showAdvanced    = false;
  bool _userIdFocused   = false;
  bool _pwdFocused      = false;

  bool   _userIdError    = false;
  bool   _pwdError       = false;
  String _userIdErrorMsg = 'Username is required';
  String _pwdErrorMsg    = 'Password is required';

  // ─── Rate limiting ────────────────────────────────────────────────────────
  static const int _maxAttempts   = 5;
  static const int _lockoutSecs   = 30;
  int    _failedAttempts   = 0;
  bool   _isLockedOut      = false;
  int    _lockoutCountdown = 0;
  Timer? _lockoutTimer;

  late AnimationController _shakeCtrl;
  late AnimationController _fadeCtrl;
  late Animation<Offset>   _shakeAnim;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _userIdFocus.addListener(() =>
        setState(() => _userIdFocused = _userIdFocus.hasFocus));
    _passwordFocus.addListener(() =>
        setState(() => _pwdFocused = _passwordFocus.hasFocus));

    _shakeCtrl = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _fadeCtrl = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..forward();
    _shakeAnim = TweenSequence<Offset>([
      TweenSequenceItem(tween: Tween(begin: Offset.zero, end: const Offset(-0.02, 0)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: const Offset(-0.02, 0), end: const Offset(0.02, 0)), weight: 40),
      TweenSequenceItem(tween: Tween(begin: const Offset(0.02, 0), end: Offset.zero), weight: 40),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
  }

  void _startLockout() {
    setState(() {
      _isLockedOut      = true;
      _lockoutCountdown = _lockoutSecs;
    });
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() => _lockoutCountdown--);
      if (_lockoutCountdown <= 0) {
        timer.cancel();
        // Clear password field and reset ALL state cleanly
        _passwordCtrl.clear();
        setState(() {
          _isLockedOut     = false;
          _failedAttempts  = 0;
          _userIdError     = false;
          _pwdError        = false;
          _pwdErrorMsg     = 'Password is required';
          _userIdErrorMsg  = 'Username is required';
        });
        // Focus password field so user can type immediately
        FocusScope.of(context).requestFocus(_passwordFocus);
      }
    });
  }

  Future<void> _login() async {
    // Block if locked out
    if (_isLockedOut) return;

    // Clear any stale errors before validating
    setState(() {
      _userIdError    = false;
      _pwdError       = false;
      _userIdErrorMsg = 'Username is required';
      _pwdErrorMsg    = 'Password is required';
    });

    final userIdEmpty = _userIdCtrl.text.trim().isEmpty;
    final pwdEmpty    = _passwordCtrl.text.trim().isEmpty;

    if (userIdEmpty || pwdEmpty) {
      setState(() {
        _userIdError = userIdEmpty;
        _pwdError    = pwdEmpty;
      });
      HapticFeedback.mediumImpact();
      _shakeCtrl.forward(from: 0);
      return;
    }

    setState(() => _loading = true);

    try {
      await AuthService.instance.login(
        instanceUrl: _instanceCtrl.text.trim(),
        userId:      _userIdCtrl.text.trim(),
        password:    _passwordCtrl.text.trim(),
      );
      _failedAttempts = 0;
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const ShipmentGroupsScreen(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      _failedAttempts++;

      setState(() {
        _loading        = false;
        _userIdError    = true;
        _pwdError       = true;
        _pwdErrorMsg    = e.toString().replaceAll('Exception: ', '');
        _userIdErrorMsg = '';
      });

      HapticFeedback.mediumImpact();
      _shakeCtrl.forward(from: 0);

      if (_failedAttempts >= _maxAttempts) {
        _startLockout();
      }
    }
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _shakeCtrl.dispose();
    _fadeCtrl.dispose();
    _instanceCtrl.dispose();
    _userIdCtrl.dispose();
    _passwordCtrl.dispose();
    _userIdFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _shakeAnim,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    _buildLogo(),
                    const SizedBox(height: 36),
                    _buildForm(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppConstants.nokiaBlue,
            boxShadow: [
              BoxShadow(
                color: AppConstants.nokiaBlue.withValues(alpha: 0.3),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Center(
            child: Text('🚢', style: TextStyle(fontSize: 36)),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'LEAP',
          style: TextStyle(
            color: AppConstants.nokiaBlue,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'DockMate',
          style: TextStyle(
            color: AppConstants.nokiaBrightBlue,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _InputField(
          controller: _userIdCtrl,
          focusNode: _userIdFocus,
          label: 'Username',
          hint: 'DOMAIN.USERNAME',
          icon: Icons.person_outline_rounded,
          hasError: _userIdError,
          isFocused: _userIdFocused,
          errorText: _userIdErrorMsg,
          inputFormatters: [
            TextInputFormatter.withFunction(
              (_, newVal) => newVal.copyWith(text: newVal.text.toUpperCase()),
            ),
          ],
          onChanged: (_) => setState(() => _userIdError = false),
        ),
        const SizedBox(height: 14),
        _InputField(
          controller: _passwordCtrl,
          focusNode: _passwordFocus,
          label: 'Password',
          hint: '••••••••',
          icon: Icons.lock_outline_rounded,
          obscureText: _obscurePassword,
          hasError: _pwdError,
          isFocused: _pwdFocused,
          errorText: _pwdErrorMsg,
          suffixIcon: SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              padding: const EdgeInsets.all(12),
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: _pwdFocused
                    ? AppConstants.nokiaBlue
                    : AppConstants.textGrey,
                size: 22,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          onChanged: (_) => setState(() => _pwdError = false),
        ),
        const SizedBox(height: 12),
        // Advanced toggle
        GestureDetector(
          onTap: () => setState(() => _showAdvanced = !_showAdvanced),
          child: Row(
            children: [
              Icon(
                _showAdvanced
                    ? Icons.keyboard_arrow_down_rounded
                    : Icons.keyboard_arrow_right_rounded,
                size: 18,
                color: AppConstants.nokiaBrightBlue,
              ),
              const SizedBox(width: 4),
              const Text(
                'Advanced',
                style: TextStyle(
                  fontSize: 12,
                  color: AppConstants.nokiaBrightBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: _showAdvanced
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _InputField(
                    controller: _instanceCtrl,
                    label: 'Instance URL',
                    hint: 'https://your-otm-instance.com',
                    icon: Icons.link_rounded,
                    isFocused: false,
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 28),
        // Sign In button
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: (_loading || _isLockedOut) ? null : _login,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isLockedOut
                  ? AppConstants.textGrey
                  : AppConstants.nokiaBlue,
              foregroundColor: Colors.white,
              disabledBackgroundColor: _isLockedOut
                  ? AppConstants.textGrey
                  : AppConstants.nokiaBlue.withValues(alpha: 0.5),
              elevation: 4,
              shadowColor: AppConstants.nokiaBlue.withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: _loading
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : _isLockedOut
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline_rounded,
                              size: 16, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(
                            'Try again in ${_lockoutCountdown}s',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      )
                    : const Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
          ),
        ),
        // Attempts warning
        if (_failedAttempts > 0 && !_isLockedOut)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${_maxAttempts - _failedAttempts} attempt${(_maxAttempts - _failedAttempts) != 1 ? 's' : ''} remaining before lockout',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: AppConstants.errorRed,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }
}

// ─── Input Field with focus state ─────────────────────────────────────────────

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.isFocused,
    this.focusNode,
    this.obscureText = false,
    this.hasError = false,
    this.errorText,
    this.suffixIcon,
    this.inputFormatters,
    this.onChanged,
  });

  final TextEditingController     controller;
  final FocusNode?                focusNode;
  final String                    label;
  final String                    hint;
  final IconData                  icon;
  final bool                      isFocused;
  final bool                      obscureText;
  final bool                      hasError;
  final String?                   errorText;
  final Widget?                   suffixIcon;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>?     onChanged;

  Color get _borderColor {
    if (hasError) return AppConstants.errorRed;
    if (isFocused) return AppConstants.nokiaBlue;
    return const Color(0xFFCBD5E1);
  }

  Color get _iconColor {
    if (hasError) return AppConstants.errorRed;
    if (isFocused) return AppConstants.nokiaBlue;
    return AppConstants.textGrey;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderColor, width: isFocused ? 2 : 1.5),
            boxShadow: isFocused
                ? [
                    BoxShadow(
                      color: AppConstants.nokiaBlue.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: obscureText,
            inputFormatters: inputFormatters,
            onChanged: onChanged,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1A1A2E),
            ),
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              labelStyle: TextStyle(
                color: hasError
                    ? AppConstants.errorRed
                    : isFocused
                        ? AppConstants.nokiaBlue
                        : AppConstants.textGrey,
                fontSize: 14,
              ),
              hintStyle: TextStyle(
                color: AppConstants.textGrey.withValues(alpha: 0.5),
              ),
              prefixIcon: Icon(icon, color: _iconColor, size: 20),
              suffixIcon: suffixIcon,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 16),
              floatingLabelBehavior: FloatingLabelBehavior.never,
            ),
          ),
        ),
        if (hasError && errorText != null && errorText!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 5, left: 4),
            child: Text(errorText!,
                style: const TextStyle(
                    fontSize: 11,
                    color: AppConstants.errorRed,
                    fontWeight: FontWeight.w500)),
          ),
      ],
    );
  }
}