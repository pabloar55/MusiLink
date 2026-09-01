import 'dart:async';
import 'dart:typed_data';

import 'package:file/file.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;
import 'package:mocktail/mocktail.dart';
import 'package:musi_link/services/notification_avatar_cache.dart';

class MockCacheManager extends Mock implements BaseCacheManager {}

class MockFile extends Mock implements File {}

const _avatarUrl =
    'https://firebasestorage.googleapis.com/v0/b/'
    'musi-link-e7759.firebasestorage.app/o/'
    'profile_photos%2Falice?alt=media&token=abc_123';

MockFile _fileWithBytes(Uint8List bytes) {
  final file = MockFile();
  when(file.length).thenAnswer((_) async => bytes.length);
  when(file.readAsBytes).thenAnswer((_) async => bytes);
  return file;
}

void main() {
  final now = DateTime.utc(2026, 9, 1, 12);

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(Duration.zero);
  });

  group('createNotificationThumbnail', () {
    test('creates a centered 128px square JPEG', () async {
      final source = image_lib.Image(width: 320, height: 180);
      image_lib.fill(source, color: image_lib.ColorRgb8(80, 120, 200));

      final thumbnail = await createNotificationThumbnail(
        image_lib.encodeJpg(source),
      );
      final decoded = thumbnail == null ? null : image_lib.decodeJpg(thumbnail);

      expect(thumbnail, isNotNull);
      expect(decoded?.width, NotificationAvatarCache.thumbnailSize);
      expect(decoded?.height, NotificationAvatarCache.thumbnailSize);
      expect(
        thumbnail!.length,
        lessThan(NotificationAvatarCache.maxThumbnailBytes),
      );
    });

    test('rejects source images with excessive dimensions', () async {
      final source = image_lib.Image(width: 2049, height: 1);

      final thumbnail = await createNotificationThumbnail(
        image_lib.encodeJpg(source),
      );

      expect(thumbnail, isNull);
    });
  });

  group('NotificationAvatarCache', () {
    late MockCacheManager cacheManager;

    setUp(() {
      cacheManager = MockCacheManager();
      when(() => cacheManager.removeFile(any())).thenAnswer((_) async {});
    });

    test('rejects untrusted URLs without touching the cache', () async {
      final cache = NotificationAvatarCache(cacheManager: cacheManager);

      expect(await cache.load('https://example.com/avatar.jpg'), isNull);

      verifyNoMoreInteractions(cacheManager);
    });

    test('returns a fresh thumbnail without loading the source', () async {
      final thumbnail = Uint8List.fromList([1, 2, 3]);
      when(() => cacheManager.getFileFromCache(any())).thenAnswer(
        (_) async => FileInfo(
          _fileWithBytes(thumbnail),
          FileSource.Cache,
          now.add(const Duration(hours: 1)),
          _avatarUrl,
        ),
      );
      final cache = NotificationAvatarCache(
        cacheManager: cacheManager,
        now: () => now,
      );

      expect(await cache.load(_avatarUrl), thumbnail);

      verifyNever(
        () => cacheManager.getSingleFile(any(), key: any(named: 'key')),
      );
    });

    test('generates and stores a thumbnail after a cache miss', () async {
      final source = Uint8List.fromList([4, 5, 6]);
      final thumbnail = Uint8List.fromList([7, 8, 9]);
      Uint8List? storedThumbnail;
      when(() => cacheManager.getFileFromCache(any())).thenAnswer((_) async {
        if (storedThumbnail == null) return null;
        return FileInfo(
          _fileWithBytes(storedThumbnail!),
          FileSource.Cache,
          now.add(const Duration(hours: 1)),
          _avatarUrl,
        );
      });
      when(() => cacheManager.getSingleFile(_avatarUrl, key: _avatarUrl))
          .thenAnswer((_) async => _fileWithBytes(source));
      when(
        () => cacheManager.putFile(
          _avatarUrl,
          any(),
          key: any(named: 'key'),
          maxAge: any(named: 'maxAge'),
          fileExtension: 'jpg',
        ),
      ).thenAnswer((invocation) async {
        storedThumbnail = invocation.positionalArguments[1] as Uint8List;
        return _fileWithBytes(storedThumbnail!);
      });
      var generations = 0;
      final cache = NotificationAvatarCache(
        cacheManager: cacheManager,
        now: () => now,
        thumbnailGenerator: (bytes) async {
          generations++;
          expect(bytes, source);
          return thumbnail;
        },
      );

      expect(await cache.load(_avatarUrl), thumbnail);
      expect(await cache.load(_avatarUrl), thumbnail);
      expect(generations, 1);
      verify(() => cacheManager.getSingleFile(_avatarUrl, key: _avatarUrl))
          .called(1);
    });

    test('uses an expired thumbnail when refreshing fails', () async {
      final staleThumbnail = Uint8List.fromList([10, 11, 12]);
      when(() => cacheManager.getFileFromCache(any())).thenAnswer(
        (_) async => FileInfo(
          _fileWithBytes(staleThumbnail),
          FileSource.Cache,
          now.subtract(const Duration(minutes: 1)),
          _avatarUrl,
        ),
      );
      when(
        () =>
            cacheManager.downloadFile(_avatarUrl, key: _avatarUrl, force: true),
      ).thenThrow(Exception('offline'));
      final cache = NotificationAvatarCache(
        cacheManager: cacheManager,
        now: () => now,
      );

      expect(await cache.load(_avatarUrl), staleThumbnail);
      verify(
        () =>
            cacheManager.downloadFile(_avatarUrl, key: _avatarUrl, force: true),
      ).called(1);
    });

    test('returns a generated thumbnail when persisting it fails', () async {
      final source = Uint8List.fromList([17, 18]);
      final thumbnail = Uint8List.fromList([19, 20]);
      when(() => cacheManager.getFileFromCache(any()))
          .thenAnswer((_) async => null);
      when(() => cacheManager.getSingleFile(_avatarUrl, key: _avatarUrl))
          .thenAnswer((_) async => _fileWithBytes(source));
      when(
        () => cacheManager.putFile(
          _avatarUrl,
          any(),
          key: any(named: 'key'),
          maxAge: any(named: 'maxAge'),
          fileExtension: 'jpg',
        ),
      ).thenThrow(Exception('disk full'));
      final cache = NotificationAvatarCache(
        cacheManager: cacheManager,
        thumbnailGenerator: (_) async => thumbnail,
      );

      expect(await cache.load(_avatarUrl), thumbnail);
    });

    test('deduplicates concurrent loads for the same URL', () async {
      final source = Uint8List.fromList([13, 14]);
      final thumbnail = Uint8List.fromList([15, 16]);
      final sourceCompleter = Completer<File>();
      when(() => cacheManager.getFileFromCache(any()))
          .thenAnswer((_) async => null);
      when(() => cacheManager.getSingleFile(_avatarUrl, key: _avatarUrl))
          .thenAnswer((_) => sourceCompleter.future);
      when(
        () => cacheManager.putFile(
          _avatarUrl,
          any(),
          key: any(named: 'key'),
          maxAge: any(named: 'maxAge'),
          fileExtension: 'jpg',
        ),
      ).thenAnswer((_) async => _fileWithBytes(thumbnail));
      final cache = NotificationAvatarCache(
        cacheManager: cacheManager,
        thumbnailGenerator: (_) async => thumbnail,
      );

      final first = cache.load(_avatarUrl);
      final second = cache.load(_avatarUrl);
      sourceCompleter.complete(_fileWithBytes(source));

      expect(await first, thumbnail);
      expect(await second, thumbnail);
      verify(() => cacheManager.getSingleFile(_avatarUrl, key: _avatarUrl))
          .called(1);
    });

    test('rejects and removes an oversized source file', () async {
      final sourceFile = MockFile();
      when(sourceFile.length)
          .thenAnswer((_) async => NotificationAvatarCache.maxSourceBytes + 1);
      when(() => cacheManager.getFileFromCache(any()))
          .thenAnswer((_) async => null);
      when(() => cacheManager.getSingleFile(_avatarUrl, key: _avatarUrl))
          .thenAnswer((_) async => sourceFile);
      final cache = NotificationAvatarCache(cacheManager: cacheManager);

      expect(await cache.load(_avatarUrl), isNull);

      verify(() => cacheManager.removeFile(_avatarUrl)).called(1);
      verifyNever(sourceFile.readAsBytes);
    });
  });
}
