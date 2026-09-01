import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:musi_link/models/artist.dart';
import 'package:musi_link/services/music_profile_service.dart';
import 'package:musi_link/services/pending_music_profile_store.dart';
import 'package:musi_link/utils/error_reporter.dart';
import 'package:musi_link/utils/music_profile_limits.dart';

typedef MusicProfilePendingCallback = void Function(
  String uid,
  List<Artist> artists,
);
typedef MusicProfileSavedCallback = void Function(String uid);

class MusicProfileSyncCoordinator {
  factory MusicProfileSyncCoordinator({
    required PendingMusicProfileStore store,
    required MusicProfileService profileService,
    required String? Function() currentUid,
    required MusicProfilePendingCallback onPending,
    required MusicProfileSavedCallback onSaved,
  }) => MusicProfileSyncCoordinator._(
    store,
    profileService,
    currentUid,
    onPending,
    onSaved,
  );

  MusicProfileSyncCoordinator._(
    this._store,
    this._profileService,
    this._currentUid,
    this._onPending,
    this._onSaved,
  );

  final PendingMusicProfileStore _store;
  final MusicProfileService _profileService;
  final String? Function() _currentUid;
  final MusicProfilePendingCallback _onPending;
  final MusicProfileSavedCallback _onSaved;
  final Map<String, PendingMusicProfileEdit> _volatileEdits = {};
  final Map<String, String> _blockedRevisions = {};
  final Map<String, String> _completedRevisions = {};

  Timer? _retryTimer;
  bool _syncing = false;
  bool _disposed = false;
  int _retryAttempt = 0;
  int _revisionSequence = 0;
  Future<void> _pendingWrites = Future.value();

  List<Artist>? pendingArtists(String uid) {
    final edit = _read(uid);
    return edit == null ? null : List<Artist>.unmodifiable(edit.artists);
  }

  Future<void> enqueue(String uid, List<Artist> artists) async {
    if (uid.isEmpty || _disposed) return;
    _blockedRevisions.remove(uid);
    _completedRevisions.remove(uid);
    final edit = PendingMusicProfileEdit(
      revision:
          '${DateTime.now().microsecondsSinceEpoch}-${_revisionSequence++}',
      artists: List<Artist>.unmodifiable(
        artists.take(MusicProfileLimits.maxArtists),
      ),
      createdAt: DateTime.now().toUtc(),
    );
    _onPending(uid, edit.artists);
    _volatileEdits[uid] = edit;
    final persistence = _pendingWrites.then((_) => _store.write(uid, edit));
    _pendingWrites = persistence.then<void>((_) {}, onError: (_, _) {});
    try {
      await persistence;
      if (_volatileEdits[uid]?.revision == edit.revision) {
        _volatileEdits.remove(uid);
      }
    } catch (error, stack) {
      unawaited(reportError(error, stack));
    }
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_drain(uid));
  }

  void resume() {
    if (_disposed) return;
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) return;
    final edit = _read(uid);
    if (edit != null) _onPending(uid, edit.artists);
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_drain(uid));
  }

  PendingMusicProfileEdit? _read(String uid) {
    final edit = _volatileEdits[uid] ?? _store.read(uid);
    if (edit == null || _completedRevisions[uid] == edit.revision) return null;
    return _blockedRevisions[uid] == edit.revision
        ? edit.copyWith(blocked: true)
        : edit;
  }

  Future<void> _drain(String uid) async {
    if (_syncing || _disposed || _currentUid() != uid) return;
    _syncing = true;
    try {
      while (!_disposed && _currentUid() == uid) {
        final edit = _read(uid);
        if (edit == null || edit.blocked) return;
        try {
          await _profileService.saveManualArtists(edit.artists);
          if (_disposed) return;
          final current = _read(uid);
          if (current?.revision == edit.revision) {
            await _remove(uid, edit.revision);
            _retryAttempt = 0;
            _onSaved(uid);
          }
        } catch (error) {
          final current = _read(uid);
          if (current?.revision != edit.revision) {
            _retryAttempt = 0;
            continue;
          }
          if (_isPermanent(error)) {
            await _block(uid, edit.revision);
            return;
          }
          _scheduleRetry(uid);
          return;
        }
      }
    } finally {
      _syncing = false;
    }
  }

  Future<void> _remove(String uid, String revision) async {
    _completedRevisions[uid] = revision;
    if (_volatileEdits[uid]?.revision == revision) {
      _volatileEdits.remove(uid);
    }
    try {
      if (await _store.removeIfRevision(uid, revision)) {
        _completedRevisions.remove(uid);
      }
    } catch (error, stack) {
      await reportError(error, stack);
    }
  }

  Future<void> _block(String uid, String revision) async {
    _blockedRevisions[uid] = revision;
    final volatile = _volatileEdits[uid];
    if (volatile?.revision == revision) {
      _volatileEdits[uid] = volatile!.copyWith(blocked: true);
    }
    try {
      await _store.blockIfRevision(uid, revision);
    } catch (error, stack) {
      await reportError(error, stack);
    }
  }

  bool _isPermanent(Object error) {
    if (error is! FirebaseException) return false;
    return const {
      'invalid-argument',
      'permission-denied',
      'failed-precondition',
      'not-found',
    }.contains(error.code);
  }

  void _scheduleRetry(String uid) {
    if (_disposed || _retryTimer != null || _currentUid() != uid) return;
    const delays = <Duration>[
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10),
      Duration(seconds: 30),
      Duration(minutes: 1),
    ];
    final delay = delays[_retryAttempt.clamp(0, delays.length - 1)];
    if (_retryAttempt < delays.length - 1) _retryAttempt++;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_drain(uid));
    });
  }

  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
  }
}
