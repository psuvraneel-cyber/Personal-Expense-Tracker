import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pet/core/theme/motion.dart';

/// Makes any surface feel physical: it shrinks slightly while pressed and
/// springs back on release, with a light haptic tick on tap.
///
/// The press-in is quick so the response feels immediate; the release is a
/// little slower and eases out. With reduced motion the scale is skipped.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = Motion.pressedScale,
    this.haptic = true,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool haptic;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return Semantics(
      button: _enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _enabled ? (_) => _set(true) : null,
        onTapUp: _enabled ? (_) => _set(false) : null,
        onTapCancel: _enabled ? () => _set(false) : null,
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.selectionClick();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _down && !reduced ? widget.scale : 1,
          duration: _down ? const Duration(milliseconds: 90) : Motion.standard,
          curve: Motion.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
