import 'package:flutter/material.dart';

import 'core/transfer.dart';
import 'core/vault.dart';
import 'ui/auth_screens.dart';
import 'ui/home_screen.dart';
import 'ui/theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final vault = Vault();
  await vault.init();
  runApp(FLockerApp(vault: vault));
}

class FLockerApp extends StatefulWidget {
  const FLockerApp({super.key, required this.vault});
  final Vault vault;

  @override
  State<FLockerApp> createState() => _FLockerAppState();
}

class _FLockerAppState extends State<FLockerApp> with WidgetsBindingObserver {
  DateTime? _leftAt;
  bool _wasUnlocked = false;

  Vault get vault => widget.vault;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    vault.addListener(_onVaultChanged);
  }

  @override
  void dispose() {
    vault.removeListener(_onVaultChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onVaultChanged() {
    final unlocked = vault.isUnlocked;
    if (_wasUnlocked && !unlocked) {
      // Locked: close every open screen and stop receiving files.
      navigatorKey.currentState?.popUntil((r) => r.isFirst);
      transferServer.stop();
    }
    _wasUnlocked = unlocked;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!vault.isUnlocked) return;
    final minutes = vault.autoLockMinutes;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (vault.autoLockHeld || minutes < 0) return;
      if (minutes == 0) {
        vault.lock();
        return;
      }
      _leftAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left != null &&
          minutes >= 0 &&
          DateTime.now().difference(left).inSeconds >= minutes * 60) {
        vault.lock();
      }
    }
  }

  Widget _root() {
    if (!vault.isSetUp) return SetupScreen(vault: vault);
    if (!vault.isUnlocked) return LockScreen(vault: vault);
    if (vault.mustResetPassword) return ResetPasswordScreen(vault: vault);
    final key = vault.pendingRecoveryKey;
    if (key != null) return RecoveryKeyScreen(vault: vault, recoveryKey: key);
    return HomeScreen(vault: vault);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'F-Locker',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: ListenableBuilder(listenable: vault, builder: (_, __) => _root()),
      );
}
