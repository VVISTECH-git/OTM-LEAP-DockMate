import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/leap_theme.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/otm_instance_service.dart';
import '../services/auth_service.dart';
import '../../shipment_groups/screens/shipment_groups_screen.dart';
import '../../../l10n/app_localizations.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// LEAP DockMate — Login Screen
//
// Instance URL flow:
//   • Active instance shown as a tappable card (friendly name + domain)
//   • Tap → saved instances list (up to 5) + "Scan new" button
//   • Scan QR or paste URL → live parse → confirm → saved & active
//   • Raw URL never shown to users during normal login
//
// Auth logic preserved:
//   • Rate limiting — 5 attempts then 30s lockout
//   • Shake animation on failed login
//   • Animated focus-state borders
//   • Username auto-uppercase
// ═══════════════════════════════════════════════════════════════════════════════

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {

  final _userIdCtrl    = TextEditingController();
  final _passwordCtrl  = TextEditingController();
  final _userIdFocus   = FocusNode();
  final _passwordFocus = FocusNode();

  bool _loading         = false;
  bool _obscurePassword = true;
  bool _userIdFocused   = false;
  bool _pwdFocused      = false;
  bool _userIdError     = false;
  bool _pwdError        = false;
  String _userIdErrorMsg = '';
  String _pwdErrorMsg    = '';

  OtmInstance? _activeInstance;

  static const int _maxAttempts = 5;
  static const int _lockoutSecs = 30;
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
        duration: const Duration(milliseconds: 400), vsync: this);
    _fadeCtrl  = AnimationController(
        duration: const Duration(milliseconds: 600), vsync: this)
      ..forward();

    _shakeAnim = TweenSequence<Offset>([
      TweenSequenceItem(tween: Tween(begin: Offset.zero,            end: const Offset(-0.02, 0)), weight: 20),
      TweenSequenceItem(tween: Tween(begin: const Offset(-0.02, 0), end: const Offset(0.02, 0)),  weight: 40),
      TweenSequenceItem(tween: Tween(begin: const Offset(0.02, 0),  end: Offset.zero),            weight: 40),
    ]).animate(CurvedAnimation(parent: _shakeCtrl, curve: Curves.easeInOut));

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadActive();
  }

  Future<void> _loadActive() async {
    final inst = await OtmInstanceService.instance.loadActive();
    if (mounted) setState(() => _activeInstance = inst);
  }

  void _startLockout() {
    setState(() { _isLockedOut = true; _lockoutCountdown = _lockoutSecs; });
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() => _lockoutCountdown--);
      if (_lockoutCountdown <= 0) {
        t.cancel();
        _passwordCtrl.clear();
        if (!mounted) return;
        setState(() {
          _isLockedOut = false; _failedAttempts = 0;
          _userIdError = false; _pwdError = false;
          _pwdErrorMsg = AppLocalizations.of(context)!.passwordRequired;
          _userIdErrorMsg = AppLocalizations.of(context)!.usernameRequired;
        });
        if (mounted) FocusScope.of(context).requestFocus(_passwordFocus);
      }
    });
  }

  Future<void> _login() async {
    if (_isLockedOut || _activeInstance == null) return;

    setState(() {
      _userIdError = false; _pwdError = false;
      _userIdErrorMsg = AppLocalizations.of(context)!.usernameRequired;
      _pwdErrorMsg = AppLocalizations.of(context)!.passwordRequired;
    });

    if (_userIdCtrl.text.trim().isEmpty || _passwordCtrl.text.trim().isEmpty) {
      setState(() {
        _userIdError = _userIdCtrl.text.trim().isEmpty;
        _pwdError    = _passwordCtrl.text.trim().isEmpty;
      });
      HapticFeedback.mediumImpact();
      _shakeCtrl.forward(from: 0);
      return;
    }

    setState(() => _loading = true);

    try {
      await AuthService.instance.login(
        instanceUrl: _activeInstance!.url,
        userId:      _userIdCtrl.text.trim(),
        password:    _passwordCtrl.text.trim(),
      );
      _failedAttempts = 0;
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, __, ___) => const ShipmentGroupsScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ));
    } catch (e) {
      if (!mounted) return;

      // Network / server errors should NOT count as a failed credential attempt.
      final isNetworkError = e is ApiException && (e.statusCode == null);
      if (!isNetworkError) _failedAttempts++;

      setState(() {
        _loading = false;
        _userIdError = !isNetworkError;
        _pwdError    = true;
        _pwdErrorMsg = e.toString().replaceAll('Exception: ', '');
        _userIdErrorMsg = '';
      });
      HapticFeedback.mediumImpact();
      _shakeCtrl.forward(from: 0);
      if (!isNetworkError && _failedAttempts >= _maxAttempts) _startLockout();
    }
  }

  void _openInstancePicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _InstancePickerSheet(
        activeInstance: _activeInstance,
        onSelected: (inst) => setState(() => _activeInstance = inst),
      ),
    );
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _shakeCtrl.dispose(); _fadeCtrl.dispose();
    _userIdCtrl.dispose(); _passwordCtrl.dispose();
    _userIdFocus.dispose(); _passwordFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LeapThemeProvider>().theme;
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: t.surface1,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          Column(children: [

        // ── LEAP brand header ──────────────────────────────────────────
        Container(
          width: double.infinity,
          color: t.navColor,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 24,
            bottom: 28, left: 20, right: 20,
          ),
          child: Column(children: [
                const Text('LEAP',
                  style: TextStyle(fontFamily: 'PlusJakartaSans',
                    fontSize: 40, fontWeight: FontWeight.w800,
                    color: Colors.white, letterSpacing: 8, height: 1.0)),
                const SizedBox(height: 5),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 22, height: 1.5, color: t.accent),
                  const SizedBox(width: 8),
                  Text('DOCKMATE', style: TextStyle(fontFamily: 'PlusJakartaSans',
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: t.accent, letterSpacing: 5)),
                  const SizedBox(width: 8),
                  Container(width: 22, height: 1.5, color: t.accent),
                ]),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 6, height: 6,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: LeapPlatform.oracleOrange)),
                    const SizedBox(width: 7),
                    Text(AppLocalizations.of(context)!.poweredBy,
                      style: TextStyle(fontFamily: 'PlusJakartaSans',
                        fontSize: 10, fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.50),
                        letterSpacing: 0.3)),
                  ]),
                ),
          ]),
        ),

        // ── Form ──────────────────────────────────────────────────────
        Expanded(
          child: SafeArea(
            top: false,
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 0, 24, MediaQuery.of(context).viewInsets.bottom + 24),
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _shakeAnim,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(height: 24),

                      _InstanceCard(
                        instance: _activeInstance,
                        theme: t,
                        onTap: _openInstancePicker,
                      ),
                      const SizedBox(height: 16),

                      _InputField(
                        controller: _userIdCtrl,
                        focusNode: _userIdFocus,
                        label: l10n.username,
                        hint: 'DOMAIN.USERNAME',
                        icon: Icons.person_outline_rounded,
                        hasError: _userIdError,
                        isFocused: _userIdFocused,
                        errorText: _userIdErrorMsg,
                        theme: t,
                        inputFormatters: [
                          TextInputFormatter.withFunction((_, v) =>
                              v.copyWith(text: v.text.toUpperCase())),
                        ],
                        onChanged: (_) => setState(() => _userIdError = false),
                      ),
                      const SizedBox(height: 12),

                      _InputField(
                        controller: _passwordCtrl,
                        focusNode: _passwordFocus,
                        label: l10n.password,
                        hint: '••••••••',
                        icon: Icons.lock_outline_rounded,
                        obscureText: _obscurePassword,
                        hasError: _pwdError,
                        isFocused: _pwdFocused,
                        errorText: _pwdErrorMsg,
                        theme: t,
                        suffixIcon: IconButton(
                          padding: const EdgeInsets.all(12),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: _pwdFocused ? t.primary : t.textMuted,
                            size: 22,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePassword = !_obscurePassword),
                        ),
                        onChanged: (_) => setState(() => _pwdError = false),
                      ),
                      const SizedBox(height: 24),

                      SizedBox(
                        width: double.infinity, height: 54,
                        child: ElevatedButton(
                          onPressed: (_loading || _isLockedOut ||
                              _activeInstance == null) ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isLockedOut ? t.textMuted : t.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: _isLockedOut
                                ? t.textMuted
                                : t.primary.withValues(alpha: 0.5),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _loading
                              ? const SizedBox(width: 22, height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2.5))
                              : _isLockedOut
                                  ? Row(mainAxisSize: MainAxisSize.min, children: [
                                      const Icon(Icons.lock_outline_rounded,
                                          size: 16, color: Colors.white),
                                      const SizedBox(width: 8),
                                      Text(l10n.tryAgainIn(_lockoutCountdown),
                                        style: const TextStyle(
                                          fontFamily: 'PlusJakartaSans',
                                          fontSize: 15, fontWeight: FontWeight.w700,
                                          color: Colors.white)),
                                    ])
                                  : Text(l10n.signIn,
                                      style: const TextStyle(fontFamily: 'PlusJakartaSans',
                                          fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                      ),

                      if (_failedAttempts > 0 && !_isLockedOut) ...[
                        const SizedBox(height: 10),
                        Text(
                          l10n.attemptsRemaining(_maxAttempts - _failedAttempts),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontFamily: 'PlusJakartaSans',
                              fontSize: 11, color: t.danger,
                              fontWeight: FontWeight.w500),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
          ]),
          // ── Palette icon — screen top-right ─────
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: _HeaderIconBtn(
              icon: Icons.palette_outlined,
              onTap: () => LeapThemePicker.show(context),
            ),
          ),
        ],
      ),
    );
  }
}



// ─── Header icon button ───────────────────────────────────────────────────────

class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

// ─── Instance card ────────────────────────────────────────────────────────────

class _InstanceCard extends StatelessWidget {
  final OtmInstance? instance;
  final AppThemeData theme;
  final VoidCallback onTap;
  const _InstanceCard({required this.instance, required this.theme, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasInstance = instance != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: theme.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasInstance ? theme.border : theme.warning,
            width: hasInstance ? 1.5 : 2,
          ),
        ),
        child: Row(children: [
          Icon(
            hasInstance ? Icons.cloud_outlined : Icons.cloud_off_outlined,
            color: hasInstance ? theme.primary : theme.warning, size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: hasInstance
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(instance!.displayName,
                      style: TextStyle(fontFamily: 'PlusJakartaSans',
                          fontSize: 14, fontWeight: FontWeight.w700, color: theme.text)),
                    const SizedBox(height: 2),
                    Text(instance!.domain,
                      style: TextStyle(fontFamily: 'PlusJakartaSans',
                          fontSize: 11, color: theme.textMuted)),
                  ])
                : Text(AppLocalizations.of(context)!.tapToSetupInstance,
                    style: TextStyle(fontFamily: 'PlusJakartaSans',
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: theme.warning)),
          ),
          const SizedBox(width: 8),
          if (hasInstance) _EnvBadge(instance: instance!, theme: theme),
          const SizedBox(width: 6),
          Icon(Icons.chevron_right_rounded, color: theme.textMuted, size: 18),
        ]),
      ),
    );
  }
}


// ─── Env badge ────────────────────────────────────────────────────────────────

class _EnvBadge extends StatelessWidget {
  final OtmInstance instance;
  final AppThemeData theme;
  const _EnvBadge({required this.instance, required this.theme});

  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    switch (instance.env) {
      case OtmEnv.production:
        bg = theme.success.withValues(alpha: 0.12); fg = theme.success; break;
      case OtmEnv.test:
        bg = theme.warning.withValues(alpha: 0.12); fg = theme.warning; break;
      case OtmEnv.development:
        bg = theme.info.withValues(alpha: 0.12); fg = theme.info; break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(100)),
      child: Text(instance.envLabel,
        style: TextStyle(fontFamily: 'PlusJakartaSans',
            fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}


// ─── Instance picker sheet ────────────────────────────────────────────────────

class _InstancePickerSheet extends StatefulWidget {
  final OtmInstance? activeInstance;
  final void Function(OtmInstance) onSelected;
  const _InstancePickerSheet({required this.activeInstance, required this.onSelected});

  @override
  State<_InstancePickerSheet> createState() => _InstancePickerSheetState();
}

class _InstancePickerSheetState extends State<_InstancePickerSheet> {
  List<OtmInstance> _saved = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final saved = await OtmInstanceService.instance.loadSaved();
    if (mounted) setState(() { _saved = saved; _loading = false; });
  }

  void _select(OtmInstance inst) async {
    await OtmInstanceService.instance.setActive(inst);
    widget.onSelected(inst);
    if (mounted) Navigator.pop(context);
  }

  void _delete(OtmInstance inst) async {
    await OtmInstanceService.instance.delete(inst);
    await _load();
  }

  void _scanNew() {
    // Capture everything needed BEFORE popping (while context is still alive)
    final themeProvider = context.read<LeapThemeProvider>();
    final onSelected    = widget.onSelected;
    final nav           = Navigator.of(context);
    nav.pop();
    showModalBottomSheet(
      context: nav.context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: themeProvider,
        child: _ScanSheet(onSaved: onSelected),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.read<LeapThemeProvider>().theme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: t.border,
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 18),
        Row(children: [
          Text(l10n.otmInstance, style: TextStyle(fontFamily: 'PlusJakartaSans',
              fontSize: 17, fontWeight: FontWeight.w800, color: t.text)),
          const Spacer(),
          if (_saved.isNotEmpty)
            Text('${_saved.length}/${OtmInstanceService.maxSaved} saved',
              style: TextStyle(fontFamily: 'PlusJakartaSans',
                  fontSize: 12, color: t.textMuted)),
        ]),
        const SizedBox(height: 4),
        Align(alignment: Alignment.centerLeft,
          child: Text(l10n.swipeToRemove,
            style: TextStyle(fontFamily: 'PlusJakartaSans',
                fontSize: 12, color: t.textMuted))),
        const SizedBox(height: 16),

        if (_loading)
          Padding(padding: const EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(color: t.primary, strokeWidth: 2))
        else if (_saved.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(l10n.noInstancesSaved,
              style: TextStyle(fontFamily: 'PlusJakartaSans',
                  fontSize: 14, color: t.textMuted)))
        else
          ...(_saved.map((inst) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Dismissible(
              key: ValueKey(inst.url),
              direction: DismissDirection.endToStart,
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                decoration: BoxDecoration(
                  color: t.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.delete_outline_rounded,
                    color: t.danger, size: 22),
              ),
              onDismissed: (_) => _delete(inst),
              child: GestureDetector(
                onTap: () => _select(inst),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: inst == widget.activeInstance
                          ? t.primary : t.border,
                      width: inst == widget.activeInstance ? 2 : 1.5,
                    ),
                  ),
                  child: Row(children: [
                    Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(inst.displayName, style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 14, fontWeight: FontWeight.w700,
                            color: t.text)),
                        const SizedBox(height: 2),
                        Text(inst.domain, style: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 11, color: t.textMuted)),
                      ],
                    )),
                    _EnvBadge(instance: inst, theme: t),
                    if (inst == widget.activeInstance) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check_circle_rounded,
                          color: t.primary, size: 18),
                    ],
                  ]),
                ),
              ),
            ),
          ))),

        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity, height: 50,
          child: OutlinedButton.icon(
            onPressed: _scanNew,
            icon: Icon(Icons.qr_code_scanner_rounded,
                color: t.primary, size: 18),
            label: Text(l10n.scanNewInstance,
              style: TextStyle(fontFamily: 'PlusJakartaSans',
                  fontWeight: FontWeight.w700, color: t.primary)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: t.primary, width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }
}


// ─── Scan / manual entry sheet ────────────────────────────────────────────────

class _ScanSheet extends StatefulWidget {
  final void Function(OtmInstance) onSaved;
  const _ScanSheet({required this.onSaved});

  @override
  State<_ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<_ScanSheet> {
  bool _scanned    = false;
  bool _showManual = false;
  bool _showGallery = false;
  OtmInstance? _parsed;
  final _urlCtrl = TextEditingController();
  final _galleryPicker = ImagePicker();

  bool? _cameraGranted; // null = pending, true = granted, false = denied

  Future<void> _pickQrFromGallery() async {
    final xfile = await _galleryPicker.pickImage(source: ImageSource.gallery);
    if (xfile == null) return;
    final result = await MobileScannerController().analyzeImage(xfile.path);
    if (result == null || result.barcodes.isEmpty) {
      if (mounted) _showSnack('No QR code found in this image.');
      return;
    }
    final raw = result.barcodes.first.rawValue ?? '';
    final inst = OtmInstanceService.parse(raw);
    if (inst != null && mounted) setState(() { _scanned = true; _parsed = inst; });
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    setState(() => _cameraGranted = status.isGranted);
    if (status.isPermanentlyDenied) _showSettingsDialog();
  }

  void _showSettingsDialog() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Camera Access Required',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        content: const Text(
          'Camera permission is required to scan QR codes. '
          'To enable it, open Settings → Apps → DockMate → Permissions.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () async { Navigator.pop(context); await openAppSettings(); },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final raw = capture.barcodes.firstOrNull?.rawValue ?? '';
    if (raw.isEmpty) return;
    final inst = OtmInstanceService.parse(raw);
    if (inst != null && mounted) {
      _scanned = true;
      setState(() => _parsed = inst);
    }
  }

  Future<void> _confirm() async {
    if (_parsed == null) return;
    await OtmInstanceService.instance.saveAndActivate(_parsed!);
    widget.onSaved(_parsed!);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LeapThemeProvider>().theme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 36, height: 4,
            decoration: BoxDecoration(color: t.border,
                borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 18),

        Text(_parsed != null ? l10n.confirmInstance : l10n.addOtmInstance,
          style: TextStyle(fontFamily: 'PlusJakartaSans',
              fontSize: 17, fontWeight: FontWeight.w800, color: t.text)),
        const SizedBox(height: 16),

        // ── Confirmed result ─────────────────────────────────────────
        if (_parsed != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(_parsed!.displayName,
                  style: TextStyle(fontFamily: 'PlusJakartaSans',
                      fontSize: 16, fontWeight: FontWeight.w800, color: t.text))),
                _EnvBadge(instance: _parsed!, theme: t),
              ]),
              const SizedBox(height: 4),
              Text(_parsed!.domain,
                style: TextStyle(fontFamily: 'PlusJakartaSans',
                    fontSize: 12, color: t.textMuted)),
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primary, foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(l10n.saveAndUse,
                style: const TextStyle(fontFamily: 'PlusJakartaSans',
                    fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: () {
              _urlCtrl.clear();
              setState(() { _parsed = null; _scanned = false; });
            },
            child: Text(l10n.scanAgain, style: TextStyle(
                fontFamily: 'PlusJakartaSans',
                color: t.primary, fontWeight: FontWeight.w600)),
          ),

        // ── Scanner / manual ─────────────────────────────────────────
        ] else ...[
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () => setState(() { _showManual = false; _showGallery = false; }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: !_showManual && !_showGallery ? t.primary : t.surface1,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: !_showManual && !_showGallery ? t.primary : t.border),
                ),
                child: Text(l10n.scanQrCode, textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'PlusJakartaSans',
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: !_showManual && !_showGallery ? Colors.white : t.textMuted)),
              ),
            )),
            const SizedBox(width: 8),
            Expanded(child: GestureDetector(
              onTap: () => setState(() { _showManual = false; _showGallery = true; }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _showGallery ? t.primary : t.surface1,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _showGallery ? t.primary : t.border),
                ),
                child: Text('From Gallery', textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'PlusJakartaSans',
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: _showGallery ? Colors.white : t.textMuted)),
              ),
            )),
            const SizedBox(width: 8),
            Expanded(child: GestureDetector(
              onTap: () => setState(() { _showManual = true; _showGallery = false; }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _showManual ? t.primary : t.surface1,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _showManual ? t.primary : t.border),
                ),
                child: Text(l10n.enterManually, textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'PlusJakartaSans',
                      fontSize: 13, fontWeight: FontWeight.w700,
                      color: _showManual ? Colors.white : t.textMuted)),
              ),
            )),
          ]),
          const SizedBox(height: 16),

          if (_showGallery) ...[ 
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _pickQrFromGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Pick QR from Gallery',
                  style: TextStyle(fontFamily: 'PlusJakartaSans',
                      fontSize: 14, fontWeight: FontWeight.w700)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.primary, foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Select an image from your gallery that contains a QR code.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'PlusJakartaSans',
                  fontSize: 12, color: t.textMuted)),
          ] else if (!_showManual) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 200,
                child: _cameraGranted == null
                    ? const Center(child: CircularProgressIndicator())
                    : _cameraGranted == true
                        ? MobileScanner(onDetect: _onDetect)
                        : _CameraPermissionPlaceholder(
                            onRetry: _requestCameraPermission),
              ),
            ),
            const SizedBox(height: 12),
            Text(l10n.pointCamera,
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'PlusJakartaSans',
                  fontSize: 12, color: t.textMuted)),
          ] else ...[
            Container(
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.border, width: 1.5),
              ),
              child: TextField(
                controller: _urlCtrl,
                onChanged: (v) {
                  final inst = OtmInstanceService.parse(v);
                  if (!mounted) return;
                  setState(() => _parsed = inst);
                },
                style: TextStyle(fontFamily: 'PlusJakartaSans',
                    fontSize: 13, color: t.text),
                decoration: InputDecoration(
                  hintText: 'https://otmgtm-...',
                  hintStyle: TextStyle(color: t.textMuted, fontSize: 13),
                  prefixIcon: Icon(Icons.link_rounded,
                      color: t.textMuted, size: 18),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft,
              child: Text(l10n.urlValidating,
                style: TextStyle(fontFamily: 'PlusJakartaSans',
                    fontSize: 11, color: t.textMuted))),
          ],
        ],
      ]),
    );
  }
}


// ─── Input field ──────────────────────────────────────────────────────────────

class _InputField extends StatelessWidget {
  const _InputField({
    required this.controller, required this.label, required this.hint,
    required this.icon, required this.isFocused, required this.theme,
    this.focusNode, this.obscureText = false, this.hasError = false,
    this.errorText, this.suffixIcon, this.inputFormatters, this.onChanged,
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
  final AppThemeData              theme;

  Color get _borderColor {
    if (hasError)  return theme.danger;
    if (isFocused) return theme.primary;
    return theme.border;
  }

  Color get _iconColor {
    if (hasError)  return theme.danger;
    if (isFocused) return theme.primary;
    return theme.textMuted;
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
            color: theme.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _borderColor, width: isFocused ? 2 : 1.5),
          ),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: obscureText,
            inputFormatters: inputFormatters,
            onChanged: onChanged,
            style: TextStyle(fontFamily: 'PlusJakartaSans',
                fontSize: 15, fontWeight: FontWeight.w500, color: theme.text),
            decoration: InputDecoration(
              labelText: label, hintText: hint,
              labelStyle: TextStyle(fontFamily: 'PlusJakartaSans',
                color: hasError ? theme.danger
                    : isFocused ? theme.primary : theme.textMuted,
                fontSize: 14),
              hintStyle: TextStyle(
                  color: theme.textMuted.withValues(alpha: 0.5)),
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
            child: Text(errorText!, style: TextStyle(
                fontFamily: 'PlusJakartaSans', fontSize: 11,
                fontWeight: FontWeight.w500, color: theme.danger)),
          ),
      ],
    );
  }
}

// ─── Camera Permission Placeholder ───────────────────────────────────────────

class _CameraPermissionPlaceholder extends StatelessWidget {
  const _CameraPermissionPlaceholder({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.no_photography_rounded,
              color: Colors.white54, size: 40),
          const SizedBox(height: 12),
          const Text(
            'Camera access denied',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            label: const Text(
              'Grant Permission',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}