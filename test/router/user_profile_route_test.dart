import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/router/app_locations.dart';
import 'package:musi_link/screens/user_profile_route_screen.dart';

import '../helpers/mocks.dart';

void main() {
  test('userProfileLocation codifica el uid y conserva fromChat', () {
    expect(
      userProfileLocation('user/with space', fromChat: true),
      '/profile/user%2Fwith%20space?fromChat=true',
    );
  });

  testWidgets('la ruta de perfil se recupera por uid cuando no hay extra', (
    tester,
  ) async {
    final userService = MockUserService();
    final userStream = StreamController<AppUser?>();
    addTearDown(userStream.close);
    when(() => userService.watchUser('user-1'))
        .thenAnswer((_) => userStream.stream);

    final router = GoRouter(
      initialLocation: '/profile/user-1',
      routes: [GoRoute(path: '/profile/:uid', builder: buildUserProfileRoute)],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [userServiceProvider.overrideWithValue(userService)],
        child: MaterialApp.router(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
    verify(() => userService.watchUser('user-1')).called(1);
  });
}
