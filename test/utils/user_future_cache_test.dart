import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/models/app_user.dart';
import 'package:musi_link/services/user_service.dart';
import 'package:musi_link/utils/user_future_cache.dart';

import '../helpers/mocks.dart';

/// Clase concreta que mezcla el mixin para poder instanciarlo en tests.
class _Cache with UserFutureCache {
  @override
  final UserService userService;

  Duration _ttl;

  _Cache(this.userService, {Duration ttl = const Duration(minutes: 5)})
    : _ttl = ttl;

  @override
  Duration get cacheTtl => _ttl;

  void setTtl(Duration ttl) => _ttl = ttl;
}

AppUser _makeUser(String uid) => AppUser(uid: uid, displayName: 'User $uid');

void main() {
  late MockUserService mockUserService;
  late _Cache cache;

  setUp(() {
    mockUserService = MockUserService();
    cache = _Cache(mockUserService);
    registerFallbackValues();
  });

  group('UserFutureCache', () {
    // ── Basic fetch ─────────────────────────────────────────────────────────

    test('cache miss: llama a UserService y devuelve el usuario', () async {
      final user = _makeUser('u1');
      when(() => mockUserService.getUser('u1')).thenAnswer((_) async => user);

      final result = await cache.getUserFuture('u1');

      expect(result, equals(user));
      verify(() => mockUserService.getUser('u1')).called(1);
    });

    test('uid vacío devuelve null sin llamar a UserService', () async {
      final result = await cache.getUserFuture('');

      expect(result, isNull);
      verifyNever(() => mockUserService.getUser(any()));
    });

    // ── Cache hit ───────────────────────────────────────────────────────────

    test(
      'cache hit: segunda llamada no vuelve a llamar a UserService',
      () async {
        final user = _makeUser('u1');
        when(() => mockUserService.getUser('u1')).thenAnswer((_) async => user);

        await cache.getUserFuture('u1'); // popula caché
        await cache.getUserFuture('u1'); // hit

        verify(() => mockUserService.getUser('u1')).called(1);
      },
    );

    test(
      'reutiliza el mismo Future mientras la petición está pendiente',
      () async {
        final completer = Completer<AppUser?>();
        when(
          () => mockUserService.getUser('u1'),
        ).thenAnswer((_) => completer.future);

        final first = cache.getUserFuture('u1');
        final second = cache.getUserFuture('u1');

        expect(identical(first, second), isTrue);
        verify(() => mockUserService.getUser('u1')).called(1);

        completer.complete(_makeUser('u1'));
        await Future.wait([first, second]);
      },
    );

    test('cache hit devuelve el mismo objeto que el fetch original', () async {
      final user = _makeUser('u1');
      when(() => mockUserService.getUser('u1')).thenAnswer((_) async => user);

      await cache.getUserFuture('u1');
      final cached = await cache.getUserFuture('u1');

      expect(cached, same(user));
    });

    // ── TTL expiry ──────────────────────────────────────────────────────────

    test('TTL expirado: vuelve a llamar a UserService', () async {
      final user = _makeUser('u1');
      when(() => mockUserService.getUser('u1')).thenAnswer((_) async => user);

      cache.setTtl(
        const Duration(microseconds: -1),
      ); // diff > -1µs siempre es true

      await cache.getUserFuture('u1');
      await cache.getUserFuture('u1'); // expirado → nuevo fetch

      verify(() => mockUserService.getUser('u1')).called(2);
    });

    // ── Invalidation ────────────────────────────────────────────────────────

    test(
      'invalidateUserFuture fuerza un nuevo fetch en la siguiente llamada',
      () async {
        final user = _makeUser('u1');
        when(() => mockUserService.getUser('u1')).thenAnswer((_) async => user);

        await cache.getUserFuture('u1');
        cache.invalidateUserFuture('u1');
        await cache.getUserFuture('u1');

        verify(() => mockUserService.getUser('u1')).called(2);
      },
    );

    test('invalidar uid no cacheado no lanza error', () {
      expect(() => cache.invalidateUserFuture('inexistente'), returnsNormally);
    });

    // ── LRU eviction ────────────────────────────────────────────────────────

    test(
      'LRU: la entrada más antigua sin uso reciente es desalojada al llenar',
      () async {
        when(() => mockUserService.getUser(any())).thenAnswer(
          (inv) async => _makeUser(inv.positionalArguments.first as String),
        );

        // Llenar caché con 100 entradas (uid_0 ... uid_99).
        for (int i = 0; i < 100; i++) {
          await cache.getUserFuture('uid_$i');
        }
        // Orden LRU: uid_0 (más antiguo) ... uid_99 (más reciente)

        // Acceder a uid_0 lo mueve al final: uid_1 pasa a ser el más antiguo.
        clearInteractions(mockUserService);
        await cache.getUserFuture('uid_0');

        // Añadir la entrada 101 → uid_1 (el más antiguo ahora) es desalojado.
        clearInteractions(mockUserService);
        await cache.getUserFuture('uid_100');

        // uid_1 ya no está en caché → se vuelve a buscar.
        clearInteractions(mockUserService);
        await cache.getUserFuture('uid_1');
        verify(() => mockUserService.getUser('uid_1')).called(1);

        // uid_0 sigue en caché → no se vuelve a buscar.
        clearInteractions(mockUserService);
        await cache.getUserFuture('uid_0');
        verifyNever(() => mockUserService.getUser(any()));
      },
    );
  });
}
