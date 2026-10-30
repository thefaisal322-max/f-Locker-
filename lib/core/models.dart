import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

enum VaultTab { videos, images, music, documents, apps, zips }

extension VaultTabInfo on VaultTab {
  String get label => switch (this) {
        VaultTab.videos => 'Videos',
        VaultTab.images => 'Images',
        VaultTab.music => 'Music',
        VaultTab.documents => 'Documents',
        VaultTab.apps => 'Apps',
        VaultTab.zips => 'Zips',
      };

  String get itemWord => switch (this) {
        VaultTab.videos => 'videos',
        VaultTab.images => 'images',
        VaultTab.music => 'songs',
        VaultTab.documents => 'documents',
        VaultTab.apps => 'apps',
        VaultTab.zips => 'zips',
      };

  IconData get icon => switch (this) {
        VaultTab.videos => Icons.play_circle_outline,
        VaultTab.images => Icons.image_outlined,
        VaultTab.music => Icons.music_note_outlined,
        VaultTab.documents => Icons.description_outlined,
        VaultTab.apps => Icons.apps,
        VaultTab.zips => Icons.folder_zip_outlined,
      };

  List<String> get extensions => switch (this) {
        VaultTab.videos => const [
            'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', '3gp', 'm4v',
            'mpeg', 'mpg', 'ts'
          ],
        VaultTab.images => const [
            'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif',
            'tif', 'tiff'
          ],
        VaultTab.music => const [
            'mp3', 'wav', 'aac', 'flac', 'ogg', 'm4a', 'wma', 'opus', 'amr'
          ],
        VaultTab.documents => const [
            'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt',
            'rtf', 'csv', 'odt'
          ],
        VaultTab.apps => const [
            'apk', 'xapk', 'apks', 'exe', 'msi', 'appx', 'msix'
          ],
        VaultTab.zips => const [
            'zip', 'rar', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz'
          ],
      };
}

/// Picks the tab a received file belongs to, by its extension.
VaultTab tabForName(String name) {
  final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
  for (final t in [
    VaultTab.videos,
    VaultTab.images,
    VaultTab.music,
    VaultTab.apps,
    VaultTab.zips
  ]) {
    if (t.extensions.contains(ext)) return t;
  }
  return VaultTab.documents;
}

String safeName(String name) {
  final s = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
  return s.isEmpty ? 'file' : s;
}

class VFolder {
  VFolder(
      {required this.id,
      required this.tab,
      required this.name,
      required this.created});

  final String id;
  final VaultTab tab;
  String name;
  final int created;

  Map<String, dynamic> toJson() =>
      {'id': id, 'tab': tab.name, 'name': name, 'created': created};

  factory VFolder.fromJson(Map<String, dynamic> j) => VFolder(
        id: j['id'] as String,
        tab: VaultTab.values.byName(j['tab'] as String),
        name: j['name'] as String,
        created: j['created'] as int,
      );
}

class VItem {
  VItem(
      {required this.id,
      required this.folderId,
      required this.name,
      required this.size,
      required this.added,
      this.origin});

  final String id;
  final String folderId;
  final String name;
  final int size;
  final int added;

  /// Where the file was before it was moved into F-Locker (null for files
  /// that came through Transfer).
  final String? origin;

  Map<String, dynamic> toJson() => {
        'id': id,
        'folderId': folderId,
        'name': name,
        'size': size,
        'added': added,
        if (origin != null) 'origin': origin,
      };

  factory VItem.fromJson(Map<String, dynamic> j) => VItem(
        id: j['id'] as String,
        folderId: j['folderId'] as String,
        name: j['name'] as String,
        size: j['size'] as int,
        added: j['added'] as int,
        origin: j['origin'] as String?,
      );
}
