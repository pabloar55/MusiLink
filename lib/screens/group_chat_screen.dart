import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/screens/chat_screen.dart';

/// Load membership from Firestore even when opening a push or a shared URL.
class GroupChatScreen extends ConsumerWidget {
  const GroupChatScreen({super.key, required this.chatId});
  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(groupChatProvider(chatId));
    final group = chat.asData?.value;
    final uid = ref.watch(firebaseAuthProvider).currentUser?.uid;
    if (group != null && group.isGroup && group.participants.contains(uid)) {
      return ChatScreen(
        key: ValueKey(chatId),
        chatId: chatId,
        group: group,
        otherUserId: '',
        otherUserName: group.name,
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/?tab=messages');
            }
          },
        ),
      ),
      body: Center(
        child: chat.isLoading
            ? const CircularProgressIndicator()
            : Text(AppLocalizations.of(context)!.groupChatUnavailable),
      ),
    );
  }
}
