// ignore_for_file: prefer_const_constructors
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/leap_theme.dart';
import '../models/shipment_group_model.dart';
import '../../documents/services/document_service.dart';
import '../../shipments/screens/shipments_screen.dart';
import '../services/shipment_group_service.dart';
import '../../../l10n/app_localizations.dart';

class ShipmentGroupDetailScreen extends StatefulWidget {
  const ShipmentGroupDetailScreen({super.key, required this.group});
  final ShipmentGroup group;

  @override
  State<ShipmentGroupDetailScreen> createState() =>
      _ShipmentGroupDetailScreenState();
}

class _ShipmentGroupDetailScreenState
    extends State<ShipmentGroupDetailScreen> {
  final _picker = ImagePicker();
  final List<DocumentFile> _docs = [];
  List<bool?> _docResults = [];

  String _selectedDocType = AppConstants.docTypes.first;
  bool   _isSubmitting    = false;
  double _uploadProgress  = 0;
  int    _uploadCurrent   = 0;
  int    _uploadTotal     = 0;

  // Resolved group with location names
  late ShipmentGroup _group;
  bool _loadingLocations = true;
  bool _locationError    = false;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _resolveLocationNames();
  }

  @override
  void dispose() {
    _deleteStagedFiles(_docs);
    super.dispose();
  }

  static void _deleteStagedFiles(List<DocumentFile> docs) {
    for (final doc in docs) {
      try { if (doc.file.existsSync()) doc.file.deleteSync(); } catch (_) {}
    }
  }

  Future<void> _resolveLocationNames() async {
    try {
      final resolved = await ShipmentGroupService.instance.fetchById(
        widget.group.shipGroupGid,
      );
      if (mounted) setState(() { _group = resolved; _loadingLocations = false; });
    } catch (_) {
      if (mounted) {
        setState(() { _loadingLocations = false; _locationError = true; });
      }
    }
  }

  // ─── Image picking ────────────────────────────────────────────────────────

  Future<void> _openDocSheet() async {
    if (_docs.length >= AppConstants.maxDocuments) {
      _showSnack('Maximum ${AppConstants.maxDocuments} documents reached', false);
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DocBottomSheet(
        selectedType: _selectedDocType,
        onTypeChanged: (t) => setState(() => _selectedDocType = t),
        onCamera: () async { Navigator.pop(context); await _pickCamera(); },
        onGallery: () async { Navigator.pop(context); await _pickMultiGallery(); },
      ),
    );
  }

  Future<void> _pickCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) {
      if (status.isPermanentlyDenied && mounted) {
        _showPermissionDeniedDialog('Camera');
      } else {
        _showSnack('Camera access denied', false);
      }
      return;
    }
    try {
      final xfile = await _picker.pickImage(
        source:       ImageSource.camera,
        imageQuality: AppConstants.imageQuality,
        maxWidth:     AppConstants.imageMaxWidth.toDouble(),
        maxHeight:    AppConstants.imageMaxHeight.toDouble(),
      );
      if (xfile == null) return;
      await _addFile(xfile.path);
    } catch (e) {
      _showSnack('Error accessing camera', false);
    }
  }

  Future<void> _pickMultiGallery() async {
    // On Android, image_picker uses the system photo picker — no permission needed.
    // Only request permission on iOS.
    if (Platform.isIOS) {
      final status = await Permission.photos.request();
      if (!status.isGranted) {
        if (status.isPermanentlyDenied && mounted) {
          _showPermissionDeniedDialog('Photo Library');
        } else {
          _showSnack('Photo library access denied', false);
        }
        return;
      }
    }
    try {
      final remaining = AppConstants.maxDocuments - _docs.length;
      if (remaining <= 0) {
        _showSnack('Maximum ${AppConstants.maxDocuments} documents reached', false);
        return;
      }
      final xfiles = await _picker.pickMultiImage(
        imageQuality: AppConstants.imageQuality,
        maxWidth:     AppConstants.imageMaxWidth.toDouble(),
        maxHeight:    AppConstants.imageMaxHeight.toDouble(),
      );
      if (xfiles.isEmpty) return;
      final toAdd = xfiles.take(remaining).toList();
      if (xfiles.length > remaining) {
        final plural = remaining > 1 ? 's' : '';
        _showSnack('Only $remaining more image$plural added (max ${AppConstants.maxDocuments})', false);
      }
      for (final xfile in toAdd) { await _addFile(xfile.path); }
    } catch (e) {
      _showSnack('Error picking images', false);
    }
  }

  static const int _maxFileSizeBytes = 25 * 1024 * 1024; // 25 MB

  Future<void> _addFile(String path) async {
    try {
      final file = File(path);
      final size = await file.length();
      if (size > _maxFileSizeBytes) {
        _showSnack(
          'File too large (${(size / (1024 * 1024)).toStringAsFixed(1)} MB). Max 25 MB.',
          false,
        );
        return;
      }
      final ts      = DateFormat('yyyyMMddHHmmss').format(DateTime.now());
      final ext     = path.split('.').last.toLowerCase();
      final renamed = await file.copy('${file.parent.path}/${ts}_${_docs.length}.$ext');
      setState(() {
        _docs.add(DocumentFile(file: renamed, docType: _selectedDocType));
        _docResults = List<bool?>.filled(_docs.length, null);
      });
    } on FileSystemException catch (e) {
      if (kDebugMode) debugPrint('File add error: $e');
      _showSnack('Could not add file — check available storage.', false);
    } catch (e) {
      if (kDebugMode) debugPrint('File add error: $e');
      _showSnack('Could not add file.', false);
    }
  }

  Future<void> _confirmRemove(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(AppLocalizations.of(context)!.removeDocument,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: context.read<LeapThemeProvider>().theme.primary,
                fontSize: 16)),
        content: Text('${AppLocalizations.of(context)!.removeDocument}: "${_docs[index].docType}"',
            style: TextStyle(
                fontSize: 14,
                color: context.read<LeapThemeProvider>().theme.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel,
                style: TextStyle(
                    color: context.read<LeapThemeProvider>().theme.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppConstants.errorRed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(AppLocalizations.of(context)!.remove),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() {
        _docs.removeAt(index);
        _docResults = List<bool?>.filled(_docs.length, null);
      });
    }
  }

  // ─── Submit ───────────────────────────────────────────────────────────────

  Future<void> _submit() async {
    if (_docs.isEmpty) { await _openDocSheet(); return; }

    setState(() {
      _isSubmitting   = true;
      _uploadProgress = 0;
      _uploadCurrent  = 0;
      _uploadTotal    = _docs.length;
      _docResults     = List<bool?>.filled(_docs.length, null);
    });

    try {
      final result = await DocumentService.instance.uploadDocuments(
        shipGroupGid: widget.group.shipGroupGid,
        files: _docs,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _uploadProgress = total > 0 ? done / total : 0;
            _uploadCurrent  = done;
            _uploadTotal    = total;
          });
        },
      );

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        for (int i = 0; i < result.fileResults.length; i++) {
          _docResults[i] = result.fileResults[i];
        }
      });

      final count = result.successCount;
      final word  = count == 1 ? 'document' : 'documents';

      if (result.allSuccess) {
        _showSnack('✅ $count $word uploaded successfully', true);
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          _deleteStagedFiles(_docs);
          setState(() { _docs.clear(); _docResults = []; });
        }
      } else if (result.partialSuccess) {
        _showSnack('⚠️ ${result.successCount} of ${result.totalCount} $word uploaded', false);
      } else {
        _showSnack('❌ Upload failed — check your connection', false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() { _isSubmitting = false; _uploadProgress = 0; });
      _showSnack('❌ Upload failed — check your connection', false);
    }
  }

  void _showPermissionDeniedDialog(String permissionName) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$permissionName Access Required',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        content: Text(
          '$permissionName permission was denied. '
          'To enable it, open Settings → Apps → DockMate → Permissions.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, bool success) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor:
          success ? AppConstants.inboundGreen : AppConstants.errorRed,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(14),
    ));
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  String _fmtEet(DateTime? dt) {
    if (dt == null) return 'N/A';
    return DateFormat('dd MMM yyyy • HH:mm').format(dt);
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final g    = _group;
    final isIB = g.isInbound;

    return Scaffold(
      backgroundColor: context.watch<LeapThemeProvider>().theme.surface1,
      appBar: AppBar(
        backgroundColor: context.watch<LeapThemeProvider>().theme.navColor,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
        ),
        title: Text(g.shipGroupXid,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isIB
                  ? const Color(0xFFE8F7F1)
                  : const Color(0xFFFFF3E8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              g.attribute5,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isIB
                    ? AppConstants.inboundGreen
                    : AppConstants.outboundOrange,
              ),
            ),
          ),
        ],
      ),
      body: _loadingLocations
          ? Center(
              child: CircularProgressIndicator(
                color: context.watch<LeapThemeProvider>().theme.primary,
                strokeWidth: 2.5,
              ),
            )
          : Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
            child: Column(
              children: [
                _InfoCard(group: g, fmtEet: _fmtEet),
                if (_locationError)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF97316)),
                      ),
                      child: Row(children: const [
                        Icon(Icons.warning_amber_rounded,
                            color: Color(0xFFF97316), size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Could not load location names — showing location IDs.',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF7A4000)),
                          ),
                        ),
                      ]),
                    ),
                  ),
                const SizedBox(height: 12),
                _DocumentsCard(
                  docs: _docs,
                  docResults: _docResults,
                  onAdd: _isSubmitting ? null : _openDocSheet,
                  onRemove: _isSubmitting ? null : _confirmRemove,
                  onPreview: _previewDoc,
                ),
              ],
            ),
          ),
          if (_isSubmitting)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                    color: Colors.black.withValues(alpha: 0.08)),
              ),
            ),
          Positioned(
            left: 14, right: 14,
            bottom: MediaQuery.of(context).viewPadding.bottom + 14,
            child: _isSubmitting
                ? _UploadProgressButton(
                    progress: _uploadProgress,
                    current: _uploadCurrent,
                    total: _uploadTotal,
                  )
                : SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            context.watch<LeapThemeProvider>().theme.primary,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: context
                            .watch<LeapThemeProvider>()
                            .theme
                            .primary
                            .withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _docs.isEmpty
                              ? '📷  Add Documents'
                              : '📤  Submit ${_docs.length} Document${_docs.length > 1 ? "s" : ""} to OTM',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _previewDoc(DocumentFile doc) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: context.watch<LeapThemeProvider>().theme.navColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.image, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(doc.docType,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4.0,
                child: Image.file(doc.file, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

// ─── Info Card ────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.group, required this.fmtEet});
  final ShipmentGroup          group;
  final String Function(DateTime?) fmtEet;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LeapThemeProvider>().theme;
    final g = group;

    return Container(
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: t.surface3,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Icon(Icons.tag_rounded, color: t.primary, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppLocalizations.of(context)!.groupId,
                        style: TextStyle(
                            fontSize: 10,
                            color: t.textMuted,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0)),
                    const SizedBox(height: 2),
                    Text(g.shipGroupXid,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: t.primary,
                            letterSpacing: 0.3)),
                  ],
                ),
              ],
            ),
          ),
          Divider(height: 1, color: t.border),

          if (g.displaySource.isNotEmpty || g.displayDest.isNotEmpty)
            _RouteRow(from: g.displaySource, to: g.displayDest),

          _NormalRow(
            icon: Icons.calendar_today_outlined,
            label: AppLocalizations.of(context)!.plannedPickup,
            value: fmtEet(g.apptStartEet),
          ),
          _NormalRow(
            icon: Icons.calendar_today_outlined,
            label: AppLocalizations.of(context)!.plannedDelivery,
            value: fmtEet(g.apptEndEet),
          ),
          if (g.truckPlate.isNotEmpty)
            _NormalRow(
              icon: Icons.local_shipping_outlined,
              label: 'Truck plate',
              value: g.truckPlate,
              valueColor: AppConstants.outboundBlue,
            ),
          if (g.attribute2.isNotEmpty)
            _NormalRow(
              icon: Icons.meeting_room_outlined,
              label: 'Dock door',
              value: g.attribute2,
            ),
          if (g.attributeNumber1.isNotEmpty)
            _NormalRow(
              icon: Icons.inventory_2_outlined,
              label: 'Ship units',
              value: g.attributeNumber1,
              valueColor: t.primary,
              valueFontSize: 16,
            ),

          // Tappable shipments row
          _TappableRow(
            icon: Icons.directions_boat_outlined,
            label: AppLocalizations.of(context)!.shipments,
            value: '${g.numberOfShipments}',
            onTap: () => Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => ShipmentsScreen(
                  shipGroupGid:    g.shipGroupGid,
                  shipGroupXid:    g.shipGroupXid,
                  expectedCount:   g.numberOfShipments,
                ),
                transitionsBuilder: (_, animation, __, child) {
                  final slide = Tween<Offset>(
                    begin: const Offset(1.0, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                      parent: animation, curve: Curves.easeOutCubic));
                  return SlideTransition(position: slide, child: child);
                },
                transitionDuration: const Duration(milliseconds: 300),
              ),
            ),
          ),

          _NormalRow(
            icon: Icons.scale_outlined,
            label: AppLocalizations.of(context)!.weight,
            value: g.totalWeight.isNotEmpty ? g.totalWeight : 'N/A',
          ),
          _NormalRow(
            icon: Icons.square_foot_outlined,
            label: AppLocalizations.of(context)!.volume,
            value: g.totalVolume.isNotEmpty ? g.totalVolume : 'N/A',
            last: true,
          ),
        ],
      ),
    );
  }
}

// ─── Route Row Skeleton ───────────────────────────────────────────────────────

class _RouteRowSkeleton extends StatefulWidget {
  @override
  State<_RouteRowSkeleton> createState() => _RouteRowSkeletonState();
}

class _RouteRowSkeletonState extends State<_RouteRowSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(child: _bar(120, _anim.value)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward_rounded,
                  color: Colors.grey.withValues(alpha: 0.3), size: 18),
            ),
            Expanded(child: Align(alignment: Alignment.centerRight,
                child: _bar(100, _anim.value))),
          ],
        ),
      ),
    );
  }

  Widget _bar(double width, double opacity) => Container(
    width: width, height: 14,
    decoration: BoxDecoration(
      color: Colors.grey.withValues(alpha: opacity),
      borderRadius: BorderRadius.circular(6),
    ),
  );
}

// ─── Route Row ────────────────────────────────────────────────────────────────

class _RouteRow extends StatelessWidget {
  const _RouteRow({required this.from, required this.to});
  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LeapThemeProvider>().theme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: AppConstants.inboundGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('FROM',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: t.textMuted,
                          letterSpacing: 0.8)),
                ]),
                const SizedBox(height: 3),
                Text(from,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: t.text)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward_rounded,
                color: t.textMuted.withValues(alpha: 0.5), size: 18),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('TO',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: t.textMuted,
                          letterSpacing: 0.8)),
                  const SizedBox(width: 6),
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(
                      color: AppConstants.errorRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                ]),
                const SizedBox(height: 3),
                Text(to,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: t.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Normal Row ───────────────────────────────────────────────────────────────

class _NormalRow extends StatelessWidget {
  const _NormalRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueFontSize,
    this.last = false,
  });
  final IconData icon;
  final String   label;
  final String   value;
  final Color?   valueColor;
  final double?  valueFontSize;
  final bool     last;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LeapThemeProvider>().theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(
                    color: t.border.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: t.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13,
                        color: t.textMuted,
                        fontWeight: FontWeight.w500)),
                Text(value,
                    style: TextStyle(
                        fontSize: valueFontSize ?? 13,
                        fontWeight: FontWeight.w700,
                        color: valueColor ?? t.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Tappable Row (Shipments) ─────────────────────────────────────────────────

class _TappableRow extends StatelessWidget {
  const _TappableRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });
  final IconData   icon;
  final String     label;
  final String     value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LeapThemeProvider>().theme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: t.border.withValues(alpha: 0.5)),
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: t.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: t.textMuted,
                      fontWeight: FontWeight.w500)),
            ),
            Text(value,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppConstants.outboundBlue)),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 13, color: AppConstants.outboundBlue),
          ],
        ),
      ),
    );
  }
}

// ─── Upload Progress Button ───────────────────────────────────────────────────

class _UploadProgressButton extends StatelessWidget {
  const _UploadProgressButton({
    required this.progress,
    required this.current,
    required this.total,
  });
  final double progress;
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LeapThemeProvider>().theme;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: t.primary),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(color: AppConstants.inboundGreen),
            ),
            Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    current < total
                        ? 'Uploading $current of $total…'
                        : 'Finishing up…',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Documents Card ───────────────────────────────────────────────────────────

class _DocumentsCard extends StatelessWidget {
  const _DocumentsCard({
    required this.docs,
    required this.docResults,
    required this.onPreview,
    this.onAdd,
    this.onRemove,
  });
  final List<DocumentFile>           docs;
  final List<bool?>                  docResults;
  final VoidCallback?                onAdd;
  final void Function(int)?          onRemove;
  final void Function(DocumentFile)  onPreview;
  @override
  Widget build(BuildContext context) {
    final t = context.watch<LeapThemeProvider>().theme;
    return Container(
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Icon(Icons.attach_file_rounded, color: t.primary, size: 18),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.documents,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: t.primary)),
                const Spacer(),
                Text('${docs.length} / ${AppConstants.maxDocuments}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.textMuted)),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: docs.isEmpty
                ? GestureDetector(
                    onTap: onAdd,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: t.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              color: t.primary, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(AppLocalizations.of(context)!.addDocument,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: t.primary)),
                                Text(AppLocalizations.of(context)!.uploadDocument,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: t.textMuted)),
                              ],
                            ),
                          ),
                          Icon(Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: t.primary.withValues(alpha: 0.5)),
                        ],
                      ),
                    ),
                  )
                : Column(
                    children: [
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemCount: docs.length,
                        itemBuilder: (_, i) => _DocThumb(
                          doc: docs[i],
                          uploadResult:
                              i < docResults.length ? docResults[i] : null,
                          onTap: () => onPreview(docs[i]),
                          onRemove: onRemove != null
                              ? () => onRemove!(i)
                              : null,
                        ),
                      ),
                      if (docs.length < AppConstants.maxDocuments &&
                          onAdd != null) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: onAdd,
                            icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                                size: 16),
                            label: Text(
                                '${AppLocalizations.of(context)!.addDocument} (${docs.length}/${AppConstants.maxDocuments})'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: t.primary,
                              side: BorderSide(color: t.primary),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),

        ],
      ),
    );
  }
}

// ─── Doc Thumbnail ────────────────────────────────────────────────────────────

class _DocThumb extends StatelessWidget {
  const _DocThumb({
    required this.doc,
    required this.onTap,
    required this.uploadResult,
    this.onRemove,
  });
  final DocumentFile  doc;
  final VoidCallback  onTap;
  final VoidCallback? onRemove;
  final bool?         uploadResult;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(doc.file, fit: BoxFit.cover),
          ),
          if (uploadResult != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: uploadResult!
                    ? AppConstants.inboundGreen.withValues(alpha: 0.55)
                    : AppConstants.errorRed.withValues(alpha: 0.55),
                child: Center(
                  child: Icon(
                    uploadResult!
                        ? Icons.check_circle_rounded
                        : Icons.error_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            )
          else if (onRemove == null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                  color: Colors.black.withValues(alpha: 0.25)),
            ),
          if (uploadResult == null)
            Positioned(
              bottom: 4, left: 4,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(doc.docType,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 7,
                        fontWeight: FontWeight.w700)),
              ),
            ),
          if (onRemove != null)
            Positioned(
              top: 4, right: 4,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close,
                      size: 10, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Doc Bottom Sheet ─────────────────────────────────────────────────────────

class _DocBottomSheet extends StatefulWidget {
  const _DocBottomSheet({
    required this.selectedType,
    required this.onTypeChanged,
    required this.onCamera,
    required this.onGallery,
  });
  final String selectedType;
  final ValueChanged<String> onTypeChanged;
  final VoidCallback onCamera;
  final VoidCallback onGallery;

  @override
  State<_DocBottomSheet> createState() => _DocBottomSheetState();
}

class _DocBottomSheetState extends State<_DocBottomSheet> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedType;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<LeapThemeProvider>().theme;
    return Container(
      decoration: BoxDecoration(
        color: theme.surface2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: theme.border,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 18),
          Text(AppLocalizations.of(context)!.addDocument,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: theme.primary)),
          const SizedBox(height: 4),
          Text(AppLocalizations.of(context)!.uploadDocument,
              style: TextStyle(fontSize: 12, color: theme.textMuted)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: AppConstants.docTypes.map((docType) {
              final sel = _selected == docType;
              return GestureDetector(
                onTap: () {
                  setState(() => _selected = docType);
                  widget.onTypeChanged(docType);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel ? theme.primary : theme.surface1,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: sel ? theme.primary : theme.border,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (sel) ...[
                        const Icon(Icons.check_rounded,
                            size: 13, color: Colors.white),
                        const SizedBox(width: 4),
                      ],
                      Text(docType,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: sel
                                  ? Colors.white
                                  : const Color(0xFF555555))),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.onCamera,
                  icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  label: Text(AppLocalizations.of(context)!.takePhoto),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primary,
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shadowColor: theme.primary.withValues(alpha: 0.3),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: widget.onGallery,
                  icon: const Icon(Icons.photo_library_rounded, size: 18),
                  label: Text(AppLocalizations.of(context)!.chooseFile),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.surface3,
                    foregroundColor: theme.primary,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}