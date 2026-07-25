import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/theme/app_theme.dart';

class PwaInstallScreen extends StatelessWidget {
  const PwaInstallScreen({required this.onContinueInBrowser, super.key});

  final VoidCallback onContinueInBrowser;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final steps = [
      l10n.pwaInstallStepMore,
      l10n.pwaInstallStepShare,
      l10n.pwaInstallStepSeeMore,
      l10n.pwaInstallStepAdd,
      l10n.pwaInstallStepOpen,
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTokens.spaceXL,
              vertical: AppTokens.spaceLG,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    padding: const EdgeInsets.all(AppTokens.spaceMD),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withAlpha(24),
                      borderRadius: BorderRadius.circular(AppTokens.radiusLG),
                    ),
                    child: Image.asset('assets/images/iconoApp.png'),
                  ),
                  const SizedBox(height: AppTokens.spaceXL),
                  Text(
                    l10n.pwaInstallTitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppTokens.spaceMD),
                  Text(
                    l10n.pwaInstallBody,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceXL),
                  for (var index = 0; index < steps.length; index++) ...[
                    _InstallStep(number: index + 1, text: steps[index]),
                    if (index != steps.length - 1)
                      const SizedBox(height: AppTokens.spaceSM),
                  ],
                  const SizedBox(height: AppTokens.spaceXL),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: onContinueInBrowser,
                      icon: const Icon(LucideIcons.compass),
                      label: Text(l10n.pwaInstallContinue),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InstallStep extends StatelessWidget {
  const _InstallStep({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTokens.spaceMD),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppTokens.radiusMD),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppTokens.spaceMD),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
