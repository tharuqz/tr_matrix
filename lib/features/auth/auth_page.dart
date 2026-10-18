import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/app_scope.dart';
import '../../core/motion.dart';
import '../../core/responsive.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../widgets/common.dart';

/// Port of routes/auth.tsx — username + PIN sign in / sign up.
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool _signUp = false;
  bool _busy = false;
  String? _error;
  final _user = TextEditingController();
  final _name = TextEditingController();
  final _pin = TextEditingController();

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = AppScope.of(context).auth;
    final err = _signUp
        ? await auth.signUp(_user.text, _name.text.trim(), _pin.text)
        : await auth.signIn(_user.text, _pin.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  void dispose() {
    _user.dispose();
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tr;
    final mobile = Responsive.isMobile(context);
    final form = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.accent.withValues(alpha: .12),
              ),
              child: Icon(Icons.hub_rounded, color: context.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text('TRMatrix', style: TRText.display(30, c.text1)),
            ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          _signUp ? 'Create your account' : 'Welcome back',
          style: TRText.display(mobile ? 26 : 30, c.text1),
        ),
        const SizedBox(height: 6),
        Text(
          _signUp
              ? 'Pick a username and a 4–6 digit PIN.'
              : 'Sign in with your username and PIN.',
          style: TRText.body(15, c.text2),
        ),
        const SizedBox(height: 24),
        TRTextField(
          controller: _user,
          hint: 'Username',
          icon: Icons.alternate_email_rounded,
          maxLength: 20,
        ),
        if (_signUp) ...[
          const SizedBox(height: 12),
          TRTextField(
            controller: _name,
            hint: 'Display name',
            icon: Icons.person_outline_rounded,
          ),
        ],
        const SizedBox(height: 12),
        TRTextField(
          controller: _pin,
          hint: _signUp ? 'PIN (4–6 digits)' : 'PIN or password',
          icon: Icons.lock_outline_rounded,
          obscure: true,
          keyboard:
              _signUp ? TextInputType.number : TextInputType.visiblePassword,
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TRText.body(13, c.danger, w: FontWeight.w500)),
        ],
        const SizedBox(height: 20),
        TRButton(
          label: _signUp ? 'Create account' : 'Sign in',
          onPressed: _submit,
          loading: _busy,
          large: mobile,
        ),
        const SizedBox(height: 12),
        TRButton(
          label: _signUp ? 'I already have an account' : 'Create a new account',
          variant: TRButtonVariant.ghost,
          onPressed: () => setState(() {
            _signUp = !_signUp;
            _error = null;
          }),
        ),
      ],
    );

    return Scaffold(
      body: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.enter): _submit},
        child: MatrixBackground(
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(mobile ? 20 : 40),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: MatrixReveal(child: form),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
