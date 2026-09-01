import 'dart:async';

import 'package:file/file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:image/image.dart' as image_lib;
import 'package:musi_link/utils/trusted_media_url.dart';

typedef NotificationThumbnailGenerator = Future<Uint8List?> Function(
  Uint8List bytes,
);

const _notificationThumbnailCacheVersion = 1;

@visibleForTesting
String notificationThumbnailCacheKey(String url) =>
    'notification-avatar-v$_notificationThumbnailCacheVersion:$url';

/// Creates a small, square JPEG for Android messaging-style notifications.
///
/// The work runs in a helper isolate so decoding and resizing do not block the
/// notification isolate's event loop.
Future<Uint8List?> createNotificationThumbnail(Uint8List bytes) =>
    compute(_createNotificationThumbnailSync, bytes);

Uint8List? _createNotificationThumbnailSync(Uint8List bytes) {
  final decoder = image_lib.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (decoder == null ||
      info == null ||
      info.width <= 0 ||
      info.height <= 0 ||
      info.width > NotificationAvatarCache.maxSourceDimension ||
      info.height > NotificationAvatarCache.maxSourceDimension ||
      info.width * info.height > NotificationAvatarCache.maxSourcePixels) {
    return null;
  }

  final source = decoder.decodeFrame(0);
  if (source == null) return null;

  final thumbnail = image_lib.copyResizeCropSquare(
    source,
    size: NotificationAvatarCache.thumbnailSize,
    interpolation: image_lib.Interpolation.average,
  );
  return image_lib.encodeJpg(thumbnail, quality: 85);
}

/// Loads and caches the reduced avatar used by Android chat notifications.
///
/// The original image cache is shared with `CachedNetworkImage`. The generated
/// thumbnail uses a separate versioned key, allowing its format or dimensions
/// to change without serving an older cached representation.
class NotificationAvatarCache {
  NotificationAvatarCache({
    BaseCacheManager? cacheManager,
    NotificationThumbnailGenerator? thumbnailGenerator,
    DateTime Function()? now,
    this.downloadTimeout = const Duration(seconds: 3),
    this.thumbnailMaxAge = const Duration(days: 1),
  }) : _cacheManager = cacheManager ?? DefaultCacheManager(),
       _thumbnailGenerator = thumbnailGenerator ?? createNotificationThumbnail,
       _now = now ?? DateTime.now;

  static const thumbnailSize = 128;
  static const maxSourceBytes = 1024 * 1024;
  static const maxThumbnailBytes = 128 * 1024;
  static const maxSourceDimension = 2048;
  static const maxSourcePixels = 2048 * 2048;

  final BaseCacheManager _cacheManager;
  final NotificationThumbnailGenerator _thumbnailGenerator;
  final DateTime Function() _now;
  final Duration downloadTimeout;
  final Duration thumbnailMaxAge;
  final Map<String, Future<Uint8List?>> _pendingLoads = {};

  Future<Uint8List?> load(String? rawUrl) {
    final url = trustedProfilePhotoUrl(rawUrl ?? '');
    if (url.isEmpty) return Future.value();

    final key = notificationThumbnailCacheKey(url);
    final pending = _pendingLoads[key];
    if (pending != null) return pending;

    final load = _load(url, key);
    _pendingLoads[key] = load;
    return load.whenComplete(() => _pendingLoads.remove(key));
  }

  Future<Uint8List?> _load(String url, String thumbnailKey) async {
    Uint8List? staleThumbnail;
    try {
      final cached = await _cacheManager.getFileFromCache(thumbnailKey);
      if (cached != null) {
        final bytes = await _readBoundedFile(
          cached.file,
          maxBytes: maxThumbnailBytes,
        );
        if (bytes == null) {
          await _removeQuietly(thumbnailKey);
        } else if (cached.validTill.isAfter(_now())) {
          return bytes;
        } else {
          staleThumbnail = bytes;
        }
      }
    } catch (_) {
      // A broken cache must never prevent notification delivery.
    }

    try {
      final File sourceFile;
      if (staleThumbnail == null) {
        sourceFile = await _cacheManager
            .getSingleFile(url, key: url)
            .timeout(downloadTimeout);
      } else {
        sourceFile =
            (await _cacheManager
                    .downloadFile(url, key: url, force: true)
                    .timeout(downloadTimeout))
                .file;
      }
      final sourceBytes = await _readBoundedFile(
        sourceFile,
        maxBytes: maxSourceBytes,
      );
      if (sourceBytes == null) {
        await _removeQuietly(url);
        return staleThumbnail;
      }

      final thumbnail = await _thumbnailGenerator(sourceBytes);
      if (thumbnail == null ||
          thumbnail.isEmpty ||
          thumbnail.length > maxThumbnailBytes) {
        await _removeQuietly(url);
        return staleThumbnail;
      }

      try {
        await _cacheManager.putFile(
          url,
          thumbnail,
          key: thumbnailKey,
          maxAge: thumbnailMaxAge,
          fileExtension: 'jpg',
        );
      } catch (_) {
        // The notification can still use the generated thumbnail this time.
      }
      return thumbnail;
    } catch (_) {
      return staleThumbnail;
    }
  }

  Future<Uint8List?> _readBoundedFile(
    File file, {
    required int maxBytes,
  }) async {
    final length = await file.length();
    if (length <= 0 || length > maxBytes) return null;
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > maxBytes) return null;
    return bytes;
  }

  Future<void> _removeQuietly(String key) async {
    try {
      await _cacheManager.removeFile(key);
    } catch (_) {
      // Best-effort cleanup only.
    }
  }
}
