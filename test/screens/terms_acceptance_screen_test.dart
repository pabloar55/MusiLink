// ignore_for_file: subtype_of_sealed_class
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/models/user_setup_state.dart';
import 'package:musi_link/providers/terms_acceptance_provider.dart';
import 'package:musi_link/router/app_router.dart';
import 'package:musi_link/screens/terms_acceptance_screen.dart';
import 'package:musi_link/services/terms_acceptance_controller.dart';
import 'package:musi_link/services/terms_acceptance_service.dart';
import 'package:musi_link/services/user_setup_controller.dart';
import 'package:musi_link/utils/app_localizations_delegates.dart';

import '../helpers/mocks.dart';

class MockTermsAcceptanceService extends Mock
    implements TermsAcceptanceService {}

void main() {
  late MockFirebaseAuth auth;
  late MockUser user;
  late MockTermsAcceptanceService service;
  late TermsAcceptanceController terms;
  late StreamController<User?> authStream;

  setUp(() {
    auth = MockFirebaseAuth();
    user = MockUser();
    service = MockTermsAcceptanceService();
    authStream = StreamController<User?>.broadcast();
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.authStateChanges()).thenAnswer((_) => authStream.stream);
    when(() => user.uid).thenReturn('alice');
    terms = TermsAcceptanceController(
      auth: auth,
      submitAcceptance: service.submitAcceptance,
    );
  });

  tearDown(() async {
    terms.dispose();
    await authStream.close();
  });

  Widget app({GoRouter? router}) => ProviderScope(
    overrides: [
      firebaseAuthProvider.overrideWithValue(auth),
      termsAcceptanceServiceProvider.overrideWithValue(service),
      termsAcceptanceControllerProvider.overrideWithValue(terms),
    ],
    child: router != null
        ? MaterialApp.router(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          )
        : const MaterialApp(
            localizationsDelegates: appLocalizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: TermsAcceptanceScreen(),
          ),
  );

  testWidgets(
    'exige marcar la casilla y avanza sin esperar al registro en el servidor',
    (tester) async {
      final acceptance = Completer<bool>();
      when(() => service.submitAcceptance('alice'))
          .thenAnswer((_) => acceptance.future);

      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Read Privacy Policy'), findsNothing);
      expect(find.text('Decline and sign out'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      expect(terms.termsAccepted, isFalse);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(terms.termsAccepted, isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      acceptance.complete(true);
      await tester.pumpAndSettle();

      verify(() => service.submitAcceptance('alice')).called(1);
      verifyNever(() => service.hasAcceptedCurrentVersion('alice'));
      expect(terms.termsAccepted, isTrue);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  for (final accepted in [true, false]) {
    testWidgets(
      'primera apertura sin loader, respuesta de aceptación: $accepted',
      (tester) async {
        final check = Completer<bool>();
        when(() => service.hasCachedAcceptance('alice')).thenReturn(false);
        when(() => service.hasAcceptedCurrentVersion('alice'))
            .thenAnswer((_) => check.future);
        terms.dispose();
        terms = TermsAcceptanceController(
          auth: auth,
          readCachedAcceptance: service.hasCachedAcceptance,
          refreshAcceptance: service.hasAcceptedCurrentVersion,
        );
        final setup = UserSetupController(auth: auth);
        addTearDown(setup.dispose);
        final notifier = AppRouterNotifier(
          auth: auth,
          setup: setup,
          terms: terms,
          initialState: const UserSetupBootstrapState(
            usernameSet: true,
            artistsSelected: true,
            onboardingDone: true,
            photoSetupDone: true,
            userUid: 'alice',
          ),
        );
        addTearDown(notifier.dispose);
        final router = GoRouter(
          initialLocation: '/',
          refreshListenable: notifier,
          redirect: (_, state) => appRedirect(notifier, state.matchedLocation),
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const Scaffold(body: Text('Inicio')),
            ),
            GoRoute(
              path: '/terms',
              builder: (_, _) => const TermsAcceptanceScreen(),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(app(router: router));
        authStream.add(user);
        await tester.pumpAndSettle();
        expect(find.text('Inicio'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(terms.termsAccepted, isFalse);

        check.complete(accepted);
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          find.byType(AlertDialog),
          accepted ? findsNothing : findsOneWidget,
        );
        expect(terms.termsAccepted, accepted);
        verify(() => service.hasAcceptedCurrentVersion('alice')).called(1);
      },
    );
  }

  testWidgets(
    'un rechazo del servidor retira la aceptación y permite reintentar',
    (tester) async {
      when(() => service.submitAcceptance('alice'))
          .thenAnswer((_) async => false);

      await tester.pumpWidget(app());
      await tester.pump();

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.text('We could not save your acceptance. Please try again.'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );
      expect(terms.termsAccepted, isFalse);
    },
  );
}
