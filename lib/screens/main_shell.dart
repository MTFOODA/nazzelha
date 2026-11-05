import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../services/app_statistics_service.dart';
import '../l10n/app_strings.dart';
import '../widgets/app_motion.dart';
import 'playlist_history_screen.dart';
import 'nazzelha_screen.dart';
import 'playlist_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  @override
  void initState() {
    super.initState();
    unawaited(context.read<AppStatisticsService>().recordWebsiteVisit());
  }

  int _index = 0;
  static const _pages = [
    NazzelhaScreen(),
    PlaylistScreen(),
    PlaylistHistoryScreen()
  ];
  static const _icons = [
    Icons.playlist_play_outlined,
    Icons.video_library_outlined,
    Icons.history_rounded
  ];
  static const _selectedIcons = [
    Icons.playlist_play_rounded,
    Icons.video_library_rounded,
    Icons.history_rounded
  ];

  void _select(int index) {
    if (index != _index) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _index = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final labels = [
      s.navHome,
      s.isAr ? 'بلاي ليست' : 'Playlist',
      s.isAr ? 'السجل' : 'History'
    ];
    final page = GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onHorizontalDragEnd: (details) {
          final direction =
              Directionality.of(context) == TextDirection.rtl ? -1 : 1;
          final velocity = (details.primaryVelocity ?? 0) * direction;
          if (velocity.abs() > 500) {
            _select((_index + (velocity < 0 ? 1 : -1)).clamp(0, 2));
          }
        },
        child: IndexedStack(
            index: _index,
            children: List.generate(
                _pages.length,
                (i) => TickerMode(
                    enabled: _index == i,
                    child: AnimatedOpacity(
                        opacity: _index == i ? 1 : 0,
                        duration: motionDuration(context, 180),
                        child: AnimatedSlide(
                            offset: _index == i
                                ? Offset.zero
                                : const Offset(0, .015),
                            duration: motionDuration(context, 200),
                            curve: Curves.easeOutCubic,
                            child: _pages[i]))))));
    return LayoutBuilder(builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 860;
      return Scaffold(
        body: desktop
            ? Row(children: [
                NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    extended: constraints.maxWidth >= 1180,
                    labelType: constraints.maxWidth >= 1180
                        ? NavigationRailLabelType.none
                        : NavigationRailLabelType.all,
                    minWidth: 92,
                    minExtendedWidth: 212,
                    leading: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 22, 12, 26),
                        child: Image.asset('assets/logo/nazzelha-v2.png',
                            width: 48, height: 48)),
                    destinations: List.generate(
                        3,
                        (i) => NavigationRailDestination(
                            icon: Icon(_icons[i]),
                            selectedIcon: Icon(_selectedIcons[i]),
                            label: Text(labels[i],
                                key: ValueKey('nav-$i-label'))))),
                const VerticalDivider(width: 1),
                Expanded(child: page),
              ])
            : SafeArea(top: true, bottom: false, child: page),
        bottomNavigationBar: desktop
            ? null
            : DecoratedBox(
                decoration: BoxDecoration(
                    border: Border(
                        top: BorderSide(
                            color: Theme.of(context).colorScheme.outline))),
                child: NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    animationDuration: motionDuration(context, 220),
                    destinations: List.generate(
                        3,
                        (i) => NavigationDestination(
                            key: ValueKey('nav-$i'),
                            icon: Icon(_icons[i]),
                            selectedIcon: AnimatedScale(
                                scale: _index == i ? 1.08 : 1,
                                duration: motionDuration(context),
                                child: Icon(_selectedIcons[i])),
                            label: labels[i])))),
      );
    });
  }
}
