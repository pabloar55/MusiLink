import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:musi_link/widgets/chat/chat_input_bar.dart';
import 'package:musi_link/widgets/discover/daily_song_reply_sheet.dart';
import 'package:musi_link/widgets/track_artwork.dart';
import 'package:musi_link/widgets/user_circle_avatar.dart';
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
    username: 'alice_music',
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
      expect(tester.widget<IconButton>(find.byType(IconButton)).iconSize, 28);
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
    'abre un bottom sheet con usuario, canción y la barra del chat sin compartir canción',
    (tester) async {
      await pump(tester);
      await tester.tap(find.text('Responder'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(DailySongReplySheet), findsOneWidget);
      expect(find.byType(ChatInputBar), findsOneWidget);
      expect(find.byType(UserCircleAvatar), findsOneWidget);
      expect(find.byType(TrackArtwork), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('@alice_music'), findsOneWidget);
      expect(find.text('Song'), findsOneWidget);
      expect(find.text('Artist'), findsOneWidget);
      expect(find.text('Escribe un mensaje...'), findsOneWidget);
      expect(find.widgetWithIcon(IconButton, LucideIcons.music), findsNothing);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, LucideIcons.sendHorizontal500),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      verifyNever(() => chat.sendDailySongReply(owner, any()));
    },
  );

  testWidgets('cierra inmediatamente sin enviando y evita enviar dos veces', (
    tester,
  ) async {
    final pending = Completer<void>();
    when(() => chat.sendDailySongReply(owner, 'Me encanta'))
        .thenAnswer((_) => pending.future);
    await pump(tester);
    await tester.tap(find.text('Responder'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Me encanta');
    await tester.pump();
    final send = tester
        .widget<IconButton>(
          find.widgetWithIcon(IconButton, LucideIcons.sendHorizontal500),
        )
        .onPressed!;
    send();
    send();
    await tester.pumpAndSettle();
    expect(pending.isCompleted, isFalse);
    expect(find.byType(DailySongReplySheet), findsNothing);
    expect(find.text('Enviando…'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    verify(() => chat.sendDailySongReply(owner, 'Me encanta')).called(1);
    pending.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'recupera una respuesta fallida tras cerrar el sheet y permite reintentar',
    (tester) async {
      final pending = Completer<void>();
      when(() => chat.sendDailySongReply(owner, 'Me encanta'))
          .thenAnswer((_) => pending.future);
      await pump(tester);
      await tester.tap(find.text('Responder'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Me encanta');
      await tester.pump();
      await tester.tap(find.byIcon(LucideIcons.sendHorizontal500));
      await tester.pumpAndSettle();
      expect(find.byType(DailySongReplySheet), findsNothing);
      pending.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.textContaining('No se pudo guardar'), findsOneWidget);
      when(() => chat.sendDailySongReply(owner, 'Me encanta'))
          .thenAnswer((_) async {});
      await tester.tap(find.byIcon(Icons.error_outline));
      await tester.pumpAndSettle();
      expect(find.text('Me encanta'), findsOneWidget);
      await tester.tap(find.byIcon(LucideIcons.sendHorizontal500));
      await tester.pumpAndSettle();
      expect(find.byType(DailySongReplySheet), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      verify(() => chat.sendDailySongReply(owner, 'Me encanta')).called(2);
      expect(tester.takeException(), isNull);
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
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, LucideIcons.sendHorizontal500),
          )
          .onPressed,
      isNull,
    );
    expect(find.text('La respuesta es demasiado larga.'), findsOneWidget);
  });

  testWidgets(
    'mantiene el compositor visible con teclado en pantalla pequeña',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 640);
      addTearDown(tester.view.reset);
      await pump(tester);
      await tester.tap(find.text('Responder'));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final field = find.byType(TextField);
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(field).dy, lessThanOrEqualTo(340));
    },
  );
}
