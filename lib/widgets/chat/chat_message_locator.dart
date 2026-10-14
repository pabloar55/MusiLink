import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:musi_link/services/chat_history_controller.dart';
import 'package:musi_link/theme/app_theme.dart';

/// Lleva la lista de un chat hasta un mensaje concreto, como el citado por una
/// respuesta, y lo resalta un instante.
///
/// Cada pantalla crea el suyo. Avisa a sus listeners cuando cambia el mensaje
/// resaltado.
class ChatMessageLocator extends ChangeNotifier {
  ChatMessageLocator({
    required this._history,
    required this._scrollController,
    required this._onUnavailable,
  });

  final ChatHistoryController _history;
  final ScrollController _scrollController;

  /// Avisa de que el mensaje buscado ya no existe o no puede mostrarse.
  final void Function() _onUnavailable;

  bool _isLocating = false;
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  bool _disposed = false;

  String? get highlightedMessageId => _highlightedMessageId;

  /// Clave que debe llevar la fila del mensaje para poder localizarla.
  Key keyFor(String messageId) => _MessageKey(this, messageId);

  /// Carga el mensaje si queda fuera del historial visible, desplaza la lista
  /// hasta él y lo resalta.
  Future<void> show(String messageId) async {
    if (_isLocating) return;
    _isLocating = true;
    try {
      final loaded = _history.indexOf(messageId) >= 0
          ? true
          : await _history.loadThrough(messageId);
      // Sin resultado, el error ya se ha mostrado.
      if (_disposed || loaded == null) return;
      if (loaded && await _scrollTo(messageId)) {
        if (!_disposed) _highlight(messageId);
        return;
      }
      if (!_disposed) _onUnavailable();
    } finally {
      _isLocating = false;
    }
  }

  /// Los mensajes tienen altura variable y solo se construyen los cercanos a
  /// la pantalla: se salta estimando la distancia por el número de mensajes y
  /// se corrige en cada fotograma hasta que el buscado está construido.
  Future<bool> _scrollTo(String messageId) async {
    // Posiciones entre las que ya se sabe que está el mensaje.
    var lower = double.negativeInfinity;
    var upper = double.infinity;
    for (var attempt = 0; attempt < 30; attempt++) {
      await WidgetsBinding.instance.endOfFrame;
      if (_disposed || !_scrollController.hasClients) return false;
      final target = _MessageKey(this, messageId).currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          alignment: 0.5,
          duration: AppTokens.durationMedium,
          curve: Curves.easeOut,
        );
        return !_disposed;
      }

      final messages = _history.messages;
      final index = _history.indexOf(messageId);
      int? oldestBuilt;
      int? newestBuilt;
      for (var i = 0; i < messages.length; i++) {
        if (_MessageKey(this, messages[i].id).currentContext == null) {
          continue;
        }
        oldestBuilt ??= i;
        newestBuilt = i;
      }
      if (index < 0 || oldestBuilt == null || newestBuilt == null) return false;

      final position = _scrollController.position;
      final perMessage =
          position.viewportDimension / (newestBuilt - oldestBuilt + 1);
      // Con la lista invertida, los mensajes antiguos quedan en offsets altos.
      final isOlder = index < oldestBuilt;
      double next;
      if (isOlder) {
        lower = position.pixels;
        next = position.pixels + (oldestBuilt - index) * perMessage;
      } else {
        upper = position.pixels;
        next = position.pixels - (index - newestBuilt) * perMessage;
      }
      if (next <= lower || next >= upper) next = (lower + upper) / 2;
      next = next
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      if (next == position.pixels) return false;
      _scrollController.jumpTo(next);
    }
    return false;
  }

  void _highlight(String messageId) {
    _highlightTimer?.cancel();
    _highlightedMessageId = messageId;
    notifyListeners();
    _highlightTimer = Timer(const Duration(milliseconds: 1200), () {
      _highlightedMessageId = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _highlightTimer?.cancel();
    super.dispose();
  }
}

/// Localiza la fila de un mensaje en una pantalla de chat concreta, de modo
/// que dos pantallas abiertas sobre el mismo chat no compartan claves.
class _MessageKey extends GlobalKey {
  const _MessageKey(this.owner, this.messageId) : super.constructor();

  final Object owner;
  final String messageId;

  @override
  bool operator ==(Object other) =>
      other is _MessageKey &&
      identical(other.owner, owner) &&
      other.messageId == messageId;

  @override
  int get hashCode => Object.hash(identityHashCode(owner), messageId);
}
