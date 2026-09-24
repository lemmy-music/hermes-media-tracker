import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// Signs the user in with an email magic link.
///
/// Two views: the email form, and — once a link has been requested — a
/// confirmation view so the user knows to check their inbox.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// Intentionally permissive — the server is the real authority.
  static final RegExp _emailPattern =
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();

  bool _sending = false;
  String? _error;

  /// Set once a link has been requested.
  String? _sentTo;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
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
      } else {
        _error = error;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _sentTo == null ? _buildForm(context) : _buildSent(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.movie_filter_outlined, size: 64, color: cs.primary),
          const SizedBox(height: 20),
          Text(
            'Media Tracker',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Track the movies, series and books you have seen, watched and '
            'read.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
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
            decoration: const InputDecoration(
              labelText: 'Email address',
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.mail_outline),
              border: OutlineInputBorder(),
            ),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (email.isEmpty) return 'Please enter your email address.';
              if (!_emailPattern.hasMatch(email)) {
                return 'Please enter a valid email address.';
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
            label: Text(_sending ? 'Sending…' : 'Send magic link'),
          ),
          const SizedBox(height: 16),
          Text(
            'No password needed — we will email you a one-time sign-in link. '
            'A new account is created on your first sign-in.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSent(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final sentTo = _sentTo!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.mark_email_read_outlined, size: 64, color: cs.primary),
        const SizedBox(height: 20),
        Text(
          'Check your inbox',
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Text(
          'We sent a sign-in link to $sentTo. Open it in this browser to '
          'finish signing in.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        _MessageBox(
          icon: Icons.info_outline,
          message: 'The link expires after a short while. Nothing in your '
              'inbox? Check the spam folder.',
          background: cs.surfaceContainerHighest,
          foreground: cs.onSurfaceVariant,
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _sentTo = null;
            _error = null;
          }),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Use a different email'),
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
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}
