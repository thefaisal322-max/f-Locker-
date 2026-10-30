import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../core/device.dart';
import '../core/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Android: shows the phone's files of one kind, grouped by folder like a
/// gallery, and returns the real paths the person picked. Using real paths
/// (not copies) is what lets F-Locker move the originals and restore them.
class DevicePicker extends StatefulWidget {
  const DevicePicker({super.key, required this.tab});
  final VaultTab tab;

  @override
  State<DevicePicker> createState() => _DevicePickerState();
}

class _DevicePickerState extends State<DevicePicker> {
  List<MapEntry<String, List<FoundFile>>>? _albums;
  String? _root;
  String? _error;
  int? _open;
  final Set<String> _sel = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final root = await Device.storageRoot();
      final albums = await scanStorage(root, widget.tab.extensions);
      if (!mounted) return;
      setState(() {
        _root = root;
        _albums = albums;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  String _albumName(String dir) {
    final root = _root;
    if (root != null && p.equals(dir, root)) return 'Phone storage';
    return p.basename(dir);
  }

  String _albumPath(String dir) {
    final root = _root;
    if (root == null) return dir;
    final rel = p.relative(dir, from: root);
    return rel == '.' ? 'Phone storage' : rel;
  }

  bool get _isImages => widget.tab == VaultTab.images;

  void _toggle(String path) => setState(() {
        if (!_sel.remove(path)) _sel.add(path);
      });

  @override
  Widget build(BuildContext context) {
    final albums = _albums;
    final open = _open;
    final inAlbum = albums != null && open != null;
    final files = inAlbum ? albums[open].value : const <FoundFile>[];
    final allSelected = inAlbum && files.every((f) => _sel.contains(f.path));

    return PopScope(
      canPop: !inAlbum,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && inAlbum) setState(() => _open = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(inAlbum
              ? _albumName(albums[open].key)
              : 'Choose ${widget.tab.itemWord}'),
          actions: [
            if (inAlbum)
              TextButton(
                onPressed: () => setState(() {
                  if (allSelected) {
                    for (final f in files) {
                      _sel.remove(f.path);
                    }
                  } else {
                    _sel.addAll(files.map((f) => f.path));
                  }
                }),
                child: Text(allSelected ? 'Select none' : 'Select all'),
              ),
          ],
        ),
        body: _error != null
            ? Center(
                child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text('Could not read the phone storage.\n$_error',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: C.muted))))
            : albums == null
                ? const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 14),
                    Text('Looking through your phone…',
                        style: TextStyle(color: C.muted)),
                  ]))
                : albums.isEmpty
                    ? Center(
                        child: Text('No ${widget.tab.itemWord} found on this phone.',
                            style: const TextStyle(color: C.muted)))
                    : inAlbum
                        ? (_isImages ? _imageGrid(files) : _fileList(files))
                        : _albumList(albums),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: _sel.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_sel.toList()),
              icon: const Icon(Icons.lock_outline),
              label: Text(_sel.isEmpty
                  ? 'Pick ${widget.tab.itemWord} to move in'
                  : 'Move ${_sel.length} into F-Locker'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _albumList(List<MapEntry<String, List<FoundFile>>> albums) =>
      ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: albums.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final a = albums[i];
          final picked = a.value.where((f) => _sel.contains(f.path)).length;
          return Material(
            color: C.surface,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => setState(() => _open = i),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: _isImages
                          ? Image.file(File(a.value.first.path),
                              fit: BoxFit.cover,
                              cacheWidth: 160,
                              errorBuilder: (_, __, ___) => _iconBox())
                          : _iconBox(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_albumName(a.key),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text(_albumPath(a.key),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: C.muted)),
                        ]),
                  ),
                  const SizedBox(width: 8),
                  Text(
                      picked > 0
                          ? '$picked / ${a.value.length}'
                          : '${a.value.length}',
                      style: TextStyle(
                          color: picked > 0 ? C.accent : C.muted,
                          fontWeight: FontWeight.w500)),
                  const Icon(Icons.chevron_right, color: C.muted),
                ]),
              ),
            ),
          );
        },
      );

  Widget _iconBox() => Container(
      color: C.accentBg,
      child: Icon(widget.tab.icon, color: C.accent));

  Widget _imageGrid(List<FoundFile> files) => GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 130, mainAxisSpacing: 3, crossAxisSpacing: 3),
        itemCount: files.length,
        itemBuilder: (context, i) {
          final f = files[i];
          final on = _sel.contains(f.path);
          return GestureDetector(
            onTap: () => _toggle(f.path),
            child: Stack(fit: StackFit.expand, children: [
              Image.file(File(f.path),
                  fit: BoxFit.cover,
                  cacheWidth: 260,
                  errorBuilder: (_, __, ___) => _iconBox()),
              if (on) Container(color: C.accent.withValues(alpha: 0.35)),
              Positioned(
                top: 6,
                right: 6,
                child: Icon(on ? Icons.check_circle : Icons.circle_outlined,
                    color: on ? C.accent : Colors.white, size: 24),
              ),
            ]),
          );
        },
      );

  Widget _fileList(List<FoundFile> files) => ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: files.length,
        itemBuilder: (context, i) {
          final f = files[i];
          return CheckboxListTile(
            value: _sel.contains(f.path),
            onChanged: (_) => _toggle(f.path),
            secondary: Icon(widget.tab.icon, color: C.accent),
            title: Text(p.basename(f.path),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
                '${formatBytes(f.size)} · ${formatDate(f.modified)}',
                style: const TextStyle(fontSize: 12, color: C.muted)),
          );
        },
      );
}
