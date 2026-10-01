import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:musi_link/l10n/app_localizations.dart';
import 'package:musi_link/models/chat.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';
import 'package:musi_link/screens/chat_screen.dart';

/// Reuse known group data while Firestore verifies membership and updates it.
class GroupChatScreen extends ConsumerWidget {
  const GroupChatScreen({super.key, required this.chatId, this.initialGroup});
  final String chatId;
  final Chat? initialGroup;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(groupChatProvider(chatId));
    // Initial data is only a bridge to the first snapshot. A missing group or
    // a permission error must never fall back to stale membership.
    final group = chat.hasError
        ? null
        : chat.hasValue
        ? chat.value
        : chat.isLoading
        ? initialGroup
        : null;
    final uid = ref.watch(firebaseAuthProvider).currentUser?.uid;
    if (group != null &&
        group.id == chatId &&
        group.isGroup &&
        group.participants.contains(uid)) {
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
