import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/models/chat.dart';
import 'package:musi_link/models/friend_request.dart';
import 'package:musi_link/providers/shared_preferences_provider.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/services/auth_service.dart';
import 'package:musi_link/services/chat_service.dart';
import 'package:musi_link/services/friend_service.dart';
import 'package:musi_link/services/music_profile_service.dart';
import 'package:musi_link/services/notification_service.dart';
import 'package:musi_link/services/last_fm_service.dart';
import 'package:musi_link/services/music_catalog_service.dart';
import 'package:musi_link/services/spotify_cloud_service.dart';
import 'package:musi_link/services/storage_service.dart';
import 'package:musi_link/services/user_service.dart';

// ── Chat activo (suprime notificaciones del chat en pantalla) ──────

class ActiveChatNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setChat(String? chatId) {
    if (!ref.mounted) return;
    state = chatId;
  }

  void clearChat(String chatId) {
    if (!ref.mounted) return;
    if (state == chatId) state = null;
  }
}

final activeChatIdProvider = NotifierProvider<ActiveChatNotifier, String?>(
  ActiveChatNotifier.new,
);

// ── Notificación pendiente (cold-start o tap en local notification) ─

class PendingNotificationNotifier extends Notifier<Map<String, dynamic>?> {
  @override
  Map<String, dynamic>? build() => null;

  void setValue(Map<String, dynamic>? data) {
    state = data;
  }
}

final pendingNotificationProvider =
    NotifierProvider<PendingNotificationNotifier, Map<String, dynamic>?>(
      PendingNotificationNotifier.new,
    );

// ── Servicios sin dependencias ──────────────────────────────────

final userServiceProvider = Provider<UserService>((ref) {
  return UserService(firestore: ref.watch(firebaseFirestoreProvider));
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService(storage: ref.watch(firebaseStorageProvider));
});

final chatServiceProvider = Provider<ChatService>((ref) {
  return ChatService(
    firestore: ref.watch(firebaseFirestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
  );
});

final friendServiceProvider = Provider<FriendService>((ref) {
  return FriendService(
    firestore: ref.watch(firebaseFirestoreProvider),
    auth: ref.watch(firebaseAuthProvider),
    functions: ref.watch(firebaseFunctionsProvider),
  );
});

// ── Servicios con dependencias ──────────────────────────────────

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return NotificationService(
    messaging: ref.read(firebaseMessagingProvider),
    firestore: ref.read(firebaseFirestoreProvider),
    auth: ref.read(firebaseAuthProvider),
    prefs: ref.read(sharedPreferencesProvider),
    onNotificationTapped: (data) =>
        ref.read(pendingNotificationProvider.notifier).setValue(data),
    getActiveChatId: () => ref.read(activeChatIdProvider),
  );
});

final authServiceProvider = Provider<AuthService>((ref) {
  final service = AuthService(
    ref.watch(userServiceProvider),
    auth: ref.watch(firebaseAuthProvider),
    googleSignIn: ref.watch(googleSignInProvider),
    notificationService: ref.watch(notificationServiceProvider),
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

final Provider<SpotifyCloudService> spotifyClientServiceProvider =
    Provider<SpotifyCloudService>((ref) {
      return SpotifyCloudService(ref.watch(firebaseFunctionsProvider));
    });

final Provider<LastFmService> lastFmServiceProvider = Provider<LastFmService>((
  ref,
) {
  return LastFmService(ref.watch(firebaseFunctionsProvider));
});

final Provider<MusicCatalogService> musicCatalogServiceProvider =
    Provider<MusicCatalogService>((ref) {
      return MusicCatalogService(
        ref.watch(spotifyClientServiceProvider),
        ref.watch(lastFmServiceProvider),
      );
    });

final Provider<MusicProfileService> musicProfileServiceProvider =
    Provider<MusicProfileService>((ref) {
      return MusicProfileService(
        ref.watch(musicCatalogServiceProvider),
        firestore: ref.watch(firebaseFirestoreProvider),
        auth: ref.watch(firebaseAuthProvider),
      );
    });

// ── UI state ────────────────────────────────────────────────────

/// ID del mensaje cuyo reaction picker está abierto; null = ninguno.
class ActiveReactionPickerNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void open(String messageId) => state = messageId;
  void close() => state = null;
  void toggle(String messageId) =>
      state = state == messageId ? null : messageId;
}

final activeReactionPickerProvider =
    NotifierProvider<ActiveReactionPickerNotifier, String?>(
      ActiveReactionPickerNotifier.new,
    );

// ── StreamProviders de Firestore ────────────────────────────────

final receivedRequestsProvider = StreamProvider<List<FriendRequest>>((ref) {
  final authUser =
      ref
          .watch(authStateProvider)
          .maybeWhen(data: (user) => user, orElse: () => null) ??
      ref.watch(firebaseAuthProvider).currentUser;
  if (authUser == null) return Stream.value(const <FriendRequest>[]);
  return ref.watch(friendServiceProvider).getReceivedRequests();
});

final sentRequestsProvider = StreamProvider<List<FriendRequest>>((ref) {
  final authUser =
      ref
          .watch(authStateProvider)
          .maybeWhen(data: (user) => user, orElse: () => null) ??
      ref.watch(firebaseAuthProvider).currentUser;
  if (authUser == null) return Stream.value(const <FriendRequest>[]);
  return ref.watch(friendServiceProvider).getSentRequests();
});

final blockedUsersProvider = StreamProvider<List<String>>((ref) {
  final authUser =
      ref
          .watch(authStateProvider)
          .maybeWhen(data: (user) => user, orElse: () => null) ??
      ref.watch(firebaseAuthProvider).currentUser;
  if (authUser == null) return Stream.value(const <String>[]);
  return ref.watch(friendServiceProvider).getBlockedUsersStream();
});

final friendsStreamProvider = StreamProvider<List<String>>((ref) {
  final authUser =
      ref
          .watch(authStateProvider)
          .maybeWhen(data: (user) => user, orElse: () => null) ??
      ref.watch(firebaseAuthProvider).currentUser;
  if (authUser == null) return Stream.value(const <String>[]);
  return ref.watch(friendServiceProvider).getFriendsStream();
});

final chatsProvider = StreamProvider<List<Chat>>((ref) {
  final authUser =
      ref
          .watch(authStateProvider)
          .maybeWhen(data: (user) => user, orElse: () => null) ??
      ref.watch(firebaseAuthProvider).currentUser;
  if (authUser == null) return Stream.value(const <Chat>[]);
  return ref.watch(chatServiceProvider).getChats();
});

/// Número de chats con al menos un mensaje no leído por el usuario actual.
final unreadChatsCountProvider = Provider<int>((ref) {
  final uid =
      ref
          .watch(authStateProvider)
          .maybeWhen(data: (user) => user?.uid, orElse: () => null) ??
      ref.watch(firebaseAuthProvider).currentUser?.uid;
  if (uid == null) return 0;
  return ref
      .watch(chatsProvider)
      .maybeWhen(
        data: (chats) =>
            chats.where((c) => (c.unreadCounts[uid] ?? 0) > 0).length,
        orElse: () => 0,
      );
});
