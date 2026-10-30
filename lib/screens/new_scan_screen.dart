import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../api.dart';
import '../session.dart';
import '../theme.dart';
import '../uploader.dart';
import '../widgets.dart';

const minPhotos = 8; // a full 3D object; a flat carving needs just one straight-on photo

class NewScanScreen extends StatefulWidget {
  const NewScanScreen({super.key, required this.session});
  final Session session;

  @override
  State<NewScanScreen> createState() => _NewScanScreenState();
}

class _NewScanScreenState extends State<NewScanScreen> {
  final _picker = ImagePicker();
  final _width = TextEditingController();
  String _kind = 'photos';
  String _shape = 'relief'; // relief = flat carving, full = 3D object
  String _quality = 'normal';
  final List<String> _paths = [];
  List<CatalogItem> _items = const [];
  List<RestorationRef> _restorations = const [];
  String? _itemId;
  String? _restorationId;
  bool _gcode = false;
  String? _error;
  double? _progress;
  String? _unfinishedScan; // set when an upload failed, so "Try again" resumes it
  List<CaptureFile> _unfinishedFiles = const [];

  @override
  void initState() {
    super.initState();
    if (widget.session.isStaffLead) {
      widget.session.api.items().then((v) {
        if (mounted) setState(() => _items = v);
      }).catchError((_) {});
    }
    if (widget.session.canRestore) {
      widget.session.api.restorations().then((v) {
        if (mounted) setState(() => _restorations = v);
      }).catchError((_) {});
    }
  }

  /// Edit the chosen files. A half-sent scan was made for the old files, so it can
  /// no longer be resumed: the next Upload starts a new scan.
  void _edit(VoidCallback change) => setState(() {
        change();
        _unfinishedScan = null;
        _unfinishedFiles = const [];
      });

  void _switchKind(String k) => _edit(() {
        _kind = k;
        _paths.clear();
        _error = null;
      });

  Future<void> _takePhoto() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 92);
    if (x != null) _edit(() => _paths.add(x.path));
  }

  Future<void> _pickPhotos() async {
    final xs = await _picker.pickMultiImage(imageQuality: 92);
    if (xs.isNotEmpty) _edit(() => _paths.addAll(xs.map((x) => x.path)));
  }

  Future<void> _video(ImageSource src) async {
    final x = await _picker.pickVideo(source: src, maxDuration: const Duration(seconds: 90));
    if (x != null) _edit(() => _paths..clear()..add(x.path));
  }

  Future<void> _upload() async {
    final files = [for (final p in _paths) CaptureFile(p, File(p).lengthSync())];
    final problem = captureProblem(_kind, _shape, files);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    final width = double.tryParse(_width.text.trim());
    if (_width.text.trim().isNotEmpty && (width == null || width <= 0 || width > 5000)) {
      setState(() => _error = 'The real width must be between 1 and 5000 mm.');
      return;
    }
    if (_gcode && width == null) {
      setState(() => _error = 'G-code needs the real width of the piece. Measure it and enter it.');
      return;
    }
    setState(() {
      _error = null;
      _progress = 0;
    });
    final uploader = ScanUploader(widget.session.api);
    void onProgress(double f) => mounted ? setState(() => _progress = f) : null;
    try {
      if (_unfinishedScan != null) {
        await uploader.resume(_unfinishedScan!, _unfinishedFiles, onProgress: onProgress);
      } else {
        await uploader.upload(
          kind: _kind,
          files: files,
          itemId: _restorationId == null ? _itemId : null,
          restorationId: _restorationId,
          realWidthMm: width,
          quality: _quality,
          gcode: _gcode,
          shape: _shape,
          onProgress: onProgress,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Uploaded. The workshop PC will pick it up.')));
      Navigator.of(context).pop(true);
    } on UploadFailed catch (e) {
      _unfinishedScan = e.scanId;
      _unfinishedFiles = files;
      if (mounted) setState(() => _error = '${e.reason} Tap Upload to try again.');
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uploading = _progress != null;
    final isPhotos = _kind == 'photos';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: const BrandAppBar(title: 'New scan', back: true),
      bottomNavigationBar: ActionBar(
        child: uploading
            ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                LinearProgressIndicator(
                  value: _progress,
                  color: brandBrown,
                  backgroundColor: lineColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 8),
                Text('Uploading ${(100 * (_progress ?? 0)).round()}%. Keep the app open.'),
              ])
            : FilledButton.icon(
                onPressed: _upload,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(_unfinishedScan != null ? 'Try again' : 'Upload'),
              ),
      ),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'relief', label: Text('Flat carving'), icon: Icon(Icons.crop_portrait)),
            ButtonSegment(value: 'full', label: Text('Full 3D object'), icon: Icon(Icons.view_in_ar_outlined)),
          ],
          selected: {_shape},
          onSelectionChanged: uploading ? null : (s) => setState(() => _shape = s.first),
        ),
        const SizedBox(height: 10),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'photos', label: Text('Photos'), icon: Icon(Icons.photo_camera_outlined)),
            ButtonSegment(value: 'video', label: Text('Video'), icon: Icon(Icons.videocam_outlined)),
          ],
          selected: {_kind},
          onSelectionChanged: uploading ? null : (s) => _switchKind(s.first),
        ),
        const SizedBox(height: 14),
        WarmCard(
          child: Text(_shape == 'relief'
              ? 'Stand straight in front of the carving, keep it flat to the camera and take one sharp photo in even light '
                  '(more are fine: the sharpest is used). Any PC can build this in a minute or two. The depth is '
                  'estimated, so enter the real width.'
              : isPhotos
                  ? 'Walk slowly around the piece and take $minPhotos or more photos, each overlapping the last. '
                      'Use even light, keep the whole piece in frame, and avoid shiny glare. '
                      'This waits for a PC with an NVIDIA graphics card.'
                  : 'Record one slow walk-around, up to 90 seconds. Keep the whole piece in frame '
                      'and move steadily. Even light works best. This waits for a PC with an NVIDIA graphics card.'),
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (isPhotos) ...[
            FilledButton.icon(
                onPressed: uploading ? null : _takePhoto,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Take photo')),
            OutlinedButton.icon(
                onPressed: uploading ? null : _pickPhotos,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose photos')),
          ] else ...[
            FilledButton.icon(
                onPressed: uploading ? null : () => _video(ImageSource.camera),
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Record video')),
            OutlinedButton.icon(
                onPressed: uploading ? null : () => _video(ImageSource.gallery),
                icon: const Icon(Icons.video_library_outlined),
                label: const Text('Choose video')),
          ],
        ]),
        const SizedBox(height: 10),
        Text(
          isPhotos
              ? '${_paths.length} photo${_paths.length == 1 ? '' : 's'} chosen'
              : (_paths.isEmpty ? 'No video chosen' : 'Video chosen'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        if (isPhotos && _paths.isNotEmpty) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 76,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _paths.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(children: [
                  Image.file(File(_paths[i]), width: 76, height: 76, fit: BoxFit.cover, cacheWidth: 152),
                  Positioned(
                    right: 0,
                    top: 0,
                    child: InkWell(
                      onTap: uploading ? null : () => _edit(() => _paths.removeAt(i)),
                      child: const Icon(Icons.cancel, size: 20, color: Colors.white),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ],
        const SizedBox(height: 18),
        TextField(
          controller: _width,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          enabled: !uploading,
          decoration: const InputDecoration(
            labelText: 'Real width of the piece (mm), optional',
            helperText: 'Measure it with a tape. It sets the true size of the 3D model.',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _quality,
          decoration: const InputDecoration(labelText: 'Quality'),
          items: const [
            DropdownMenuItem(value: 'fast', child: Text('Fast (rough shape)')),
            DropdownMenuItem(value: 'normal', child: Text('Normal')),
            DropdownMenuItem(value: 'high', child: Text('High (slower)')),
          ],
          onChanged: uploading ? null : (v) => setState(() => _quality = v ?? 'normal'),
        ),
        if (widget.session.canRestore && _restorations.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _restorationId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Temple restoration (optional)',
              helperText: 'Pick one to keep this scan with that restoration. Only the owner and artisans see it.',
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Not for a restoration')),
              for (final r in _restorations)
                DropdownMenuItem<String?>(value: r.id, child: Text(r.label)),
            ],
            onChanged: uploading ? null : (v) => setState(() => _restorationId = v),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Also make CNC G-code (flat carvings; needs the width)'),
            value: _gcode,
            onChanged: uploading ? null : (v) => setState(() => _gcode = v ?? false),
          ),
        ],
        if (widget.session.isStaffLead && _items.isNotEmpty && _restorationId == null) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _itemId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Product (optional)'),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Choose later')),
              for (final i in _items)
                DropdownMenuItem<String?>(value: i.id, child: Text('${i.name}  (${i.sku})')),
            ],
            onChanged: uploading ? null : (v) => setState(() => _itemId = v),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: badRed)),
        ],
      ]),
    );
  }
}
