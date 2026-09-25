import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/models/track.dart';
import 'package:musi_link/providers/daily_song_provider.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/services/daily_song_interaction_service.dart';
import 'package:musi_link/widgets/discover/daily_song_actions.dart';

import '../helpers/mocks.dart';

class MockInteractions extends Mock implements DailySongInteractionService {}

class MockChat extends Mock implements ChatService {}

void main() {
  final publishedAt = DateTime.now();
  final owner = AppUser(
    uid: 'alice',
    displayName: 'Alice',
    dailySong: const Track(title: 'Song', artist: 'Artist', imageUrl: ''),
    dailySongUpdatedAt: publishedAt,
  );
  final publication = (ownerId: 'alice', publishedAt: publishedAt);
  late MockInteractions interactions;
  late MockChat chat;

  setUp(() {
    interactions = MockInteractions();
    chat = MockChat();
  });

  Future<void> pump(
    WidgetTester tester, {
    String uid = 'bob',
    List<String> friends = const ['alice'],
    List<String> blocked = const [],
    Set<String> likes = const {},
    AppUser? songOwner,
  }) async {
    final auth = MockFirebaseAuth();
    final user = MockUser();
    when(() => user.uid).thenReturn(uid);
    when(() => auth.currentUser).thenReturn(user);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          authStateProvider.overrideWith((ref) => Stream.value(user)),
          friendsStreamProvider.overrideWith((ref) => Stream.value(friends)),
          blockedUsersProvider.overrideWith((ref) => Stream.value(blocked)),
          dailySongLikesProvider(publication)
              .overrideWith((ref) => Stream.value(likes)),
          dailySongMyLikeProvider(publication)
              .overrideWith((ref) => Stream.value(likes.contains(uid))),
          userStreamProvider('bob').overrideWith(
            (ref) => Stream.value(
              const AppUser(
                uid: 'bob',
                displayName: 'Bob',
                username: 'bob_music',
              ),
            ),
          ),
          dailySongInteractionServiceProvider.overrideWithValue(interactions),
          chatServiceProvider.overrideWithValue(chat),
        ],
        child: MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: DailySongActions(owner: songOwner ?? owner)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'permite dar y quitar like, sin duplicar pulsaciones pendientes',
    (tester) async {
      final pending = Completer<void>();
      when(() => interactions.setLiked(publication, true))
          .thenAnswer((_) => pending.future);
      await pump(tester);
      expect(find.text('0 · Me gusta'), findsNothing);
      expect(find.text('Quitar me gusta'), findsNothing);
      expect(tester.widget<IconButton>(find.byType(IconButton)).iconSize, 32);
      await tester.tap(find.byIcon(Icons.favorite_border));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.favorite_border));
      verify(() => interactions.setLiked(publication, true)).called(1);
      pending.complete();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      when(() => interactions.setLiked(publication, false))
          .thenAnswer((_) async {});
      await pump(tester, likes: {'bob'});
      await tester.tap(find.byIcon(Icons.favorite));
      await tester.pumpAndSettle();
      verify(() => interactions.setLiked(publication, false)).called(1);
    },
  );

  testWidgets('el titular ve likes y no puede responder ni darse like', (
    tester,
  ) async {
    await pump(tester, uid: 'alice', likes: {'bob'});
    expect(find.text('Responder'), findsNothing);
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, '1 · Me gusta'),
    );
    expect(button.onPressed, isNotNull);
    await tester.tap(find.text('1 · Me gusta'));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('@bob_music'), findsOneWidget);
  });

  testWidgets(
    'oculta acciones para desconocidos, bloqueados y canciones caducadas',
    (tester) async {
      await pump(tester, friends: []);
      expect(find.byType(TextButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await pump(tester, blocked: ['alice']);
      expect(find.byType(TextButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await pump(
        tester,
        songOwner: owner.copyWith(
          dailySongUpdatedAt: DateTime.now().subtract(
            const Duration(hours: 25),
          ),
        ),
      );
      expect(find.byType(TextButton), findsNothing);
    },
  );

  testWidgets(
    'conserva el borrador tras error y envía la respuesta privada al reintentar',
    (tester) async {
      var attempts = 0;
      when(() => chat.sendDailySongReply(owner, 'Me encanta'))
          .thenAnswer((_) async {
            if (attempts++ == 0) throw StateError('offline');
          });
      await pump(tester);
      await tester.tap(find.text('Responder'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Me encanta');
      await tester.pump();
      await tester.tap(find.text('Enviar'));
      await tester.pumpAndSettle();
      expect(find.text('Me encanta'), findsOneWidget);
      expect(find.textContaining('No se pudo guardar'), findsOneWidget);
      await tester.tap(find.text('Enviar'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Respuesta enviada al chat.'), findsOneWidget);
      verify(() => chat.sendDailySongReply(owner, 'Me encanta')).called(2);
    },
  );

  testWidgets('no envía respuestas que exceden el límite UTF-8', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Responder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '🎵' * 501);
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(find.text('La respuesta es demasiado larga.'), findsOneWidget);
  });
}
