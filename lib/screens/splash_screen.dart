import 'dart:async';
import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;
  Timer? _navigation;
  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 520));
    _navigation = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) Navigator.of(context).pushReplacementNamed('/home');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = 1;
    } else {
      _animation.forward();
    }
  }

  @override
  void dispose() {
    _navigation?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final curve =
        CurvedAnimation(parent: _animation, curve: Curves.easeOutCubic);
    return Scaffold(
        body: Center(
            child: FadeTransition(
                opacity: curve,
                child: ScaleTransition(
                    scale: Tween(begin: .94, end: 1.0).animate(curve),
                    child: Padding(
                        padding: const EdgeInsets.all(28),
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          Image.asset('assets/logo/nazzelha-v2.png',
                              width: 126, height: 126),
                          const SizedBox(height: 24),
                          Text('Nazzelha',
                              style: theme.textTheme.headlineLarge
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),
                          Text(
                              AppStrings.of(context)
                                  .text('All your media, one place.'),
                              style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ]))))));
  }
}
