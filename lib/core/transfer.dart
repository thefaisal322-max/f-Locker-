// Transfer: move files from another phone or PC straight into the locker,
// over the local Wi-Fi. The receiver shows its address and a 6-digit code;
// both sides derive the same AES key from the code, so files travel encrypted
// and a wrong code is rejected.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'crypto.dart';
import 'vault.dart';

const int transferPort = 47321;
const String _hello = 'F-LOCKER-HELLO';

Future<Uint8List> transferKeyFor(String code) => deriveKeyIsolate(
    code, Uint8List.fromList(utf8.encode('f-locker-transfer-v1')), 60000);

Future<List<String>> localAddresses() async {
  try {
    final list = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    return [
      for (final i in list)
        for (final a in i.addresses) a.address
    ];
  } catch (_) {
    return [];
  }
}

class Incoming {
  Incoming(this.name, this.size);
  final String name;
  final int size;
  int received = 0;
  String status = 'Receiving';
  bool done = false;
  bool failed = false;

  double? get progress =>
      done ? 1 : (size > 0 ? (received / size).clamp(0, 1).toDouble() : null);
}

class TransferServer extends ChangeNotifier {
  HttpServer? _server;
  Uint8List? _key;
  String? code;
  String? error;
  List<String> addresses = [];
  final List<Incoming> incoming = [];
  DateTime _lastTick = DateTime.fromMillisecondsSinceEpoch(0);

  bool get running => _server != null;

  Future<void> start(Vault vault) async {
    if (running) return;
    error = null;
    final c = (Random.secure().nextInt(900000) + 100000).toString();
    final key = await transferKeyFor(c);
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, transferPort);
    } on SocketException catch (e) {
      error = 'Could not open port $transferPort: ${e.message}';
      notifyListeners();
      return;
    }
    _key = key;
    code = c;
    addresses = await localAddresses();
    _server!.listen((req) => _handle(vault, req), onError: (Object _) {});
    notifyListeners();
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    _key = null;
    code = null;
    notifyListeners();
    await s?.close(force: true);
  }

  void _tick() {
    final now = DateTime.now();
    if (now.difference(_lastTick).inMilliseconds > 200) {
      _lastTick = now;
      notifyListeners();
    }
  }

  Future<void> _reply(HttpRequest req, int status, String msg) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.text;
    req.response.write(msg);
    await req.response.close();
  }

  Future<Uint8List> _readSmall(HttpRequest req) async {
    final b = BytesBuilder();
    await for (final c in req) {
      b.add(c);
      if (b.length > 4096) throw const FormatException('Too large');
    }
    return b.takeBytes();
  }

  Future<void> _handle(Vault vault, HttpRequest req) async {
    try {
      final key = _key;
      if (key == null || !vault.isUnlocked) {
        await _reply(req, 503, 'The receiving F-Locker is locked.');
        return;
      }
      if (req.method == 'POST' && req.uri.path == '/hello') {
        try {
          final clear = await openBytes(await _readSmall(req), key);
          if (utf8.decode(clear) != _hello) throw WrongSecret();
        } catch (_) {
          await _reply(req, 403, 'Wrong code.');
          return;
        }
        await _reply(req, 200, 'OK');
        return;
      }
      if (req.method == 'POST' && req.uri.path == '/upload') {
        await _upload(vault, req, key);
        return;
      }
      await _reply(req, 404, 'Not found');
    } catch (_) {
      try {
        await _reply(req, 500, 'Something went wrong.');
      } catch (_) {}
    }
  }

  Future<void> _upload(Vault vault, HttpRequest req, Uint8List key) async {
    final rawName = req.headers.value('x-name');
    if (rawName == null) {
      await _reply(req, 400, 'Missing file name.');
      return;
    }
    final name = p.basename(utf8.decode(base64Url.decode(rawName)));
    final size = int.tryParse(req.headers.value('x-size') ?? '') ?? 0;
    final inc = Incoming(name, size);
    incoming.insert(0, inc);
    notifyListeners();

    await vault.tempDir.create(recursive: true);
    final tmp = File(p.join(vault.tempDir.path, 'rx_${newId()}.part'));
    final sink = tmp.openWrite();
    try {
      await for (final chunk in req) {
        sink.add(chunk);
        inc.received += chunk.length;
        _tick();
      }
      await sink.close();
      inc.status = 'Locking';
      notifyListeners();
      await vault.importEncrypted(tmp.path, key, name, size);
      inc
        ..status = 'Locked'
        ..done = true;
      notifyListeners();
      await _reply(req, 200, 'OK');
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      inc
        ..status = e is WrongSecret ? 'Wrong code' : 'Failed'
        ..failed = true;
      notifyListeners();
      await _reply(req, e is WrongSecret ? 403 : 400, 'Could not lock the file.');
    } finally {
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }
}

/// Kept for the whole app session so receiving continues across tabs.
final TransferServer transferServer = TransferServer();

class TransferError implements Exception {
  TransferError(this.message);
  final String message;
  @override
  String toString() => message;
}

class TransferClient {
  static String cleanHost(String input) {
    var h = input.trim();
    h = h.replaceFirst(RegExp(r'^https?://'), '');
    final colon = h.indexOf(':');
    if (colon > 0) h = h.substring(0, colon);
    return h;
  }

  static Future<(int, String)> _post(String host, String path, List<int> body,
      {Map<String, String> headers = const {}}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.post(host, transferPort, path);
      headers.forEach(req.headers.set);
      req.contentLength = body.length;
      req.add(body);
      final res = await req.close();
      return (res.statusCode, await utf8.decodeStream(res));
    } finally {
      client.close(force: true);
    }
  }

  /// Checks the address and code. Returns the key to send with.
  static Future<Uint8List> connect(String host, String code) async {
    final key = await transferKeyFor(code.trim());
    final hello = await sealBytes(utf8.encode(_hello), key);
    try {
      final (status, msg) = await _post(host, '/hello', hello);
      if (status != 200) throw TransferError(msg);
    } on SocketException {
      throw TransferError(
          'Could not reach $host. Check the address and that both devices are on the same Wi-Fi.');
    }
    return key;
  }

  static Future<void> sendFile(String host, Uint8List key, String path,
      String tempDir, void Function(double) onProgress) async {
    await Directory(tempDir).create(recursive: true);
    final enc = File(p.join(tempDir, 'tx_${newId()}.part'));
    try {
      await encryptFileIsolate(path, enc.path, key);
      final total = await enc.length();
      final size = await File(path).length();
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      try {
        final req = await client.post(host, transferPort, '/upload');
        req.headers.set('x-name', base64Url.encode(utf8.encode(p.basename(path))));
        req.headers.set('x-size', '$size');
        req.contentLength = total;
        var sent = 0;
        await req.addStream(enc.openRead().map((c) {
          sent += c.length;
          onProgress(total == 0 ? 1 : sent / total);
          return c;
        }));
        final res = await req.close();
        final msg = await utf8.decodeStream(res);
        if (res.statusCode != 200) throw TransferError(msg);
      } finally {
        client.close(force: true);
      }
    } finally {
      try {
        await enc.delete();
      } catch (_) {}
    }
  }
}
