import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/vault.dart';
import 'folder_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// One of the six content tabs: a list of folders. A folder must exist
/// before anything can be uploaded.
class TabView extends StatelessWidget {
  const TabView({super.key, required this.vault, required this.tab});
  final Vault vault;
  final VaultTab tab;

  Future<void> _newFolder(BuildContext context) async {
    final name = await askText(context,
        title: 'New ${tab.label.toLowerCase()} folder', label: 'Folder name');
    if (name == null || !context.mounted) return;
    final err = await vault.createFolder(tab, name);
    if (err != null && context.mounted) showSnack(context, err);
  }

  Future<void> _rename(BuildContext context, VFolder f) async {
    final name = await askText(context,
        title: 'Rename folder',
        label: 'Folder name',
        initial: f.name,
        action: 'Rename');
    if (name == null || !context.mounted) return;
    final err = await vault.renameFolder(f, name);
    if (err != null && context.mounted) showSnack(context, err);
  }

  Future<void> _delete(BuildContext context, VFolder f) async {
    final n = vault.itemsOf(f.id).length;
    final ok = await askConfirm(context,
        title: 'Delete "${f.name}"?',
        message: n == 0
            ? 'This empty folder will be removed.'
            : 'This folder and the $n ${tab.itemWord} in it are deleted for good. '
                'Restore them first if you want to keep them.');
    if (ok) await vault.deleteFolder(f);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: vault,
        builder: (context, _) {
          final fs = vault.foldersOf(tab);
          return Scaffold(
            backgroundColor: Colors.transparent,
            floatingActionButton: FloatingActionButton.extended(
              heroTag: 'new-folder-${tab.name}',
              backgroundColor: C.accent,
              foregroundColor: C.bg,
              onPressed: () => _newFolder(context),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('New folder',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            body: fs.isEmpty
                ? _Empty(tab: tab)
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                        child: Row(children: [
                          Expanded(
                              child: Text('${tab.label} folders',
                                  style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700))),
                          Text(
                              '${vault.countInTab(tab)} ${tab.itemWord} · no limit',
                              style: const TextStyle(
                                  fontSize: 13, color: C.muted)),
                        ]),
                      ),
                      for (final f in fs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _FolderCard(
                            folder: f,
                            count: vault.itemsOf(f.id).length,
                            word: tab.itemWord,
                            onOpen: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                    builder: (_) => FolderScreen(
                                        vault: vault, folder: f))),
                            onRename: () => _rename(context, f),
                            onDelete: () => _delete(context, f),
                          ),
                        ),
                    ],
                  ),
          );
        },
      );
}

class _FolderCard extends StatelessWidget {
  const _FolderCard(
      {required this.folder,
      required this.count,
      required this.word,
      required this.onOpen,
      required this.onRename,
      required this.onDelete});
  final VFolder folder;
  final int count;
  final String word;
  final VoidCallback onOpen, onRename, onDelete;

  @override
  Widget build(BuildContext context) => Material(
        color: C.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: C.accentBg, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.folder_outlined,
                    color: C.accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(folder.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text('$count $word',
                          style:
                              const TextStyle(fontSize: 13, color: C.muted)),
                    ]),
              ),
              PopupMenuButton<String>(
                tooltip: 'Folder options',
                icon: const Icon(Icons.more_vert, color: C.muted2),
                onSelected: (v) => v == 'rename' ? onRename() : onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ]),
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.tab});
  final VaultTab tab;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(40, 0, 40, 80),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                  color: C.surface, borderRadius: BorderRadius.circular(26)),
              child: const Icon(Icons.folder_outlined, size: 40, color: C.muted),
            ),
            const SizedBox(height: 16),
            const Text('No folders yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
                'Create a folder first. Then you can upload ${tab.itemWord} into it.'
                '${tab == VaultTab.apps ? ' Lock app files such as .apk and .exe here.' : ''}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: C.muted, height: 1.5)),
          ]),
        ),
      );
}
