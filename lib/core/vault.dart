import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'crypto.dart';
import 'device.dart';
import 'models.dart';

/// Everything F-Locker keeps: settings, the encrypted index of folders and
/// items, and one encrypted blob per locked file.
///
/// On Windows the data lives in a "FLockerData" folder next to F-Locker.exe,
/// so the app runs from a USB stick without being installed.
class Vault extends ChangeNotifier {
  late Directory root;
  Map<String, dynamic>? _config;
  Uint8List? _master;
  List<VFolder> folders = [];
  List<VItem> items = [];

  /// True after unlocking with the recovery key: a new password is required.
  bool mustResetPassword = false;

  /// A new recovery key the person still has to see and save.
  String? pendingRecoveryKey;

  int _hold = 0;
  int _running = 0;
  final List<Completer<void>> _waiting = [];
  Future<void> _saveChain = Future<void>.value();

  static const int _iterations = 120000;
  static const List<int> autoLockChoices = [0, 1, 5, 15, -1];

  File get _configFile => File(p.join(root.path, 'config.json'));
  File get _indexFile => File(p.join(root.path, 'index.bin'));
  Directory get blobDir => Directory(p.join(root.path, 'blobs'));
  Directory get tempDir => Directory(p.join(root.path, 'temp'));
  String blobPath(String id) => p.join(blobDir.path, '$id.flk');

  bool get isSetUp => _config != null;
  bool get isUnlocked => _master != null;
  bool get autoLockHeld => _hold > 0;

  Map<String, dynamic> get _settings =>
      (_config!['settings'] as Map<String, dynamic>?) ??
      (_config!['settings'] = <String, dynamic>{});

  int get autoLockMinutes {
    final v = _settings['autoLockMinutes'];
    return (v is int && autoLockChoices.contains(v)) ? v : 1;
  }

  Future<void> setAutoLock(int minutes) async {
    _settings['autoLockMinutes'] = minutes;
    await _saveConfig();
    notifyListeners();
  }

  /// Runs [job] (a file picker, opening a file, a long upload) without the
  /// app locking itself because it went to the background meanwhile.
  Future<T> withoutAutoLock<T>(Future<T> Function() job) async {
    _hold++;
    try {
      return await job();
    } finally {
      _hold--;
    }
  }

  // ---------------------------------------------------------------- start

  Future<void> init() async {
    root = await _resolveRoot();
    await blobDir.create(recursive: true);
    await _wipeTemp();
    if (await _configFile.exists()) {
      _config = jsonDecode(await _configFile.readAsString())
          as Map<String, dynamic>;
    }
  }

  static Future<Directory> _resolveRoot() async {
    if (Platform.isWindows) {
      // FLOCKER_HOME is set by the single-file F-Locker.exe launcher to the
      // folder it sits in, so the data stays next to the file you clicked.
      final home = Platform.environment['FLOCKER_HOME'] ??
          File(Platform.resolvedExecutable).parent.path;
      final d = Directory(p.join(home, 'FLockerData'));
      try {
        await d.create(recursive: true);
        final probe = File(p.join(d.path, '.write-test'));
        await probe.writeAsString('ok');
        await probe.delete();
        Device.hideOnWindows(d.path);
        return d;
      } catch (_) {
        // The folder is read-only (for example Program Files); fall back.
      }
    }
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'vault'));
    await d.create(recursive: true);
    return d;
  }

  // ------------------------------------------------------------ passwords

  Future<void> setup(String password) async {
    final master = randomBytes(32);
    final rk = newRecoveryKey();
    _config = <String, dynamic>{
      'v': 1,
      'iterations': _iterations,
      'settings': <String, dynamic>{'autoLockMinutes': 1},
    };
    await _wrap(master, password, 'pw');
    await _wrap(master, rk, 'rk');
    await _saveConfig();
    _master = master;
    folders = [];
    items = [];
    await _saveIndex();
    pendingRecoveryKey = rk;
    notifyListeners();
  }

  Future<void> _wrap(Uint8List master, String secret, String prefix) async {
    final salt = randomBytes(16);
    final it = _config!['iterations'] as int;
    final kek = await deriveKeyIsolate(secret, salt, it);
    _config!['${prefix}Salt'] = base64Encode(salt);
    _config!['${prefix}Wrapped'] = base64Encode(await sealBytes(master, kek));
  }

  Future<Uint8List> _unwrap(String secret, String prefix) async {
    final salt = base64Decode(_config!['${prefix}Salt'] as String);
    final it = _config!['iterations'] as int;
    final kek = await deriveKeyIsolate(secret, salt, it);
    return openBytes(base64Decode(_config!['${prefix}Wrapped'] as String), kek);
  }

  Future<bool> unlock(String password) async {
    try {
      _master = await _unwrap(password, 'pw');
    } on WrongSecret {
      return false;
    }
    await _loadIndex();
    notifyListeners();
    return true;
  }

  /// Opens the locker with the 10-letter key. A new password must follow.
  Future<bool> unlockWithRecovery(String key) async {
    final k = normalizeRecoveryKey(key);
    if (k.length != 10) return false;
    try {
      _master = await _unwrap(k, 'rk');
    } on WrongSecret {
      return false;
    }
    await _loadIndex();
    mustResetPassword = true;
    notifyListeners();
    return true;
  }

  /// After a recovery: sets the new password and replaces the used key.
  Future<void> setNewPassword(String password) async {
    final rk = newRecoveryKey();
    await _wrap(_master!, password, 'pw');
    await _wrap(_master!, rk, 'rk');
    await _saveConfig();
    mustResetPassword = false;
    pendingRecoveryKey = rk;
    notifyListeners();
  }

  Future<bool> changePassword(String current, String next) async {
    try {
      await _unwrap(current, 'pw');
    } on WrongSecret {
      return false;
    }
    await _wrap(_master!, next, 'pw');
    await _saveConfig();
    return true;
  }

  Future<bool> regenerateRecoveryKey(String password) async {
    try {
      await _unwrap(password, 'pw');
    } on WrongSecret {
      return false;
    }
    final rk = newRecoveryKey();
    await _wrap(_master!, rk, 'rk');
    await _saveConfig();
    pendingRecoveryKey = rk;
    notifyListeners();
    return true;
  }

  void acknowledgeRecoveryKey() {
    pendingRecoveryKey = null;
    notifyListeners();
  }

  Future<void> lock() async {
    if (_master == null) return;
    _master = null;
    folders = [];
    items = [];
    mustResetPassword = false;
    pendingRecoveryKey = null;
    notifyListeners();
    await _wipeTemp();
  }

  // ---------------------------------------------------------------- index

  Future<void> _loadIndex() async {
    if (!await _indexFile.exists()) {
      folders = [];
      items = [];
      return;
    }
    final clear = await openBytes(await _indexFile.readAsBytes(), _master!);
    final j = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    folders = (j['folders'] as List)
        .map((e) => VFolder.fromJson(e as Map<String, dynamic>))
        .toList();
    items = (j['items'] as List)
        .map((e) => VItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> _saveIndex() {
    final next = _saveChain.then((_) => _writeIndex());
    _saveChain = next.catchError((Object _) {});
    return next;
  }

  Future<void> _writeIndex() async {
    final key = _master;
    if (key == null) return;
    final j = {
      'folders': folders.map((f) => f.toJson()).toList(),
      'items': items.map((i) => i.toJson()).toList(),
    };
    await _writeAtomic(
        _indexFile, await sealBytes(utf8.encode(jsonEncode(j)), key));
  }

  Future<void> _saveConfig() => _writeAtomic(_configFile,
      utf8.encode(const JsonEncoder.withIndent('  ').convert(_config)));

  static Future<void> _writeAtomic(File f, List<int> bytes) async {
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      await tmp.rename(f.path);
    } on FileSystemException {
      if (await f.exists()) await f.delete();
      await tmp.rename(f.path);
    }
  }

  Future<void> _wipeTemp() async {
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } catch (_) {
      // A file may still be open in another app; it is removed next time.
    }
  }

  // -------------------------------------------------------------- folders

  List<VFolder> foldersOf(VaultTab tab) => folders
      .where((f) => f.tab == tab)
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  List<VItem> itemsOf(String folderId) =>
      items.where((i) => i.folderId == folderId).toList()
        ..sort((a, b) => b.added.compareTo(a.added));

  int countInTab(VaultTab tab) {
    final ids = folders.where((f) => f.tab == tab).map((f) => f.id).toSet();
    return items.where((i) => ids.contains(i.folderId)).length;
  }

  int get totalBytes => items.fold(0, (s, i) => s + i.size);

  Future<String?> createFolder(VaultTab tab, String name) async {
    final n = name.trim();
    if (n.isEmpty) return 'Type a folder name.';
    if (foldersOf(tab).any((f) => f.name.toLowerCase() == n.toLowerCase())) {
      return 'A folder named "$n" already exists here.';
    }
    folders.add(VFolder(
        id: newId(),
        tab: tab,
        name: n,
        created: DateTime.now().millisecondsSinceEpoch));
    await _saveIndex();
    notifyListeners();
    return null;
  }

  Future<String?> renameFolder(VFolder f, String name) async {
    final n = name.trim();
    if (n.isEmpty) return 'Type a folder name.';
    if (foldersOf(f.tab).any(
        (o) => o.id != f.id && o.name.toLowerCase() == n.toLowerCase())) {
      return 'A folder named "$n" already exists here.';
    }
    f.name = n;
    await _saveIndex();
    notifyListeners();
    return null;
  }

  Future<VFolder> folderNamed(VaultTab tab, String name) async {
    for (final f in foldersOf(tab)) {
      if (f.name.toLowerCase() == name.toLowerCase()) return f;
    }
    await createFolder(tab, name);
    return foldersOf(tab).firstWhere((f) => f.name == name);
  }

  Future<void> deleteFolder(VFolder f) async {
    for (final it in itemsOf(f.id)) {
      await _deleteBlob(it.id);
    }
    items.removeWhere((i) => i.folderId == f.id);
    folders.removeWhere((x) => x.id == f.id);
    await _saveIndex();
    notifyListeners();
  }

  // ---------------------------------------------------------------- items

  /// Moves files into [folder]: each file is encrypted, then removed from
  /// where it was. There is no limit on how many.
  /// [moved] lists the original paths that were removed.
  Future<({int locked, List<String> moved})> addFiles(
      VFolder folder, List<String> paths,
      {void Function(int processed)? onProgress}) async {
    var locked = 0;
    var processed = 0;
    final moved = <String>[];
    for (final path in paths) {
      if (!isUnlocked) break;
      final id = newId();
      final out = blobPath(id);
      try {
        final size = await File(path).length();
        await encryptFileIsolate(path, out, _master!);
        items.add(VItem(
            id: id,
            folderId: folder.id,
            name: safeName(p.basename(path)),
            size: size,
            added: DateTime.now().millisecondsSinceEpoch,
            origin: File(path).absolute.path));
        await _saveIndex();
        locked++;
        try {
          await File(path).delete();
          moved.add(path);
        } catch (_) {
          // In use or no permission: the file is locked but the original stays.
        }
      } catch (_) {
        await _deleteFile(out);
      }
      processed++;
      onProgress?.call(processed);
      notifyListeners();
    }
    return (locked: locked, moved: moved);
  }

  /// Puts a file received through Transfer into "<tab> › Received".
  Future<void> importEncrypted(
      String encPath, Uint8List transferKey, String name, int size) async {
    final tab = tabForName(name);
    final folder = await folderNamed(tab, 'Received');
    final id = newId();
    final out = blobPath(id);
    try {
      await transcodeFileIsolate(encPath, transferKey, out, _master!);
    } catch (_) {
      await _deleteFile(out);
      rethrow;
    }
    items.add(VItem(
        id: id,
        folderId: folder.id,
        name: safeName(name),
        size: size,
        added: DateTime.now().millisecondsSinceEpoch));
    await _saveIndex();
    notifyListeners();
  }

  Future<Uint8List> loadBytes(VItem it) =>
      _limited(() => decryptBytesIsolate(blobPath(it.id), _master!));

  /// Decrypts into the temp folder (wiped on lock) so another app can open it.
  Future<String> decryptToTemp(VItem it) async {
    final dir = Directory(p.join(tempDir.path, it.id));
    await dir.create(recursive: true);
    final out = p.join(dir.path, safeName(it.name));
    if (await File(out).exists()) return out;
    final part = '$out.part';
    try {
      await decryptFileIsolate(blobPath(it.id), part, _master!);
      await File(part).rename(out);
    } catch (_) {
      await _deleteFile(part);
      rethrow;
    }
    return out;
  }

  /// Takes a file out of F-Locker and puts it back where it came from
  /// (or into [fallbackDir] if it has no original place). Returns the path.
  Future<String> restoreItem(VItem it, String? fallbackDir) async {
    final origin = it.origin;
    final String target;
    if (origin != null) {
      target = origin;
    } else if (fallbackDir != null) {
      target = p.join(fallbackDir, safeName(it.name));
    } else {
      throw StateError('No place to restore "${it.name}" to');
    }
    final dir = p.dirname(target);
    await Directory(dir).create(recursive: true);
    final out = await _uniquePath(dir, p.basename(target));
    final part = '$out.flpart';
    try {
      await decryptFileIsolate(blobPath(it.id), part, _master!);
      await File(part).rename(out);
    } catch (_) {
      await _deleteFile(part);
      rethrow;
    }
    await deleteItems([it]);
    return out;
  }

  Future<void> deleteItems(List<VItem> list) async {
    final ids = list.map((i) => i.id).toSet();
    for (final id in ids) {
      await _deleteBlob(id);
    }
    items.removeWhere((i) => ids.contains(i.id));
    await _saveIndex();
    notifyListeners();
  }

  Future<void> _deleteBlob(String id) => _deleteFile(blobPath(id));

  static Future<void> _deleteFile(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static Future<String> _uniquePath(String dir, String name) async {
    var path = p.join(dir, name);
    final base = p.basenameWithoutExtension(name), ext = p.extension(name);
    var n = 1;
    while (await File(path).exists()) {
      path = p.join(dir, '$base ($n)$ext');
      n++;
    }
    return path;
  }

  /// At most three images are decrypted at the same time.
  Future<T> _limited<T>(Future<T> Function() job) async {
    while (_running >= 3) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    _running++;
    try {
      return await job();
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }
}
