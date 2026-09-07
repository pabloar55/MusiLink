import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/router/go_router_provider.dart';
import 'package:musi_link/widgets/onboarding/onboarding_page.dart';

/// Pantalla de bienvenida con slider de 5 páginas explicativas.
/// Se muestra solo la primera vez que el usuario inicia sesión.
/// El router guarda el progreso de forma independiente por cuenta.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  static const int _totalPages = 3;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _completeOnboarding() {
    ref.read(appRouterNotifierProvider).setOnboardingDone();
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final pages = [
      OnboardingPage(
        icon: LucideIcons.compass,
        title: l10n.onboardingDiscoverTitle,
        description: l10n.onboardingDiscoverDesc,
      ),
      OnboardingPage(
        icon: LucideIcons.music,
        title: l10n.onboardingProfileTitle,
        description: l10n.onboardingProfileDesc,
      ),
      OnboardingPage(
        icon: LucideIcons.users,
        title: l10n.onboardingConnectTitle,
        description: l10n.onboardingConnectDesc,
      ),
    ];

    final isLastPage = _currentPage == _totalPages - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Botón Skip arriba a la derecha
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 16),
                child: TextButton(
                  onPressed: _completeOnboarding,
                  child: Text(
                    l10n.onboardingSkip,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),

            // PageView con las páginas
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                children: pages,
              ),
            ),

            // Dot indicators
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_totalPages, (index) {
                  final isActive = index == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isActive ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: isActive
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    ),
                  );
                }),
              ),
            ),

            // Botón Next / Get Started
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: isLastPage ? _completeOnboarding : _nextPage,
                  child: Text(
                    isLastPage
                        ? l10n.onboardingGetStarted
                        : l10n.onboardingNext,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
