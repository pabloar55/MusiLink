import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/providers/discover_provider.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/profile_photo_upload_provider.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/providers/user_profile_provider.dart';

void clearSessionState(WidgetRef ref) {
  ref.read(chatServiceProvider).clearCache();
  ref.read(musicProfileServiceProvider).clearCache();
  ref.read(userServiceProvider).clearCache();
  ref.read(activeChatIdProvider.notifier).setChat(null);
  ref.read(pendingNotificationProvider.notifier).setValue(null);
  ref.read(activeReactionPickerProvider.notifier).close();

  ref.invalidate(authStateProvider);
  ref.invalidate(profilePhotoUploadProvider);
  ref.invalidate(currentUserProvider);
  ref.invalidate(userStreamProvider);
  ref.invalidate(compatibilityProvider);
  ref.invalidate(relationshipProvider);
  ref.invalidate(receivedRequestsProvider);
  ref.invalidate(sentRequestsProvider);
  ref.invalidate(friendsStreamProvider);
  ref.invalidate(chatsProvider);
  ref.invalidate(unreadChatsCountProvider);
  ref.invalidate(discoverProvider);
}
