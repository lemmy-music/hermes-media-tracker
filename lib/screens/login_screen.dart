import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_strings.dart';
import '../providers/auth_provider.dart';

/// Signs the user in with an email magic link **or** the code from that email.
///
/// Two views: the email form, and — once the email has been requested — a
/// confirmation view carrying a numeric code input, so the user can finish
/// sign-in *in this browser/PWA context* without leaving to open the link
/// (which on iOS would land in a different storage — see PROJECT.md).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// Intentionally permissive — the server is the real authority.
  static final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  /// Shortest / longest code we accept. Supabase's default is 6 digits; we
  /// tolerate up to 8 so a differently configured project still works.
  static const int _minCodeLength = 6;
  static const int _maxCodeLength = 8;

  /// Seconds the "resend" action stays disabled after a send.
  static const int _resendCooldownSeconds = 30;

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();

  bool _sending = false;
  bool _verifying = false;
  String? _error;
  String? _codeError;

  /// Set once a link/code email has been requested.
  String? _sentTo;

  /// Remaining seconds of the resend cooldown (0 == ready).
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// A plausible code: 6–8 digits, nothing else.
  bool get _codeLooksValid {
    final code = _codeController.text.trim();
    if (code.length < _minCodeLength || code.length > _maxCodeLength) {
      return false;
    }
    return int.tryParse(code) != null;
  }

  Future<void> _send() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    // Read the provider *before* awaiting so no BuildContext is used across
    // an async gap.
    final auth = context.read<AuthProvider>();
    final email = _emailController.text.trim();

    setState(() {
      _sending = true;
      _error = null;
    });

    final error = await auth.sendMagicLink(email);

    if (!mounted) return;
    setState(() {
      _sending = false;
      if (error == null) {
        _sentTo = email;
        _codeError = null;
        _codeController.clear();
      } else {
        _error = error;
      }
    });
    if (error == null) _startResendCooldown();
  }

  Future<void> _verify() async {
    if (!_codeLooksValid) return;
    final auth = context.read<AuthProvider>();
    final email = _sentTo;
    if (email == null) return;
    final code = _codeController.text.trim();

    setState(() {
      _verifying = true;
      _codeError = null;
    });

    final error = await auth.verifyEmailCode(email: email, code: code);

    // On success the SDK tells `onAuthStateChange` and the AuthGate swaps the
    // screen out from under us — guard the state write either way.
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _codeError = error;
    });
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0 || _sending) return;
    final auth = context.read<AuthProvider>();
    final email = _sentTo;
    if (email == null) return;

    setState(() {
      _sending = true;
      _codeError = null;
    });

    final error = await auth.sendMagicLink(email);

    if (!mounted) return;
    setState(() {
      _sending = false;
      if (error != null) _codeError = error;
    });
    if (error == null) _startResendCooldown();
  }

  void _startResendCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = _resendCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCooldown -= 1;
        if (_resendCooldown <= 0) {
          _resendCooldown = 0;
          timer.cancel();
        }
      });
    });
  }

  void _useDifferentEmail() {
    _cooldownTimer?.cancel();
    setState(() {
      _sentTo = null;
      _error = null;
      _codeError = null;
      _resendCooldown = 0;
      _codeController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The default lets the keyboard shrink the viewport; the inner
      // SingleChildScrollView then keeps the code field reachable on phones.
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _sentTo == null
                  ? _buildForm(context)
                  : _buildSent(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.movie_filter_outlined, size: 64, color: cs.primary),
          const SizedBox(height: 20),
          Text(
            strings.appTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            strings.loginTagline,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _emailController,
            enabled: !_sending,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: strings.emailAddress,
              hintText: strings.emailHint,
              prefixIcon: const Icon(Icons.mail_outline),
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (email.isEmpty) return strings.emailRequired;
              if (!_emailPattern.hasMatch(email)) {
                return strings.emailInvalid;
              }
              return null;
            },
            onFieldSubmitted: (_) => _sending ? null : _send(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            _MessageBox(
              icon: Icons.error_outline,
              message: _error!,
              background: cs.errorContainer,
              foreground: cs.onErrorContainer,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_outlined),
            label: Text(_sending ? strings.sending : strings.sendMagicLink),
          ),
          const SizedBox(height: 16),
          Text(
            strings.magicLinkDetails,
            style: theme.textTheme.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSent(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final strings = context.strings;
    final sentTo = _sentTo!;
    final canResend = _resendCooldown == 0 && !_sending;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.mark_email_read_outlined, size: 64, color: cs.primary),
        const SizedBox(height: 20),
        Text(
          strings.checkInbox,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          strings.sentLinkTo(sentTo),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        _MessageBox(
          icon: Icons.info_outline,
          message: strings.linkOrCodeHint,
          background: cs.surfaceContainerHighest,
          foreground: cs.onSurfaceVariant,
        ),
        const SizedBox(height: 20),
        TextField(
          key: const Key('login-code-field'),
          controller: _codeController,
          enabled: !_verifying,
          autofocus: true,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          textAlign: TextAlign.center,
          maxLength: _maxCodeLength,
          autofillHints: const [AutofillHints.oneTimeCode],
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: theme.textTheme.headlineSmall?.copyWith(letterSpacing: 8),
          decoration: InputDecoration(
            labelText: strings.codeLabel,
            hintText: strings.codeHint,
            counterText: '',
            prefixIcon: const Icon(Icons.password_outlined),
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() => _codeError = null),
          onSubmitted: (_) {
            if (_codeLooksValid && !_verifying) _verify();
          },
        ),
        if (_codeError != null) ...[
          const SizedBox(height: 16),
          _MessageBox(
            icon: Icons.error_outline,
            message: _codeError!,
            background: cs.errorContainer,
            foreground: cs.onErrorContainer,
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          key: const Key('login-sign-in'),
          onPressed: (_codeLooksValid && !_verifying) ? _verify : null,
          icon: _verifying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.login_outlined),
          label: Text(_verifying ? strings.checkingCode : strings.signIn),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            TextButton.icon(
              key: const Key('login-resend'),
              onPressed: canResend ? _resend : null,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(
                _resendCooldown > 0
                    ? strings.resendInSeconds(_resendCooldown)
                    : strings.resendEmail,
              ),
            ),
            TextButton.icon(
              onPressed: _verifying ? null : _useDifferentEmail,
              icon: const Icon(Icons.arrow_back, size: 18),
              label: Text(strings.useDifferentEmail),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          strings.linkExpiryNote,
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Small rounded callout used for hints and errors.
class _MessageBox extends StatelessWidget {
  const _MessageBox({
    required this.icon,
    required this.message,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String message;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
