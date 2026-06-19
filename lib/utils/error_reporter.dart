import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Reports a non-fatal error to Firebase Crashlytics.
/// Silently ignores failures when Crashlytics is unavailable (e.g., in tests).
Future<void> reportError(Object error, StackTrace stack) async {
  if (kDebugMode) {
    debugPrint('Reported error: $error');
    debugPrintStack(stackTrace: stack);
  }

  if (isNetworkError(error)) return;

  try {
    await FirebaseCrashlytics.instance.recordError(error, stack);
  } catch (_) {}
}

/// Returns true when [e] looks like a transient network failure.
bool isNetworkError(Object e) {
  if (e is FirebaseException) {
    return e.code == 'unavailable' ||
        e.code == 'deadline-exceeded' ||
        e.code == 'network-request-failed';
  }

  final msg = e.toString().toLowerCase();
  return msg.contains('unavailable') ||
      msg.contains('socketexception') ||
      msg.contains('failed host lookup') ||
      msg.contains('failed to resolve name') ||
      msg.contains('network is unreachable') ||
      msg.contains('clientexception');
}
