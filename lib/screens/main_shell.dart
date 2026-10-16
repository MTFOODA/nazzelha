import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import 'home_screen.dart';
import 'nazzelha_sawa_screen.dart';

/// Top-level navigation shell.
///
/// Hosts the existing download page (Home) and the new Nazzelha Sawa queue
/// behind a bottom navigation bar. A right-swipe on the Home tab also opens
/// Nazzelha Sawa; the gesture only listens for a deliberate horizontal drag,
/// so it does not interfere with dropdowns, text fields, or the queue list's
/// vertical scrolling.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.of(context);
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onHorizontalDragEnd: _index == 0 ? _onSwipeEnd : null,
        child: IndexedStack(
          index: _index,
          children: const [
            HomeScreen(),
            NazzelhaSawaScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.download_outlined),
            selectedIcon: const Icon(Icons.download),
            label: strings.navDownload,
          ),
          NavigationDestination(
            icon: const Icon(Icons.playlist_play_outlined),
            selectedIcon: const Icon(Icons.playlist_play),
            label: strings.navSawa,
          ),
        ],
      ),
    );
  }

  void _onSwipeEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    // Swipe right (positive primary velocity in LTR) opens Nazzelha Sawa.
    if (velocity > 400) {
      setState(() => _index = 1);
    }
  }
}
