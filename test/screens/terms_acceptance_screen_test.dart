// ignore_for_file: subtype_of_sealed_class
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/router/app_router.dart';
import 'package:musi_link/router/go_router_provider.dart';
import 'package:musi_link/screens/terms_acceptance_screen.dart';
import 'package:musi_link/services/terms_acceptance_service.dart';

import '../helpers/mocks.dart';

class MockTermsAcceptanceService extends Mock
    implements TermsAcceptanceService {}

void main() {
  late MockFirebaseAuth auth;
  late MockUser user;
  late MockTermsAcceptanceService service;
  late AppRouterNotifier notifier;
  late StreamController<User?> authStream;

  setUp(() {
    auth = MockFirebaseAuth();
    user = MockUser();
    service = MockTermsAcceptanceService();
    authStream = StreamController<User?>.broadcast();
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.authStateChanges()).thenAnswer((_) => authStream.stream);
    when(() => user.uid).thenReturn('alice');
    notifier = AppRouterNotifier(auth: auth);
  });

  tearDown(() async {
    notifier.dispose();
    await authStream.close();
  });

  Widget app() => ProviderScope(
    overrides: [
      firebaseAuthProvider.overrideWithValue(auth),
      termsAcceptanceServiceProvider.overrideWithValue(service),
      appRouterNotifierProvider.overrideWithValue(notifier),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TermsAcceptanceScreen(),
    ),
  );

  testWidgets(
    'exige marcar la casilla y confirmar el registro en el servidor',
    (tester) async {
      final acceptance = Completer<void>();
      when(() => service.hasAcceptedCurrentVersion('alice'))
          .thenAnswer((_) async => false);
      when(() => service.acceptCurrentVersion())
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
      expect(notifier.termsAccepted, isFalse);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );

      await tester.tap(find.byType(FilledButton));
      await tester.pump();

      expect(find.text('Accepting…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      acceptance.complete();
      await tester.pumpAndSettle();

      verify(() => service.acceptCurrentVersion()).called(1);
      verify(() => service.hasAcceptedCurrentVersion('alice')).called(1);
      expect(notifier.termsAccepted, isTrue);
    },
  );

  testWidgets('no muestra el diálogo si la aceptación ya existe', (
    tester,
  ) async {
    when(() => service.hasAcceptedCurrentVersion('alice'))
        .thenAnswer((_) async => true);

    await tester.pumpWidget(app());

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(notifier.termsAccepted, isTrue);
  });

  testWidgets(
    'un fallo al comprobar el servidor mantiene el acceso bloqueado',
    (tester) async {
      when(() => service.hasAcceptedCurrentVersion('alice'))
          .thenThrow(StateError('offline'));

      await tester.pumpWidget(app());
      await tester.pump();

      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('Try again'), findsOneWidget);
      expect(notifier.termsAccepted, isFalse);
    },
  );
}
