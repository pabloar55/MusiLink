import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/service_providers.dart';

class FailedDailySongReply {
  const FailedDailySongReply({required this.owner, required this.text});
  final AppUser owner;
  final String text;

  bool matches(AppUser user) =>
      owner.uid == user.uid &&
      owner.dailySongUpdatedAt == user.dailySongUpdatedAt;
}

/// Failed replies survive sheet/card disposal and are cleared on account change.
class DailySongReplyNotifier extends Notifier<List<FailedDailySongReply>> {
  Object _session = Object();

  @override
  List<FailedDailySongReply> build() {
    final auth = ref.watch(firebaseAuthProvider);
    ref.watch(
      authStateProvider.select(
        (value) => value.asData?.value?.uid ?? auth.currentUser?.uid,
      ),
    );
    _session = Object();
    return const [];
  }

  Future<FailedDailySongReply?> send(
    AppUser owner,
    String text, {
    FailedDailySongReply? retryOf,
  }) async {
    if (!ref.mounted) return null;
    final session = _session;
    final senderId = ref.read(firebaseAuthProvider).currentUser?.uid;
    final service = ref.read(chatServiceProvider);
    if (retryOf != null) {
      state = state.where((reply) => !identical(reply, retryOf)).toList();
    }
    try {
      await service.sendDailySongReply(owner, text);
      return null;
    } catch (_) {
      if (!ref.mounted ||
          !identical(session, _session) ||
          senderId == null ||
          ref.read(firebaseAuthProvider).currentUser?.uid != senderId) {
        return null;
      }
      final failed = FailedDailySongReply(owner: owner, text: text);
      state = [...state, failed];
      return failed;
    }
  }
}

final dailySongReplyProvider =
    NotifierProvider<DailySongReplyNotifier, List<FailedDailySongReply>>(
      DailySongReplyNotifier.new,
    );
