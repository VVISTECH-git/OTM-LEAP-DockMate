import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/leap_theme.dart';

import '../models/shipment_group_model.dart';
import '../providers/shipment_groups_provider.dart';
import 'shipment_group_detail_screen.dart';
import '../../auth/screens/login_screen.dart';
import '../../auth/services/auth_service.dart';
import '../../../l10n/app_localizations.dart';

class ShipmentGroupsScreen extends StatefulWidget {
  const ShipmentGroupsScreen({super.key});

  @override
  State<ShipmentGroupsScreen> createState() => _ShipmentGroupsScreenState();
}

class _ShipmentGroupsScreenState extends State<ShipmentGroupsScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ShipmentGroupsProvider>().init();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LeapThemeProvider>().theme;
    return Scaffold(
      backgroundColor: t.surface1,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context),
            _buildSearchBar(context),
            const Expanded(child: _GroupList()),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    final t        = context.watch<LeapThemeProvider>().theme;
    final provider = context.watch<ShipmentGroupsProvider>();
    final isIB     = provider.isInbound;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
      color: t.navColor,
      child: Row(
        children: [
          // ── LEAP DockMate branding ────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('LEAP',
                    style: TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 8,
                        height: 1.0)),
                const SizedBox(height: 3),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 16, height: 1.5,
                      color: t.accent),
                  const SizedBox(width: 6),
                  Text('DOCKMATE',
                      style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: t.accent,
                          letterSpacing: 4)),
                  const SizedBox(width: 6),
                  Container(
                      width: 16, height: 1.5,
                      color: t.accent),
                ]),
                const SizedBox(height: 6),
                // ── Badge moved here — part of branding, frees up right side ──
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isIB
                        ? const Color(0xFFE8F7F1)
                        : const Color(0xFFFFF3E8),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isIB ? AppLocalizations.of(context)!.inboundUpper
                         : AppLocalizations.of(context)!.outboundUpper,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: isIB
                          ? AppConstants.inboundGreen
                          : AppConstants.outboundOrange,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Switch button ─────────────────────────────────────────
          GestureDetector(
            onTap: () => _confirmSwitch(context, provider),
            child: Container(
              width: 34, height: 34,
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4), width: 1),
              ),
              child: const Center(
                child: Text('⇄',
                    style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
            ),
          ),
          // ── Theme ────────────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.palette_outlined,
                color: Colors.white, size: 22),
            tooltip: 'Change theme',
            onPressed: () => LeapThemePicker.show(context),
          ),
          // ── Logout ───────────────────────────────────────────────
          IconButton(
            icon: const Icon(Icons.logout_rounded,
                color: Colors.white, size: 22),
            onPressed: _logout,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final t = context.watch<LeapThemeProvider>().theme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      color: t.surface2,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.border, width: 1.5),
        ),
        child: Row(
          children: [
            const SizedBox(width: 10),
            Icon(Icons.search_rounded, color: t.textMuted, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (q) =>
                    context.read<ShipmentGroupsProvider>().setSearch(q),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: t.text,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Search group ID, truck plate…',
                  hintStyle: TextStyle(
                    color: t.textMuted.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                  isDense: true,
                ),
              ),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchCtrl,
              builder: (_, value, __) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    context.read<ShipmentGroupsProvider>().setSearch('');
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.close_rounded,
                        color: t.textMuted, size: 16),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }


  void _confirmSwitch(BuildContext context, ShipmentGroupsProvider provider) {
    final t = context.read<LeapThemeProvider>().theme;
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context)!.switchView,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: t.text),
            ),
            const SizedBox(height: 6),
            Text(
              provider.isInbound
                  ? AppLocalizations.of(context)!.showExporter
                  : AppLocalizations.of(context)!.showImporter,
              style: TextStyle(fontSize: 13, color: t.textMuted),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: t.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(AppLocalizations.of(context)!.cancel,
                        style: TextStyle(color: t.textMuted)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      provider.switchTeam();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.primary,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(AppLocalizations.of(context)!.switchTeam(
                        provider.isInbound ? 'Outbound' : 'Inbound'),
                        style: const TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final t = context.read<LeapThemeProvider>().theme;
    HapticFeedback.lightImpact();
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sign Out',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: t.text)),
            const SizedBox(height: 6),
            Text('Are you sure you want to sign out?',
                style: TextStyle(fontSize: 13, color: t.textMuted)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: t.border),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('Cancel',
                        style: TextStyle(color: t.textMuted)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.danger,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Sign Out',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirm == true) {
      await AuthService.instance.logout();
      if (mounted) {
        Navigator.of(context).pushReplacement(PageRouteBuilder(
          pageBuilder: (_, __, ___) => const LoginScreen(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ));
      }
    }
  }
}

// ─── Group List ────────────────────────────────────────────────────────────────

class _GroupList extends StatelessWidget {
  const _GroupList();

  @override
  Widget build(BuildContext context) {
    final t        = context.watch<LeapThemeProvider>().theme;
    final provider = context.watch<ShipmentGroupsProvider>();

    if (provider.state == LoadState.loading) {
      return Center(
        child: CircularProgressIndicator(color: t.primary, strokeWidth: 2.5),
      );
    }

    if (provider.state == LoadState.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('😕', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 12),
              Text(provider.error,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: t.primary)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: provider.load,
                style: ElevatedButton.styleFrom(
                    backgroundColor: t.primary),
                child: Text(AppLocalizations.of(context)!.retry,
                    style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
    }

    final groups = provider.groups;

    if (groups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: t.surface3,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Icon(Icons.inbox_outlined,
                      color: t.primary, size: 30),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'No ${provider.isInbound ? "Inbound" : "Outbound"} Groups',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: t.primary),
              ),
              const SizedBox(height: 6),
              Text(
                'No shipment groups found.\nPull down to refresh.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13, color: t.textMuted, height: 1.5),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: t.primary,
      onRefresh: provider.load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
        itemCount: groups.length,
        itemBuilder: (_, i) => _GroupCard(group: groups[i]),
      ),
    );
  }
}

// ─── Group Card ────────────────────────────────────────────────────────────────

class _GroupCard extends StatefulWidget {
  const _GroupCard({required this.group});
  final ShipmentGroup group;

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleCtrl;
  late Animation<double>   _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
      lowerBound: 0.0,
      upperBound: 1.0,
      value: 1.0,
    );
    _scaleAnim = Tween<double>(begin: 0.98, end: 1.0).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t    = context.watch<LeapThemeProvider>().theme;
    final g    = widget.group;
    final isIB = g.isInbound;

    return ScaleTransition(
      scale: _scaleAnim,
      child: GestureDetector(
        onTapDown: (_) => _scaleCtrl.reverse(),
        onTapUp: (_) {
          _scaleCtrl.forward();
          HapticFeedback.lightImpact();
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (_, __, ___) =>
                  ShipmentGroupDetailScreen(group: g),
              transitionsBuilder: (_, animation, __, child) {
                final slide = Tween<Offset>(
                  begin: const Offset(0, 0.06),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                    parent: animation, curve: Curves.easeOutCubic));
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              transitionDuration: const Duration(milliseconds: 280),
            ),
          );
        },
        onTapCancel: () => _scaleCtrl.forward(),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: t.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.border, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left colour bar
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: isIB
                        ? AppConstants.inboundGreen
                        : AppConstants.outboundBlue,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top row: icon + ID + direction tag
                        Row(
                          children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: isIB
                                    ? const Color(0xFFE8F7F1)
                                    : const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: Text(
                                  isIB ? '📥' : '📤',
                                  style: const TextStyle(fontSize: 18),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                g.shipGroupXid,
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: t.primary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: isIB
                                    ? const Color(0xFFE8F7F1)
                                    : const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Text(
                                g.attribute5,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: isIB
                                      ? AppConstants.inboundGreen
                                      : AppConstants.outboundBlue,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Middle row: appt start | appt end | ship units
                        Row(
                          children: [
                            _MetaItem(
                              label: 'APPT START',
                              value: _fmtEet(g.apptStartEet),
                            ),
                            _MetaItem(
                              label: 'APPT END',
                              value: _fmtEet(g.apptEndEet),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    g.attributeNumber1.isNotEmpty
                                        ? g.attributeNumber1
                                        : '—',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      color: t.primary,
                                      height: 1,
                                    ),
                                  ),
                                  Text(
                                    'Ship units',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: t.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Bottom row: weight | truck plate | door | chevron
                        Row(
                          children: [
                            Text(
                              g.totalWeight.isNotEmpty
                                  ? g.totalWeight
                                  : 'N/A',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: t.textMuted,
                              ),
                            ),
                            if (g.truckPlate.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE6F1FB),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  g.truckPlate,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: AppConstants.outboundBlue,
                                  ),
                                ),
                              ),
                            ],
                            if (g.attribute2.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                g.attribute2,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: t.textMuted,
                                ),
                              ),
                            ],
                            const Spacer(),
                            Icon(Icons.arrow_forward_ios_rounded,
                                size: 13, color: t.textMuted.withValues(alpha: 0.4)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _fmtEet(DateTime? dt) {
    if (dt == null) return 'N/A';
    return DateFormat('dd MMM • HH:mm').format(dt);
  }
}

class _MetaItem extends StatelessWidget {
  const _MetaItem({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LeapThemeProvider>().theme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  color: t.textMuted,
                  letterSpacing: 0.4)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: t.text),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}