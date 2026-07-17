// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/services/notification_service.dart';
import 'package:musi_link/services/user_service.dart';

// ── Firebase Auth ────────────────────────────────────────────
class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUser extends Mock implements User {}

class MockUserCredential extends Mock implements UserCredential {}

// ── Cloud Functions ─────────────────────────────────────────
class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class MockHttpsCallableResult<T> extends Mock
    implements HttpsCallableResult<T> {}

// ── Google Sign-In ───────────────────────────────────────────
class MockGoogleSignIn extends Mock implements GoogleSignIn {
  @override
  Stream<GoogleSignInAuthenticationEvent> get authenticationEvents =>
      const Stream.empty();
}

class MockGoogleSignInAccount extends Mock implements GoogleSignInAccount {}

class MockGoogleSignInAuthentication extends Mock
    implements GoogleSignInAuthentication {}

// ── Firestore ────────────────────────────────────────────────
class MockFirebaseFirestore extends Mock implements FirebaseFirestore {
  /// Si se asigna, [runTransaction] ejecuta el handler con este fake.
  FakeTransaction? fakeTransaction;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    return await transactionHandler(fakeTransaction!);
  }
}

class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

class MockDocumentReference extends Mock
    implements DocumentReference<Map<String, dynamic>> {}

class MockDocumentSnapshot extends Mock
    implements DocumentSnapshot<Map<String, dynamic>> {}

class MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

class MockQueryDocumentSnapshot extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

class MockQuery extends Mock implements Query<Map<String, dynamic>> {}

class MockWriteBatch extends Mock implements WriteBatch {}

/// Transaction es una clase concreta en cloud_firestore, no abstracta.
/// Mock no puede interceptar métodos concretos, así que usamos un Fake
/// que registra las llamadas para verificar en los tests.
class FakeTransaction extends Fake implements Transaction {
  DocumentSnapshot<Map<String, dynamic>>? getResult;
  final List<DocumentSnapshot<Map<String, dynamic>>> getResults = [];
  final List<MapEntry<DocumentReference<Object?>, Map<String, dynamic>>>
  updates = [];
  final List<MapEntry<DocumentReference<Object?>, Map<String, dynamic>>> sets =
      [];
  final List<DocumentReference<Object?>> deletes = [];
  bool getCalled = false;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) async {
    getCalled = true;
    if (getResults.isNotEmpty) {
      return getResults.removeAt(0) as DocumentSnapshot<T>;
    }
    return getResult! as DocumentSnapshot<T>;
  }

  @override
  Transaction update(
    DocumentReference<Object?> documentReference,
    Map<Object, Object?> data,
  ) {
    updates.add(MapEntry(documentReference, Map<String, dynamic>.from(data)));
    return this;
  }

  @override
  Transaction set<T>(
    DocumentReference<T> documentReference,
    T data, [
    SetOptions? options,
  ]) {
    sets.add(
      MapEntry(
        documentReference as DocumentReference<Object?>,
        Map<String, dynamic>.from(data as Map),
      ),
    );
    return this;
  }

  @override
  Transaction delete(DocumentReference<Object?> documentReference) {
    deletes.add(documentReference);
    return this;
  }
}

// ── Services ─────────────────────────────────────────────────
class MockUserService extends Mock implements UserService {}

class MockNotificationService extends Mock implements NotificationService {}

// ── Fakes para fallback values ───────────────────────────────
class FakeDocumentReference extends Fake
    implements DocumentReference<Map<String, dynamic>> {}

// ── Fallback values ──────────────────────────────────────────
void registerFallbackValues() {
  registerFallbackValue(<String, dynamic>{});
  registerFallbackValue(FakeDocumentReference());
  registerFallbackValue(SetOptions(merge: true));
}
