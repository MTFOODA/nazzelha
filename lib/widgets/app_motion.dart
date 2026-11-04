import 'package:flutter/material.dart';

Duration motionDuration(BuildContext context, [int milliseconds = 180]) =>
    MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: milliseconds);

class PressMotion extends StatefulWidget {
  final Widget child;
  final bool enabled;
  const PressMotion({super.key, required this.child, this.enabled = true});
  @override
  State<PressMotion> createState() => _PressMotionState();
}

class _PressMotionState extends State<PressMotion> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown:
            widget.enabled ? (_) => setState(() => _pressed = true) : null,
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
            scale: !MediaQuery.disableAnimationsOf(context) &&
                    _pressed &&
                    widget.enabled
                ? .975
                : 1,
            duration: motionDuration(context, 120),
            curve: Curves.easeOutCubic,
            child: widget.child),
      );
}

class AppActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool outlined;
  final bool busy;
  const AppActionButton(
      {super.key,
      required this.label,
      required this.icon,
      this.onPressed,
      this.outlined = false,
      this.busy = false});
  @override
  Widget build(BuildContext context) {
    final glyph = busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2))
        : Icon(icon, size: 20);
    return PressMotion(
        enabled: onPressed != null && !busy,
        child: outlined
            ? OutlinedButton.icon(
                onPressed: busy ? null : onPressed,
                icon: glyph,
                label: Text(label))
            : FilledButton.icon(
                onPressed: busy ? null : onPressed,
                icon: glyph,
                label: Text(label)));
  }
}

class SoftPageTransitions extends PageTransitionsBuilder {
  const SoftPageTransitions();
  @override
  Widget buildTransitions<T>(
      PageRoute<T> route,
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curve =
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
        opacity: curve,
        child: SlideTransition(
            position: Tween(begin: const Offset(0, .025), end: Offset.zero)
                .animate(curve),
            child: child));
  }
}
