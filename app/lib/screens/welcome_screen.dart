import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/tokens.dart';
import '../widgets/chrome.dart';
import 'create_account_screen.dart';
import 'sign_in_screen.dart';

/// Launch frame `2003:172`. Light uses the app canvas; dark keeps the black
/// welcome ground so the gray / white wordmarks stay readable.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: dark ? PaperTokens.welcomeBackground : colors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            PaperTokens.space24,
            72,
            PaperTokens.space24,
            PaperTokens.space32,
          ),
          child: Column(
            children: [
              const _WelcomeLogo(),
              const SizedBox(height: PaperTokens.space16),
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontFamily: PaperTokens.fontFamily,
                    fontSize: PaperTokens.displaySize,
                    height: PaperTokens.displayHeight,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                  children: [
                    TextSpan(text: 'Paper', style: TextStyle(color: colors.ink)),
                    const TextSpan(
                      text: 'Sync',
                      style: TextStyle(color: PaperTokens.logoBlue),
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: PaperTokens.space8),
              Text(
                'Your paper notebook, searchable\nand safely synced.',
                textAlign: TextAlign.center,
                style: PaperType.bodyRelaxed(colors.meta),
              ),
              const Spacer(),
              _WelcomePrimary(
                label: 'Sign in',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SignInScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: PaperTokens.space12),
              SecondaryButton(
                label: 'Create account',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CreateAccountScreen(),
                    ),
                  );
                },
              ),
              TextButton(
                onPressed: onContinue,
                child: Text(
                  'Continue without account',
                  style: PaperType.caption(colors.meta),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// App-icon brand mark above the PaperSync wordmark; no pale card.
class _WelcomeLogo extends StatelessWidget {
  const _WelcomeLogo();

  static const _size = PaperTokens.penGlyph;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: Image.asset(
        dark
            ? 'assets/images/logo-welcome-dark.png'
            : 'assets/images/logo-welcome.png',
        width: _size,
        height: _size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

class _WelcomePrimary extends StatelessWidget {
  const _WelcomePrimary({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.ink,
          foregroundColor: colors.onAccent,
          side: BorderSide(color: colors.page),
          minimumSize: const Size(double.infinity, PaperTokens.minTap),
        ),
        child: Text(label),
      ),
    );
  }
}
