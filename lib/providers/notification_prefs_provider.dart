import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:musi_link/providers/firebase_providers.dart';
import 'package:musi_link/providers/shared_preferences_provider.dart';
import 'package:musi_link/utils/firestore_collections.dart';

const _kVibrationKey = 'notification_vibration';
const _kSoundKey = 'notification_sound';
const _kFriendDigestKey = 'notification_friend_digest';

class VibrationNotifier extends Notifier<bool> {
  @override
  bool build() {
    return ref.read(sharedPreferencesProvider).getBool(_kVibrationKey) ?? true;
  }

  void toggle() {
    state = !state;
    ref.read(sharedPreferencesProvider).setBool(_kVibrationKey, state);
    _syncToFirestore();
  }

  void _syncToFirestore() {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return;
    ref
        .read(firebaseFirestoreProvider)
        .collection(FirestoreCollections.userPrivate)
        .doc(uid)
        .set({'notifVibration': state}, SetOptions(merge: true));
  }
}

final vibrationEnabledProvider = NotifierProvider<VibrationNotifier, bool>(
  VibrationNotifier.new,
);

class SoundNotifier extends Notifier<bool> {
  @override
  bool build() {
    return ref.read(sharedPreferencesProvider).getBool(_kSoundKey) ?? true;
  }

  void toggle() {
    state = !state;
    ref.read(sharedPreferencesProvider).setBool(_kSoundKey, state);
    _syncToFirestore();
  }

  void _syncToFirestore() {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return;
    ref
        .read(firebaseFirestoreProvider)
        .collection(FirestoreCollections.userPrivate)
        .doc(uid)
        .set({'notifSound': state}, SetOptions(merge: true));
  }
}

final soundEnabledProvider = NotifierProvider<SoundNotifier, bool>(
  SoundNotifier.new,
);

class FriendDigestNotifier extends Notifier<bool> {
  @override
  bool build() {
    return ref.read(sharedPreferencesProvider).getBool(_kFriendDigestKey) ??
        true;
  }

  void toggle() {
    state = !state;
    ref.read(sharedPreferencesProvider).setBool(_kFriendDigestKey, state);
    _syncToFirestore();
  }

  void _syncToFirestore() {
    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (uid == null) return;
    ref
        .read(firebaseFirestoreProvider)
        .collection(FirestoreCollections.userPrivate)
        .doc(uid)
        .set({'notifFriendDigest': state}, SetOptions(merge: true));
  }
}

final friendDigestEnabledProvider =
    NotifierProvider<FriendDigestNotifier, bool>(FriendDigestNotifier.new);
