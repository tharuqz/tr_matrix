import 'package:flutter/material.dart';

Duration matrixDuration(BuildContext context, [int milliseconds = 220]) =>
    MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: milliseconds);

class MatrixReveal extends StatelessWidget {
  final Widget child;
  const MatrixReveal({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: matrixDuration(context),
      curve: Curves.easeOutCubic,
      builder:
          (_, value, content) => Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 10 * (1 - value)),
              child: content,
            ),
          ),
      child: child,
    );
  }
}

/// Retains the same navigation child across branch changes.
class MatrixPageMotion extends StatefulWidget {
  final Object trigger;
  final Widget child;
  const MatrixPageMotion({
    super.key,
    required this.trigger,
    required this.child,
  });
  @override
  State<MatrixPageMotion> createState() => _MatrixPageMotionState();
}

class _MatrixPageMotionState extends State<MatrixPageMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    value: 1,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = matrixDuration(context, 260);
    if (MediaQuery.disableAnimationsOf(context)) _controller.value = 1;
  }

  @override
  void didUpdateWidget(MatrixPageMotion old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger &&
        !MediaQuery.disableAnimationsOf(context))
      _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _fade, child: widget.child);
}
