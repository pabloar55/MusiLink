import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musi_link/utils/error_reporter.dart';

void main() {
  group('isRateLimitError', () {
    test('reconoce resource-exhausted de Firebase', () {
      final error = FirebaseException(
        plugin: 'firebase_functions',
        code: 'resource-exhausted',
      );

      expect(isRateLimitError(error), isTrue);
    });

    test('no oculta otros errores de Firebase', () {
      final error = FirebaseException(
        plugin: 'firebase_functions',
        code: 'permission-denied',
      );

      expect(isRateLimitError(error), isFalse);
      expect(isRateLimitError(StateError('unexpected')), isFalse);
    });
  });
}
