import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/vault.dart';
import 'theme.dart';
import 'widgets.dart';

/// Inside a folder: the locked items and the upload button.
class FolderScreen extends StatefulWidget {
  const FolderScreen({super.key, required this.vault, required this.folder});
  final Vault vault;
  final VFolder folder;

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  bool _busy = false;
  String _busyText = '';
  int _done = 0;
  int _total = 0;
  final Map<String, Future<Uint8List>> _thumbs = {};

  Vault get vault => widget.vault;
  VFolder get folder => widget.folder;

  Future<Uint8List> _thumb(VItem it) {
    final f = _thumbs.remove(it.id) ?? vault.loadBytes(it);
    _thumbs[it.id] = f;
    if (_thumbs.length > 80) _thumbs.remove(_thumbs.keys.first);
    return f;
  }

  FileType get _type => switch (folder.tab) {
        VaultTab.videos => FileType.video,
        VaultTab.images => FileType.image,
        VaultTab.music => FileType.audio,
        VaultTab.documents => FileType.any,
        VaultTab.apps || VaultTab.zips =>
          Platform.isAndroid ? FileType.any : FileType.custom,
      };

  Future<void> _upload() async {
    final type = _type;
    FilePickerResult? r;
    try {
      r = await vault.withoutAutoLock(() => FilePicker.platform.pickFiles(
          allowMultiple: true,
          type: type,
          allowedExtensions:
              type == FileType.custom ? folder.tab.extensions : null,
          lockParentWindow: true));
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open the files: $e');
      return;
    }
    final paths =
        r?.files.map((f) => f.path).whereType<String>().toList() ?? <String>[];
    if (paths.isEmpty || !mounted) return;
    setState(() {
      _busy = true;
      _busyText = 'Locking';
      _done = 0;
      _total = paths.length;
    });
    final n = await vault.withoutAutoLock(() => vault.addFiles(folder, paths,
        deleteSources: Platform.isWindows && vault.deleteOriginals,
        onProgress: (d) {
      if (mounted) setState(() => _done = d);
    }));
    if (Platform.isAndroid) {
      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _busy = false);
    final word = n == 1 ? 'file' : 'files';
    showSnack(
        context,
        n == paths.length
            ? 'Locked $n $word.'
            : 'Locked $n of ${paths.length} files. Some could not be read.');
  }

  Future<void> _run(String text, Future<void> Function() job,
      {int total = 0}) async {
    setState(() {
      _busy = true;
      _busyText = text;
      _done = 0;
      _total = total;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) showSnack(context, '$text failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(VItem it, List<VItem> all) async {
    if (folder.tab == VaultTab.images) {
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ImageViewer(
              vault: vault, items: all, initial: all.indexOf(it))));
      return;
    }
    await _run('Opening', () async {
      final path = await vault.decryptToTemp(it);
      await vault.withoutAutoLock(() => openExternal(path));
    });
  }

  Future<void> _export(List<VItem> list, {required bool remove}) async {
    if (list.isEmpty) return;
    final dir = await vault.withoutAutoLock(() => FilePicker.platform
        .getDirectoryPath(
            dialogTitle: 'Choose where to put the files',
            lockParentWindow: true));
    if (dir == null || !mounted) return;
    var ok = 0;
    await _run(remove ? 'Restoring' : 'Saving', () async {
      for (final it in list) {
        await vault.exportItem(it, dir);
        if (remove) await vault.deleteItems([it]);
        ok++;
        if (mounted) setState(() => _done = ok);
      }
    }, total: list.length);
    if (mounted && ok > 0) {
      showSnack(context, '$ok ${ok == 1 ? 'file' : 'files'} put in $dir');
    }
  }

  Future<void> _delete(VItem it) async {
    final ok = await askConfirm(context,
        title: 'Delete "${it.name}"?',
        message:
            'It is removed from F-Locker for good. Restore it first if you want to keep a copy.');
    if (ok) await vault.deleteItems([it]);
  }

  Future<void> _deleteFolder() async {
    final n = vault.itemsOf(folder.id).length;
    final ok = await askConfirm(context,
        title: 'Delete "${folder.name}"?',
        message: n == 0
            ? 'This empty folder will be removed.'
            : 'This folder and the $n ${folder.tab.itemWord} in it are deleted for good.');
    if (!ok) return;
    await vault.deleteFolder(folder);
    if (mounted) Navigator.of(context).pop();
  }

  void _itemSheet(VItem it, List<VItem> all) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: C.surface,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(it.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${formatBytes(it.size)} · ${formatDate(it.added)}'),
          ),
          ListTile(
              leading: const Icon(Icons.open_in_new),
              title: const Text('Open'),
              onTap: () {
                Navigator.pop(ctx);
                _open(it, all);
              }),
          ListTile(
              leading: const Icon(Icons.copy_all_outlined),
              title: const Text('Save a copy outside the locker'),
              onTap: () {
                Navigator.pop(ctx);
                _export([it], remove: false);
              }),
          ListTile(
              leading: const Icon(Icons.lock_open_outlined),
              title: const Text('Restore (unlock and remove from locker)'),
              onTap: () {
                Navigator.pop(ctx);
                _export([it], remove: true);
              }),
          ListTile(
              leading: const Icon(Icons.delete_outline, color: C.danger),
              title: const Text('Delete', style: TextStyle(color: C.danger)),
              onTap: () {
                Navigator.pop(ctx);
                _delete(it);
              }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: vault,
        builder: (context, _) {
          final items = vault.itemsOf(folder.id);
          return Scaffold(
            appBar: AppBar(
              title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(folder.tab.label,
                        style: const TextStyle(fontSize: 13, color: C.muted)),
                    Text(folder.name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                  ]),
              actions: [
                PopupMenuButton<String>(
                  tooltip: 'Folder options',
                  onSelected: (v) => v == 'restore'
                      ? _export(items, remove: true)
                      : _deleteFolder(),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                        value: 'restore', child: Text('Restore everything')),
                    PopupMenuItem(value: 'delete', child: Text('Delete folder')),
                  ],
                ),
              ],
            ),
            body: Column(children: [
              Container(
                margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                    color: C.accentBg, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.verified_user_outlined,
                      size: 18, color: C.accentText),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          '${items.length} ${folder.tab.itemWord} · AES-256 encrypted · no limit',
                          style: const TextStyle(
                              fontSize: 13, color: C.accentText))),
                ]),
              ),
              Expanded(
                  child: items.isEmpty
                      ? _empty()
                      : folder.tab == VaultTab.images
                          ? _grid(items)
                          : _list(items)),
            ]),
            bottomNavigationBar: SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: const BoxDecoration(
                    color: C.surface,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(22))),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_busy) ...[
                    Row(children: [
                      Expanded(
                          child: Text(
                              '$_busyText${_total > 0 ? ' $_done of $_total' : ''}…')),
                      if (_total > 0)
                        Text('${(_done * 100 / _total).round()}%',
                            style: const TextStyle(color: C.muted)),
                    ]),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                          minHeight: 6,
                          value: _total > 0 ? _done / _total : null,
                          backgroundColor: C.border),
                    ),
                    const SizedBox(height: 14),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _upload,
                      icon: const Icon(Icons.upload),
                      label: Text('Upload ${folder.tab.itemWord}'),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      );

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(folder.tab.icon, size: 48, color: C.muted),
            const SizedBox(height: 14),
            const Text('This folder is empty',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Tap Upload to lock ${folder.tab.itemWord} here.',
                style: const TextStyle(color: C.muted)),
          ]),
        ),
      );

  Widget _grid(List<VItem> items) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150, mainAxisSpacing: 4, crossAxisSpacing: 4),
        itemCount: items.length,
        itemBuilder: (context, i) {
          final it = items[i];
          return Material(
            color: C.surface,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _open(it, items),
              onLongPress: () => _itemSheet(it, items),
              child: FutureBuilder<Uint8List>(
                future: _thumb(it),
                builder: (context, snap) {
                  final data = snap.data;
                  if (data != null) {
                    return Image.memory(data,
                        fit: BoxFit.cover,
                        cacheWidth: 300,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => const Center(
                            child: Icon(Icons.broken_image_outlined,
                                color: C.muted)));
                  }
                  return Center(
                      child: Icon(
                          snap.hasError
                              ? Icons.error_outline
                              : Icons.lock_outline,
                          color: C.muted));
                },
              ),
            ),
          );
        },
      );

  Widget _list(List<VItem> items) => ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final it = items[i];
          return Material(
            color: C.surface,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _open(it, items),
              onLongPress: () => _itemSheet(it, items),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                child: Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: C.accentBg,
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(folder.tab.icon, color: C.accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(it.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text(
                              '${formatBytes(it.size)} · ${formatDate(it.added)}',
                              style: const TextStyle(
                                  fontSize: 12, color: C.muted)),
                        ]),
                  ),
                  IconButton(
                      tooltip: 'Options',
                      icon: const Icon(Icons.more_vert, color: C.muted2),
                      onPressed: () => _itemSheet(it, items)),
                ]),
              ),
            ),
          );
        },
      );
}

/// Full-screen image viewer that decrypts in memory only.
class ImageViewer extends StatefulWidget {
  const ImageViewer(
      {super.key,
      required this.vault,
      required this.items,
      required this.initial});
  final Vault vault;
  final List<VItem> items;
  final int initial;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer> {
  late final PageController _pc =
      PageController(initialPage: widget.initial < 0 ? 0 : widget.initial);
  late int _i = widget.initial < 0 ? 0 : widget.initial;
  final Map<int, Future<Uint8List>> _cache = {};

  Future<Uint8List> _load(int i) =>
      _cache.putIfAbsent(i, () => widget.vault.loadBytes(widget.items[i]));

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text(widget.items[_i].name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16))),
        body: PageView.builder(
          controller: _pc,
          itemCount: widget.items.length,
          onPageChanged: (i) => setState(() {
            _i = i;
            _cache.removeWhere((k, _) => (k - i).abs() > 2);
          }),
          itemBuilder: (context, i) => FutureBuilder<Uint8List>(
            future: _load(i),
            builder: (context, s) {
              final data = s.data;
              if (data != null) {
                return InteractiveViewer(
                  maxScale: 6,
                  child: Center(
                      child: Image.memory(data,
                          errorBuilder: (_, __, ___) => const Text(
                              'This image cannot be shown.',
                              style: TextStyle(color: C.muted)))),
                );
              }
              if (s.hasError) {
                return const Center(
                    child: Text('Could not open this image.',
                        style: TextStyle(color: C.muted)));
              }
              return const Center(child: CircularProgressIndicator());
            },
          ),
        ),
      );
}
