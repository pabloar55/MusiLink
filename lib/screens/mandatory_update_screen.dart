import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/services/app_update_service.dart';
import 'package:musi_link/theme/app_theme.dart';

class MandatoryUpdateScreen extends StatelessWidget {
  const MandatoryUpdateScreen({
    super.key,
    required this.policy,
    required this.onUpdate,
    required this.onRetry,
    this.isOpeningStore = false,
    this.storeOpenFailed = false,
  });

  final AppUpdatePolicy policy;
  final Future<void> Function() onUpdate;
  final Future<void> Function() onRetry;
  final bool isOpeningStore;
  final bool storeOpenFailed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTokens.spaceXL),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 96,
                      height: 96,
                      padding: const EdgeInsets.all(AppTokens.spaceLG),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withAlpha(24),
                        borderRadius: BorderRadius.circular(AppTokens.radiusLG),
                      ),
                      child: Image.asset('assets/images/iconoApp.png'),
                    ),
                    const SizedBox(height: AppTokens.space2XL),
                    Icon(
                      LucideIcons.download,
                      size: 32,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: AppTokens.spaceLG),
                    Text(
                      l10n.updateRequiredTitle,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: AppTokens.spaceMD),
                    Text(
                      l10n.updateRequiredBody,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceSM),
                    Text(
                      l10n.updateCurrentVersion(
                        policy.currentVersion,
                        policy.currentBuild,
                      ),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (storeOpenFailed) ...[
                      const SizedBox(height: AppTokens.spaceLG),
                      Text(
                        l10n.updateStoreOpenError,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppTokens.space2XL),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: isOpeningStore ? null : onUpdate,
                        icon: isOpeningStore
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(LucideIcons.externalLink),
                        label: Text(l10n.updateNowButton),
                      ),
                    ),
                    const SizedBox(height: AppTokens.spaceSM),
                    TextButton(
                      onPressed: isOpeningStore ? null : onRetry,
                      child: Text(l10n.updateRetryButton),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
