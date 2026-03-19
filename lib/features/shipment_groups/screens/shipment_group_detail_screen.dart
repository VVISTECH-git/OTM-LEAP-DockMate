// ignore_for_file: prefer_const_constructors
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/leap_theme.dart';
import '../models/shipment_group_model.dart';
import '../../documents/services/document_service.dart';

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

  // FIX: Track per-file upload result so each thumbnail can show ✅/❌ after submission.
  List<bool?> _docResults = []; // null = not yet uploaded, true = success, false = failed

  String _selectedDocType = AppConstants.docTypes.first;
  bool   _isSubmitting    = false;
  double _uploadProgress  = 0;
  int    _uploadCurrent   = 0;  // FIX: Track which file number is currently uploading
  int    _uploadTotal     = 0;

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
        onCamera: () async {
          Navigator.pop(context);
          await _pickCamera();
        },
        onGallery: () async {
          Navigator.pop(context);
          await _pickMultiGallery();
        },
      ),
    );
  }

  // Camera — single shot, called again via + button for burst
  Future<void> _pickCamera() async {
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
      debugPrint('Camera error: $e');
      _showSnack('Error accessing camera', false);
    }
  }

  // Gallery — multi-select up to remaining slots
  Future<void> _pickMultiGallery() async {
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
        _showSnack(
          'Only $remaining more image$plural added (max ${AppConstants.maxDocuments})',
          false,
        );
      }
      for (final xfile in toAdd) {
        await _addFile(xfile.path);
      }
    } catch (e) {
      debugPrint('Gallery error: $e');
      _showSnack('Error picking images', false);
    }
  }

  // Shared helper — rename and add to _docs
  Future<void> _addFile(String path) async {
    try {
      final file    = File(path);
      final ts      = DateFormat('yyyyMMddHHmmss').format(DateTime.now());
      final ext     = path.split('.').last.toLowerCase();
      final renamed = await file.copy(
          '${file.parent.path}/${ts}_${_docs.length}.$ext');
      setState(() {
        _docs.add(DocumentFile(file: renamed, docType: _selectedDocType));
        _docResults = List<bool?>.filled(_docs.length, null);
      });
    } catch (e) {
      debugPrint('File add error: $e');
    }
  }

  Future<void> _confirmRemove(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove Document',
            style: TextStyle(
                fontWeight: FontWeight.w800,
                color: context.read<LeapThemeProvider>().theme.primary,
                fontSize: 16)),
        content: Text(
          'Remove "${_docs[index].docType}" document?',
          style: TextStyle(fontSize: 14, color: context.read<LeapThemeProvider>().theme.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: TextStyle(color: context.read<LeapThemeProvider>().theme.textMuted)),
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
            child: const Text('Remove'),
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

  Future<void> _submit() async {
    if (_docs.isEmpty) { await _openDocSheet(); return; }

    setState(() {
      _isSubmitting   = true;
      _uploadProgress = 0;
      _uploadCurrent  = 0;
      _uploadTotal    = _docs.length;
      _docResults     = List<bool?>.filled(_docs.length, null);
    });

    // onProgress only updates the progress bar and counter.
    // Per-file results (fileResults) cannot be read here because `result`
    // hasn't been assigned yet — they are applied after the await returns.
    final result = await DocumentService.instance.uploadDocuments(
      shipGroupGid: widget.group.shipGroupGid,
      files: _docs,
      onProgress: (done, total) => setState(() {
        _uploadProgress = total > 0 ? done / total : 0;
        _uploadCurrent  = done;
        _uploadTotal    = total;
      }),
    );

    // Now apply per-file ✅/❌ results and stop the spinner.
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
      // Small delay so user can see the ✅ thumbnails before they disappear.
      await Future.delayed(const Duration(milliseconds: 800));
      setState(() {
        _docs.clear();
        _docResults = [];
      });
    } else if (result.partialSuccess) {
      _showSnack('⚠️ ${result.successCount} of ${result.totalCount} $word uploaded', false);
    } else {
      _showSnack('❌ Upload failed — check your connection', false);
    }
  }

  void _showSnack(String msg, bool success) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      backgroundColor:
          success ? AppConstants.inboundGreen : AppConstants.errorRed,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(14),
    ));
  }

  String _fmt(String s) {
    if (s.isEmpty) return 'N/A';
    try { return DateFormat('dd MMM yyyy • HH:mm').format(DateTime.parse(s)); }
    catch (_) { return s; }
  }

  @override
  Widget build(BuildContext context) {
    final g    = widget.group;
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
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(g.shipGroupXid,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 14),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isIB
                  ? const Color(0xFFE8F7F1)
                  : const Color(0xFFFFF3E8),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              g.shipGroupTypeGid,
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
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 110),
            child: Column(
              children: [
                _InfoCard(group: g, fmtDT: _fmt),
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

          // FIX: AbsorbPointer blocks all taps on the scrollable content while
          // uploading — prevents removing/previewing docs mid-upload.
          if (_isSubmitting)
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.08),
                ),
              ),
            ),

          // Sticky submit button — fixed 54px height always, always blue.
          // During upload: button becomes a progress container (no grey disabled state).
          Positioned(
            left: 14, right: 14,
            bottom: MediaQuery.of(context).padding.bottom + 14,
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
                        backgroundColor: context.watch<LeapThemeProvider>().theme.primary,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: context.watch<LeapThemeProvider>().theme.primary.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        _docs.isEmpty
                            ? '📷  Add Documents'
                            : '📤  Submit ${_docs.length} Document${_docs.length > 1 ? "s" : ""} to OTM',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700),
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: context.watch<LeapThemeProvider>().theme.navColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
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

// ─── Upload Progress Button ──────────────────────────────────────────────────
// Replaces the submit button during upload. Same 54px height, always blue,
// progress fill animates from left. No grey disabled state ever shown.

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
            // Blue base
            Container(color: t.primary),
            // Green progress fill sliding in from left
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.clamp(0.0, 1.0),
              child: Container(
                color: AppConstants.inboundGreen,
              ),
            ),
            // Spinner + text centred on top
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
                      fontWeight: FontWeight.w700,
                    ),
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

// ─── Info Card ────────────────────────────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.group, required this.fmtDT});
  final ShipmentGroup group;
  final String Function(String) fmtDT;

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
                    child: Icon(Icons.tag_rounded,
                        color: t.primary, size: 20),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('GROUP ID',
                        style: TextStyle(
                            fontSize: 10,
                            color: t.textMuted,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0)),
                    const SizedBox(height: 2),
                    Text(group.shipGroupXid,
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
          _RouteRow(from: group.displaySource, to: group.displayDest),
          Divider(height: 1, color: t.border),
          _NormalRow(
            icon: Icons.schedule_outlined,
            label: 'Planned Pickup',
            value: fmtDT(group.startTime),
          ),
          _NormalRow(
            icon: Icons.flag_outlined,
            label: 'Planned Delivery',
            value: fmtDT(group.endTime),
          ),
          _NormalRow(
            icon: Icons.inventory_2_outlined,
            label: 'Shipments',
            value: '${group.numberOfShipments}',
            valueStyle: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: t.primary,
            ),
          ),
          _NormalRow(
            icon: Icons.scale_outlined,
            label: 'Weight',
            value: group.totalWeight.isNotEmpty ? group.totalWeight : 'N/A',
          ),
          _NormalRow(
            icon: Icons.square_foot_outlined,
            label: 'Volume',
            value: group.totalVolume.isNotEmpty ? group.totalVolume : 'N/A',
            last: true,
          ),
        ],
      ),
    );
  }
}

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
                  Text('PICKUP',
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: t.textMuted,
                          letterSpacing: 0.8)),
                ]),
                const SizedBox(height: 3),
                Text(from,
                    style: TextStyle(
                        fontSize: 15,
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('DELIVERY',
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
                  ],
                ),
                const SizedBox(height: 3),
                Text(to,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A1A2E))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NormalRow extends StatelessWidget {
  const _NormalRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueStyle,
    this.last = false,
  });
  final IconData   icon;
  final String     label;
  final String     value;
  final TextStyle? valueStyle;
  final bool       last;

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LeapThemeProvider>().theme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: t.border.withValues(alpha: 0.5))),
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
                    style: valueStyle ??
                        TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: t.text)),
              ],
            ),
          ),
        ],
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
  final List<DocumentFile>    docs;
  // FIX: docResults carries per-file upload status: null=pending, true=✅, false=❌
  final List<bool?>            docResults;
  final VoidCallback?          onAdd;
  final void Function(int)?    onRemove;
  final void Function(DocumentFile) onPreview;

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
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Icon(Icons.attach_file_rounded,
                    color: t.primary, size: 18),
                const SizedBox(width: 8),
                Text('Documents',
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
                                Text('Add Document',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: t.primary)),
                                Text('Tap to upload POD, BOL, Invoice…',
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
                          // FIX: Pass per-file result so thumbnail shows ✅/❌/pending
                          uploadResult: i < docResults.length ? docResults[i] : null,
                          onTap: () => onPreview(docs[i]),
                          // FIX: onRemove is null during upload (AbsorbPointer also
                          // blocks it, but this is a second layer of safety).
                          onRemove: onRemove != null ? () => onRemove!(i) : null,
                        ),
                      ),
                      if (docs.length < AppConstants.maxDocuments && onAdd != null) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: onAdd,
                            icon: const Icon(
                                Icons.add_photo_alternate_outlined, size: 16),
                            label: Text(
                                'Add Document (${docs.length}/${AppConstants.maxDocuments})'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: t.primary,
                              side: BorderSide(
                                  color: t.primary),
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
  final DocumentFile doc;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  // FIX: null = not uploaded yet, true = success, false = failed
  final bool? uploadResult;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Image thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(doc.file, fit: BoxFit.cover),
          ),

          // During upload: subtle dim only — no spinner on thumbnails.
          // Spinner lives on the button only, keeping the UI clean.
          // After upload: ✅ green or ❌ red overlay with icon.
          if (uploadResult != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: uploadResult!
                    ? AppConstants.inboundGreen.withValues(alpha: 0.55)
                    : AppConstants.errorRed.withValues(alpha: 0.55),
                child: Center(
                  child: Icon(
                    uploadResult! ? Icons.check_circle_rounded : Icons.error_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            )
          else if (onRemove == null)
            // Uploading — just dim, spinner is on the button
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Container(
                color: Colors.black.withValues(alpha: 0.25),
              ),
            ),

          // Doc type label at bottom left
          if (uploadResult == null)
            Positioned(
              bottom: 4, left: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
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

          // Remove button — hidden during upload
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
                  child: const Icon(Icons.close, size: 10, color: Colors.white),
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
          Text('Add Documents',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: theme.primary)),
          const SizedBox(height: 4),
          Text('Select type · Camera for burst · Gallery for multi-select',
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
                      color: sel
                          ? theme.primary
                          : theme.border,
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
                  label: const Text('Take Photo'),
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
                  label: const Text('Select Multiple'),
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