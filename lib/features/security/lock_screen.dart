import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/security/app_lock.dart';
import '../../core/theme/app_theme.dart';

/// Covers the whole app while it is locked.
class AppLockGate extends StatelessWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppLock.instance,
      builder: (_, __) {
        final l = AppLock.instance;
        return Stack(
          fit: StackFit.expand,
          children: [
            // Keep the app alive underneath (calls/zones keep running) but hidden.
            ExcludeFocus(
              excluding: l.locked,
              child: Offstage(
                offstage: l.locked,
                child: TickerMode(enabled: !l.locked, child: child),
              ),
            ),
            if (l.locked)
              Positioned.fill(
                child: PinPad(
                  title: 'TR MATRIX is locked',
                  subtitle: 'Enter your PIN',
                  onDone: l.unlock,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Ask for the PIN (or fingerprint) before doing something private.
/// Returns true when unlocked. If no PIN is set, asks to create one.
Future<bool> confirmUnlock(
  BuildContext context, {
  String title = 'Locked chats',
}) async {
  final l = AppLock.instance;
  if (!l.enabled) {
    final ok = await showSetPinDialog(context);
    return ok;
  }
  final ok = await Navigator.of(context, rootNavigator: true).push<bool>(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: true,
      pageBuilder: (ctx, _, __) => PinPad(
        title: title,
        subtitle: 'Enter your PIN',
        canCancel: true,
        onDone: () => Navigator.pop(ctx, true),
      ),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
  return ok == true;
}

/// Create (or change) the PIN. Returns true when saved.
Future<bool> showSetPinDialog(BuildContext context) async {
  final ok = await Navigator.of(context, rootNavigator: true).push<bool>(
    PageRouteBuilder(
      opaque: false,
      pageBuilder: (ctx, _, __) =>
          _SetPin(onSaved: () => Navigator.pop(ctx, true)),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
  return ok == true;
}

class PinPad extends StatefulWidget {
  final String title, subtitle;
  final VoidCallback onDone;
  final bool canCancel;
  final bool checkPin;
  final ValueChanged<String>? onEntered; // used when creating a PIN
  final int? fixedLength;
  const PinPad({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onDone,
    this.canCancel = false,
    this.checkPin = true,
    this.onEntered,
    this.fixedLength,
  });
  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _err = false;
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
  );
  final _focus = FocusNode();

  AppLock get _l => AppLock.instance;
  int get _len => widget.checkPin ? _l.pinLength : (widget.fixedLength ?? 0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    // Fingerprint pops up straight away, only if you switched it on.
    if (widget.checkPin && _l.useBiometric) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _bio());
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _bio() async {
    final ok = await _l.authenticateBiometric();
    if (!mounted) return;
    if (ok && _l.useBiometric) {
      widget.onDone();
    } else {
      _focus.requestFocus();
    }
  }

  void _press(String d) {
    if (_pin.length >= 8) return;
    setState(() {
      _pin += d;
      _err = false;
    });
    final full = _len > 0 ? _pin.length == _len : false;
    if (!widget.checkPin) {
      if (full) _submit();
      return;
    }
    if (_l.verify(_pin)) {
      HapticFeedback.lightImpact();
      widget.onDone();
    } else if (full || _pin.length == 8) {
      _fail();
    }
  }

  void _submit() {
    if (!widget.checkPin) {
      if (_pin.length < 4) return _fail();
      widget.onEntered?.call(_pin);
      setState(() => _pin = '');
      return;
    }
    if (_l.verify(_pin)) {
      widget.onDone();
    } else {
      _fail();
    }
  }

  void _fail() {
    HapticFeedback.heavyImpact();
    setState(() => _err = true);
    _shake.forward(from: 0);
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) setState(() => _pin = '');
    });
  }

  void _back() {
    if (_pin.isNotEmpty)
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr, a = context.accent;
    final desktop = switch (Theme.of(context).platform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux =>
        true,
      _ => false,
    };
    final slots = _len > 0
        ? _len
        : math.max(4, math.min(8, _pin.length + (_pin.length < 8 ? 1 : 0)));
    Widget key(String label, {IconData? icon, VoidCallback? onTap}) => Padding(
          padding: const EdgeInsets.all(8),
          child: InkResponse(
            onTap: onTap ?? () => _press(label),
            radius: 40,
            child: Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: icon == null
                    ? c.surface2.withValues(alpha: .8)
                    : Colors.transparent,
                border: icon == null ? Border.all(color: c.border) : null,
              ),
              child: icon != null
                  ? Icon(icon, color: c.text1, size: 26)
                  : Text(label, style: TRText.display(26, c.text1)),
            ),
          ),
        );
    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (e) {
        if (e is! KeyDownEvent) return;
        final ch = e.character;
        if (ch != null && RegExp(r'^\d$').hasMatch(ch)) _press(ch);
        if (e.logicalKey == LogicalKeyboardKey.backspace) _back();
        if (e.logicalKey == LogicalKeyboardKey.enter) _submit();
        if (e.logicalKey == LogicalKeyboardKey.escape && widget.canCancel)
          Navigator.pop(context, false);
      },
      child: Material(
        color: c.bg.withValues(alpha: .97),
        child: SafeArea(
          child: Stack(
            children: [
              if (widget.canCancel)
                Positioned(
                  top: 8,
                  left: 8,
                  child: IconButton(
                    icon: Icon(Icons.close_rounded, color: c.text2),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ),
              Center(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: a.withValues(alpha: .14),
                          boxShadow: [
                            BoxShadow(
                              color: a.withValues(alpha: .35),
                              blurRadius: 24,
                            ),
                          ],
                        ),
                        child: Icon(Icons.lock_rounded, color: a, size: 28),
                      ),
                      const SizedBox(height: 16),
                      Text(widget.title, style: TRText.display(20, c.text1)),
                      const SizedBox(height: 4),
                      Text(
                        _err ? 'Wrong PIN, try again' : widget.subtitle,
                        style: TRText.body(13, _err ? c.danger : c.text3),
                      ),
                      const SizedBox(height: 20),
                      AnimatedBuilder(
                        animation: _shake,
                        builder: (_, child) => Transform.translate(
                          offset: Offset(
                            math.sin(_shake.value * math.pi * 6) *
                                10 *
                                (1 - _shake.value),
                            0,
                          ),
                          child: child,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < slots; i++)
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                ),
                                width: 14,
                                height: 14,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i < _pin.length
                                      ? (_err ? c.danger : a)
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: _err
                                        ? c.danger
                                        : (i < _pin.length ? a : c.text3),
                                    width: 1.5,
                                  ),
                                  boxShadow: i < _pin.length && !_err
                                      ? [
                                          BoxShadow(
                                            color: a.withValues(alpha: .5),
                                            blurRadius: 8,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (!desktop) ...[
                        for (final row in const [
                          ['1', '2', '3'],
                          ['4', '5', '6'],
                          ['7', '8', '9'],
                        ])
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [for (final d in row) key(d)],
                          ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            widget.checkPin && _l.useBiometric
                                ? key(
                                    '',
                                    icon: Icons.fingerprint_rounded,
                                    onTap: _bio,
                                  )
                                : (_len == 0 || !widget.checkPin)
                                    ? key(
                                        '',
                                        icon: Icons.check_rounded,
                                        onTap: _submit,
                                      )
                                    : const SizedBox(width: 88, height: 88),
                            key('0'),
                            key(
                              '',
                              icon: Icons.backspace_outlined,
                              onTap: _back,
                            ),
                          ],
                        ),
                      ] else if (widget.checkPin && _l.useBiometric)
                        IconButton(
                          tooltip: 'Fingerprint unlock',
                          icon: Icon(Icons.fingerprint_rounded, color: a),
                          onPressed: _bio,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetPin extends StatefulWidget {
  final VoidCallback onSaved;
  const _SetPin({required this.onSaved});
  @override
  State<_SetPin> createState() => _SetPinState();
}

class _SetPinState extends State<_SetPin> {
  String? _first;
  int _round = 0;
  @override
  Widget build(BuildContext context) {
    return PinPad(
      key: ValueKey(_round),
      title: _first == null ? 'Create a PIN' : 'Confirm your PIN',
      subtitle: _first == null ? '4 to 8 digits' : 'Enter the same PIN again',
      canCancel: true,
      checkPin: false,
      fixedLength: _first?.length,
      onDone: () {},
      onEntered: (pin) async {
        if (_first == null) {
          setState(() {
            _first = pin;
            _round++;
          });
          return;
        }
        if (pin != _first) {
          setState(() {
            _first = null;
            _round++;
          });
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(content: Text("PINs didn't match. Try again.")),
          );
          return;
        }
        await AppLock.instance.setPin(pin);
        if (!mounted) return;
        AppLock.instance.unlock();
        widget.onSaved();
      },
    );
  }
}
