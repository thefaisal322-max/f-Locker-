import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/models.dart';
import '../core/transfer.dart';
import '../core/vault.dart';
import 'theme.dart';
import 'widgets.dart';

class _Out {
  _Out(this.name);
  final String name;
  double progress = 0;
  String status = 'Waiting';
  bool failed = false;
}

/// Transfer tab: receive files from another phone or PC into the locker,
/// or send files to another F-Locker.
class TransferView extends StatefulWidget {
  const TransferView({super.key, required this.vault});
  final Vault vault;

  @override
  State<TransferView> createState() => _TransferViewState();
}

class _TransferViewState extends State<TransferView> {
  bool _receive = true;
  final _host = TextEditingController();
  final _code = TextEditingController();
  Uint8List? _key;
  String? _connectedTo;
  bool _busy = false;
  String? _error;
  final List<_Out> _outgoing = [];

  Future<void> _connect() async {
    final host = TransferClient.cleanHost(_host.text);
    final code = _code.text.trim();
    if (host.isEmpty || code.length != 6) {
      setState(() => _error = 'Type the address and the 6-digit code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final key = await TransferClient.connect(host, code);
      if (!mounted) return;
      setState(() {
        _key = key;
        _connectedTo = host;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    final key = _key, host = _connectedTo;
    if (key == null || host == null) return;
    FilePickerResult? r;
    try {
      r = await widget.vault.withoutAutoLock(() => FilePicker.platform
          .pickFiles(allowMultiple: true, lockParentWindow: true));
    } catch (e) {
      if (mounted) showSnack(context, 'Could not open the files: $e');
      return;
    }
    final paths =
        r?.files.map((f) => f.path).whereType<String>().toList() ?? <String>[];
    if (paths.isEmpty) return;
    setState(() => _busy = true);
    await widget.vault.withoutAutoLock(() async {
      for (final path in paths) {
        final o = _Out(p.basename(path));
        setState(() => _outgoing.insert(0, o));
        try {
          o.status = 'Sending';
          await TransferClient.sendFile(
              host, key, path, widget.vault.tempDir.path, (v) {
            if (mounted) setState(() => o.progress = v);
          });
          o
            ..progress = 1
            ..status = 'Sent';
        } catch (e) {
          o
            ..failed = true
            ..status = 'Failed: $e';
        }
        if (mounted) setState(() {});
      }
    });
    try {
      await FilePicker.platform.clearTemporaryFiles();
    } catch (_) {}
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Text('Transfer',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 14),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: true,
                  label: Text('Receive'),
                  icon: Icon(Icons.download)),
              ButtonSegment(
                  value: false, label: Text('Send'), icon: Icon(Icons.upload)),
            ],
            selected: {_receive},
            onSelectionChanged: (s) => setState(() => _receive = s.first),
          ),
          const SizedBox(height: 18),
          if (_receive) _receiveUi() else _sendUi(),
        ],
      );

  Widget _card(List<Widget> children) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: C.surface, borderRadius: BorderRadius.circular(18)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children),
      );

  Widget _receiveUi() => ListenableBuilder(
        listenable: transferServer,
        builder: (context, _) {
          final s = transferServer;
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!s.running)
                  _card([
                    const Text(
                        'Get files from another phone or PC on the same Wi-Fi. '
                        'They are encrypted on the way and go straight into your locker.',
                        style: TextStyle(color: C.muted2, height: 1.5)),
                    ErrorText(s.error),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                        onPressed: () => transferServer.start(widget.vault),
                        icon: const Icon(Icons.wifi_tethering),
                        label: const Text('Start receiving')),
                  ])
                else
                  _card([
                    const Text(
                        'On the other device open F-Locker › Transfer › Send and type:',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: C.muted)),
                    const SizedBox(height: 14),
                    const Text('Address',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: C.muted)),
                    for (final a in s.addresses.isEmpty
                        ? ['Not connected to Wi-Fi']
                        : s.addresses)
                      SelectableText(a,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 12),
                    const Text('Code',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: C.muted)),
                    SelectableText(
                        '${s.code!.substring(0, 3)} ${s.code!.substring(3)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 34,
                            letterSpacing: 6,
                            color: C.accent,
                            fontFamily: 'monospace',
                            fontFamilyFallback: ['Consolas', 'Courier New'])),
                    const SizedBox(height: 12),
                    const Text(
                        'Keep this screen open. On Windows, allow F-Locker through the firewall if asked.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: C.muted)),
                    const SizedBox(height: 14),
                    OutlinedButton(
                        onPressed: transferServer.stop,
                        child: const Text('Stop receiving')),
                  ]),
                if (s.incoming.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text('Incoming',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  for (final inc in s.incoming)
                    _progressTile(
                      name: inc.name,
                      right: inc.status,
                      progress: inc.progress,
                      failed: inc.failed,
                      below:
                          'Into: ${tabForName(inc.name).label} › Received',
                    ),
                ],
              ]);
        },
      );

  Widget _sendUi() => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_key == null)
              _card([
                const Text(
                    'On the other device choose Receive. Then type what it shows.',
                    style: TextStyle(color: C.muted2, height: 1.5)),
                const SizedBox(height: 16),
                TextField(
                  controller: _host,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'Address (for example 192.168.1.5)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: '6-digit code'),
                  onSubmitted: (_) => _connect(),
                ),
                ErrorText(_error),
                const SizedBox(height: 10),
                FilledButton(
                    onPressed: _busy ? null : _connect,
                    child: BusyLabel(busy: _busy, label: 'Connect')),
              ])
            else
              _card([
                Row(children: [
                  const Icon(Icons.check_circle_outline, color: C.accent),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Connected to $_connectedTo')),
                  TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _key = null;
                                _connectedTo = null;
                              }),
                      child: const Text('Disconnect')),
                ]),
                const SizedBox(height: 14),
                FilledButton.icon(
                    onPressed: _busy ? null : _send,
                    icon: const Icon(Icons.upload),
                    label: const Text('Pick files and send')),
              ]),
            if (_outgoing.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('Sent',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              for (final o in _outgoing)
                _progressTile(
                    name: o.name,
                    right: o.failed ? 'Failed' : o.status,
                    progress: o.progress,
                    failed: o.failed,
                    below: o.failed ? o.status : null),
            ],
          ]);

  Widget _progressTile(
          {required String name,
          required String right,
          required double? progress,
          required bool failed,
          String? below}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: C.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500))),
            const SizedBox(width: 10),
            Text(right,
                style: TextStyle(
                    fontSize: 13, color: failed ? C.danger : C.muted)),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
                minHeight: 6,
                value: failed ? 0 : progress,
                backgroundColor: C.border),
          ),
          if (below != null) ...[
            const SizedBox(height: 8),
            Text(below,
                style: TextStyle(
                    fontSize: 13, color: failed ? C.danger : C.muted)),
          ],
        ]),
      );
}
