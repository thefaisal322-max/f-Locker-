// Small platform helpers: Android file access and gallery refresh (through
// the "f_locker/native" channel in MainActivity.kt), and hiding files on
// Windows.

import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

class Device {
  static const MethodChannel _ch = MethodChannel('f_locker/native');

  static Future<String> storageRoot() async {
    try {
      return await _ch.invokeMethod<String>('storageRoot') ??
          '/storage/emulated/0';
    } catch (_) {
      return '/storage/emulated/0';
    }
  }

  /// Android: can F-Locker move files in and out of the phone's folders?
  static Future<bool> hasFileAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _ch.invokeMethod<bool>('hasAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Asks Android for "All files access". On Android 11+ this opens the
  /// settings page, so it waits until the person comes back.
  static Future<bool> requestFileAccess() async {
    if (!Platform.isAndroid) return true;
    final r = await _ch.invokeMethod<String>('requestAccess');
    if (r == 'granted') return true;
    if (r == 'settings') {
      await _nextResume();
      return hasFileAccess();
    }
    return false;
  }

  static Future<void> _nextResume() {
    final c = Completer<void>();
    late final AppLifecycleListener l;
    l = AppLifecycleListener(onResume: () {
      l.dispose();
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }

  /// Tells the Android gallery that files were removed or put back.
  static Future<void> mediaScan(List<String> paths) async {
    if (!Platform.isAndroid || paths.isEmpty) return;
    try {
      await _ch.invokeMethod<void>('mediaScan', {'paths': paths});
    } catch (_) {}
  }

  /// Windows: gives a file or folder the "hidden" attribute.
  static void hideOnWindows(String path) {
    if (!Platform.isWindows) return;
    try {
      final setAttributes = DynamicLibrary.open('kernel32.dll').lookupFunction<
          Int32 Function(Pointer<Utf16>, Uint32),
          int Function(Pointer<Utf16>, int)>('SetFileAttributesW');
      final ptr = path.toNativeUtf16();
      setAttributes(ptr, 0x2); // FILE_ATTRIBUTE_HIDDEN
      calloc.free(ptr);
    } catch (_) {}
  }
}

class FoundFile {
  const FoundFile(this.path, this.size, this.modified);
  final String path;
  final int size;
  final int modified;
}

/// Finds files with [extensions] on the phone, grouped by folder ("albums"),
/// newest first. Runs in the background.
Future<List<MapEntry<String, List<FoundFile>>>> scanStorage(
    String root, List<String> extensions) {
  final exts = extensions.toSet();
  return Isolate.run(() => _scan(root, exts));
}

List<MapEntry<String, List<FoundFile>>> _scan(String root, Set<String> exts) {
  final skip = {
    p.join(root, 'Android', 'data'),
    p.join(root, 'Android', 'obb'),
  };
  final out = <String, List<FoundFile>>{};
  final stack = <Directory>[Directory(root)];
  while (stack.isNotEmpty) {
    final dir = stack.removeLast();
    List<FileSystemEntity> list;
    try {
      list = dir.listSync(followLinks: false);
    } catch (_) {
      continue;
    }
    for (final e in list) {
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      if (e is Directory) {
        if (!skip.contains(e.path)) stack.add(e);
      } else if (e is File) {
        final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
        if (!exts.contains(ext)) continue;
        try {
          final s = e.statSync();
          out
              .putIfAbsent(dir.path, () => [])
              .add(FoundFile(e.path, s.size, s.modified.millisecondsSinceEpoch));
        } catch (_) {}
      }
    }
  }
  for (final l in out.values) {
    l.sort((a, b) => b.modified.compareTo(a.modified));
  }
  final albums = out.entries.toList()
    ..sort((a, b) => b.value.first.modified.compareTo(a.value.first.modified));
  return albums;
}
