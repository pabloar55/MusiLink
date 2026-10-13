import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:musi_link/models/message.dart';
import 'package:musi_link/services/chat_service.dart';

/// Ventana en vivo del historial de un chat: carga inicial, paginación hacia
/// mensajes antiguos y ampliación hasta un mensaje concreto.
///
/// Cada pantalla crea la suya, de modo que dos pantallas abiertas sobre el
/// mismo chat paginan por separado.
class ChatHistoryController extends ChangeNotifier {
  ChatHistoryController({
    required this._service,
    required this._chatId,
    required this._onMessages,
    required this._onError,
  }) {
    final cached = _service.getCachedMessages(_chatId);
    if (cached != null) {
      _messages = cached;
      _isInitialLoading = false;
    }
  }

  final ChatService _service;
  final String _chatId;

  /// Llega tras cada actualización del stream; [isFirst] distingue la que
  /// completa la carga inicial.
  final void Function({required bool isFirst}) _onMessages;

  /// Avisa de un fallo de carga. Con [unavailable], el chat no pudo abrirse y
  /// no hay nada que mostrar.
  final void Function({required bool unavailable}) _onError;

  StreamSubscription<List<Message>>? _subscription;
  DateTime? _oldestLiveTimestamp;
  int _generation = 0;
  ({String messageId, Completer<bool?> loaded})? _awaitedMessage;
  bool _disposed = false;

  /// Timestamp de borrado suave derivado del documento del chat en Firestore.
  /// Se restaura junto al historial y se comprueba en [start].
  DateTime? _deletedSince;

  // Paginación: lista única de mensajes acumulados.
  List<Message> _messages = [];
  bool _isInitialLoading = true;
  bool _hasReceivedMessages = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;

  List<Message> get messages => _messages;
  bool get isInitialLoading => _isInitialLoading;
  bool get isLoadingMore => _isLoadingMore;

  int indexOf(String messageId) =>
      _messages.indexWhere((message) => message.id == messageId);

  /// El historial persistido incluye el filtro de borrado: permite escuchar
  /// inmediatamente y comprobar el documento actualizado en segundo plano.
  Future<void> start() async {
    final history = _service.getCachedHistory(_chatId);
    final startedFromCache = history != null;
    if (history != null) {
      _deletedSince = history.since;
      _listen();
    }

    final DateTime? verifiedSince;
    try {
      verifiedSince = await _service.getDeletedSince(_chatId);
    } catch (_) {
      if (_disposed || startedFromCache) return;
      _isInitialLoading = false;
      notifyListeners();
      _onError(unavailable: true);
      return;
    }
    if (_disposed) return;
    if (startedFromCache && verifiedSince == _deletedSince) return;

    final cached = _service.getCachedMessages(_chatId);
    _deletedSince = verifiedSince;
    _hasReceivedMessages = false;
    _isLoadingMore = false;
    _hasMore = true;
    _messages = cached ?? [];
    if (cached != null || startedFromCache) _isInitialLoading = false;
    notifyListeners();
    _listen();
  }

  void _listen({DateTime? from, bool completesPagination = false}) {
    final generation = ++_generation;
    var awaitingPage = completesPagination;
    _oldestLiveTimestamp = from;
    _subscription?.cancel();
    final stream = _service.getMessages(
      _chatId,
      since: _deletedSince,
      from: from,
    );
    _subscription = stream.listen(
      (messages) {
        if (_disposed || generation != _generation) return;
        if (awaitingPage) {
          awaitingPage = false;
          _isLoadingMore = false;
        }
        _onMessagesUpdated(messages);
      },
      onError: (Object error, StackTrace stack) {
        if (_disposed || generation != _generation) return;
        _awaitedMessage?.loaded.complete(null);
        _awaitedMessage = null;
        if (awaitingPage) _hasMore = true;
        awaitingPage = false;
        _isInitialLoading = false;
        _isLoadingMore = false;
        notifyListeners();
        _onError(unavailable: false);
      },
    );
  }

  void _onMessagesUpdated(List<Message> streamMessages) {
    final isFirst = !_hasReceivedMessages;
    final confirmed = streamMessages.where((message) => !message.isPending);
    _messages = streamMessages;
    _isInitialLoading = false;
    _hasReceivedMessages = streamMessages.isEmpty || confirmed.isNotEmpty;
    // Si la primera carga tiene menos del límite de página, no hay mensajes más antiguos.
    if (isFirst) {
      _hasMore = confirmed.length >= ChatService.messagesPageSize;
    }
    // Fijar el límite por timestamp evita que los mensajes ya visibles salgan
    // de la consulta de 30 al llegar mensajes nuevos y dejen de actualizarse.
    if (_oldestLiveTimestamp == null && confirmed.isNotEmpty) {
      _listen(from: confirmed.first.timestamp);
    }
    notifyListeners();
    _onMessages(isFirst: isFirst);
    final awaited = _awaitedMessage;
    if (awaited != null && indexOf(awaited.messageId) >= 0) {
      _awaitedMessage = null;
      awaited.loaded.complete(true);
    }
  }

  /// Carga la página anterior a la más antigua ya visible.
  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    if (!_hasReceivedMessages || _messages.isEmpty) return;
    final cursor = _messages.first.timestamp;
    final generation = _generation;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final older = await _service.loadOlderMessages(
        _chatId,
        before: cursor,
        since: _deletedSince,
      );

      if (_disposed || generation != _generation) return;

      if (older.isEmpty) {
        _hasMore = false;
        _finishLoadingMore();
        return;
      }

      if (older.length < ChatService.messagesPageSize) {
        _hasMore = false;
      }
      // La nueva suscripción reemplaza toda la ventana, incluidas reacciones,
      // lecturas y borrados.
      _listen(from: older.first.timestamp, completesPagination: true);
    } catch (_) {
      if (!_disposed) _finishLoadingMore();
    }
  }

  /// Amplía el historial en vivo hasta un mensaje anterior al cargado.
  /// Devuelve false si ya no existe o quedó fuera del historial del usuario,
  /// y null si la carga falla; ese fallo ya se ha notificado como error.
  Future<bool?> loadThrough(String messageId) async {
    _isLoadingMore = true;
    notifyListeners();
    final Message? original;
    try {
      original = await _service.getMessage(_chatId, messageId);
    } catch (_) {
      if (_disposed) return null;
      _finishLoadingMore();
      _onError(unavailable: false);
      return null;
    }
    if (_disposed) return null;
    // Una página cargada entretanto puede haberlo traído ya.
    if (indexOf(messageId) >= 0) {
      _finishLoadingMore();
      return true;
    }
    final since = _deletedSince;
    if (original == null ||
        (since != null && !original.timestamp.isAfter(since))) {
      _finishLoadingMore();
      return false;
    }

    final loaded = Completer<bool?>();
    _awaitedMessage = (messageId: messageId, loaded: loaded);
    _listen(from: original.timestamp, completesPagination: true);
    return loaded.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _awaitedMessage = null;
        if (_disposed) return null;
        _finishLoadingMore();
        _onError(unavailable: false);
        return null;
      },
    );
  }

  void _finishLoadingMore() {
    _isLoadingMore = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _awaitedMessage?.loaded.complete(null);
    super.dispose();
  }
}
