import 'dart:io';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/vault.dart';
import 'settings_view.dart';
import 'tab_view.dart';
import 'theme.dart';
import 'transfer_view.dart';
import 'widgets.dart';

class _Section {
  const _Section(this.label, this.icon, [this.tab]);
  final String label;
  final IconData icon;
  final VaultTab? tab;
}

final List<_Section> _sections = [
  const _Section('Settings', Icons.settings_outlined),
  const _Section('Transfer', Icons.swap_vert),
  for (final t in VaultTab.values) _Section(t.label, t.icon, t),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.vault});
  final Vault vault;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 2; // Videos

  Widget _content() {
    final s = _sections[_index];
    final tab = s.tab;
    if (tab != null) {
      return TabView(key: ValueKey(tab), vault: widget.vault, tab: tab);
    }
    if (_index == 0) return SettingsView(vault: widget.vault);
    return TransferView(vault: widget.vault);
  }

  Future<void> _lockAndExit() async {
    await widget.vault.lock();
    exit(0);
  }

  List<Widget> _actions() => [
        IconButton(
            tooltip: 'Lock now',
            icon: const Icon(Icons.lock_outline),
            onPressed: widget.vault.lock),
        if (Platform.isWindows)
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: OutlinedButton.icon(
                onPressed: _lockAndExit,
                icon: const Icon(Icons.power_settings_new, size: 18),
                label: const Text('Lock & exit')),
          ),
      ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, c) => c.maxWidth >= 820 ? _wide() : _narrow());

  Widget _narrow() => Scaffold(
        appBar: AppBar(
            title: const Text('F-Locker',
                style: TextStyle(fontWeight: FontWeight.w700)),
            actions: _actions()),
        body: Column(children: [
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _sections.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final s = _sections[i];
                final on = i == _index;
                return ChoiceChip(
                  showCheckmark: false,
                  selected: on,
                  onSelected: (_) => setState(() => _index = i),
                  avatar: Icon(s.icon, size: 18, color: on ? C.bg : C.text),
                  label: Text(s.label),
                  labelStyle: TextStyle(
                      color: on ? C.bg : C.text, fontWeight: FontWeight.w500),
                  selectedColor: C.accent,
                  backgroundColor: C.bg,
                  side: BorderSide(color: on ? C.accent : C.border),
                  shape: const StadiumBorder(),
                );
              },
            ),
          ),
          Expanded(child: _content()),
        ]),
      );

  Widget _wide() => Scaffold(
        body: SafeArea(
          child: Column(children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 8, 10),
              decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: C.border))),
              child: Row(children: [
                const LogoMark(size: 34),
                const SizedBox(width: 12),
                const Text('F-Locker',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(width: 14),
                if (Platform.isWindows)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: C.surface2,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text(
                          'Portable · nothing installed · data stays next to F-Locker.exe',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: C.muted2)),
                    ),
                  ),
                const Spacer(),
                ..._actions(),
              ]),
            ),
            Expanded(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 240,
                      child: ListenableBuilder(
                        listenable: widget.vault,
                        builder: (context, _) => ListView(
                          padding: const EdgeInsets.all(12),
                          children: [
                            for (var i = 0; i < _sections.length; i++) ...[
                              if (i == 2)
                                const Divider(color: C.border, height: 20),
                              _SideItem(
                                section: _sections[i],
                                selected: i == _index,
                                count: _sections[i].tab == null
                                    ? null
                                    : widget.vault
                                        .countInTab(_sections[i].tab!),
                                onTap: () => setState(() => _index = i),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const VerticalDivider(width: 1, color: C.border),
                    Expanded(child: _content()),
                  ]),
            ),
          ]),
        ),
      );
}

class _SideItem extends StatelessWidget {
  const _SideItem(
      {required this.section,
      required this.selected,
      required this.count,
      required this.onTap});
  final _Section section;
  final bool selected;
  final int? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? C.accent : C.muted2;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? C.accentBg : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(children: [
              Icon(section.icon, size: 20, color: fg),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(section.label,
                      style:
                          TextStyle(color: fg, fontWeight: FontWeight.w500))),
              if (count != null)
                Text('$count',
                    style: const TextStyle(fontSize: 12, color: C.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}
