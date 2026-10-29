import 'dart:io';

import 'package:flutter/material.dart';

import '../core/vault.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key, required this.vault});
  final Vault vault;

  static const _autoLockLabels = {
    0: 'Immediately',
    1: 'After 1 min',
    5: 'After 5 min',
    15: 'After 15 min',
    -1: 'Never',
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: vault,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const Text('Settings',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            _Group('Security', [
              _Row(
                title: 'Change password',
                subtitle: 'Needs your current password',
                onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => _ChangePasswordDialog(vault: vault)),
              ),
              _Row(
                title: 'Recovery key',
                subtitle: 'Make a new 10-letter key. The old one stops working.',
                onTap: () => showDialog<void>(
                    context: context,
                    builder: (_) => _NewKeyDialog(vault: vault)),
              ),
              _Row(
                title: 'Auto-lock',
                subtitle: 'Lock when you leave the app',
                trailing: DropdownButton<int>(
                  value: vault.autoLockMinutes,
                  dropdownColor: C.surface,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final e in _autoLockLabels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) {
                    if (v != null) vault.setAutoLock(v);
                  },
                ),
              ),
            ]),
            _Group('Storage', [
              _Row(title: 'Vault location', subtitle: vault.root.path),
              const _Row(
                title: 'Items per folder',
                subtitle: 'No limit on adding items',
                trailing: Text('Unlimited',
                    style: TextStyle(
                        color: C.accent, fontWeight: FontWeight.w700)),
              ),
              _Row(
                title: 'Locked items',
                subtitle:
                    '${vault.items.length} items · ${formatBytes(vault.totalBytes)}',
              ),
              if (Platform.isWindows)
                _Row(
                  title: 'Delete originals after locking',
                  subtitle:
                      'Removes the original file from this PC once it is safely locked',
                  trailing: Switch(
                      value: vault.deleteOriginals,
                      onChanged: vault.setDeleteOriginals),
                )
              else
                const _Row(
                  title: 'Gallery originals',
                  subtitle:
                      'Android keeps the original in the gallery. Delete it there after locking.',
                ),
            ]),
            const _Group('About', [
              _Row(
                  title: 'F-Locker 1.0.0',
                  subtitle:
                      'AES-256-GCM encryption · password + 10-letter recovery key'),
            ]),
          ],
        ),
      );
}

class _Group extends StatelessWidget {
  const _Group(this.title, this.rows);
  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
            child: Text(title,
                style: const TextStyle(fontSize: 13, color: C.muted)),
          ),
          Material(
            color: C.surface,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: C.border),
                rows[i],
              ],
            ]),
          ),
        ],
      );
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.subtitle, this.trailing, this.onTap});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!,
                          style:
                              const TextStyle(fontSize: 12, color: C.muted)),
                    ],
                  ]),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
            if (trailing == null && onTap != null)
              const Icon(Icons.chevron_right, color: C.muted),
          ]),
        ),
      );
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.vault});
  final Vault vault;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _new2 = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (_new.text.length < 4) {
      setState(() => _error = 'Use at least 4 characters.');
      return;
    }
    if (_new.text != _new2.text) {
      setState(() => _error = 'The two new passwords are not the same.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.vault.changePassword(_old.text, _new.text);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'The current password is wrong.';
      });
      return;
    }
    Navigator.of(context).pop();
    showSnack(context, 'Password changed.');
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Change password'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              PasswordField(
                  controller: _old, label: 'Current password', autofocus: true),
              const SizedBox(height: 12),
              PasswordField(controller: _new, label: 'New password'),
              const SizedBox(height: 12),
              PasswordField(
                  controller: _new2,
                  label: 'Repeat new password',
                  onSubmitted: (_) => _save()),
              ErrorText(_error),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _busy ? null : _save,
              child: BusyLabel(busy: _busy, label: 'Save')),
        ],
      );
}

class _NewKeyDialog extends StatefulWidget {
  const _NewKeyDialog({required this.vault});
  final Vault vault;

  @override
  State<_NewKeyDialog> createState() => _NewKeyDialogState();
}

class _NewKeyDialogState extends State<_NewKeyDialog> {
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.vault.regenerateRecoveryKey(_pw.text);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'Wrong password.';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('New recovery key'),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'Type your password. You get a new 10-letter key and the old key stops working.',
                style: TextStyle(color: C.muted2, height: 1.5)),
            const SizedBox(height: 14),
            PasswordField(
                controller: _pw,
                label: 'Password',
                autofocus: true,
                onSubmitted: (_) => _go()),
            ErrorText(_error),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: _busy ? null : _go,
              child: BusyLabel(busy: _busy, label: 'Make new key')),
        ],
      );
}
