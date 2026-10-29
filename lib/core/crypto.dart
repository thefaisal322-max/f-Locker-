// Encryption core for F-Locker.
//
// Keys: a random 256-bit master key encrypts every file and the index.
// The master key is stored twice, wrapped (AES-256-GCM) by a key derived
// with PBKDF2-HMAC-SHA256 from the password and from the 10-letter recovery key.
//
// File format ("FLK1"): 16-byte header (magic, 8-byte nonce prefix, chunk size)
// followed by frames of [u32 length][AES-GCM ciphertext + 16-byte tag].
// Each 1 MiB chunk gets its own nonce (prefix + counter). The last chunk is
// marked through the AAD so a cut-off file is detected.

import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

const int chunkSize = 1 << 20;
const List<int> _magic = [0x46, 0x4C, 0x4B, 0x31];
final Random _rng = Random.secure();
final AesGcm _aes = AesGcm.with256bits();

/// Thrown when a password, recovery key or transfer code is wrong
/// (or the data was changed).
class WrongSecret implements Exception {
  @override
  String toString() => 'Wrong password, key or code';
}

Uint8List randomBytes(int n) {
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = _rng.nextInt(256);
  }
  return b;
}

String newId() =>
    randomBytes(12).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Letters and digits that are hard to mix up (no 0/O, 1/I/L).
const String recoveryAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

String newRecoveryKey() => String.fromCharCodes(List.generate(
    10,
    (_) => recoveryAlphabet
        .codeUnitAt(_rng.nextInt(recoveryAlphabet.length))));

String normalizeRecoveryKey(String s) =>
    s.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');

Future<Uint8List> deriveKey(String secret, Uint8List salt,
    {int iterations = 120000}) async {
  final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);
  final k = await pbkdf2.deriveKeyFromPassword(password: secret, nonce: salt);
  return Uint8List.fromList(await k.extractBytes());
}

/// Encrypts a small value: nonce(12) + ciphertext + tag(16).
Future<Uint8List> sealBytes(List<int> plain, List<int> key) async {
  final nonce = randomBytes(12);
  final box =
      await _aes.encrypt(plain, secretKey: SecretKey(key), nonce: nonce);
  final out = Uint8List(12 + box.cipherText.length + 16);
  out.setRange(0, 12, nonce);
  out.setRange(12, 12 + box.cipherText.length, box.cipherText);
  out.setRange(12 + box.cipherText.length, out.length, box.mac.bytes);
  return out;
}

Future<Uint8List> openBytes(List<int> sealed, List<int> key) async {
  if (sealed.length < 28) throw WrongSecret();
  final data = Uint8List.fromList(sealed);
  final nonce = Uint8List.sublistView(data, 0, 12);
  final ct = Uint8List.sublistView(data, 12, data.length - 16);
  final mac = Mac(Uint8List.sublistView(data, data.length - 16));
  try {
    final clear = await _aes.decrypt(SecretBox(ct, nonce: nonce, mac: mac),
        secretKey: SecretKey(key));
    return Uint8List.fromList(clear);
  } on SecretBoxAuthenticationError {
    throw WrongSecret();
  }
}

Uint8List _nonceFor(Uint8List base, int counter) {
  final nonce = Uint8List(12)..setRange(0, 8, base);
  nonce.buffer.asByteData().setUint32(8, counter);
  return nonce;
}

Future<Uint8List> _encChunk(Uint8List clear, SecretKey key, Uint8List base,
    int counter, bool last) async {
  final box = await _aes.encrypt(clear,
      secretKey: key, nonce: _nonceFor(base, counter), aad: [last ? 1 : 0]);
  final len = box.cipherText.length + 16;
  final out = Uint8List(4 + len);
  out.buffer.asByteData().setUint32(0, len);
  out.setRange(4, 4 + box.cipherText.length, box.cipherText);
  out.setRange(4 + box.cipherText.length, out.length, box.mac.bytes);
  return out;
}

Future<(List<int>, bool)> _decChunk(
    Uint8List body, SecretKey key, Uint8List base, int counter) async {
  final ct = Uint8List.sublistView(body, 0, body.length - 16);
  final mac = Mac(Uint8List.sublistView(body, body.length - 16));
  final nonce = _nonceFor(base, counter);
  try {
    final clear = await _aes.decrypt(SecretBox(ct, nonce: nonce, mac: mac),
        secretKey: key, aad: const [0]);
    return (clear, false);
  } on SecretBoxAuthenticationError {
    try {
      final clear = await _aes.decrypt(SecretBox(ct, nonce: nonce, mac: mac),
          secretKey: key, aad: const [1]);
      return (clear, true);
    } on SecretBoxAuthenticationError {
      throw WrongSecret();
    }
  }
}

Stream<List<int>> encryptStream(
    Stream<List<int>> input, List<int> keyBytes) async* {
  final key = SecretKey(keyBytes);
  final base = randomBytes(8);
  final header = Uint8List(16)
    ..setRange(0, 4, _magic)
    ..setRange(4, 12, base);
  header.buffer.asByteData().setUint32(12, chunkSize);
  yield header;
  final buf = BytesBuilder();
  var counter = 0;
  await for (final part in input) {
    buf.add(part);
    while (buf.length > chunkSize) {
      final all = buf.takeBytes();
      yield await _encChunk(Uint8List.sublistView(all, 0, chunkSize), key,
          base, counter++, false);
      buf.add(Uint8List.sublistView(all, chunkSize));
    }
  }
  yield await _encChunk(buf.takeBytes(), key, base, counter++, true);
}

Stream<List<int>> decryptStream(
    Stream<List<int>> input, List<int> keyBytes) async* {
  final key = SecretKey(keyBytes);
  final buf = BytesBuilder();
  Uint8List? base;
  int? need;
  var counter = 0;
  var done = false;
  await for (final part in input) {
    buf.add(part);
    while (true) {
      if (base == null) {
        if (buf.length < 16) break;
        final all = buf.takeBytes();
        for (var i = 0; i < 4; i++) {
          if (all[i] != _magic[i]) {
            throw const FormatException('Not an F-Locker file');
          }
        }
        base = Uint8List.fromList(all.sublist(4, 12));
        buf.add(Uint8List.sublistView(all, 16));
        continue;
      }
      if (need == null) {
        if (buf.length < 4) break;
        final all = buf.takeBytes();
        final len = (all[0] << 24) | (all[1] << 16) | (all[2] << 8) | all[3];
        if (len < 16 || len > chunkSize + 16) {
          throw const FormatException('The data is damaged');
        }
        need = 4 + len;
        buf.add(all);
      }
      final n = need;
      if (buf.length < n) break;
      if (done) throw const FormatException('The data is damaged');
      final all = buf.takeBytes();
      final body = Uint8List.sublistView(all, 4, n);
      buf.add(Uint8List.sublistView(all, n));
      need = null;
      final (clear, last) = await _decChunk(body, key, base, counter++);
      if (last) done = true;
      if (clear.isNotEmpty) yield clear;
    }
  }
  if (!done) throw const FormatException('The data is incomplete');
}

Future<void> encryptFile(String inPath, String outPath, List<int> key) async {
  final out = File(outPath).openWrite();
  try {
    await out.addStream(encryptStream(File(inPath).openRead(), key));
  } finally {
    await out.close();
  }
}

Future<void> decryptFile(String inPath, String outPath, List<int> key) async {
  final out = File(outPath).openWrite();
  try {
    await out.addStream(decryptStream(File(inPath).openRead(), key));
  } finally {
    await out.close();
  }
}

Future<Uint8List> decryptFileToBytes(String inPath, List<int> key) async {
  final b = BytesBuilder(copy: false);
  await for (final c in decryptStream(File(inPath).openRead(), key)) {
    b.add(c);
  }
  return b.takeBytes();
}

/// Re-encrypts a file from one key to another without writing plain data.
Future<void> transcodeFile(
    String inPath, List<int> keyIn, String outPath, List<int> keyOut) async {
  final out = File(outPath).openWrite();
  try {
    await out.addStream(
        encryptStream(decryptStream(File(inPath).openRead(), keyIn), keyOut));
  } finally {
    await out.close();
  }
}

// Background-isolate versions, so big files never freeze the screen.
// They only capture plain values (strings and bytes).

Future<Uint8List> deriveKeyIsolate(String secret, Uint8List salt, int it) =>
    Isolate.run(() => deriveKey(secret, salt, iterations: it));

Future<void> encryptFileIsolate(String a, String b, Uint8List key) =>
    Isolate.run(() => encryptFile(a, b, key));

Future<void> decryptFileIsolate(String a, String b, Uint8List key) =>
    Isolate.run(() => decryptFile(a, b, key));

Future<Uint8List> decryptBytesIsolate(String a, Uint8List key) =>
    Isolate.run(() => decryptFileToBytes(a, key));

Future<void> transcodeFileIsolate(
        String a, Uint8List keyIn, String b, Uint8List keyOut) =>
    Isolate.run(() => transcodeFile(a, keyIn, b, keyOut));
