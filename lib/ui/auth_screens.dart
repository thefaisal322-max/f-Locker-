import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/vault.dart';
import 'theme.dart';
import 'widgets.dart';

const _title = TextStyle(fontSize: 26, fontWeight: FontWeight.w700);
const _body = TextStyle(fontSize: 15, color: C.muted2, height: 1.5);

String? _checkNewPassword(String a, String b) {
  if (a.length < 4) return 'Use at least 4 characters.';
  if (a != b) return 'The two passwords are not the same.';
  return null;
}

// ------------------------------------------------------------------ setup

class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.vault});
  final Vault vault;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _create() async {
    final err = _checkNewPassword(_pw.text, _pw2.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await widget.vault.setup(_pw.text);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(children: [
        const Center(child: LogoMark()),
        const SizedBox(height: 18),
        const Text('Welcome to F-Locker',
            style: _title, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text(
            'Create a password. You need it every time you open the locker.',
            style: _body,
            textAlign: TextAlign.center),
        const SizedBox(height: 28),
        PasswordField(controller: _pw, label: 'Password', autofocus: true),
        const SizedBox(height: 12),
        PasswordField(
            controller: _pw2,
            label: 'Repeat password',
            onSubmitted: (_) => _create()),
        ErrorText(_error),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: _busy ? null : _create,
            child: BusyLabel(busy: _busy, label: 'Create password')),
      ]);
}

// ------------------------------------------------------------------- lock

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.vault});
  final Vault vault;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;
  int _fails = 0;
  DateTime? _waitUntil;

  Future<void> _unlock() async {
    final wait = _waitUntil;
    if (wait != null && DateTime.now().isBefore(wait)) {
      final s = wait.difference(DateTime.now()).inSeconds + 1;
      setState(() => _error = 'Too many tries. Wait $s seconds.');
      return;
    }
    if (_pw.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.vault.unlock(_pw.text);
    if (!mounted || ok) return;
    _fails++;
    if (_fails % 5 == 0) {
      _waitUntil = DateTime.now().add(const Duration(seconds: 30));
    }
    _pw.clear();
    setState(() {
      _busy = false;
      _error = 'Wrong password.';
    });
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(children: [
        const Center(child: LogoMark()),
        const SizedBox(height: 18),
        const Text('F-Locker', style: _title, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text('Enter your password to unlock',
            style: _body, textAlign: TextAlign.center),
        const SizedBox(height: 28),
        PasswordField(
            controller: _pw,
            label: 'Password',
            autofocus: true,
            onSubmitted: (_) => _unlock()),
        ErrorText(_error),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: _busy ? null : _unlock,
            child: BusyLabel(busy: _busy, label: 'Unlock')),
        const SizedBox(height: 24),
        TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => RecoveryUnlockScreen(vault: widget.vault))),
          child: const Text('Forgot password? Use your 10-letter recovery key',
              textAlign: TextAlign.center),
        ),
      ]);
}

// --------------------------------------------------------- recovery unlock

class RecoveryUnlockScreen extends StatefulWidget {
  const RecoveryUnlockScreen({super.key, required this.vault});
  final Vault vault;

  @override
  State<RecoveryUnlockScreen> createState() => _RecoveryUnlockScreenState();
}

class _RecoveryUnlockScreenState extends State<RecoveryUnlockScreen> {
  final _key = TextEditingController();
  bool _busy = false;
  String? _error;
  int _fails = 0;

  Future<void> _go() async {
    if (_fails >= 5) {
      setState(() => _error = 'Too many tries. Close F-Locker and try again later.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.vault.unlockWithRecovery(_key.text);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      return;
    }
    _fails++;
    setState(() {
      _busy = false;
      _error = 'This key is not correct.';
    });
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(showBack: true, children: [
        const Text('Reset password', style: _title),
        const SizedBox(height: 8),
        const Text(
            'Type the 10-letter recovery key you saved when you set up F-Locker. '
            'It opens the locker one time, then you must set a new password.',
            style: _body),
        const SizedBox(height: 24),
        TextField(
          controller: _key,
          autofocus: true,
          maxLength: 10,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          enableSuggestions: false,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]'))
          ],
          style: const TextStyle(
              fontSize: 22,
              letterSpacing: 6,
              fontFamily: 'monospace',
              fontFamilyFallback: ['Consolas', 'Courier New']),
          decoration:
              const InputDecoration(labelText: 'Recovery key (10 letters)'),
          onSubmitted: (_) => _go(),
        ),
        ErrorText(_error),
        const SizedBox(height: 16),
        FilledButton(
            onPressed: _busy ? null : _go,
            child: BusyLabel(busy: _busy, label: 'Unlock with key')),
      ]);
}

// ---------------------------------------------------- new password (forced)

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, required this.vault});
  final Vault vault;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    final err = _checkNewPassword(_pw.text, _pw2.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await widget.vault.setNewPassword(_pw.text);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AuthScaffold(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: C.accentBg, borderRadius: BorderRadius.circular(12)),
          child: const Row(children: [
            Icon(Icons.check_circle_outline, color: C.accent),
            SizedBox(width: 10),
            Expanded(
                child: Text('Key accepted. The locker is open.',
                    style: TextStyle(color: C.accentText))),
          ]),
        ),
        const SizedBox(height: 24),
        const Text('Set a new password', style: _title),
        const SizedBox(height: 8),
        const Text(
            'This is required. The old recovery key stops working and you get a new one next.',
            style: _body),
        const SizedBox(height: 24),
        PasswordField(controller: _pw, label: 'New password', autofocus: true),
        const SizedBox(height: 12),
        PasswordField(
            controller: _pw2,
            label: 'Repeat new password',
            onSubmitted: (_) => _save()),
        ErrorText(_error),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: _busy ? null : _save,
            child: BusyLabel(busy: _busy, label: 'Save new password')),
      ]);
}

// ------------------------------------------------------- show recovery key

class RecoveryKeyScreen extends StatefulWidget {
  const RecoveryKeyScreen(
      {super.key, required this.vault, required this.recoveryKey});
  final Vault vault;
  final String recoveryKey;

  @override
  State<RecoveryKeyScreen> createState() => _RecoveryKeyScreenState();
}

class _RecoveryKeyScreenState extends State<RecoveryKeyScreen> {
  bool _saved = false;

  String get _text =>
      'F-Locker recovery key: ${widget.recoveryKey}\r\n'
      'It opens your locker one time if you forget the password.\r\n';

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.recoveryKey));
    if (mounted) showSnack(context, 'Recovery key copied.');
  }

  Future<void> _saveFile() async {
    final bytes = Uint8List.fromList(utf8.encode(_text));
    try {
      final path = await widget.vault.withoutAutoLock(() =>
          FilePicker.platform.saveFile(
              dialogTitle: 'Save recovery key',
              fileName: 'F-Locker-recovery-key.txt',
              bytes: bytes));
      if (path == null) return;
      if (Platform.isWindows) await File(path).writeAsBytes(bytes);
      if (mounted) showSnack(context, 'Recovery key saved.');
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save the file: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final chars = widget.recoveryKey.split('');
    Widget box(String ch) => Expanded(
          child: Container(
            height: 54,
            margin: const EdgeInsets.all(4),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: C.bg,
                border: Border.all(color: C.border),
                borderRadius: BorderRadius.circular(10)),
            child: Text(ch,
                style: const TextStyle(
                    fontSize: 24,
                    color: C.accent,
                    fontFamily: 'monospace',
                    fontFamilyFallback: ['Consolas', 'Courier New'])),
          ),
        );
    return AuthScaffold(children: [
      const Text('Save your recovery key', style: _title),
      const SizedBox(height: 8),
      const Text(
          'If you forget your password, this 10-letter key opens the locker one time. '
          'After you use it, you must set a new password and you get a new key.',
          style: _body),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: C.surface, borderRadius: BorderRadius.circular(18)),
        child: Column(children: [
          Row(children: [for (final c in chars.take(5)) box(c)]),
          Row(children: [for (final c in chars.skip(5)) box(c)]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: _copy,
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy'))),
            const SizedBox(width: 10),
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: _saveFile,
                    icon: const Icon(Icons.save_alt, size: 18),
                    label: const Text('Save as file'))),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: C.warnBg, borderRadius: BorderRadius.circular(12)),
        child: const Text(
            'Write it down and keep it outside this device. Without the password '
            'and this key, locked files cannot be opened by anyone.',
            style: TextStyle(color: C.warnText, height: 1.5)),
      ),
      const SizedBox(height: 12),
      CheckboxListTile(
        value: _saved,
        onChanged: (v) => setState(() => _saved = v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        title: const Text('I have saved my recovery key'),
      ),
      const SizedBox(height: 8),
      FilledButton(
          onPressed: _saved ? widget.vault.acknowledgeRecoveryKey : null,
          child: const Text('Continue')),
    ]);
  }
}
