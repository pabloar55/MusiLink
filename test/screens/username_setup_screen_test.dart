import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/screens/username_setup_screen.dart';
import 'package:musi_link/services/user_service.dart';

import '../helpers/mocks.dart';

Widget _app({
  required MockFirebaseAuth auth,
  required MockUserService userService,
}) {
  return ProviderScope(
    overrides: [
      firebaseAuthProvider.overrideWithValue(auth),
      userServiceProvider.overrideWithValue(userService),
    ],
    child: const MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: UsernameSetupScreen(),
    ),
  );
}

void main() {
  late MockFirebaseAuth auth;
  late MockUser authUser;
  late MockUserService userService;

  setUp(() {
    auth = MockFirebaseAuth();
    authUser = MockUser();
    userService = MockUserService();
    when(() => auth.currentUser).thenReturn(authUser);
    when(() => authUser.displayName).thenReturn('Alice');
  });

  testWidgets('ignora respuestas antiguas del debounce', (tester) async {
    final aliceResult = Completer<bool>();
    final bobResult = Completer<bool>();
    when(
      () => userService.usernameExists('alice_name'),
    ).thenAnswer((_) => aliceResult.future);
    when(
      () => userService.usernameExists('bob_name'),
    ).thenAnswer((_) => bobResult.future);

    await tester.pumpWidget(_app(auth: auth, userService: userService));
    final usernameField = find.byType(TextFormField).at(1);

    await tester.enterText(usernameField, 'alice_name');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(usernameField, 'bob_name');
    await tester.pump(const Duration(milliseconds: 600));

    aliceResult.complete(false);
    await tester.pump();

    FilledButton button = tester.widget(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('Available'), findsNothing);

    bobResult.complete(false);
    await tester.pump();

    button = tester.widget(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
    expect(find.text('Available'), findsOneWidget);
  });

  testWidgets('muestra conflicto autoritativo devuelto por la callable', (
    tester,
  ) async {
    when(
      () => userService.usernameExists('alice_name'),
    ).thenAnswer((_) async => false);
    when(
      () => userService.createUserProfile(
        displayName: any(named: 'displayName'),
        username: any(named: 'username'),
      ),
    ).thenThrow(const UsernameAlreadyTakenException());

    await tester.pumpWidget(_app(auth: auth, userService: userService));
    await tester.enterText(find.byType(TextFormField).at(1), 'alice_name');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('This username is already taken'), findsWidgets);
  });
}
